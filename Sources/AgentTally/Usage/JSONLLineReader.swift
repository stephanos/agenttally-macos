import Foundation

enum JSONLLineReader {
  private static let chunkSize = 64 * 1024
  private static let newline = UInt8(ascii: "\n")

  static func readLines(from fileURL: URL, handleLine: (String) -> Void) {
    guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
      return
    }
    defer {
      try? fileHandle.close()
    }

    var pending = Data()
    while let chunk = try? fileHandle.read(upToCount: chunkSize), !chunk.isEmpty {
      pending.append(chunk)

      while let newlineIndex = pending.firstIndex(of: newline) {
        let lineData = pending[..<newlineIndex]
        emitLine(lineData, handleLine: handleLine)
        pending.removeSubrange(...newlineIndex)
      }
    }

    if !pending.isEmpty {
      emitLine(pending, handleLine: handleLine)
    }
  }

  private static func emitLine(_ lineData: Data.SubSequence, handleLine: (String) -> Void) {
    guard let line = String(data: Data(lineData), encoding: .utf8) else {
      return
    }

    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }

    handleLine(trimmed)
  }
}
