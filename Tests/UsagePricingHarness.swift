import Foundation

func testUsagePricing() throws {
  try testLoadSharedPricingUsesFreshCache()
  try testLoadSharedPricingRefreshesOnlineEvenWithFreshCache()
  try testLoadSharedPricingFallsBackToFreshCacheWhenForcedRefreshFails()
  try testLoadSharedPricingFallsBackToBundledOffline()
  try testBundledPricingIncludesCurrentFallbackModels()
  try testLookupPricingMatchesAliasesAndProviders()
  try testLookupPricingFallsBackToFuzzyMatch()
  try testCalculateClaudeCostHandlesTieredAndCacheTokens()
  try testCalculateCodexCostUsesCachedInputRate()
}

private func testLoadSharedPricingUsesFreshCache() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let cacheURL =
    homeDirectory
    .appendingPathComponent(".cache")
    .appendingPathComponent("agenttally")
    .appendingPathComponent("litellm-pricing.json")

  try FileManager.default.createDirectory(
    at: cacheURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )

  let cached = PricingCacheFile(
    fetchedAt: Date(timeIntervalSince1970: 10_000),
    pricing: [
      "claude-sonnet-4-20250514": ModelPricing(
        inputCostPerToken: 0.1,
        outputCostPerToken: 0.2,
        cacheCreationInputTokenCost: nil,
        cacheReadInputTokenCost: nil,
        inputCostPerTokenAbove200kTokens: nil,
        outputCostPerTokenAbove200kTokens: nil,
        cacheCreationInputTokenCostAbove200kTokens: nil,
        cacheReadInputTokenCostAbove200kTokens: nil
      )
    ]
  )
  try JSONEncoder().encode(cached).write(to: cacheURL)

  let pricing = try waitFor {
    try await UsagePricingStore.loadSharedPricing(
      offline: false,
      context: UsageTrackingContext(
        environment: [:],
        homeDirectory: homeDirectory,
        now: Date(timeIntervalSince1970: 10_100),
        pricingDataLoader: { _ in throw TestFailure(description: "network should not be used") }
      )
    )
  }

  try expect(
    pricing["claude-sonnet-4-20250514"]?.inputCostPerToken == 0.1,
    "fresh cache should win"
  )
}

private func testLoadSharedPricingFallsBackToBundledOffline() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let pricing = try waitFor {
    try await UsagePricingStore.loadSharedPricing(
      offline: true,
      context: UsageTrackingContext(
        environment: [:],
        homeDirectory: homeDirectory,
        now: Date(timeIntervalSince1970: 20_000),
        pricingDataLoader: { _ in throw TestFailure(description: "offline should not hit network") }
      )
    )
  }

  try expect(
    pricing["claude-sonnet-4-20250514"] != nil,
    "offline pricing should fall back to bundled entries"
  )
}

private func testBundledPricingIncludesCurrentFallbackModels() throws {
  try expect(
    UsagePricing.bundled["claude-3-5-haiku-20241022"] != nil,
    "bundled pricing should retain Claude 3.5 Haiku"
  )
  try expect(
    UsagePricing.bundled["claude-opus-4-20250514"] != nil,
    "bundled pricing should retain Claude Opus 4"
  )
  try expect(
    UsagePricing.bundled["gpt-5-mini"] != nil,
    "bundled pricing should retain GPT-5 mini"
  )
  try expect(
    UsagePricing.bundled["gpt-5.2-codex"] != nil,
    "bundled pricing should retain GPT-5.2 Codex"
  )
  try expect(
    UsagePricing.bundled["gpt-5.5"] != nil,
    "bundled pricing should retain GPT-5.5"
  )
}

private func testLookupPricingMatchesAliasesAndProviders() throws {
  let pricing: [String: ModelPricing] = [
    "gpt-5": ModelPricing(
      inputCostPerToken: 1,
      outputCostPerToken: 2,
      cacheCreationInputTokenCost: nil,
      cacheReadInputTokenCost: 0.5,
      inputCostPerTokenAbove200kTokens: nil,
      outputCostPerTokenAbove200kTokens: nil,
      cacheCreationInputTokenCostAbove200kTokens: nil,
      cacheReadInputTokenCostAbove200kTokens: nil
    )
  ]

  let resolved = UsagePricing.lookupPricing(
    modelName: "openai/gpt-5-codex",
    pricing: pricing,
    providerPrefixes: ["openai/"],
    aliases: ["gpt-5-codex": "gpt-5"]
  )

  try expect(resolved?.outputCostPerToken == 2, "alias and provider prefix should resolve pricing")
}

private func testLookupPricingFallsBackToFuzzyMatch() throws {
  let pricing: [String: ModelPricing] = [
    "claude-sonnet-4-20250514": ModelPricing(
      inputCostPerToken: 1,
      outputCostPerToken: 2,
      cacheCreationInputTokenCost: nil,
      cacheReadInputTokenCost: nil,
      inputCostPerTokenAbove200kTokens: nil,
      outputCostPerTokenAbove200kTokens: nil,
      cacheCreationInputTokenCostAbove200kTokens: nil,
      cacheReadInputTokenCostAbove200kTokens: nil
    )
  ]

  let resolved = UsagePricing.lookupPricing(
    modelName: "anthropic/claude-sonnet-4-20250514-latest",
    pricing: pricing,
    providerPrefixes: ["anthropic/"]
  )

  try expect(
    resolved?.outputCostPerToken == 2,
    "fuzzy matching should resolve near-equal model names"
  )
}

