import Foundation

public enum StatusPresenter {
  public static let staleDataInterval: TimeInterval = 120

  public static func shouldShowWarningSymbol(for state: AppState) -> Bool {
    state.lastError != nil
  }

  public static func title(for state: AppState, now: Date = Date()) -> String {
    if shouldShowWarningSymbol(for: state) {
      return "ERR CC"
    }

    if state.isRefreshing && shouldShowLoadingTitle(lastRefreshAt: state.lastRefreshAt, now: now) {
      return "? CC"
    }

    if state.lastRefreshAt != nil {
      return "$\(Int(floor(state.todayCost))) CC"
    }

    return "? CC"
  }

  public static func lastUpdatedLabel(for state: AppState, now: Date = Date()) -> String {
    if state.isRefreshing, state.lastRefreshAt == nil {
      return "refreshing..."
    }

    if let lastRefreshAt = state.lastRefreshAt {
      return TimeUtils.formatRelativeTime(since: lastRefreshAt, now: now)
    }

    return "waiting for first refresh"
  }

  public static func shouldShowLoadingTitle(
    lastRefreshAt: Date?,
    now: Date = Date()
  ) -> Bool {
    guard let lastRefreshAt else {
      return true
    }

    return now.timeIntervalSince(lastRefreshAt) > staleDataInterval
  }
}
