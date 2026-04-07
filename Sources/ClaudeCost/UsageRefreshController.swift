import Foundation

enum UsageRefreshController {
  static func beginRefresh(from state: AppState) -> AppState? {
    guard !state.isRefreshing else {
      return nil
    }

    var nextState = state
    nextState.isRefreshing = true
    return nextState
  }

  static func applySuccess(
    snapshot: UsageSnapshot,
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
}
