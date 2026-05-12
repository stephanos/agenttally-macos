import Foundation

public struct AgentRawData: Sendable {
  public let name: String
  public let found: Bool
  public let today: Double
  public let month: Double
}

public struct UsageSnapshot: Sendable {
  public let agents: [AgentRawData]

  public init(agents: [AgentRawData]) {
    self.agents = agents
  }
}

enum UsageFetcherError: LocalizedError {
  case invalidResponse(String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse(let message):
      return message
    }
  }
}

enum UsageFetcher {
  static func fetchUsage(
    offline: Bool = false,
    agents: [AgentKind] = AgentKind.allCases
  ) async throws -> UsageSnapshot {
    try await fetchUsage(offline: offline, agents: agents, context: .live)
  }

  static func fetchUsage(
    offline: Bool,
    agents: [AgentKind],
    context: UsageTrackingContext
  ) async throws -> UsageSnapshot {
    let result = try await fetchUsage(
      offline: offline,
      agents: agents,
      context: context,
      cache: UsageFileSummaryCache()
    )
    return result.snapshot
  }

  static func fetchUsage(
    offline: Bool,
    agents: [AgentKind],
    context: UsageTrackingContext,
    cache: UsageFileSummaryCache
  ) async throws -> (snapshot: UsageSnapshot, cache: UsageFileSummaryCache) {
    try await NativeUsageLoader.loadUsage(
      since: currentMonthStartString(now: context.now),
      offline: offline,
      agents: agents,
      context: context,
      cache: cache
    )
  }

  private static func currentMonthStartString(now: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyyMM"
    return "\(formatter.string(from: now))01"
  }
}
