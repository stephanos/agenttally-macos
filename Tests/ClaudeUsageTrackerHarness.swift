import Foundation

func testClaudeUsageTracker() throws {
  try testClaudeTrackerUsesCostUSDWhenPresent()
  try testClaudeTrackerDeduplicatesDuplicateMessages()
  try testClaudeTrackerSkipsMalformedLines()
  try testClaudeTrackerParsesFractionalSecondTimestamps()
  try testClaudeTrackerReusesUnchangedCachedFileSummary()
  try testClaudeTrackerParsesOnlyAppendedCachedFileSuffix()
  try testClaudeTrackerUsesLastSeenTimestampWhenMissing()
  try testClaudeTrackerSupportsTopLevelUsageAndModel()
  try testClaudeTrackerUsesCostUSDWithoutUsage()
}

private let claudeTrackerNow = Calendar.current.date(
  from: DateComponents(year: 2026, month: 5, day: 4, hour: 12, minute: 0, second: 0)
)!

private func testClaudeTrackerUsesCostUSDWhenPresent() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let usageFile =
    homeDirectory
    .appendingPathComponent(".claude")
    .appendingPathComponent("projects")
    .appendingPathComponent("demo")
    .appendingPathComponent("usage.jsonl")

  try writeTestFile(
    usageFile,
    contents: [
      #"{"sessionId":"session-1","timestamp":"2026-05-04T08:00:00Z","costUSD":1.25,"message":{"id":"m1","model":"claude-sonnet-4-20250514","usage":{"input_tokens":1000,"output_tokens":500}}}"#,
      #"{"sessionId":"session-1","timestamp":"2026-05-04T08:05:00Z","message":{"id":"m2","model":"claude-sonnet-4-20250514","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":250}}}"#,
    ].joined(separator: "\n"),
    modifiedAt: 1_000
  )

  let raw = ClaudeUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: UsageTrackingContext(
      environment: [:],
      homeDirectory: homeDirectory,
      now: claudeTrackerNow,
      pricingDataLoader: { _ in Data() }
    )
  )

  try expect(raw.found, "Claude should be found when usage files exist")
  try expect(raw.today > 1.25, "today should include explicit and calculated entries")
}

private func testClaudeTrackerUsesLastSeenTimestampWhenMissing() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let usageFile = homeDirectory.appendingPathComponent(".claude").appendingPathComponent(
    "history.jsonl")

  try writeTestFile(
    usageFile,
    contents: [
      #"{"type":"user","timestamp":"2026-05-04T08:00:00Z"}"#,
      #"{"type":"assistant","costUSD":0.5,"message":{"id":"m1","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"output_tokens":50}}}"#,
    ].joined(separator: "\n"),
    modifiedAt: 2_000
  )

  let raw = ClaudeUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: UsageTrackingContext(
      environment: [:],
      homeDirectory: homeDirectory,
      now: claudeTrackerNow,
      pricingDataLoader: { _ in Data() }
    )
  )

  try expectNear(raw.today, 0.5, "should use last seen timestamp when missing from the record")
}

private func testClaudeTrackerSupportsTopLevelUsageAndModel() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let usageFile = homeDirectory.appendingPathComponent(".claude").appendingPathComponent(
    "history.jsonl")

  try writeTestFile(
    usageFile,
    contents: [
      #"{"timestamp":"2026-05-04T08:00:00Z","model":"claude-sonnet-4-20250514","usage":{"input_tokens":1000,"output_tokens":500}}"#
    ].joined(separator: "\n"),
    modifiedAt: 3_000
  )

  let raw = ClaudeUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: UsageTrackingContext(
      environment: [:],
      homeDirectory: homeDirectory,
      now: claudeTrackerNow,
      pricingDataLoader: { _ in Data() }
    )
  )

  let expectedCost = UsagePricing.calculateClaudeCost(
    inputTokens: 1000,
    outputTokens: 500,
    cacheCreationInputTokens: 0,
    cacheReadInputTokens: 0,
    pricing: UsagePricing.bundled["claude-sonnet-4-20250514"]!
  )
  try expectNear(raw.today, expectedCost, "should support top-level model and usage fields")
}