private func testCalculateClaudeCostHandlesTieredAndCacheTokens() throws {
  let pricing = ModelPricing(
    inputCostPerToken: 1,
    outputCostPerToken: 10,
    cacheCreationInputTokenCost: 2,
    cacheReadInputTokenCost: 0.5,
    inputCostPerTokenAbove200kTokens: 3,
    outputCostPerTokenAbove200kTokens: nil,
    cacheCreationInputTokenCostAbove200kTokens: nil,
    cacheReadInputTokenCostAbove200kTokens: nil
  )

  let cost = UsagePricing.calculateClaudeCost(
    inputTokens: 200_001,
    outputTokens: 2,
    cacheCreationInputTokens: 3,
    cacheReadInputTokens: 4,
    pricing: pricing
  )

  let expectedCost = 200_000.0 * 1.0 + 1.0 * 3.0 + 2.0 * 10.0 + 3.0 * 2.0 + 4.0 * 0.5
  try expectNear(cost, expectedCost, "Claude pricing should include tiered and cache token rates")
}

private func testCalculateCodexCostUsesCachedInputRate() throws {
  let pricing = ModelPricing(
    inputCostPerToken: 1,
    outputCostPerToken: 10,
    cacheCreationInputTokenCost: nil,
    cacheReadInputTokenCost: 0.25,
    inputCostPerTokenAbove200kTokens: nil,
    outputCostPerTokenAbove200kTokens: nil,
    cacheCreationInputTokenCostAbove200kTokens: nil,
    cacheReadInputTokenCostAbove200kTokens: nil
  )

  let cost = UsagePricing.calculateCodexCost(
    inputTokens: 100,
    cachedInputTokens: 25,
    outputTokens: 3,
    pricing: pricing
  )

  let expectedCost = 75.0 * 1.0 + 25.0 * 0.25 + 3.0 * 10.0
  try expectNear(cost, expectedCost, "Codex pricing should discount cached input tokens")
}

private func testLoadSharedPricingRefreshesOnlineEvenWithFreshCache() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let cacheURL =
    homeDirectory
    .appendingPathComponent(".cache")
    .appendingPathComponent("agenttally")
    .appendingPathComponent("litellm-pricing.json")

  try FileManager.default.createDirectory(
    at: cacheURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )

  let cached = PricingCacheFile(
    fetchedAt: Date(timeIntervalSince1970: 10_000),
    pricing: [
      "claude-sonnet-4-20250514": ModelPricing(
        inputCostPerToken: 0.1,
        outputCostPerToken: 0.2,
        cacheCreationInputTokenCost: nil,
        cacheReadInputTokenCost: nil,
        inputCostPerTokenAbove200kTokens: nil,
        outputCostPerTokenAbove200kTokens: nil,
        cacheCreationInputTokenCostAbove200kTokens: nil,
        cacheReadInputTokenCostAbove200kTokens: nil
      )
    ]
  )
  try JSONEncoder().encode(cached).write(to: cacheURL)

  let pricing = try waitFor {
    try await UsagePricingStore.loadSharedPricing(
      offline: false,
      refreshIfPossible: true,
      context: UsageTrackingContext(
        environment: [:],
        homeDirectory: homeDirectory,
        now: Date(timeIntervalSince1970: 10_100),
        pricingDataLoader: { _ in
          Data(
            #"{"claude-sonnet-4-20250514":{"input_cost_per_token":0.3,"output_cost_per_token":0.4}}"#
              .utf8
          )
        }
      )
    )
  }

  try expect(
    pricing["claude-sonnet-4-20250514"]?.inputCostPerToken == 0.3,
    "forced online refresh should replace a still-fresh cache"
  )
}

private func testLoadSharedPricingFallsBackToFreshCacheWhenForcedRefreshFails() throws {
  let homeDirectory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: homeDirectory) }

  let cacheURL =
    homeDirectory
    .appendingPathComponent(".cache")
    .appendingPathComponent("agenttally")
    .appendingPathComponent("litellm-pricing.json")

  try FileManager.default.createDirectory(
    at: cacheURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )

  let cached = PricingCacheFile(
    fetchedAt: Date(timeIntervalSince1970: 10_000),
    pricing: [
      "claude-sonnet-4-20250514": ModelPricing(
        inputCostPerToken: 0.1,
        outputCostPerToken: 0.2,
        cacheCreationInputTokenCost: nil,
        cacheReadInputTokenCost: nil,
        inputCostPerTokenAbove200kTokens: nil,
        outputCostPerTokenAbove200kTokens: nil,
        cacheCreationInputTokenCostAbove200kTokens: nil,
        cacheReadInputTokenCostAbove200kTokens: nil
      )
    ]
  )
  try JSONEncoder().encode(cached).write(to: cacheURL)

  let pricing = try waitFor {
    try await UsagePricingStore.loadSharedPricing(
      offline: false,
      refreshIfPossible: true,
      context: UsageTrackingContext(
        environment: [:],
        homeDirectory: homeDirectory,
        now: Date(timeIntervalSince1970: 10_100),
        pricingDataLoader: { _ in throw TestFailure(description: "network unavailable") }
      )
    )
  }

  try expect(
    pricing["claude-sonnet-4-20250514"]?.inputCostPerToken == 0.1,
    "forced online refresh should fall back to cache when the request fails"
  )
}
