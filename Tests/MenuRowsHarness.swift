import Foundation

func testMenuRowsBuilder() throws {
  let now = Date(timeIntervalSinceReferenceDate: 1_030)
  let claudeSpending = AgentSpending(
    name: "Claude Code",
    isInstalled: true,
    todayCost: 48.35,
    monthCost: 208.12,
    avgPerDay: 52.03,
    lastUsageDetectedAt: now.addingTimeInterval(-40)
  )
  let codexSpending = AgentSpending(
    name: "Codex",
    isInstalled: true,
    todayCost: 10.0,
    monthCost: 40.0,
    avgPerDay: 10.0,
    lastUsageDetectedAt: now.addingTimeInterval(-15)
  )
  let codexNotInstalled = AgentSpending(
    name: "Codex", isInstalled: false, todayCost: 0, monthCost: 0, avgPerDay: 0)

  let rows = MenuRowsBuilder.rows(
    for: AppState(
      isRefreshing: false,
      agentSpendings: [claudeSpending, codexSpending],
      businessDays: 4,
      lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
      lastErrorByAgent: [:]
    ),
    startAtLogin: .make(status: .enabled),
    appVersion: "0.1",
    now: now
  )

  try expect(
    rows.first == .section("Claude Code spending"),
    "menu should start with spending sections after data is available"
  )
  let headerIndex = rows.firstIndex(of: .disabled("AgentTally v0.1"))!
  let codexSectionIdx = rows.firstIndex(of: .section("Codex spending"))
  try expect(
    codexSectionIdx != nil && codexSectionIdx! < headerIndex,
    "app controls should appear below spending sections"
  )
  try expect(
    rows[headerIndex - 1] == .separator,
    "refresh rows should be separated from the app controls section"
  )
  let lastRefreshedIndex = rows.firstIndex { row in
    if case .disabled(let label) = row {
      return label.hasPrefix("Last refreshed:")
    }
    return false
  }
  guard let lastRefreshedIndex else {
    throw TestFailure(description: "menu should include a last refreshed row")
  }
  try expect(
    rows[lastRefreshedIndex - 1] == .separator,
    "spending sections should be separated from refresh rows"
  )
  if case .disabled(let label) = rows[lastRefreshedIndex] {
    try expect(
      label.hasPrefix("Last refreshed:"), "last refreshed should lead the refresh section")
  } else {
    throw TestFailure(
      description: "first row in the refresh section should be 'Last refreshed:'")
  }
  try expect(
    rows[lastRefreshedIndex + 1]
      == .action(title: "Refresh", kind: .refresh, keyEquivalent: "", state: .off),
    "refresh action should appear below the last refreshed row"
  )
  try expect(
    rows[lastRefreshedIndex + 2] == .separator,
    "refresh rows should be separated from app controls"
  )
  try expect(
    rows[headerIndex + 1]
      == .action(
        title: "Check for Updates...",
        kind: .checkForUpdates,
        keyEquivalent: "",
        state: .off
      ),
    "update action should appear directly below the version row"
  )
  try expect(
    rows.contains(.disabled("Today: $49")),
    "today cost should round up to the next display dollar"
  )
  let spendingLabelIndex = rows.firstIndex(of: .section("Claude Code spending"))
  let todayIndex = rows.firstIndex(of: .disabled("Today: $49"))
  try expect(
    spendingLabelIndex != nil && todayIndex != nil && spendingLabelIndex! + 1 == todayIndex!,
    "menu should place the spending source label directly above the spending rows"
  )
  try expect(
    rows.contains(.disabled("Month: $209 (4 business days)")),
    "month cost should round up to the next display dollar and label business days"
  )
  try expect(
    rows.contains(.disabled("Avg/Biz Day: $53")),
    "average cost should clarify it is per business day"
  )
  try expect(
    rows.contains(.disabled("Last usage: 40s ago")),
    "Claude section should show when usage was last detected"
  )

  // Codex section present and separated
  let claudeSectionIdx = rows.firstIndex(of: .section("Claude Code spending"))!
  let separatorAfterClaude = rows.dropFirst(claudeSectionIdx + 1).firstIndex(of: .separator)
  try expect(
    separatorAfterClaude != nil && codexSectionIdx != nil,
    "menu should have a separator between Claude Code and Codex sections"
  )
  try expect(
    rows.contains(.disabled("Today: $10")),
    "Codex today cost should be shown"
  )
  try expect(
    rows.contains(.disabled("Month: $40 (4 business days)")),
    "Codex month cost should be shown"
  )
  try expect(
    rows.contains(.disabled("Last usage: 15s ago")),
    "Codex section should show when usage was last detected"
  )

  // Codex not installed
  let rowsCodexMissing = MenuRowsBuilder.rows(
    for: AppState(
      agentSpendings: [claudeSpending, codexNotInstalled],
      businessDays: 4,
      lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000)
    ),
    startAtLogin: .make(status: .enabled)
  )
  try expect(
    rowsCodexMissing.contains(.disabled("Codex: not installed")),
    "Codex not installed should show 'not installed' row"
  )
  try expect(
    !rowsCodexMissing.contains(.section("Codex spending")),
    "Codex not installed should not show spending section"
  )

  try expect(
    rows.contains(
      .action(
        title: "Check for Updates...",
        kind: .checkForUpdates,
        keyEquivalent: "",
        state: .off
      )
    ),
    "menu should contain update check action"
  )
  let updateAvailableRows = MenuRowsBuilder.rows(
    for: AppState(),
    startAtLogin: .make(status: .enabled),
    softwareUpdate: SoftwareUpdateViewState(availableVersion: "0.8"),
    appVersion: "0.7",
    now: now
  )
  let updateAvailableHeaderIndex = updateAvailableRows.firstIndex(of: .disabled("AgentTally v0.7"))!
  try expect(
    updateAvailableRows[updateAvailableHeaderIndex + 1]
      == .action(
        title: "Update Available: v0.8...",
        kind: .checkForUpdates,
        keyEquivalent: "",
        state: .off
      ),
    "available updates should be visible directly below the header"
  )
  try expect(
    rows.contains(
      .action(
        title: "Open at Login",
        kind: .startAtLogin,
        keyEquivalent: "",
        state: .on
      )
    ),
    "menu should contain start at login toggle"
  )
  try expect(
    rows.last == .action(title: "Quit", kind: .quit, keyEquivalent: "q", state: .off),
    "quit should be the final row in the bottom app section"
  )
  try expect(
    MenuRowsBuilder.rows(for: AppState(), startAtLogin: .make(status: .requiresApproval))
      .contains(.disabled("Open at login pending approval in System Settings")),
    "approval message should be shown"
  )

  let refreshingRows = MenuRowsBuilder.rows(
    for: AppState(
      isRefreshing: true,
      agentSpendings: [claudeSpending, codexSpending],
      businessDays: 4,
      lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
      lastErrorByAgent: [:]
    ),
    startAtLogin: .make(status: .enabled)
  )
  try expect(
    refreshingRows.contains(.disabled("Refreshing ...")),
    "refreshing state should replace the refresh action with a disabled row"
  )

  let errorRows = MenuRowsBuilder.rows(
    for: AppState(
      isRefreshing: false,
      agentSpendings: [claudeSpending, codexSpending],
      businessDays: 4,
      lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
      lastErrorByAgent: [.codex: "helper timed out"]
    ),
    startAtLogin: .make(status: .enabled)
  )
  try expect(
    errorRows.contains(.disabled("Error: helper timed out")),
    "refresh failures should surface the affected agent error in the menu"
  )
  try expect(
    errorRows.contains(.disabled("Today: $49")),
    "one agent error should not hide another agent's cached summary rows"
  )
  try expect(
    errorRows.contains(.disabled("Today: $10")),
    "an errored agent should still show cached summary rows when available"
  )

  let firstRefreshErrorRows = MenuRowsBuilder.rows(
    for: AppState(
      isRefreshing: false,
      agentSpendings: [],
      businessDays: 0,
      lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
      lastErrorByAgent: [.codex: "helper timed out"]
    ),
    startAtLogin: .make(status: .enabled)
  )
  try expect(
    firstRefreshErrorRows.contains(.section("Codex spending")),
    "first-refresh agent errors should create a section for the affected agent"
  )
  try expect(
    firstRefreshErrorRows.contains(.disabled("Error: helper timed out")),
    "first-refresh agent errors should still be visible without cached spending"
  )

  // No agent data yet (before first refresh)
  let emptyRows = MenuRowsBuilder.rows(
    for: AppState(agentSpendings: []),
    startAtLogin: .make(status: .enabled)
  )
  try expect(
    !emptyRows.contains(.section("Claude Code spending")),
    "no spending sections before first refresh"
  )
}
