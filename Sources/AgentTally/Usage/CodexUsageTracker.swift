import Foundation

enum CodexUsageTracker {
  private static let providerPrefixes = [
    "openai/",
    "azure/openai/",
    "azure/",
    "openrouter/openai/",
  ]
  private static let aliases = [
    "gpt-5-codex": "gpt-5",
    "gpt-5.3-codex": "gpt-5.2-codex",
  ]

  private struct TokenUsage {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int

    init(inputTokens: Int, cachedInputTokens: Int, outputTokens: Int) {
      self.inputTokens = inputTokens
      self.cachedInputTokens = cachedInputTokens
      self.outputTokens = outputTokens
    }

    init?(dictionary: [String: Any]?) {
      guard let dictionary else {
        return nil
      }

      self.inputTokens = dictionary["input_tokens"] as? Int ?? 0
      self.cachedInputTokens = dictionary["cached_input_tokens"] as? Int ?? 0
      self.outputTokens = dictionary["output_tokens"] as? Int ?? 0
    }

    init(totals: CodexTokenTotals) {
      self.inputTokens = totals.inputTokens
      self.cachedInputTokens = totals.cachedInputTokens
      self.outputTokens = totals.outputTokens
    }

    func subtracting(_ previous: TokenUsage) -> TokenUsage {
      TokenUsage(
        inputTokens: max(0, inputTokens - previous.inputTokens),
        cachedInputTokens: max(0, cachedInputTokens - previous.cachedInputTokens),
        outputTokens: max(0, outputTokens - previous.outputTokens)
      )
    }

    var totals: CodexTokenTotals {
      CodexTokenTotals(
        inputTokens: inputTokens,
        cachedInputTokens: cachedInputTokens,
        outputTokens: outputTokens
      )
    }
  }

  static func load(
    since: String,
    pricing: [String: ModelPricing],
    context: UsageTrackingContext
  ) -> AgentRawData {
    let cache = CodexUsageFileSummaryCache()
    let result = load(since: since, pricing: pricing, context: context, cache: cache)
    return result.rawData
  }

  static func load(
    since: String,
    pricing: [String: ModelPricing],
    context: UsageTrackingContext,
    cache: CodexUsageFileSummaryCache
  ) -> (rawData: AgentRawData, cache: CodexUsageFileSummaryCache) {
    let sessionsDirectory = codexSessionsDirectory(context: context)
    guard FileManager.default.fileExists(atPath: sessionsDirectory.path) else {
      return (
        AgentRawData(name: "Codex", found: false, today: 0, month: 0),
        CodexUsageFileSummaryCache()
      )
    }

    let localDayFormatter = makeLocalDayFormatter()
    let fractionalTimestampFormatter = makeFractionalTimestampFormatter()
    let plainTimestampFormatter = makePlainTimestampFormatter()
    let today = formatLocalDay(context.now, formatter: localDayFormatter)
    let sinceDate = isoDateString(fromCompactDate: since)
    let pricingFingerprint = UsagePricingFingerprint.make(for: pricing)
    var costsByDate: [String: Double] = [:]
    // A turn's token_count events are copied verbatim into every forked/resumed
    // session file, so the same turn id can appear across many files. Counting
    // each turn only once avoids massively over-counting heavily forked days.
    var seenTurnIds = Set<String>()
    var nextCache = cache
    var activeCacheKeys = Set<String>()

    for sessionFile in currentMonthSessionFiles(
      root: sessionsDirectory,
      sinceDate: sinceDate,
      localDayFormatter: localDayFormatter
    ) {
      let cacheKey = UsageFileCacheKey.path(for: sessionFile)
      guard
        let identity = UsageFileCacheKey.identity(
          for: sessionFile,
          pricingFingerprint: pricingFingerprint
        )
      else {
        continue
      }
      activeCacheKeys.insert(cacheKey)

      let summary: CodexUsageFileSummary
      if let cached = nextCache.files[cacheKey], cached.identity == identity {
        summary = cached
      } else if let cached = nextCache.files[cacheKey],
        canParseAppendedSuffix(cached: cached.identity, current: identity)
      {
        let parsed = parseTurnCosts(
          from: sessionFile,
          startingAt: UInt64(cached.identity.size),
          pricing: pricing,
          initialState: cached.parserState,
          localDayFormatter: localDayFormatter,
          fractionalTimestampFormatter: fractionalTimestampFormatter,
          plainTimestampFormatter: plainTimestampFormatter
        )
        summary = CodexUsageFileSummary(
          identity: identity,
          turnCosts: mergeTurnCosts(cached.turnCosts, parsed.turnCosts),
          untrackedCostsByDate: mergeCosts(
            cached.untrackedCostsByDate,
            parsed.untrackedCostsByDate
          ),
          parserState: parsed.parserState
        )
      } else {
        let parsed = parseTurnCosts(
          from: sessionFile,
          startingAt: 0,
          pricing: pricing,
          initialState: .empty,
          localDayFormatter: localDayFormatter,
          fractionalTimestampFormatter: fractionalTimestampFormatter,
          plainTimestampFormatter: plainTimestampFormatter
        )
        summary = CodexUsageFileSummary(
          identity: identity,
          turnCosts: parsed.turnCosts,
          untrackedCostsByDate: parsed.untrackedCostsByDate,
          parserState: parsed.parserState
        )
      }

      if nextCache.files[cacheKey]?.identity != identity {
        nextCache.files[cacheKey] = summary
      }

      for (turnId, turnCost) in summary.turnCosts {
        guard seenTurnIds.insert(turnId).inserted, turnCost.localDay >= sinceDate else {
          continue
        }
        costsByDate[turnCost.localDay, default: 0] += turnCost.cost
      }

      for (day, cost) in summary.untrackedCostsByDate where day >= sinceDate {
        costsByDate[day, default: 0] += cost
      }
    }

    nextCache.files = nextCache.files.filter { activeCacheKeys.contains($0.key) }

    return (
      AgentRawData(
        name: "Codex",
        found: true,
        today: costsByDate[today] ?? 0,
        month: costsByDate.values.reduce(0, +)
      ),
      nextCache
    )
  }

