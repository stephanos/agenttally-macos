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
  try testAgentsNeedingRefreshDecision()
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

private func testAgentsNeedingRefreshDecision() throws {
  let claudeFingerprint = UsageDataFingerprint(value: "claude")
  let codexFingerprint = UsageDataFingerprint(value: "codex")
  let changedCodexFingerprint = UsageDataFingerprint(value: "codex-changed")
  let scan = UsageDataScan(agents: [
    .claude: AgentUsageDataScan(
      fingerprint: claudeFingerprint,
      lastUsageDetectedAt: nil
    ),
    .codex: AgentUsageDataScan(
      fingerprint: changedCodexFingerprint,
      lastUsageDetectedAt: nil
    ),
  ])
  let cachedAgentData: [AgentKind: AgentRawData] = [
    .claude: AgentRawData(name: "Claude Code", found: true, today: 1, month: 2),
    .codex: AgentRawData(name: "Codex", found: true, today: 3, month: 4),
  ]

  try expect(
    UsageRefreshController.agentsNeedingRefresh(
      pricingMode: .offline,
      currentUsageDataScan: scan,
      cachedUsageDataFingerprints: [
        .claude: claudeFingerprint,
        .codex: codexFingerprint,
      ],
      cachedAgentData: cachedAgentData
    ) == [.codex],
    "offline refresh should only request agents with changed usage data"
  )

  try expect(
    UsageRefreshController.agentsNeedingRefresh(
      pricingMode: .offline,
      currentUsageDataScan: scan,
      cachedUsageDataFingerprints: [
        .claude: claudeFingerprint,
        .codex: changedCodexFingerprint,
      ],
      cachedAgentData: [.claude: cachedAgentData[.claude]!]
    ) == [.codex],
    "offline refresh should request agents missing cached data"
  )

  try expect(
    UsageRefreshController.agentsNeedingRefresh(
      pricingMode: .online,
      currentUsageDataScan: scan,
      cachedUsageDataFingerprints: [
        .claude: claudeFingerprint,
        .codex: changedCodexFingerprint,
      ],
      cachedAgentData: cachedAgentData
    ) == AgentKind.allCases,
    "online refresh should request all agents because pricing may change"
  )
}

private func testApplySuccess() throws {
  let now = Calendar.current.date(
    from: DateComponents(year: 2026, month: 4, day: 2, hour: 12, minute: 0, second: 0)
  )!
  let state = AppState(
    isRefreshing: true,
    agentSpendings: [],
    businessDays: 3,
    lastRefreshAt: nil,
    lastOnlinePricingRefreshAt: nil,
    lastError: "old error"
  )
  let snapshot = UsageSnapshot(agents: [
    AgentRawData(name: "Claude Code", found: true, today: 48.35, month: 208.12),
    AgentRawData(name: "Codex", found: false, today: 0, month: 0),
  ])

  let nextState = UsageRefreshController.applySuccess(
    snapshot: snapshot,
    pricingMode: .online,
    lastUsageDetectedAtByAgent: [.claude: now.addingTimeInterval(-60)],
    to: state,
    now: now
  )

  let claude = nextState.agentSpendings.first(where: { $0.name == "Claude Code" })
  let codex = nextState.agentSpendings.first(where: { $0.name == "Codex" })

  try expect(!nextState.isRefreshing, "successful refresh should clear refreshing state")
  try expect(nextState.lastRefreshAt == now, "successful refresh should update last refresh time")
  try expect(claude?.todayCost == 48.35, "successful refresh should update today cost")
  try expect(claude?.monthCost == 208.12, "successful refresh should update month cost")
  try expect(nextState.businessDays == 2, "successful refresh should recompute business days")
  try expectNear(claude?.avgPerDay ?? 0, 104.06, "successful refresh should recompute average")
  try expect(
    claude?.lastUsageDetectedAt == now.addingTimeInterval(-60),
    "successful refresh should map last usage detection time onto the agent"
  )
  try expect(codex?.isInstalled == false, "not-installed agent should be reflected in state")
  try expect(
    nextState.lastOnlinePricingRefreshAt == now,
    "online refresh should update last online pricing refresh time"
  )
  try expect(nextState.lastError == nil, "successful refresh should clear the previous error")
}

private func testApplyFailure() throws {
  let now = Date(timeIntervalSinceReferenceDate: 3_000)
  let spending = AgentSpending(
    name: "Claude Code", isInstalled: true, todayCost: 48.35, monthCost: 208.12, avgPerDay: 52.03)
  let state = AppState(
    isRefreshing: true,
    agentSpendings: [spending],
    businessDays: 4,
    lastRefreshAt: Date(timeIntervalSinceReferenceDate: 2_500),
    lastOnlinePricingRefreshAt: Date(timeIntervalSinceReferenceDate: 2_400),
    lastError: nil
  )

  let nextState = UsageRefreshController.applyFailure(
    error: FakeRefreshError(),
    to: state,
    now: now
  )

  let claude = nextState.agentSpendings.first(where: { $0.name == "Claude Code" })

  try expect(!nextState.isRefreshing, "failed refresh should clear refreshing state")
  try expect(
    nextState.lastRefreshAt == now, "failed refresh should record when the failure happened")
  try expect(nextState.lastError == "helper timed out", "failed refresh should surface the error")
  try expect(claude?.todayCost == 48.35, "failed refresh should preserve cached today cost")
  try expect(claude?.monthCost == 208.12, "failed refresh should preserve cached month cost")
}
