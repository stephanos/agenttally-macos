import Foundation

public enum PricingRefreshMode: Equatable {
  case offline
  case online
}

public struct AppState {
  public var isRefreshing = false
  public var agentSpendings: [AgentSpending] = []
  public var businessDays = 0
  public var lastRefreshAt: Date?
  public var lastOnlinePricingRefreshAt: Date?
  public var lastErrorByAgent: [AgentKind: String] = [:]

  public init(
    isRefreshing: Bool = false,
    agentSpendings: [AgentSpending] = [],
    businessDays: Int = 0,
    lastRefreshAt: Date? = nil,
    lastOnlinePricingRefreshAt: Date? = nil,
    lastErrorByAgent: [AgentKind: String] = [:]
  ) {
    self.isRefreshing = isRefreshing
    self.agentSpendings = agentSpendings
    self.businessDays = businessDays
    self.lastRefreshAt = lastRefreshAt
    self.lastOnlinePricingRefreshAt = lastOnlinePricingRefreshAt
    self.lastErrorByAgent = lastErrorByAgent
  }
}
