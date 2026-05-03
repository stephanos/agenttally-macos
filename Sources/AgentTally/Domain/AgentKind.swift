import Foundation

public enum AgentKind: String, CaseIterable, Sendable {
  case claude
  case codex

  public var displayName: String {
    switch self {
    case .claude:
      return "Claude Code"
    case .codex:
      return "Codex"
    }
  }

  public var abbreviation: String {
    switch self {
    case .claude:
      return "CC"
    case .codex:
      return "CX"
    }
  }

  var helperArgument: String {
    rawValue
  }

  init?(displayName: String) {
    switch displayName {
    case AgentKind.claude.displayName:
      self = .claude
    case AgentKind.codex.displayName:
      self = .codex
    default:
      return nil
    }
  }
}
