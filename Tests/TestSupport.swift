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
