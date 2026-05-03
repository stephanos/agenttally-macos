import Foundation

public enum DemoFixtures {
  public static func appState(now: Date = Date()) -> AppState {
    let businessDays = 12

    return AppState(
      isRefreshing: false,
      agentSpendings: [
        agentSpending(
          .claude,
          todayCost: 0,
          monthCost: 167,
          businessDays: businessDays,
          lastUsageDetectedAt: now.addingTimeInterval(-17 * 60 * 60)
        ),
        agentSpending(
          .codex,
          todayCost: 34,
          monthCost: 215,
          businessDays: businessDays,
          lastUsageDetectedAt: now.addingTimeInterval(-9)
        ),
      ],
      businessDays: businessDays,
      lastRefreshAt: now,
      lastOnlinePricingRefreshAt: now,
      lastErrorByAgent: [:]
    )
  }

  private static func agentSpending(
    _ agent: AgentKind,
    todayCost: Double,
    monthCost: Double,
    businessDays: Int,
    lastUsageDetectedAt: Date
  ) -> AgentSpending {
    AgentSpending(
      name: agent.displayName,
      isInstalled: true,
      todayCost: todayCost,
      monthCost: monthCost,
      avgPerDay: avgPerBusinessDay(monthCost: monthCost, businessDays: businessDays),
      lastUsageDetectedAt: lastUsageDetectedAt
    )
  }

  private static func avgPerBusinessDay(monthCost: Double, businessDays: Int) -> Double {
    guard businessDays > 0 else {
      return 0
    }

    return monthCost / Double(businessDays)
  }
}
