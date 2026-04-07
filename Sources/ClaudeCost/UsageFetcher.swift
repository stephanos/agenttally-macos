import Foundation

private final class ProcessCompletionState: @unchecked Sendable {
  private let lock = NSLock()
  private var hasResumed = false

  func tryMarkResumed() -> Bool {
    lock.lock()
    defer { lock.unlock() }

    guard !hasResumed else {
      return false
    }

    hasResumed = true
    return true
  }
}

struct UsagePayload: Codable {
  let today: Double
  let month: Double
}

public struct UsageSnapshot: Sendable {
  public let today: Double
  public let month: Double

  public init(today: Double, month: Double) {
    self.today = today
    self.month = month
  }
}

enum UsageFetcherError: LocalizedError {
  case failedToStart
  case helperNotFound
  case timedOut(String)
  case emptyOutput(String)
  case commandFailed(String, String)
  case invalidResponse(String)

  var errorDescription: String? {
    switch self {
    case .failedToStart:
      return "failed to start task"
    case .helperNotFound:
      return "usage helper not found"
    case .timedOut(let path):
      return "timed out waiting for \(path)"
    case .emptyOutput(let path):
      return "empty output from \(path)"
    case .commandFailed(let path, let message):
      if message.isEmpty {
        return "command failed: \(path)"
      }
      return "\(path): \(message)"
    case .invalidResponse(let message):
      return message
    }
  }
}

enum UsageFetcher {
  private static let helperTimeout: TimeInterval = 30

  static func fetchUsage() async throws -> UsageSnapshot {
    let monthStart = currentMonthStartString()
    let helperURL = try usageHelperURL()

    let output = try await runHelper(at: helperURL, arguments: [monthStart])
    return try UsagePayloadParser.decodeSnapshot(from: output)
  }

  static func shouldTimeOut(processIsRunning: Bool) -> Bool {
    processIsRunning
  }

  private static func usageHelperURL() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CLAUDECOST_HELPER_PATH"],
      !override.isEmpty
    {
      let url = URL(fileURLWithPath: override).standardizedFileURL
      if FileManager.default.isExecutableFile(atPath: url.path) {
        return url
      }
    }

    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let executableDirectory = executableURL.deletingLastPathComponent()
    let candidates = [
      executableDirectory.appendingPathComponent("claudecost-usage-helper"),
      executableDirectory.deletingLastPathComponent().appendingPathComponent(
        "claudecost-usage-helper"),
    ]

    for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
      return candidate
    }

    throw UsageFetcherError.helperNotFound
  }

  private static func runHelper(at helperURL: URL, arguments: [String]) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      let stdout = Pipe()
      let stderr = Pipe()
      let completionState = ProcessCompletionState()

      @Sendable func resumeOnce(with result: Result<Data, Error>) {
        guard completionState.tryMarkResumed() else {
          return
        }
        continuation.resume(with: result)
      }

      process.executableURL = helperURL
      process.arguments = arguments
      process.standardOutput = stdout
      process.standardError = stderr

      process.terminationHandler = { process in
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stderrString =
          String(data: stderrData, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
          resumeOnce(
            with: .failure(UsageFetcherError.commandFailed(helperURL.path, stderrString))
          )
          return
        }

        guard !stdoutData.isEmpty else {
          resumeOnce(with: .failure(UsageFetcherError.emptyOutput(helperURL.path)))
          return
        }

        resumeOnce(with: .success(stdoutData))
      }

      do {
        try process.run()
      } catch {
        resumeOnce(with: .failure(UsageFetcherError.failedToStart))
        return
      }

      DispatchQueue.global().asyncAfter(deadline: .now() + helperTimeout) {
        guard shouldTimeOut(processIsRunning: process.isRunning) else {
          return
        }

        process.terminate()
        resumeOnce(with: .failure(UsageFetcherError.timedOut(helperURL.path)))
      }
    }
  }

  private static func currentMonthStartString(now: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyyMM"
    return "\(formatter.string(from: now))01"
  }
}
