import Foundation

struct ModelPricing: Codable, Equatable, Sendable {
  let inputCostPerToken: Double
  let outputCostPerToken: Double
  let cacheCreationInputTokenCost: Double?
  let cacheReadInputTokenCost: Double?
  let inputCostPerTokenAbove200kTokens: Double?
  let outputCostPerTokenAbove200kTokens: Double?
  let cacheCreationInputTokenCostAbove200kTokens: Double?
  let cacheReadInputTokenCostAbove200kTokens: Double?

  enum CodingKeys: String, CodingKey {
    case inputCostPerToken = "input_cost_per_token"
    case outputCostPerToken = "output_cost_per_token"
    case cacheCreationInputTokenCost = "cache_creation_input_token_cost"
    case cacheReadInputTokenCost = "cache_read_input_token_cost"
    case inputCostPerTokenAbove200kTokens = "input_cost_per_token_above_200k_tokens"
    case outputCostPerTokenAbove200kTokens = "output_cost_per_token_above_200k_tokens"
    case cacheCreationInputTokenCostAbove200kTokens =
      "cache_creation_input_token_cost_above_200k_tokens"
    case cacheReadInputTokenCostAbove200kTokens =
      "cache_read_input_token_cost_above_200k_tokens"
  }
}

struct PricingCacheFile: Codable, Equatable, Sendable {
  let fetchedAt: Date
  let pricing: [String: ModelPricing]
}

enum UsagePricing {
  static let bundled: [String: ModelPricing] = [
    "claude-3-5-haiku-20241022": ModelPricing(
      inputCostPerToken: 0.0000008,
      outputCostPerToken: 0.000004,
      cacheCreationInputTokenCost: nil,
      cacheReadInputTokenCost: nil,
      inputCostPerTokenAbove200kTokens: nil,
      outputCostPerTokenAbove200kTokens: nil,
      cacheCreationInputTokenCostAbove200kTokens: nil,
      cacheReadInputTokenCostAbove200kTokens: nil
    ),
    "claude-3-5-sonnet-20241022": ModelPricing(
      inputCostPerToken: 0.000003,
      outputCostPerToken: 0.000015,
      cacheCreationInputTokenCost: 0.00000375,
      cacheReadInputTokenCost: 0.0000003,
      inputCostPerTokenAbove200kTokens: nil,
      outputCostPerTokenAbove200kTokens: nil,
      cacheCreationInputTokenCostAbove200kTokens: nil,
      cacheReadInputTokenCostAbove200kTokens: nil
    ),
    "claude-3-7-sonnet-20250219": ModelPricing(
      inputCostPerToken: 0.000003,
      outputCostPerToken: 0.000015,
      cacheCreationInputTokenCost: 0.00000375,
      cacheReadInputTokenCost: 0.0000003,
      inputCostPerTokenAbove200kTokens: 0.000006,
      outputCostPerTokenAbove200kTokens: 0.0000225,
      cacheCreationInputTokenCostAbove200kTokens: 0.0000075,
      cacheReadInputTokenCostAbove200kTokens: 0.0000006
    ),
    "claude-sonnet-4-20250514": ModelPricing(
      inputCostPerToken: 0.000003,
      outputCostPerToken: 0.000015,
      cacheCreationInputTokenCost: 0.00000375,
      cacheReadInputTokenCost: 0.0000003,
      inputCostPerTokenAbove200kTokens: 0.000006,
      outputCostPerTokenAbove200kTokens: 0.0000225,
      cacheCreationInputTokenCostAbove200kTokens: 0.0000075,
      cacheReadInputTokenCostAbove200kTokens: 0.0000006
    ),
    "claude-opus-4-20250514": ModelPricing(
      inputCostPerToken: 0.000015,
      outputCostPerToken: 0.000075,
      cacheCreationInputTokenCost: 0.00001875,
      cacheReadInputTokenCost: 0.0000015,
      inputCostPerTokenAbove200kTokens: nil,
      outputCostPerTokenAbove200kTokens: nil,
      cacheCreationInputTokenCostAbove200kTokens: nil,
      cacheReadInputTokenCostAbove200kTokens: nil
    ),
    "gpt-5": ModelPricing(
      inputCostPerToken: 0.00000125,
      outputCostPerToken: 0.00001,
      cacheCreationInputTokenCost: nil,
      cacheReadInputTokenCost: 0.000000125,
      inputCostPerTokenAbove200kTokens: nil,
      outputCostPerTokenAbove200kTokens: nil,
      cacheCreationInputTokenCostAbove200kTokens: nil,
      cacheReadInputTokenCostAbove200kTokens: nil
    ),
    "gpt-5-mini": ModelPricing(
      inputCostPerToken: 0.00000025,
      outputCostPerToken: 0.000002,
      cacheCreationInputTokenCost: nil,
      cacheReadInputTokenCost: 0.000000025,
      inputCostPerTokenAbove200kTokens: nil,
      outputCostPerTokenAbove200kTokens: nil,
      cacheCreationInputTokenCostAbove200kTokens: nil,
      cacheReadInputTokenCostAbove200kTokens: nil
    ),
    "gpt-5.2-codex": ModelPricing(
      inputCostPerToken: 0.00000125,
      outputCostPerToken: 0.00001,
      cacheCreationInputTokenCost: nil,
      cacheReadInputTokenCost: 0.000000125,
      inputCostPerTokenAbove200kTokens: nil,
      outputCostPerTokenAbove200kTokens: nil,
      cacheCreationInputTokenCostAbove200kTokens: nil,
      cacheReadInputTokenCostAbove200kTokens: nil
    ),
    "gpt-5.5": ModelPricing(
      inputCostPerToken: 0.000005,
      outputCostPerToken: 0.00003,
      cacheCreationInputTokenCost: nil,
      cacheReadInputTokenCost: 0.0000005,
      inputCostPerTokenAbove200kTokens: nil,
      outputCostPerTokenAbove200kTokens: nil,
      cacheCreationInputTokenCostAbove200kTokens: nil,
      cacheReadInputTokenCostAbove200kTokens: nil
    ),
  ]

