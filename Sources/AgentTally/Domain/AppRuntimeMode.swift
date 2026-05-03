import Foundation

public enum AppRuntimeMode: Equatable, Sendable {
  case live
  case demo

  public static func current(
    arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> AppRuntimeMode {
    if arguments.dropFirst().contains("--demo") {
      return .demo
    }

    return .live
  }
}
