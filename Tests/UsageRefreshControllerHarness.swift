import Foundation

private struct FakeRefreshError: LocalizedError {
  let errorDescription: String? = "helper timed out"
}

func testUsageRefreshController() throws {
  try testBeginRefresh()
  try testBeginRefreshUsesOnlinePricingOnFirstLaunchWhenPluggedIn()
  try testBeginRefreshUsesOfflinePricingOnBattery()
  try testBeginRefreshUsesOfflinePricingWithinOnlineRefreshWindow()
  try testBeginRefreshUsesOnlinePricingAfterRefreshWindow()
  try testApplySuccess()
  try testApplyFailure()
}

private func testBeginRefresh() throws {
  let startedState = UsageRefreshController.beginRefresh(
    from: AppState(),
    isOnBatteryPower: false
  )
  try expect(startedState?.state.isRefreshing == true, "refresh should start from idle state")

  let blockedState = UsageRefreshController.beginRefresh(
    from: AppState(isRefreshing: true),
    isOnBatteryPower: false
  )
  try expect(blockedState == nil, "refresh should not start while another refresh is active")
}

private func testBeginRefreshUsesOnlinePricingOnFirstLaunchWhenPluggedIn() throws {
  let request = UsageRefreshController.beginRefresh(
    from: AppState(),
    isOnBatteryPower: false
  )

  try expect(
    request?.pricingMode == .online,
    "first refresh on external power should fetch online pricing"
  )
}

private func testBeginRefreshUsesOfflinePricingOnBattery() throws {
  let request = UsageRefreshController.beginRefresh(
    from: AppState(),
    isOnBatteryPower: true
  )

  try expect(
    request?.pricingMode == .offline,
    "battery-powered refresh should use offline pricing"
  )
}

private func testBeginRefreshUsesOfflinePricingWithinOnlineRefreshWindow() throws {
  let now = Date(timeIntervalSinceReferenceDate: 10_000)
  let request = UsageRefreshController.beginRefresh(
    from: AppState(lastOnlinePricingRefreshAt: now.addingTimeInterval(-1_800)),
    isOnBatteryPower: false,
    now: now
  )

  try expect(
    request?.pricingMode == .offline,
    "refreshes within the online pricing window should stay offline"
  )
}

private func testBeginRefreshUsesOnlinePricingAfterRefreshWindow() throws {
  let now = Date(timeIntervalSinceReferenceDate: 10_000)
  let request = UsageRefreshController.beginRefresh(
    from: AppState(lastOnlinePricingRefreshAt: now.addingTimeInterval(-3_700)),
    isOnBatteryPower: false,
    now: now
  )

  try expect(
    request?.pricingMode == .online,
    "refreshes after the online pricing window should go online again"
  )
}

private func testApplySuccess() throws {
  let now = Calendar.current.date(
    from: DateComponents(year: 2026, month: 4, day: 2, hour: 12, minute: 0, second: 0)
  )!
  let state = AppState(
    isRefreshing: true,
    todayCost: 1,
    monthCost: 2,
    businessDays: 3,
    avgPerDay: 4,
    lastRefreshAt: nil,
    lastOnlinePricingRefreshAt: nil,
    lastError: "old error"
  )
  let snapshot = UsageSnapshot(today: 48.35, month: 208.12)

  let nextState = UsageRefreshController.applySuccess(
    snapshot: snapshot,
    pricingMode: .online,
    to: state,
    now: now
  )

  try expect(!nextState.isRefreshing, "successful refresh should clear refreshing state")
  try expect(nextState.lastRefreshAt == now, "successful refresh should update last refresh time")
  try expect(nextState.todayCost == 48.35, "successful refresh should update today cost")
  try expect(nextState.monthCost == 208.12, "successful refresh should update month cost")
  try expect(nextState.businessDays == 2, "successful refresh should recompute business days")
  try expectNear(nextState.avgPerDay, 104.06, "successful refresh should recompute average")
  try expect(
    nextState.lastOnlinePricingRefreshAt == now,
    "online refresh should update last online pricing refresh time"
  )
  try expect(nextState.lastError == nil, "successful refresh should clear the previous error")
}

private func testApplyFailure() throws {
  let now = Date(timeIntervalSinceReferenceDate: 3_000)
  let state = AppState(
    isRefreshing: true,
    todayCost: 48.35,
    monthCost: 208.12,
    businessDays: 4,
    avgPerDay: 52.03,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 2_500),
    lastOnlinePricingRefreshAt: Date(timeIntervalSinceReferenceDate: 2_400),
    lastError: nil
  )

  let nextState = UsageRefreshController.applyFailure(
    error: FakeRefreshError(),
    to: state,
    now: now
  )

  try expect(!nextState.isRefreshing, "failed refresh should clear refreshing state")
  try expect(
    nextState.lastRefreshAt == now, "failed refresh should record when the failure happened")
  try expect(nextState.lastError == "helper timed out", "failed refresh should surface the error")
  try expect(nextState.todayCost == 48.35, "failed refresh should preserve cached today cost")
  try expect(nextState.monthCost == 208.12, "failed refresh should preserve cached month cost")
}
