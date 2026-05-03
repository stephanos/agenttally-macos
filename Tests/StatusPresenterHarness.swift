import Foundation

func testStatusPresenter() throws {
  let claudeSpending = AgentSpending(
    name: "Claude Code", isInstalled: true, todayCost: 48.35, monthCost: 0, avgPerDay: 0)
  let codexSpending = AgentSpending(
    name: "Codex", isInstalled: true, todayCost: 12.0, monthCost: 0, avgPerDay: 0)
  let codexNotInstalled = AgentSpending(
    name: "Codex", isInstalled: false, todayCost: 0, monthCost: 0, avgPerDay: 0)
  let fractionalSpending = AgentSpending(
    name: "Claude Code", isInstalled: true, todayCost: 0.01, monthCost: 0, avgPerDay: 0)

  let freshState = AppState(
    isRefreshing: true,
    agentSpendings: [claudeSpending],
    businessDays: 0,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
    lastErrorByAgent: [:]
  )

  try expect(
    StatusPresenter.title(
      for: freshState,
      now: Date(timeIntervalSinceReferenceDate: 1_100)
    ) == "$49 CC",
    "only Claude installed should show CC only"
  )

  let bothInstalledState = AppState(
    isRefreshing: false,
    agentSpendings: [claudeSpending, codexSpending],
    businessDays: 0,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
    lastErrorByAgent: [:]
  )

  try expect(
    StatusPresenter.title(
      for: bothInstalledState,
      now: Date(timeIntervalSinceReferenceDate: 1_100)
    ) == "$49 CC $12 CX",
    "both installed should show CC and CX separated by a space"
  )

  let codexOnlyState = AppState(
    isRefreshing: false,
    agentSpendings: [
      AgentSpending(
        name: "Claude Code", isInstalled: false, todayCost: 0, monthCost: 0, avgPerDay: 0),
      codexSpending,
    ],
    businessDays: 0,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
    lastErrorByAgent: [:]
  )

  try expect(
    StatusPresenter.title(
      for: codexOnlyState,
      now: Date(timeIntervalSinceReferenceDate: 1_100)
    ) == "$12 CX",
    "only Codex installed should show CX only"
  )
  try expect(
    StatusPresenter.title(
      for: codexOnlyState,
      now: Date(timeIntervalSinceReferenceDate: 1_121)
    ) == "? CX",
    "stale Codex-only state should not fall back to the Claude abbreviation"
  )

  let codexNotInstalledState = AppState(
    isRefreshing: false,
    agentSpendings: [claudeSpending, codexNotInstalled],
    businessDays: 0,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
    lastErrorByAgent: [:]
  )

  try expect(
    StatusPresenter.title(
      for: codexNotInstalledState,
      now: Date(timeIntervalSinceReferenceDate: 1_100)
    ) == "$49 CC",
    "Codex not installed should be omitted from title"
  )

  let idleState = AppState(
    isRefreshing: false,
    agentSpendings: [claudeSpending],
    businessDays: 0,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
    lastErrorByAgent: [:]
  )

  try expect(
    StatusPresenter.title(
      for: idleState,
      now: Date(timeIntervalSinceReferenceDate: 1_121)
    ) == "? CC",
    "stale cached data should show loading title even when idle"
  )

  let fractionalState = AppState(
    isRefreshing: false,
    agentSpendings: [fractionalSpending],
    businessDays: 0,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
    lastErrorByAgent: [:]
  )
  try expect(
    StatusPresenter.title(
      for: fractionalState,
      now: Date(timeIntervalSinceReferenceDate: 1_100)
    ) == "$1 CC",
    "positive fractional costs should round up for display"
  )

  let errorState = AppState(
    isRefreshing: false,
    agentSpendings: [claudeSpending, codexSpending],
    businessDays: 0,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
    lastErrorByAgent: [.codex: "boom"]
  )

  try expect(
    StatusPresenter.title(for: errorState, now: Date(timeIntervalSinceReferenceDate: 1_100))
      == "$49 CC $12 CX",
    "agent errors should not hide available cached title data"
  )
  let noDataErrorState = AppState(
    isRefreshing: false,
    agentSpendings: [],
    businessDays: 0,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
    lastErrorByAgent: [.codex: "boom"]
  )
  try expect(
    StatusPresenter.title(
      for: noDataErrorState,
      now: Date(timeIntervalSinceReferenceDate: 1_100)
    ) == "ERR CX",
    "agent errors without cached data should name the affected agent"
  )
  try expect(
    StatusPresenter.shouldShowWarningSymbol(for: errorState),
    "error state should show a warning symbol"
  )
  try expect(
    !StatusPresenter.shouldShowWarningSymbol(for: freshState),
    "non-error state should not show a warning symbol"
  )
  try expect(
    StatusPresenter.lastRefreshedLabel(for: AppState(isRefreshing: true)) == "refreshing...",
    "first refresh should surface a refreshing status"
  )
  try expect(
    StatusPresenter.lastRefreshedLabel(for: AppState()) == "waiting for first refresh",
    "empty state should explain that no refresh has completed"
  )
}
