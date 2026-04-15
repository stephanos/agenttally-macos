import Foundation

enum UsageRefreshController {
  private static let onlinePricingRefreshInterval: TimeInterval = 60 * 60

  struct RefreshRequest {
    let state: AppState
    let pricingMode: PricingRefreshMode
  }

  static func beginRefresh(
    from state: AppState,
    isOnBatteryPower: Bool,
    now: Date = Date()
  ) -> RefreshRequest? {
    guard !state.isRefreshing else {
      return nil
    }

    var nextState = state
    nextState.isRefreshing = true
    return RefreshRequest(
      state: nextState,
      pricingMode: pricingMode(
        from: state,
        isOnBatteryPower: isOnBatteryPower,
        now: now
      )
    )
  }

  static func applySuccess(
    snapshot: UsageSnapshot,
    pricingMode: PricingRefreshMode,
    to state: AppState,
    now: Date = Date()
  ) -> AppState {
    var nextState = state
    nextState.isRefreshing = false
    nextState.lastRefreshAt = now
    nextState.todayCost = snapshot.today
    nextState.monthCost = snapshot.month
    nextState.businessDays = TimeUtils.businessDaysThisMonth(now: now)
    nextState.avgPerDay =
      nextState.businessDays > 0 ? nextState.monthCost / Double(nextState.businessDays) : 0
    if pricingMode == .online {
      nextState.lastOnlinePricingRefreshAt = now
    }
    nextState.lastError = nil
    return nextState
  }

  static func applyFailure(
    error: Error,
    to state: AppState,
    now: Date = Date()
  ) -> AppState {
    var nextState = state
    nextState.isRefreshing = false
    nextState.lastRefreshAt = now
    nextState.lastError = error.localizedDescription
    return nextState
  }

  static func pricingMode(
    from state: AppState,
    isOnBatteryPower: Bool,
    now: Date = Date()
  ) -> PricingRefreshMode {
    if isOnBatteryPower {
      return .offline
    }

    guard let lastOnlinePricingRefreshAt = state.lastOnlinePricingRefreshAt else {
      return .online
    }

    if now.timeIntervalSince(lastOnlinePricingRefreshAt) >= onlinePricingRefreshInterval {
      return .online
    }

    return .offline
  }
}
