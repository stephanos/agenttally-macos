import Foundation

func testJSONLLineReader() throws {
  try testJSONLLineReaderReadsChunkedAndUnterminatedLines()
}

private func testJSONLLineReaderReadsChunkedAndUnterminatedLines() throws {
  let directory = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }

  let longLine = String(repeating: "a", count: 70_000)
  let file = directory.appendingPathComponent("usage.jsonl")
  try writeTestFile(
    file,
    contents: "\n  first  \n\(longLine)\nlast",
    modifiedAt: 1_000
  )

  var lines: [String] = []
  JSONLLineReader.readLines(from: file) { line in
    lines.append(line)
  }

  try expect(
    lines == ["first", longLine, "last"],
    "line reader should trim lines, skip blanks, and read across chunk boundaries"
  )
}
