import Foundation

func testCodexUsageTracker() throws {
  try testCodexTrackerUsesLastTokenUsage()
  try testCodexTrackerParsesFractionalSecondTimestamps()
  try testCodexTrackerReconstructsTotalsWhenLastUsageIsMissing()
  try testCodexTrackerMatchesAliasedModelPricing()
  try testCodexTrackerTreatsEmptyCodexHomeLikeDefault()
  try testCodexTrackerReusesUnchangedCachedFileSummary()
  try testCodexTrackerParsesOnlyAppendedCachedFileSuffix()
}

private let codexTrackerNow = Calendar.current.date(
  from: DateComponents(year: 2026, month: 5, day: 4, hour: 12, minute: 0, second: 0)
)!

private func testCodexTrackerUsesLastTokenUsage() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let sessionFile =
    homeDirectory
    .appendingPathComponent(".codex")
    .appendingPathComponent("sessions")
    .appendingPathComponent("2026")
    .appendingPathComponent("05")
    .appendingPathComponent("04")
    .appendingPathComponent("session.jsonl")

  try writeTestFile(
    sessionFile,
    contents: [
      #"{"timestamp":"2026-05-04T08:00:00Z","type":"turn_context","payload":{"model":"gpt-5"}}"#,
      #"{"timestamp":"2026-05-04T08:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":250,"output_tokens":100}}}}"#,
    ].joined(separator: "\n"),
    modifiedAt: 1_000
  )

  let raw = CodexUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: UsageTrackingContext(
      environment: [:],
      homeDirectory: homeDirectory,
      now: codexTrackerNow,
      pricingDataLoader: { _ in Data() }
    )
  )

  try expect(raw.found, "Codex should be found when session files exist")
  try expect(raw.today > 0, "last_token_usage should produce a cost")
}

private func testCodexTrackerParsesFractionalSecondTimestamps() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let sessionFile =
    homeDirectory
    .appendingPathComponent(".codex")
    .appendingPathComponent("sessions")
    .appendingPathComponent("2026")
    .appendingPathComponent("05")
    .appendingPathComponent("04")
    .appendingPathComponent("session.jsonl")

  try writeTestFile(
    sessionFile,
    contents: [
      #"{"timestamp":"2026-05-04T08:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5"}}"#,
      #"{"timestamp":"2026-05-04T08:01:00.123Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":250,"output_tokens":100}}}}"#,
    ].joined(separator: "\n"),
    modifiedAt: 1_500
  )

  let raw = CodexUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: UsageTrackingContext(
      environment: [:],
      homeDirectory: homeDirectory,
      now: codexTrackerNow,
      pricingDataLoader: { _ in Data() }
    )
  )

  try expect(raw.today > 0, "fractional-second timestamps should still produce a cost")
}

private func testCodexTrackerReconstructsTotalsWhenLastUsageIsMissing() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let sessionFile =
    homeDirectory
    .appendingPathComponent(".codex")
    .appendingPathComponent("sessions")
    .appendingPathComponent("2026")
    .appendingPathComponent("05")
    .appendingPathComponent("04")
    .appendingPathComponent("session.jsonl")

  try writeTestFile(
    sessionFile,
    contents: [
      #"{"timestamp":"2026-05-04T08:00:00Z","type":"turn_context","payload":{"model":"gpt-5-codex"}}"#,
      #"{"timestamp":"2026-05-04T08:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":250,"output_tokens":100}}}}"#,
      #"{"timestamp":"2026-05-04T08:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1300,"cached_input_tokens":300,"output_tokens":180}}}}"#,
    ].joined(separator: "\n"),
    modifiedAt: 2_000
  )

  let raw = CodexUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: UsageTrackingContext(
      environment: [:],
      homeDirectory: homeDirectory,
      now: codexTrackerNow,
      pricingDataLoader: { _ in Data() }
    )
  )

  let firstCost = UsagePricing.calculateCodexCost(
    inputTokens: 1000,
    cachedInputTokens: 250,
    outputTokens: 100,
    pricing: UsagePricing.bundled["gpt-5"]!
  )
  let secondCost = UsagePricing.calculateCodexCost(
    inputTokens: 300,
    cachedInputTokens: 50,
    outputTokens: 80,
    pricing: UsagePricing.bundled["gpt-5"]!
  )

  try expectNear(
    raw.today, firstCost + secondCost, "total_token_usage deltas should be reconstructed")
}

private func testCodexTrackerMatchesAliasedModelPricing() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let sessionFile =
    homeDirectory
    .appendingPathComponent(".codex")
    .appendingPathComponent("sessions")
    .appendingPathComponent("2026")
    .appendingPathComponent("05")
    .appendingPathComponent("04")
    .appendingPathComponent("session.jsonl")

  try writeTestFile(
    sessionFile,
    contents: [
      #"{"timestamp":"2026-05-04T08:00:00Z","type":"turn_context","payload":{"model":"openai/gpt-5-codex"}}"#,
      #"{"timestamp":"2026-05-04T08:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}}}}"#,
    ].joined(separator: "\n"),
    modifiedAt: 3_000
  )

  let raw = CodexUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: UsageTrackingContext(
      environment: [:],
      homeDirectory: homeDirectory,
      now: codexTrackerNow,
      pricingDataLoader: { _ in Data() }
    )
  )

  try expect(raw.today > 0, "provider-prefixed alias should resolve to bundled pricing")
}

