import Foundation

public enum StatusPresenter {
  public static let staleDataInterval: TimeInterval = 120
  private static let placeholderAgent = AgentKind.claude

  public static func displayDollarAmount(for amount: Double) -> Int {
    guard amount > 0 else {
      return 0
    }

    return Int(ceil(amount))
  }

  public static func shouldShowWarningSymbol(for state: AppState) -> Bool {
    !state.lastErrorByAgent.isEmpty
  }

  public static func title(for state: AppState, now: Date = Date()) -> String {
    if shouldShowLoadingTitle(lastRefreshAt: state.lastRefreshAt, now: now) {
      return loadingTitle(for: state)
    }

    if state.lastRefreshAt != nil {
      let parts = state.agentSpendings
        .filter { $0.isInstalled }
        .map { "$\(displayDollarAmount(for: $0.todayCost)) \(abbreviation(for: $0.name))" }
      if !parts.isEmpty {
        return parts.joined(separator: " ")
      }
    }

    if !state.lastErrorByAgent.isEmpty {
      return errorTitle(for: state)
    }

    return loadingTitle(for: state)
  }

  private static func errorTitle(for state: AppState) -> String {
    let abbreviations = AgentKind.allCases
      .filter { state.lastErrorByAgent[$0] != nil }
      .map(\.abbreviation)
    guard !abbreviations.isEmpty else {
      return "ERR \(placeholderAgent.abbreviation)"
    }

    return "ERR \(abbreviations.joined(separator: " "))"
  }

  private static func loadingTitle(for state: AppState) -> String {
    let abbreviations = state.agentSpendings
      .filter { $0.isInstalled }
      .map { abbreviation(for: $0.name) }
    guard !abbreviations.isEmpty else {
      return "? \(placeholderAgent.abbreviation)"
    }

    return "? \(abbreviations.joined(separator: " "))"
  }

  private static func abbreviation(for agentName: String) -> String {
    AgentKind(displayName: agentName)?.abbreviation ?? agentName
  }

  public static func lastRefreshedLabel(for state: AppState, now: Date = Date()) -> String {
    if state.isRefreshing, state.lastRefreshAt == nil {
      return "refreshing..."
    }

    if let lastRefreshAt = state.lastRefreshAt {
      return TimeUtils.formatRelativeTime(since: lastRefreshAt, now: now)
    }

    return "waiting for first refresh"
  }

  public static func lastUsageDetectedLabel(
    for date: Date?,
    now: Date = Date()
  ) -> String {
    guard let date else {
      return "not detected"
    }

    return TimeUtils.formatRelativeTime(since: date, now: now)
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
