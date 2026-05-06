import Foundation

func testUsageDataScanner() throws {
  try testClaudeFingerprintIgnoresNonUsageFiles()
  try testCodexFingerprintScopesToCurrentMonthSessions()
  try testUsageDataScannerTreatsEmptyCodexHomeLikeDefault()
}

private func testClaudeFingerprintIgnoresNonUsageFiles() throws {
  let fileManager = FileManager.default
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? fileManager.removeItem(at: homeDirectory) }

  let usageFile =
    homeDirectory
    .appendingPathComponent(".claude")
    .appendingPathComponent("projects")
    .appendingPathComponent("sample-project")
    .appendingPathComponent("session.jsonl")
  let settingsFile =
    homeDirectory
    .appendingPathComponent(".claude")
    .appendingPathComponent("settings.json")

  try writeTestFile(usageFile, contents: "{}\n", modifiedAt: 1_000)
  try writeTestFile(settingsFile, contents: "one\n", modifiedAt: 1_000)

  let firstScan = testScan(homeDirectory: homeDirectory)

  try writeTestFile(settingsFile, contents: "two\n", modifiedAt: 2_000)
  let unchangedScan = testScan(homeDirectory: homeDirectory)
  try expect(
    firstScan.agents[.claude]?.fingerprint == unchangedScan.agents[.claude]?.fingerprint,
    "Claude fingerprint should ignore non-project usage files"
  )

  try writeTestFile(usageFile, contents: "{\"usage\":true}\n", modifiedAt: 3_000)
  let changedScan = testScan(homeDirectory: homeDirectory)
  try expect(
    firstScan.agents[.claude]?.fingerprint != changedScan.agents[.claude]?.fingerprint,
    "Claude fingerprint should change when project JSONL changes"
  )
  try expect(
    firstScan.agents[.codex]?.fingerprint == changedScan.agents[.codex]?.fingerprint,
    "Claude changes should not affect the Codex fingerprint"
  )
  try expect(
    changedScan.agents[.claude]?.lastUsageDetectedAt == Date(timeIntervalSince1970: 3_000),
    "Claude scan should expose the latest usage file modification time"
  )
}

private func testCodexFingerprintScopesToCurrentMonthSessions() throws {
  let fileManager = FileManager.default
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? fileManager.removeItem(at: homeDirectory) }

  let codexHome = homeDirectory.appendingPathComponent("codex-home")
  let previousMonthFile =
    codexHome
    .appendingPathComponent("sessions")
    .appendingPathComponent("2026")
    .appendingPathComponent("04")
    .appendingPathComponent("30")
    .appendingPathComponent("old.jsonl")
  let currentMonthFile =
    codexHome
    .appendingPathComponent("sessions")
    .appendingPathComponent("2026")
    .appendingPathComponent("05")
    .appendingPathComponent("02")
    .appendingPathComponent("current.jsonl")

  try writeTestFile(previousMonthFile, contents: "old\n", modifiedAt: 1_000)
  try writeTestFile(currentMonthFile, contents: "current\n", modifiedAt: 1_000)

  let environment = ["CODEX_HOME": codexHome.path]
  let firstScan = testScan(homeDirectory: homeDirectory, environment: environment)

  try writeTestFile(previousMonthFile, contents: "older\n", modifiedAt: 2_000)
  let unchangedScan = testScan(homeDirectory: homeDirectory, environment: environment)
  try expect(
    firstScan.agents[.codex]?.fingerprint == unchangedScan.agents[.codex]?.fingerprint,
    "Codex fingerprint should ignore sessions before month start"
  )

  try writeTestFile(currentMonthFile, contents: "changed\n", modifiedAt: 3_000)
  let changedScan = testScan(homeDirectory: homeDirectory, environment: environment)
  try expect(
    firstScan.agents[.codex]?.fingerprint != changedScan.agents[.codex]?.fingerprint,
    "Codex fingerprint should change when current-month sessions change"
  )
  try expect(
    firstScan.agents[.claude]?.fingerprint == changedScan.agents[.claude]?.fingerprint,
    "Codex changes should not affect the Claude fingerprint"
  )
  try expect(
    changedScan.agents[.codex]?.lastUsageDetectedAt == Date(timeIntervalSince1970: 3_000),
    "Codex scan should expose the latest current-month session modification time"
  )
}

private func testScan(
  homeDirectory: URL,
  environment: [String: String] = [:]
) -> UsageDataScan {
  UsageDataScanner.makeScan(
    monthStart: "20260501",
    today: "2026-05-03",
    environment: environment,
    homeDirectory: homeDirectory,
    timeZone: TimeZone(secondsFromGMT: 0)!
  )
}

private func testUsageDataScannerTreatsEmptyCodexHomeLikeDefault() throws {
  let fileManager = FileManager.default
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? fileManager.removeItem(at: homeDirectory) }

  // Create the default Codex location (~/.codex/sessions)
  let defaultCodexHome = homeDirectory.appendingPathComponent(".codex")
  let defaultSessionsDir = defaultCodexHome.appendingPathComponent("sessions")
  try FileManager.default.createDirectory(at: defaultSessionsDir, withIntermediateDirectories: true)

  // Write a Codex session
  let sessionFile =
    defaultSessionsDir
    .appendingPathComponent("2026")
    .appendingPathComponent("05")
    .appendingPathComponent("03")
    .appendingPathComponent("session.jsonl")

  try writeTestFile(sessionFile, contents: "test\n", modifiedAt: 1_000)

  // Scan with empty CODEX_HOME (should still find the default location)
  let scan = testScan(
    homeDirectory: homeDirectory,
    environment: ["CODEX_HOME": ""]  // Empty string
  )

  try expect(
    scan.agents[.codex]?.lastUsageDetectedAt != nil,
    "scanner with empty CODEX_HOME should read from ~/.codex (the default location)"
  )
}
