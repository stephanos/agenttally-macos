import Foundation

@main
struct TestHarness {
  static func main() throws {
    let tests: [(String, () throws -> Void)] = [
      ("StatusPresenter", testStatusPresenter),
      ("UsageRefreshController", testUsageRefreshController),
      ("UsageFetcher", testUsageFetcherTimeoutDecision),
      ("UsagePayloadParser", testUsagePayloadParser),
      ("TimeUtils", testTimeUtils),
      ("MenuRowsBuilder", testMenuRowsBuilder),
      ("LoginItemManager", testLoginItemManager),
    ]

    var failures: [String] = []

    for (name, test) in tests {
      do {
        try test()
        print("PASS \(name)")
      } catch {
        failures.append("FAIL \(name): \(error)")
      }
    }

    if failures.isEmpty {
      print("All tests passed")
    } else {
      for failure in failures {
        print(failure)
      }
      exit(1)
    }
  }
}
