import Foundation

func testUsageFetcherTimeoutDecision() throws {
  try expect(
    UsageFetcher.shouldTimeOut(processIsRunning: true),
    "running helper should trigger timeout handling"
  )
  try expect(
    !UsageFetcher.shouldTimeOut(processIsRunning: false),
    "completed helper should not trigger timeout handling"
  )
}