private func testClaudeTrackerUsesCostUSDWithoutUsage() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let usageFile = homeDirectory.appendingPathComponent(".claude").appendingPathComponent(
    "history.jsonl")

  try writeTestFile(
    usageFile,
    contents: [
      #"{"timestamp":"2026-05-04T08:00:00Z","costUSD":0.75}"#
    ].joined(separator: "\n"),
    modifiedAt: 4_000
  )

  let raw = ClaudeUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: UsageTrackingContext(
      environment: [:],
      homeDirectory: homeDirectory,
      now: claudeTrackerNow,
      pricingDataLoader: { _ in Data() }
    )
  )

  try expectNear(raw.today, 0.75, "should count costUSD even if usage data is missing")
}

private func testClaudeTrackerDeduplicatesDuplicateMessages() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let usageFile =
    homeDirectory
    .appendingPathComponent(".claude")
    .appendingPathComponent("projects")
    .appendingPathComponent("demo")
    .appendingPathComponent("session.jsonl")

  let duplicatedLine =
    #"{"sessionId":"session-1","requestId":"req-1","timestamp":"2026-05-04T08:00:00Z","message":{"id":"m1","model":"claude-sonnet-4-20250514","usage":{"input_tokens":1000,"output_tokens":500}}}"#

  try writeTestFile(
    usageFile,
    contents: [duplicatedLine, duplicatedLine].joined(separator: "\n"),
    modifiedAt: 2_000
  )

  let raw = ClaudeUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: UsageTrackingContext(
      environment: [:],
      homeDirectory: homeDirectory,
      now: claudeTrackerNow,
      pricingDataLoader: { _ in Data() }
    )
  )

  let expectedCost = UsagePricing.calculateClaudeCost(
    inputTokens: 1000,
    outputTokens: 500,
    cacheCreationInputTokens: 0,
    cacheReadInputTokens: 0,
    pricing: UsagePricing.bundled["claude-sonnet-4-20250514"]!
  )
  try expectNear(raw.today, expectedCost, "duplicate request IDs should only be counted once")
}

private func testClaudeTrackerSkipsMalformedLines() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let usageFile =
    homeDirectory
    .appendingPathComponent(".config")
    .appendingPathComponent("claude")
    .appendingPathComponent("projects")
    .appendingPathComponent("demo")
    .appendingPathComponent("usage.jsonl")

  try writeTestFile(
    usageFile,
    contents: [
      "not-json",
      #"{"timestamp":"2026-05-04T09:00:00Z","message":{"id":"m2","model":"claude-sonnet-4-20250514","usage":{"input_tokens":500,"output_tokens":250}}}"#,
    ].joined(separator: "\n"),
    modifiedAt: 3_000
  )

  let raw = ClaudeUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: UsageTrackingContext(
      environment: [:],
      homeDirectory: homeDirectory,
      now: claudeTrackerNow,
      pricingDataLoader: { _ in Data() }
    )
  )

  try expect(raw.today > 0, "malformed lines should be ignored when valid usage lines exist")
}

private func testClaudeTrackerParsesFractionalSecondTimestamps() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let usageFile =
    homeDirectory
    .appendingPathComponent(".claude")
    .appendingPathComponent("projects")
    .appendingPathComponent("demo")
    .appendingPathComponent("usage.jsonl")

  try writeTestFile(
    usageFile,
    contents: [
      #"{"sessionId":"session-1","timestamp":"2026-05-04T08:00:00.123Z","message":{"id":"m1","model":"claude-opus","usage":{"input_tokens":100,"output_tokens":50}}}"#,
      #"{"sessionId":"session-1","timestamp":"2026-05-04T08:01:00.456789Z","message":{"id":"m2","model":"claude-sonnet-4-20250514","usage":{"input_tokens":200,"output_tokens":75}}}"#,
    ].joined(separator: "\n"),
    modifiedAt: 4_000
  )

  let raw = ClaudeUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: UsageTrackingContext(
      environment: [:],
      homeDirectory: homeDirectory,
      now: claudeTrackerNow,
      pricingDataLoader: { _ in Data() }
    )
  )

  try expect(raw.today > 0, "should parse both requests with fractional-second timestamps")
}

