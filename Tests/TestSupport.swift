import Foundation

struct TestFailure: Error, CustomStringConvertible {
  let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  guard condition() else {
    throw TestFailure(description: message)
  }
}

func expectNear(
  _ actual: Double, _ expected: Double, tolerance: Double = 0.000_001, _ message: String
)
  throws
{
  try expect(abs(actual - expected) <= tolerance, message)
}

func waitFor<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
  let semaphore = DispatchSemaphore(value: 0)
  var result: Result<T, Error>!

  Task {
    do {
      result = .success(try await operation())
    } catch {
      result = .failure(error)
    }
    semaphore.signal()
  }

  semaphore.wait()
  return try result.get()
}

func makeTemporaryDirectory() throws -> URL {
  let url = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("agenttally-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

func writeTestFile(_ url: URL, contents: String, modifiedAt: TimeInterval) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try Data(contents.utf8).write(to: url)
  try FileManager.default.setAttributes(
    [.modificationDate: Date(timeIntervalSince1970: modifiedAt)],
    ofItemAtPath: url.path
  )
}

func sameByteCountInvalidJSON(as contents: String) -> String {
  String(repeating: "x", count: contents.utf8.count)
}