  private static func parseTurnCosts(
    from sessionFile: URL,
    startingAt offset: UInt64,
    pricing: [String: ModelPricing],
    initialState: CodexUsageParserState,
    localDayFormatter: DateFormatter,
    fractionalTimestampFormatter: ISO8601DateFormatter,
    plainTimestampFormatter: ISO8601DateFormatter
  ) -> (
    turnCosts: [String: CodexTurnCost],
    untrackedCostsByDate: [String: Double],
    parserState: CodexUsageParserState
  ) {
    var turnCosts: [String: CodexTurnCost] = [:]
    var untrackedCostsByDate: [String: Double] = [:]
    var currentModel = initialState.currentModel
    var currentTurnId = initialState.currentTurnId
    var previousTotals = initialState.previousTotals.map(TokenUsage.init(totals:))

    JSONLLineReader.readLines(from: sessionFile, startingAt: offset) { line in
      guard !line.isEmpty,
        let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
      else {
        return
      }

      if entry["type"] as? String == "turn_context" {
        currentModel = (entry["payload"] as? [String: Any])?["model"] as? String
        return
      }

      guard entry["type"] as? String == "event_msg",
        let payload = entry["payload"] as? [String: Any]
      else {
        return
      }

      // Each turn is bracketed by a task_started event carrying its id; the id is
      // stable across replays, so it is used both to attribute the turn's day and
      // to deduplicate turns copied into forked/resumed sessions.
      if payload["type"] as? String == "task_started" {
        currentTurnId = payload["turn_id"] as? String
        return
      }

      guard payload["type"] as? String == "token_count",
        let timestamp = entry["timestamp"] as? String,
        let timestampDate = parseTimestamp(
          timestamp,
          fractionalFormatter: fractionalTimestampFormatter,
          plainFormatter: plainTimestampFormatter
        ),
        let modelName = currentModel,
        let modelPricing = UsagePricing.lookupPricing(
          modelName: modelName,
          pricing: pricing,
          providerPrefixes: providerPrefixes,
          aliases: aliases
        )
      else {
        return
      }

      let info = payload["info"] as? [String: Any] ?? [:]
      let lastUsage = TokenUsage(dictionary: info["last_token_usage"] as? [String: Any])
      let totalUsage = TokenUsage(dictionary: info["total_token_usage"] as? [String: Any])

      let delta: TokenUsage?
      if let lastUsage {
        delta = lastUsage
      } else if let totalUsage {
        delta = previousTotals.map { totalUsage.subtracting($0) } ?? totalUsage
        previousTotals = totalUsage
      } else {
        delta = nil
      }

      guard let delta else {
        return
      }

      let cost = UsagePricing.calculateCodexCost(
        inputTokens: delta.inputTokens,
        cachedInputTokens: delta.cachedInputTokens,
        outputTokens: delta.outputTokens,
        pricing: modelPricing
      )

      // Prefer the turn id's embedded creation time so a turn replayed into a
      // later fork is still counted on the day it originally ran. Events without
      // a turn id fall back to their own timestamp and are counted as-is.
      if let turnId = currentTurnId {
        let day =
          localDay(fromTurnId: turnId, formatter: localDayFormatter)
          ?? formatLocalDay(timestampDate, formatter: localDayFormatter)
        turnCosts[turnId, default: CodexTurnCost(localDay: day, cost: 0)].cost += cost
      } else {
        let day = formatLocalDay(timestampDate, formatter: localDayFormatter)
        untrackedCostsByDate[day, default: 0] += cost
      }
    }

    return (
      turnCosts,
      untrackedCostsByDate,
      CodexUsageParserState(
        currentModel: currentModel,
        currentTurnId: currentTurnId,
        previousTotals: previousTotals?.totals
      )
    )
  }