  static func lookupPricing(
    modelName: String,
    pricing: [String: ModelPricing],
    providerPrefixes: [String],
    aliases: [String: String] = [:]
  ) -> ModelPricing? {
    var candidates = Set([modelName])

    for prefix in providerPrefixes {
      if modelName.hasPrefix(prefix) {
        candidates.insert(String(modelName.dropFirst(prefix.count)))
      } else {
        candidates.insert("\(prefix)\(modelName)")
      }
    }

    for candidate in candidates {
      if let value = pricing[candidate] {
        return value
      }
      if let alias = aliases[candidate], let value = pricing[alias] {
        return value
      }
    }

    let lowercasedModelName = modelName.lowercased()
    for (candidate, value) in pricing {
      let lowercasedCandidate = candidate.lowercased()
      if lowercasedCandidate == lowercasedModelName
        || lowercasedCandidate.hasSuffix(lowercasedModelName)
        || lowercasedModelName.hasSuffix(lowercasedCandidate)
        || lowercasedCandidate.contains(lowercasedModelName)
        || lowercasedModelName.contains(lowercasedCandidate)
      {
        return value
      }
    }

    return nil
  }

  static func calculateTieredCost(
    tokenCount: Int,
    basePrice: Double?,
    tieredPrice: Double?
  ) -> Double {
    guard tokenCount > 0, let basePrice else {
      return 0
    }

    let threshold = 200_000
    guard tokenCount > threshold, let tieredPrice else {
      return Double(tokenCount) * basePrice
    }

    return Double(threshold) * basePrice + Double(tokenCount - threshold) * tieredPrice
  }

  static func calculateClaudeCost(
    inputTokens: Int,
    outputTokens: Int,
    cacheCreationInputTokens: Int,
    cacheReadInputTokens: Int,
    pricing: ModelPricing
  ) -> Double {
    calculateTieredCost(
      tokenCount: inputTokens,
      basePrice: pricing.inputCostPerToken,
      tieredPrice: pricing.inputCostPerTokenAbove200kTokens
    )
      + calculateTieredCost(
        tokenCount: outputTokens,
        basePrice: pricing.outputCostPerToken,
        tieredPrice: pricing.outputCostPerTokenAbove200kTokens
      )
      + calculateTieredCost(
        tokenCount: cacheCreationInputTokens,
        basePrice: pricing.cacheCreationInputTokenCost,
        tieredPrice: pricing.cacheCreationInputTokenCostAbove200kTokens
      )
      + calculateTieredCost(
        tokenCount: cacheReadInputTokens,
        basePrice: pricing.cacheReadInputTokenCost,
        tieredPrice: pricing.cacheReadInputTokenCostAbove200kTokens
      )
  }

  static func calculateCodexCost(
    inputTokens: Int,
    cachedInputTokens: Int,
    outputTokens: Int,
    pricing: ModelPricing
  ) -> Double {
    let cachedInput = min(cachedInputTokens, inputTokens)
    let nonCachedInput = inputTokens - cachedInput
    let cacheRate = pricing.cacheReadInputTokenCost ?? pricing.inputCostPerToken

    return Double(nonCachedInput) * pricing.inputCostPerToken
      + Double(cachedInput) * cacheRate
      + Double(outputTokens) * pricing.outputCostPerToken
  }
}
