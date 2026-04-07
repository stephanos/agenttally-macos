import Foundation

public struct AppState {
  public var isRefreshing = false
  public var todayCost = 0.0
  public var monthCost = 0.0
  public var businessDays = 0
  public var avgPerDay = 0.0
  public var lastRefreshAt: Date?
  public var lastError: String?

  public init(
    isRefreshing: Bool = false,
    todayCost: Double = 0.0,
    monthCost: Double = 0.0,
    businessDays: Int = 0,
    avgPerDay: Double = 0.0,
    lastRefreshAt: Date? = nil,
    lastError: String? = nil
  ) {
    self.isRefreshing = isRefreshing
    self.todayCost = todayCost
    self.monthCost = monthCost
    self.businessDays = businessDays
    self.avgPerDay = avgPerDay
    self.lastRefreshAt = lastRefreshAt
    self.lastError = lastError
  }
}
