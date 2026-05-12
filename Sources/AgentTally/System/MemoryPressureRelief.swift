import Darwin

enum MemoryPressureRelief {
  @discardableResult
  static func relieve() -> Int {
    malloc_zone_pressure_relief(nil, 0)
  }
}