private func testClaudeTrackerReusesUnchangedCachedFileSummary() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let usageFile =
    homeDirectory
    .appendingPathComponent(".claude")
    .appendingPathComponent("projects")
    .appendingPathComponent("demo")
    .appendingPathComponent("usage.jsonl")

  let validContents =
    #"{"sessionId":"session-1","timestamp":"2026-05-04T08:00:00Z","costUSD":1.25,"message":{"id":"m1","model":"claude-sonnet-4-20250514","usage":{"input_tokens":1000,"output_tokens":500}}}"#
  try writeTestFile(usageFile, contents: validContents, modifiedAt: 5_000)

  let context = UsageTrackingContext(
    environment: [:],
    homeDirectory: homeDirectory,
    now: claudeTrackerNow,
    pricingDataLoader: { _ in Data() }
  )
  let first = ClaudeUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: context,
    cache: ClaudeUsageFileSummaryCache()
  )

  try expectNear(first.rawData.today, 1.25, "first parse should read the valid file")

  try writeTestFile(
    usageFile,
    contents: sameByteCountInvalidJSON(as: validContents),
    modifiedAt: 5_000
  )
  let unchanged = ClaudeUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: context,
    cache: first.cache
  )

  try expectNear(
    unchanged.rawData.today,
    1.25,
    "unchanged file identity should reuse the cached Claude summary"
  )

  try writeTestFile(
    usageFile,
    contents: sameByteCountInvalidJSON(as: validContents),
    modifiedAt: 5_001
  )
  let changed = ClaudeUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: context,
    cache: unchanged.cache
  )

  try expectNear(changed.rawData.today, 0, "changed file identity should reparse the file")
}

private func testClaudeTrackerParsesOnlyAppendedCachedFileSuffix() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let usageFile =
    homeDirectory
    .appendingPathComponent(".claude")
    .appendingPathComponent("projects")
    .appendingPathComponent("demo")
    .appendingPathComponent("usage.jsonl")

  let firstLine =
    #"{"sessionId":"session-1","timestamp":"2026-05-04T08:00:00Z","costUSD":1.25,"message":{"id":"m1","model":"claude-sonnet-4-20250514","usage":{"input_tokens":1000,"output_tokens":500}}}"#
  let secondLine =
    #"{"sessionId":"session-1","timestamp":"2026-05-04T08:01:00Z","costUSD":2.50,"message":{"id":"m2","model":"claude-sonnet-4-20250514","usage":{"input_tokens":1000,"output_tokens":500}}}"#
  try writeTestFile(usageFile, contents: "\(firstLine)\n", modifiedAt: 6_000)

  let context = UsageTrackingContext(
    environment: [:],
    homeDirectory: homeDirectory,
    now: claudeTrackerNow,
    pricingDataLoader: { _ in Data() }
  )
  let first = ClaudeUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: context,
    cache: ClaudeUsageFileSummaryCache()
  )

  try writeTestFile(
    usageFile,
    contents: "\(sameByteCountInvalidJSON(as: firstLine))\n\(secondLine)\n",
    modifiedAt: 6_001
  )
  let appended = ClaudeUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: context,
    cache: first.cache
  )

  try expectNear(
    appended.rawData.today,
    3.75,
    "append-only Claude changes should reuse cached prefix records and parse only the suffix"
  )
}
