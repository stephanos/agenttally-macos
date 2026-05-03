import CryptoKit
import Foundation

public struct UsageDataFingerprint: Equatable, Sendable {
  public let value: String

  public init(value: String) {
    self.value = value
  }
}

public struct AgentUsageDataScan: Sendable {
  public let fingerprint: UsageDataFingerprint
  public let lastUsageDetectedAt: Date?

  public init(
    fingerprint: UsageDataFingerprint,
    lastUsageDetectedAt: Date?
  ) {
    self.fingerprint = fingerprint
    self.lastUsageDetectedAt = lastUsageDetectedAt
  }
}

public struct UsageDataScan: Sendable {
  public let agents: [AgentKind: AgentUsageDataScan]

  public init(agents: [AgentKind: AgentUsageDataScan]) {
    self.agents = agents
  }

  public var lastUsageDetectedAtByAgent: [AgentKind: Date] {
    var detectedAtByAgent: [AgentKind: Date] = [:]
    for (agent, scan) in agents {
      if let lastUsageDetectedAt = scan.lastUsageDetectedAt {
        detectedAtByAgent[agent] = lastUsageDetectedAt
      }
    }
    return detectedAtByAgent
  }
}

enum UsageDataScanner {
  private static let manifestVersion = "agenttally-usage-fingerprint-v1"
  private static let claudeProjectsDirectoryName = "projects"
  private static let codexSessionsDirectoryName = "sessions"

  private struct ScanContext {
    let monthStart: String
    let environment: [String: String]
    let homeDirectory: URL
    let fileManager: FileManager
  }

  private protocol UsageDataSource: Sendable {
    var agent: AgentKind { get }

    func appendManifest(
      to lines: inout [String],
      context: ScanContext
    ) -> Date?
  }

  private struct ClaudeUsageDataSource: UsageDataSource {
    let agent = AgentKind.claude

    func appendManifest(
      to lines: inout [String],
      context: ScanContext
    ) -> Date? {
      UsageDataScanner.appendClaudeManifest(
        to: &lines,
        environment: context.environment,
        homeDirectory: context.homeDirectory,
        fileManager: context.fileManager
      )
    }
  }

  private struct CodexUsageDataSource: UsageDataSource {
    let agent = AgentKind.codex

    func appendManifest(
      to lines: inout [String],
      context: ScanContext
    ) -> Date? {
      UsageDataScanner.appendCodexManifest(
        to: &lines,
        monthStart: context.monthStart,
        environment: context.environment,
        homeDirectory: context.homeDirectory,
        fileManager: context.fileManager
      )
    }
  }

  static func currentScan(
    now: Date = Date(),
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    fileManager: FileManager = .default,
    timeZone: TimeZone = .current
  ) -> UsageDataScan {
    makeScan(
      monthStart: monthStartString(now: now, timeZone: timeZone),
      today: localDayString(now: now, timeZone: timeZone),
      environment: environment,
      homeDirectory: homeDirectory,
      fileManager: fileManager,
      timeZone: timeZone
    )
  }

  static func makeScan(
    monthStart: String,
    today: String,
    environment: [String: String],
    homeDirectory: URL,
    fileManager: FileManager = .default,
    timeZone: TimeZone = .current
  ) -> UsageDataScan {
    let commonLines = [
      "version|\(manifestVersion)",
      "month-start|\(escape(monthStart))",
      "today|\(escape(today))",
      "time-zone|\(escape(timeZone.identifier))|\(timeZone.secondsFromGMT())",
    ]
    let context = ScanContext(
      monthStart: monthStart,
      environment: environment,
      homeDirectory: homeDirectory,
      fileManager: fileManager
    )

    let sources: [any UsageDataSource] = [
      ClaudeUsageDataSource(),
      CodexUsageDataSource(),
    ]
    var agentScans: [AgentKind: AgentUsageDataScan] = [:]

    for source in sources {
      var lines = commonLines
      let lastUsageDetectedAt = source.appendManifest(to: &lines, context: context)
      let manifest = lines.joined(separator: "\n")
      let digest = SHA256.hash(data: Data(manifest.utf8))
      let fingerprint = UsageDataFingerprint(
        value: digest.map { String(format: "%02x", $0) }.joined()
      )
      agentScans[source.agent] = AgentUsageDataScan(
        fingerprint: fingerprint,
        lastUsageDetectedAt: lastUsageDetectedAt
      )
    }

    return UsageDataScan(agents: agentScans)
  }

  private static func appendClaudeManifest(
    to lines: inout [String],
    environment: [String: String],
    homeDirectory: URL,
    fileManager: FileManager
  ) -> Date? {
    lines.append("claude-config-dir|\(escape(environment["CLAUDE_CONFIG_DIR"] ?? ""))")

    let projectsDirectories = claudeProjectsDirectories(
      environment: environment,
      homeDirectory: homeDirectory,
      fileManager: fileManager
    )
    if projectsDirectories.isEmpty {
      lines.append("claude|projects-missing")
      return nil
    }

    var latestUsageDetectedAt: Date?
    for projectsDirectory in projectsDirectories {
      let directoryLatestUsageDetectedAt = appendJSONLFileMetadata(
        under: projectsDirectory,
        scope: "claude",
        to: &lines,
        fileManager: fileManager
      )
      latestUsageDetectedAt = latest(
        latestUsageDetectedAt,
        directoryLatestUsageDetectedAt
      )
    }
    return latestUsageDetectedAt
  }