private func testCodexTrackerTreatsEmptyCodexHomeLikeDefault() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  // Create a Codex session directory at ~/.codex/sessions (the default location)
  let codexHome = homeDirectory.appendingPathComponent(".codex")
  let sessionsDir = codexHome.appendingPathComponent("sessions")
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

  // Write a test session file
  let sessionFile =
    sessionsDir
    .appendingPathComponent("2026")
    .appendingPathComponent("05")
    .appendingPathComponent("04")
    .appendingPathComponent("session.jsonl")

  try writeTestFile(
    sessionFile,
    contents: [
      #"{"timestamp":"2026-05-04T08:00:00Z","type":"turn_context","payload":{"model":"gpt-5"}}"#,
      #"{"timestamp":"2026-05-04T08:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":50,"cached_input_tokens":0,"output_tokens":10}}}}"#,
    ].joined(separator: "\n"),
    modifiedAt: 1_000
  )

  // Test with empty CODEX_HOME (should use default ~/.codex)
  let raw = CodexUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: UsageTrackingContext(
      environment: ["CODEX_HOME": ""],  // Empty string
      homeDirectory: homeDirectory,
      now: codexTrackerNow,
      pricingDataLoader: { _ in Data() }
    )
  )

  try expect(
    raw.found && raw.today > 0,
    "tracker with empty CODEX_HOME should read from ~/.codex (the default location)"
  )
}

private func testCodexTrackerReusesUnchangedCachedFileSummary() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let sessionFile =
    homeDirectory
    .appendingPathComponent(".codex")
    .appendingPathComponent("sessions")
    .appendingPathComponent("2026")
    .appendingPathComponent("05")
    .appendingPathComponent("04")
    .appendingPathComponent("session.jsonl")

  let validContents = [
    #"{"timestamp":"2026-05-04T08:00:00Z","type":"turn_context","payload":{"model":"gpt-5"}}"#,
    #"{"timestamp":"2026-05-04T08:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":250,"output_tokens":100}}}}"#,
  ].joined(separator: "\n")
  try writeTestFile(sessionFile, contents: validContents, modifiedAt: 5_000)

  let context = UsageTrackingContext(
    environment: [:],
    homeDirectory: homeDirectory,
    now: codexTrackerNow,
    pricingDataLoader: { _ in Data() }
  )
  let first = CodexUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: context,
    cache: CodexUsageFileSummaryCache()
  )

  try expect(first.rawData.today > 0, "first parse should read the valid Codex file")

  try writeTestFile(
    sessionFile,
    contents: sameByteCountInvalidJSON(as: validContents),
    modifiedAt: 5_000
  )
  let unchanged = CodexUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: context,
    cache: first.cache
  )

  try expectNear(
    unchanged.rawData.today,
    first.rawData.today,
    "unchanged file identity should reuse the cached Codex summary"
  )

  try writeTestFile(
    sessionFile,
    contents: sameByteCountInvalidJSON(as: validContents),
    modifiedAt: 5_001
  )
  let changed = CodexUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: context,
    cache: unchanged.cache
  )

  try expectNear(changed.rawData.today, 0, "changed file identity should reparse the Codex file")
}

private func testCodexTrackerParsesOnlyAppendedCachedFileSuffix() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let sessionFile =
    homeDirectory
    .appendingPathComponent(".codex")
    .appendingPathComponent("sessions")
    .appendingPathComponent("2026")
    .appendingPathComponent("05")
    .appendingPathComponent("04")
    .appendingPathComponent("session.jsonl")

  let modelLine =
    #"{"timestamp":"2026-05-04T08:00:00Z","type":"turn_context","payload":{"model":"gpt-5"}}"#
  let firstUsageLine =
    #"{"timestamp":"2026-05-04T08:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":250,"output_tokens":100}}}}"#
  let secondUsageLine =
    #"{"timestamp":"2026-05-04T08:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":500,"output_tokens":200}}}}"#
  let firstContents = "\(modelLine)\n\(firstUsageLine)\n"
  try writeTestFile(sessionFile, contents: firstContents, modifiedAt: 6_000)

  let context = UsageTrackingContext(
    environment: [:],
    homeDirectory: homeDirectory,
    now: codexTrackerNow,
    pricingDataLoader: { _ in Data() }
  )
  let first = CodexUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: context,
    cache: CodexUsageFileSummaryCache()
  )

  try writeTestFile(
    sessionFile,
    contents:
      "\(sameByteCountInvalidJSON(as: modelLine))\n\(sameByteCountInvalidJSON(as: firstUsageLine))\n\(modelLine)\n\(secondUsageLine)\n",
    modifiedAt: 6_001
  )
  let appended = CodexUsageTracker.load(
    since: "20260501",
    pricing: UsagePricing.bundled,
    context: context,
    cache: first.cache
  )

  try expect(
    appended.rawData.today > first.rawData.today,
    "append-only Codex changes should include appended suffix costs"
  )
  try expectNear(
    appended.rawData.today,
    first.rawData.today * 3,
    "append-only Codex changes should reuse cached prefix totals and parse only the suffix"
  )
}
