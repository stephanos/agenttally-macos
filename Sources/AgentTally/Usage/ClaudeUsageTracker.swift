import Foundation

enum ClaudeUsageTracker {
  private static let providerPrefixes = [
    "anthropic/",
    "anthropic.claude-",
    "claude-",
    "openrouter/anthropic/",
    "openrouter/openai/",
  ]

  private struct Entry: Decodable {
    let timestamp: String?
    let sessionId: String?
    let requestId: String?
    let costUSD: Double?
    let message: Message?
  }

  private struct Message: Decodable {
    let id: String?
    let model: String?
    let usage: Usage?
  }

  private struct Usage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
      case inputTokens = "input_tokens"
      case outputTokens = "output_tokens"
      case cacheCreationInputTokens = "cache_creation_input_tokens"
      case cacheReadInputTokens = "cache_read_input_tokens"
    }
  }

  static func load(
    since: String,
    pricing: [String: ModelPricing],
    context: UsageTrackingContext
  ) -> AgentRawData {
    let cache = ClaudeUsageFileSummaryCache()
    let result = load(since: since, pricing: pricing, context: context, cache: cache)
    return result.rawData
  }

  static func load(
    since: String,
    pricing: [String: ModelPricing],
    context: UsageTrackingContext,
    cache: ClaudeUsageFileSummaryCache
  ) -> (rawData: AgentRawData, cache: ClaudeUsageFileSummaryCache) {
    let projectsDirectories = claudeProjectsDirectories(context: context)
    guard !projectsDirectories.isEmpty else {
      return (
        AgentRawData(name: "Claude Code", found: false, today: 0, month: 0),
        ClaudeUsageFileSummaryCache()
      )
    }

    let sinceDate = isoDateString(fromCompactDate: since)
    let localDayFormatter = makeLocalDayFormatter()
    let fractionalTimestampFormatter = makeFractionalTimestampFormatter()
    let plainTimestampFormatter = makePlainTimestampFormatter()
    let decoder = JSONDecoder()
    let today = formatLocalDay(context.now, formatter: localDayFormatter)
    let pricingFingerprint = UsagePricingFingerprint.make(for: pricing)
    var todayCost = 0.0
    var monthCost = 0.0
    var seenKeys = Set<String>()
    var nextCache = cache
    var activeCacheKeys = Set<String>()

    for projectsDirectory in projectsDirectories {
      for fileURL in walkJSONLFiles(under: projectsDirectory) {
        let projectName =
          fileURL.path.replacingOccurrences(of: projectsDirectory.path + "/", with: "").split(
            separator: "/"
          ).first.map(String.init) ?? "unknown"

        let cacheKey = UsageFileCacheKey.path(for: fileURL)
        guard
          let identity = UsageFileCacheKey.identity(
            for: fileURL,
            pricingFingerprint: pricingFingerprint
          )
        else {
          continue
        }
        activeCacheKeys.insert(cacheKey)

        let records: [ClaudeUsageRecord]
        if let cached = nextCache.files[cacheKey], cached.identity == identity {
          records = cached.records
        } else {
          records = parseRecords(
            from: fileURL,
            projectName: projectName,
            pricing: pricing,
            decoder: decoder,
            localDayFormatter: localDayFormatter,
            fractionalTimestampFormatter: fractionalTimestampFormatter,
            plainTimestampFormatter: plainTimestampFormatter
          )
          nextCache.files[cacheKey] = ClaudeUsageFileSummary(
            identity: identity,
            records: records
          )
        }

        for record in records {
          guard record.localDate >= sinceDate,
            seenKeys.insert(record.dedupeKey).inserted
          else {
            continue
          }

          monthCost += record.cost
          if record.localDate == today {
            todayCost += record.cost
          }
        }
      }
    }

    nextCache.files = nextCache.files.filter { activeCacheKeys.contains($0.key) }

    return (
      AgentRawData(name: "Claude Code", found: true, today: todayCost, month: monthCost),
      nextCache
    )
  }

  private static func parseRecords(
    from fileURL: URL,
    projectName: String,
    pricing: [String: ModelPricing],
    decoder: JSONDecoder,
    localDayFormatter: DateFormatter,
    fractionalTimestampFormatter: ISO8601DateFormatter,
    plainTimestampFormatter: ISO8601DateFormatter
  ) -> [ClaudeUsageRecord] {
    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
      return []
    }

    var records: [ClaudeUsageRecord] = []
    for rawLine in content.split(whereSeparator: \.isNewline) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else {
        continue
      }

      guard let entry = try? decoder.decode(Entry.self, from: Data(line.utf8)),
        let timestamp = entry.timestamp,
        let usage = entry.message?.usage,
        let timestampDate = parseTimestamp(
          timestamp,
          fractionalFormatter: fractionalTimestampFormatter,
          plainFormatter: plainTimestampFormatter
        )
      else {
        continue
      }

      let sessionId =
        entry.sessionId ?? "\(projectName):\(fileURL.deletingPathExtension().lastPathComponent)"
      let dedupeKey =
        entry.requestId
        ?? entry.message?.id
        ?? "\(fileURL.path)|\(timestamp)|\(sessionId)|\(entry.message?.model ?? "<unknown>")|\(usage.inputTokens ?? 0)|\(usage.outputTokens ?? 0)|\(usage.cacheCreationInputTokens ?? 0)|\(usage.cacheReadInputTokens ?? 0)"

      let calculatedCost =
        entry.message?.model.flatMap {
          UsagePricing.lookupPricing(
            modelName: $0,
            pricing: pricing,
            providerPrefixes: providerPrefixes
          )
        }.map {
          UsagePricing.calculateClaudeCost(
            inputTokens: usage.inputTokens ?? 0,
            outputTokens: usage.outputTokens ?? 0,
            cacheCreationInputTokens: usage.cacheCreationInputTokens ?? 0,
            cacheReadInputTokens: usage.cacheReadInputTokens ?? 0,
            pricing: $0
          )
        } ?? 0

      let effectiveCost =
        if let explicitCost = entry.costUSD, explicitCost.isFinite {
          explicitCost
        } else {
          calculatedCost
        }

      records.append(
        ClaudeUsageRecord(
          dedupeKey: dedupeKey,
          localDate: formatLocalDay(timestampDate, formatter: localDayFormatter),
          cost: effectiveCost
        )
      )
    }
    return records
  }

  private static func claudeProjectsDirectories(context: UsageTrackingContext) -> [URL] {
    let configured = (context.environment["CLAUDE_CONFIG_DIR"] ?? "")
      .split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    let roots =
      configured.isEmpty
      ? [
        context.homeDirectory.appendingPathComponent(".config").appendingPathComponent("claude"),
        context.homeDirectory.appendingPathComponent(".claude"),
      ]
      : configured.map { URL(fileURLWithPath: $0) }

    return
      roots
      .map { $0.appendingPathComponent("projects") }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  private static func walkJSONLFiles(under directory: URL) -> [URL] {
    guard FileManager.default.fileExists(atPath: directory.path) else {
      return []
    }

    var files: [URL] = []
    let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: nil
    )

    while let next = enumerator?.nextObject() as? URL {
      if next.pathExtension == "jsonl" {
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
    _ timestamp: String,
    fractionalFormatter: ISO8601DateFormatter,
    plainFormatter: ISO8601DateFormatter
  ) -> Date? {
    if let date = fractionalFormatter.date(from: timestamp) {
      return date
    }

    return plainFormatter.date(from: timestamp)
  }

  private static func isoDateString(fromCompactDate value: String) -> String {
    "\(value.prefix(4))-\(value.dropFirst(4).prefix(2))-\(value.dropFirst(6).prefix(2))"
  }
}