  private static func appendCodexManifest(
    to lines: inout [String],
    monthStart: String,
    environment: [String: String],
    homeDirectory: URL,
    fileManager: FileManager
  ) -> Date? {
    let codexHome = codexHomeDirectory(environment: environment, homeDirectory: homeDirectory)
    let sessionsDirectory = codexHome.appendingPathComponent(codexSessionsDirectoryName)
    let sinceDate =
      "\(monthStart.prefix(4))-\(monthStart.dropFirst(4).prefix(2))-\(monthStart.dropFirst(6).prefix(2))"

    lines.append("codex-home|\(escape(environment["CODEX_HOME"] ?? ""))")
    return appendJSONLFileMetadata(
      under: sessionsDirectory,
      scope: "codex",
      to: &lines,
      fileManager: fileManager
    ) { fileURL in
      guard let sessionDate = codexSessionDate(for: fileURL, sessionsDirectory: sessionsDirectory)
      else {
        return false
      }
      return sessionDate >= sinceDate
    }
  }

  private static func claudeProjectsDirectories(
    environment: [String: String],
    homeDirectory: URL,
    fileManager: FileManager
  ) -> [URL] {
    let envPaths = (environment["CLAUDE_CONFIG_DIR"] ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let candidateDirectories: [URL]
    if !envPaths.isEmpty {
      candidateDirectories = envPaths
        .split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .map { URL(fileURLWithPath: $0).standardizedFileURL }
    } else {
      candidateDirectories = [
        homeDirectory
          .appendingPathComponent(".config")
          .appendingPathComponent("claude"),
        homeDirectory.appendingPathComponent(".claude"),
      ].map { $0.standardizedFileURL }
    }

    var seen = Set<String>()
    var projectsDirectories: [URL] = []
    for directory in candidateDirectories {
      let normalizedDirectory = directory.standardizedFileURL
      let normalizedPath = normalizedDirectory.path
      let projectsDirectory = normalizedDirectory
        .appendingPathComponent(claudeProjectsDirectoryName)
        .standardizedFileURL

      guard !seen.contains(normalizedPath),
        isDirectory(normalizedDirectory, fileManager: fileManager),
        isDirectory(projectsDirectory, fileManager: fileManager)
      else {
        continue
      }

      seen.insert(normalizedPath)
      projectsDirectories.append(projectsDirectory)
    }

    return projectsDirectories
  }

  private static func codexHomeDirectory(
    environment: [String: String],
    homeDirectory: URL
  ) -> URL {
    if let override = environment["CODEX_HOME"] {
      return URL(fileURLWithPath: override.isEmpty ? "." : override).standardizedFileURL
    }

    return homeDirectory.appendingPathComponent(".codex").standardizedFileURL
  }

  private static func appendJSONLFileMetadata(
    under directory: URL,
    scope: String,
    to lines: inout [String],
    fileManager: FileManager,
    shouldInclude: (URL) -> Bool = { _ in true }
  ) -> Date? {
    let normalizedDirectory = directory.standardizedFileURL
    lines.append("\(scope)|directory|\(escape(normalizedDirectory.path))")

    guard isDirectory(normalizedDirectory, fileManager: fileManager) else {
      lines.append("\(scope)|directory-missing")
      return nil
    }

    guard
      let enumerator = fileManager.enumerator(
        at: normalizedDirectory,
        includingPropertiesForKeys: nil
      )
    else {
      lines.append("\(scope)|enumerator-missing")
      return nil
    }

    var fileCount = 0
    var totalSize: Int64 = 0
    var latestModificationTime: TimeInterval = -1
    var unreadableFileCount = 0

    for case let fileURL as URL in enumerator {
      guard fileURL.pathExtension == "jsonl", shouldInclude(fileURL) else {
        continue
      }

      guard
        let metadata = fileMetadata(
          for: fileURL.standardizedFileURL,
          fileManager: fileManager
        )
      else {
        unreadableFileCount += 1
        continue
      }

      fileCount += 1
      totalSize += metadata.size
      latestModificationTime = max(latestModificationTime, metadata.modificationTime)
    }

    lines.append("\(scope)|file-count|\(fileCount)")
    lines.append("\(scope)|total-size|\(totalSize)")
    lines.append("\(scope)|latest-mtime|\(latestModificationTime)")
    lines.append("\(scope)|unreadable-file-count|\(unreadableFileCount)")

    guard latestModificationTime >= 0 else {
      return nil
    }
    return Date(timeIntervalSince1970: latestModificationTime)
  }

  private static func fileMetadata(
    for fileURL: URL,
    fileManager: FileManager
  ) -> (size: Int64, modificationTime: TimeInterval)? {
    guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path) else {
      return nil
    }

    let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
    let modificationTime =
      (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
    return (size, modificationTime)
  }

  private static func latest(_ left: Date?, _ right: Date?) -> Date? {
    switch (left, right) {
    case (.none, .none):
      return nil
    case (.some(let date), .none), (.none, .some(let date)):
      return date
    case (.some(let leftDate), .some(let rightDate)):
      return max(leftDate, rightDate)
    }
  }

  private static func codexSessionDate(for fileURL: URL, sessionsDirectory: URL) -> String? {
    let sessionsPath = sessionsDirectory.standardizedFileURL.path
    let filePath = fileURL.standardizedFileURL.path
    let prefix = sessionsPath.hasSuffix("/") ? sessionsPath : "\(sessionsPath)/"

    guard filePath.hasPrefix(prefix) else {
      return nil
    }

    let relativePath = String(filePath.dropFirst(prefix.count))
    let components = relativePath.split(separator: "/").map(String.init)
    guard components.count == 4 else {
      return nil
    }

    let year = components[0]
    let month = components[1]
    let day = components[2]
    guard year.count == 4, month.count == 2, day.count == 2 else {
      return nil
    }

    return "\(year)-\(month)-\(day)"
  }

  private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private static func monthStartString(now: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyyMM"
    return "\(formatter.string(from: now))01"
  }

  private static func localDayString(now: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: now)
  }

  private static func escape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "|", with: "\\|")
  }
}
