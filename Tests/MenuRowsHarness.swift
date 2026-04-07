import Foundation

func testMenuRowsBuilder() throws {
  let rows = MenuRowsBuilder.rows(
    for: AppState(
      isRefreshing: false,
      todayCost: 48.35,
      monthCost: 208.12,
      businessDays: 4,
      avgPerDay: 52.03,
      lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
      lastError: nil
    ),
    startAtLogin: .make(status: .enabled),
    now: Date(timeIntervalSinceReferenceDate: 1_030)
  )

  try expect(rows.first == .disabled("Claude Code spend"), "menu should start with header")
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
    MenuRowsBuilder.rows(for: AppState(), startAtLogin: .make(status: .requiresApproval))
      .contains(.disabled("Open at login pending approval in System Settings")),
    "approval message should be shown"
  )

  let refreshingRows = MenuRowsBuilder.rows(
    for: AppState(
      isRefreshing: true,
      todayCost: 48.35,
      monthCost: 208.12,
      businessDays: 4,
      avgPerDay: 52.03,
      lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
      lastError: nil
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
      todayCost: 48.35,
      monthCost: 208.12,
      businessDays: 4,
      avgPerDay: 52.03,
      lastRefreshAt: Date(timeIntervalSinceReferenceDate: 1_000),
      lastError: "helper timed out"
    ),
    startAtLogin: .make(status: .enabled)
  )
  try expect(
    errorRows.contains(.disabled("Error: helper timed out")),
    "refresh failures should surface the localized error message in the menu"
  )
  try expect(
    !errorRows.contains(.disabled("Today: $48.35")),
    "error state should hide stale summary rows"
  )
}
