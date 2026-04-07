import Foundation

func testUsagePayloadParser() throws {
  let output = Data(
    """
    [ccusage] WARN Fetching pricing
    {"today":48.35,"month":208.12}
    """.utf8)

  let snapshot = try UsagePayloadParser.decodeSnapshot(from: output)
  try expect(snapshot.today == 48.35, "today payload should decode")
  try expect(snapshot.month == 208.12, "month payload should decode")

  do {
    _ = try UsagePayloadParser.decodeSnapshot(from: Data("not json".utf8))
    throw TestFailure(description: "invalid payload should throw")
  } catch {}
}
