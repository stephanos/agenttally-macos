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
  let costsByDate: [String: Double]
  let parserState: CodexUsageParserState
}

struct CodexUsageParserState: Equatable, Sendable {
  let currentModel: String?
  let previousTotals: CodexTokenTotals?

  static let empty = CodexUsageParserState(currentModel: nil, previousTotals: nil)
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
