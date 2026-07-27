import CryptoKit
import Foundation

struct UsageFileSummaryCache: Sendable {
  var claude = ClaudeUsageFileSummaryCache()
  var codex = CodexUsageFileSummaryCache()
}

struct UsageFileIdentity: Equatable, Sendable {
  let size: Int64
  let modificationTime: TimeInterval
  let pricingFingerprint: String
}

struct ClaudeUsageFileSummaryCache: Sendable {
  var files: [String: ClaudeUsageFileSummary] = [:]
}

struct ClaudeUsageFileSummary: Equatable, Sendable {
  let identity: UsageFileIdentity
  let records: [ClaudeUsageRecord]
}

struct ClaudeUsageRecord: Equatable, Sendable {
  let dedupeKey: String
  let localDate: String
  let cost: Double
}

struct CodexUsageFileSummaryCache: Sendable {
  var files: [String: CodexUsageFileSummary] = [:]
}

struct CodexUsageFileSummary: Equatable, Sendable {
  let identity: UsageFileIdentity
  // Cost per turn, keyed by the turn's id. A turn's events can be replayed into
  // forked/resumed session files, so aggregation deduplicates on the turn id.
  let turnCosts: [String: CodexTurnCost]
  // Cost for token_count events that lack a turn id, keyed by local day. These
  // cannot be deduplicated, but are negligible in practice.
  let untrackedCostsByDate: [String: Double]
  let parserState: CodexUsageParserState
}

struct CodexTurnCost: Equatable, Sendable {
  // Local day derived from the turn id's UUIDv7 timestamp (the turn's true
  // creation time), so replayed turns keep their original day rather than the
  // restamped timestamp of the fork.
  let localDay: String
  var cost: Double
}

struct CodexUsageParserState: Equatable, Sendable {
  let currentModel: String?
  let currentTurnId: String?
  let previousTotals: CodexTokenTotals?

  static let empty = CodexUsageParserState(
    currentModel: nil,
    currentTurnId: nil,
    previousTotals: nil
  )
}

struct CodexTokenTotals: Equatable, Sendable {
  let inputTokens: Int
  let cachedInputTokens: Int
  let outputTokens: Int
}

enum UsageFileCacheKey {
  static func path(for fileURL: URL) -> String {
    fileURL.standardizedFileURL.path
  }

  static func identity(
    for fileURL: URL,
    pricingFingerprint: String,
    fileManager: FileManager = .default
  ) -> UsageFileIdentity? {
    guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path) else {
      return nil
    }

    return UsageFileIdentity(
      size: (attributes[.size] as? NSNumber)?.int64Value ?? -1,
      modificationTime: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1,
      pricingFingerprint: pricingFingerprint
    )
  }
}

enum UsagePricingFingerprint {
  static func make(for pricing: [String: ModelPricing]) -> String {
    let manifest = pricing.keys.sorted().map { key in
      let value = pricing[key]!
      return [
        key,
        value.inputCostPerToken.description,
        value.outputCostPerToken.description,
        value.cacheCreationInputTokenCost?.description ?? "",
        value.cacheReadInputTokenCost?.description ?? "",
        value.inputCostPerTokenAbove200kTokens?.description ?? "",
        value.outputCostPerTokenAbove200kTokens?.description ?? "",
        value.cacheCreationInputTokenCostAbove200kTokens?.description ?? "",
        value.cacheReadInputTokenCostAbove200kTokens?.description ?? "",
      ].joined(separator: "|")
    }.joined(separator: "\n")
    let digest = SHA256.hash(data: Data(manifest.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