  private static func mergeTurnCosts(
    _ cached: [String: CodexTurnCost],
    _ appended: [String: CodexTurnCost]
  ) -> [String: CodexTurnCost] {
    var merged = cached
    for (turnId, turnCost) in appended {
      if var existing = merged[turnId] {
        existing.cost += turnCost.cost
        merged[turnId] = existing
      } else {
        merged[turnId] = turnCost
      }
    }
    return merged
  }

  private static func mergeCosts(
    _ cached: [String: Double],
    _ appended: [String: Double]
  ) -> [String: Double] {
    var merged = cached
    for (day, cost) in appended {
      merged[day, default: 0] += cost
    }
    return merged
  }

  /// Decodes the local day from a UUIDv7 turn id, whose first 48 bits are the
  /// creation time in milliseconds since the Unix epoch.
  private static func localDay(fromTurnId turnId: String, formatter: DateFormatter) -> String? {
    let hex = turnId.replacingOccurrences(of: "-", with: "").prefix(12)
    guard hex.count == 12, let milliseconds = UInt64(hex, radix: 16) else {
      return nil
    }
    let date = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    return formatLocalDay(date, formatter: formatter)
  }

  private static func canParseAppendedSuffix(
    cached: UsageFileIdentity,
    current: UsageFileIdentity
  ) -> Bool {
    cached.pricingFingerprint == current.pricingFingerprint
      && cached.size >= 0
      && current.size > cached.size
  }

  private static func codexSessionsDirectory(context: UsageTrackingContext) -> URL {
    CodexPathResolver.resolveCodexHome(
      from: context.environment,
      homeDirectory: context.homeDirectory
    )
    .appendingPathComponent("sessions")
  }

  private static func currentMonthSessionFiles(
    root: URL,
    sinceDate: String,
    localDayFormatter: DateFormatter
  ) -> [URL] {
    var files: [URL] = []
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)

    while let next = enumerator?.nextObject() as? URL {
      guard next.pathExtension == "jsonl" else {
        continue
      }

      if shouldIncludeCurrentMonthSessionFile(
        next,
        sinceDate: sinceDate,
        localDayFormatter: localDayFormatter
      ) {
        files.append(next)
      }
    }

    // Session paths encode the start time (sessions/YYYY/MM/DD/rollout-<ts>-…),
    // so sorting by path yields a stable chronological order for aggregation.
    return files.sorted { $0.path < $1.path }
  }

  private static func shouldIncludeCurrentMonthSessionFile(
    _ fileURL: URL,
    sinceDate: String,
    localDayFormatter: DateFormatter
  ) -> Bool {
    if let sessionDate = sessionDate(for: fileURL), sessionDate >= sinceDate {
      return true
    }

    if let modificationDay = fileModificationDay(for: fileURL, formatter: localDayFormatter),
      modificationDay >= sinceDate
    {
      return true
    }

    return false
  }

  private static func sessionDate(for fileURL: URL) -> String? {
    let components = fileURL.pathComponents
    guard let sessionsIndex = components.lastIndex(of: "sessions"),
      components.count > sessionsIndex + 3
    else {
      return nil
    }

    let year = components[sessionsIndex + 1]
    let month = components[sessionsIndex + 2]
    let day = components[sessionsIndex + 3]
    return "\(year)-\(month)-\(day)"
  }

  private static func fileModificationDay(for fileURL: URL, formatter: DateFormatter) -> String? {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
      let modificationDate = attributes[.modificationDate] as? Date
    else {
      return nil
    }

    return formatLocalDay(modificationDate, formatter: formatter)
  }

  private static func makeLocalDayFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }

  private static func formatLocalDay(_ date: Date, formatter: DateFormatter) -> String {
    formatter.string(from: date)
  }

  private static func isoDateString(fromCompactDate value: String) -> String {
    "\(value.prefix(4))-\(value.dropFirst(4).prefix(2))-\(value.dropFirst(6).prefix(2))"
  }

  private static func makeFractionalTimestampFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }

  private static func makePlainTimestampFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }

  private static func parseTimestamp(
    _ value: String,
    fractionalFormatter: ISO8601DateFormatter,
    plainFormatter: ISO8601DateFormatter
  ) -> Date? {
    if let date = fractionalFormatter.date(from: value) {
      return date
    }

    return plainFormatter.date(from: value)
  }
}
