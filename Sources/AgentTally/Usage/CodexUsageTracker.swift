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
    var nextCache = cache
    var activeCacheKeys = Set<String>()

    for sessionFile in currentMonthSessionFiles(root: sessionsDirectory, sinceDate: sinceDate) {
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

      let fileCostsByDate: [String: Double]
      let parserState: CodexUsageParserState
      if let cached = nextCache.files[cacheKey], cached.identity == identity {
        fileCostsByDate = cached.costsByDate
        parserState = cached.parserState
      } else if let cached = nextCache.files[cacheKey],
        canParseAppendedSuffix(cached: cached.identity, current: identity)
      {
        let parsed = parseCostsByDate(
          from: sessionFile,
          startingAt: UInt64(cached.identity.size),
          pricing: pricing,
          initialState: cached.parserState,
          localDayFormatter: localDayFormatter,
          fractionalTimestampFormatter: fractionalTimestampFormatter,
          plainTimestampFormatter: plainTimestampFormatter
        )
        fileCostsByDate = mergeCosts(cached.costsByDate, parsed.costsByDate)
        parserState = parsed.parserState
      } else {
        let parsed = parseCostsByDate(
          from: sessionFile,
          startingAt: 0,
          pricing: pricing,
          initialState: .empty,
          localDayFormatter: localDayFormatter,
          fractionalTimestampFormatter: fractionalTimestampFormatter,
          plainTimestampFormatter: plainTimestampFormatter
        )
        fileCostsByDate = parsed.costsByDate
        parserState = parsed.parserState
      }

      if nextCache.files[cacheKey]?.identity != identity {
        nextCache.files[cacheKey] = CodexUsageFileSummary(
          identity: identity,
          costsByDate: fileCostsByDate,
          parserState: parserState
        )
      }

      for (day, cost) in fileCostsByDate {
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

  private static func parseCostsByDate(
    from sessionFile: URL,
    startingAt offset: UInt64,
    pricing: [String: ModelPricing],
    initialState: CodexUsageParserState,
    localDayFormatter: DateFormatter,
    fractionalTimestampFormatter: ISO8601DateFormatter,
    plainTimestampFormatter: ISO8601DateFormatter
  ) -> (costsByDate: [String: Double], parserState: CodexUsageParserState) {
    var costsByDate: [String: Double] = [:]
    var currentModel = initialState.currentModel
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
        let payload = entry["payload"] as? [String: Any],
        payload["type"] as? String == "token_count",
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
      let day = formatLocalDay(timestampDate, formatter: localDayFormatter)
      costsByDate[day, default: 0] += cost
    }

    return (
      costsByDate,
      CodexUsageParserState(
        currentModel: currentModel,
        previousTotals: previousTotals?.totals
      )
    )
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

  private static func currentMonthSessionFiles(root: URL, sinceDate: String) -> [URL] {
    var files: [URL] = []
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)

    while let next = enumerator?.nextObject() as? URL {
      guard next.pathExtension == "jsonl" else {
        continue
      }

      let components = next.pathComponents
      guard let sessionsIndex = components.lastIndex(of: "sessions"),
        components.count > sessionsIndex + 3
      else {
        continue
      }

      let year = components[sessionsIndex + 1]
      let month = components[sessionsIndex + 2]
      let day = components[sessionsIndex + 3]
      let sessionDate = "\(year)-\(month)-\(day)"
      if sessionDate >= sinceDate {
        files.append(next)
      }
    }

    return files
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
