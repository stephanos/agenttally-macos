import Foundation

enum NativeUsageLoader {
  static func loadUsage(
    since: String,
    offline: Bool,
    agents: [AgentKind],
    context: UsageTrackingContext = .live
  ) async throws -> UsageSnapshot {
    let result = try await loadUsage(
      since: since,
      offline: offline,
      agents: agents,
      context: context,
      cache: UsageFileSummaryCache()
    )
    return result.snapshot
  }

  static func loadUsage(
    since: String,
    offline: Bool,
    agents: [AgentKind],
    context: UsageTrackingContext = .live,
    cache: UsageFileSummaryCache
  ) async throws -> (snapshot: UsageSnapshot, cache: UsageFileSummaryCache) {
    let pricing = try await UsagePricingStore.loadSharedPricing(
      offline: offline,
      refreshIfPossible: !offline,
      context: context
    )

    var rawAgents: [AgentRawData] = []
    var nextCache = cache
    for agent in agents {
      switch agent {
      case .claude:
        let result = ClaudeUsageTracker.load(
          since: since,
          pricing: pricing,
          context: context,
          cache: nextCache.claude
        )
        nextCache.claude = result.cache
        rawAgents.append(result.rawData)
      case .codex:
        let result = CodexUsageTracker.load(
          since: since,
          pricing: pricing,
          context: context,
          cache: nextCache.codex
        )
        nextCache.codex = result.cache
        rawAgents.append(result.rawData)
      }
    }

    return (UsageSnapshot(agents: rawAgents), nextCache)
  }
}
