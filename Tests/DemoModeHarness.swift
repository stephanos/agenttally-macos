import Foundation

func testDemoMode() throws {
  try testRuntimeModeDetection()
  try testDemoFixtures()
}

private func testRuntimeModeDetection() throws {
  try expect(
    AppRuntimeMode.current(arguments: ["AgentTally"]) == .live,
    "default runtime mode should be live"
  )
  try expect(
    AppRuntimeMode.current(arguments: ["AgentTally", "--demo"]) == .demo,
    "--demo should enable demo mode"
  )
  try expect(
    AppRuntimeMode.current(arguments: ["AgentTally", "--fixture-data"]) == .live,
    "unsupported fixture arguments should not enable demo mode"
  )
}

private func testDemoFixtures() throws {
  let now = Date(timeIntervalSinceReferenceDate: 10_000)
  let state = DemoFixtures.appState(now: now)

  try expect(state.agentSpendings.count == 2, "demo state should include both built-in agents")
  try expect(state.businessDays == 12, "demo state should include business day count")
  try expect(state.lastRefreshAt == now, "demo state should refresh relative to the current time")
  try expect(
    StatusPresenter.title(for: state, now: now) == "$0 CC $34 CX",
    "demo title should match canned visible spending"
  )

  let rows = MenuRowsBuilder.rows(
    for: state,
    startAtLogin: .make(status: .enabled),
    appVersion: "0.0.0-dev",
    now: now
  )
  try expect(
    rows.contains(.disabled("Month: $167")),
    "demo rows should show the fixture month cost without business-day text"
  )
  try expect(
    !rows.contains(.disabled("Avg/Biz Day: $14")),
    "demo rows should not show a business-day average"
  )
}
