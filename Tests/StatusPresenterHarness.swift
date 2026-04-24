import Foundation

func testStatusPresenter() throws {
  let freshState = AppState(
    isRefreshing: true,
    todayCost: 48.35,
    monthCost: 0,
    businessDays: 0,
    avgPerDay: 0,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
    lastError: nil
  )

  try expect(
    StatusPresenter.title(
      for: freshState,
      now: Date(timeIntervalSinceReferenceDate: 1_100)
    ) == "$49 CC",
    "fresh cached data should stay visible while refreshing"
  )

  try expect(
    StatusPresenter.title(
      for: freshState,
      now: Date(timeIntervalSinceReferenceDate: 1_121)
    ) == "? CC",
    "stale data should show loading title"
  )

  let fractionalState = AppState(
    isRefreshing: false,
    todayCost: 0.01,
    monthCost: 0,
    businessDays: 0,
    avgPerDay: 0,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
    lastError: nil
  )
  try expect(
    StatusPresenter.title(for: fractionalState) == "$1 CC",
    "positive fractional costs should round up for display"
  )

  let errorState = AppState(
    isRefreshing: false,
    todayCost: 48.35,
    monthCost: 0,
    businessDays: 0,
    avgPerDay: 0,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
    lastError: "boom"
  )

  try expect(StatusPresenter.title(for: errorState) == "ERR CC", "error state should win")
  try expect(
    StatusPresenter.shouldShowWarningSymbol(for: errorState),
    "error state should show a warning symbol"
  )
  try expect(
    !StatusPresenter.shouldShowWarningSymbol(for: freshState),
    "non-error state should not show a warning symbol"
  )
  try expect(
    StatusPresenter.lastUpdatedLabel(for: AppState(isRefreshing: true)) == "refreshing...",
    "first refresh should surface a refreshing status"
  )
  try expect(
    StatusPresenter.lastUpdatedLabel(for: AppState()) == "waiting for first refresh",
    "empty state should explain that no refresh has completed"
  )
}
