import Foundation

enum CodexPathResolver {
  static func resolveCodexHome(
    from environment: [String: String],
    homeDirectory: URL
  ) -> URL {
    guard let codexHomeEnv = environment["CODEX_HOME"],
      !codexHomeEnv.isEmpty
    else {
      // Default: ~/.codex
      return homeDirectory.appendingPathComponent(".codex")
    }

    // Use the provided path as-is
    return URL(fileURLWithPath: codexHomeEnv)
  }
}
