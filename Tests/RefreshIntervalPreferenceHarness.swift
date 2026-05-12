import Foundation

func testRefreshIntervalPreference() throws {
  try testRefreshIntervalPreferenceDefaultsToOneMinute()
  try testRefreshIntervalPreferenceLoadsStoredValue()
  try testRefreshIntervalPreferenceFallsBackFromInvalidValue()
  try testRefreshIntervalOptionProvidesTimerTolerance()
}

private func testRefreshIntervalPreferenceDefaultsToOneMinute() throws {
  let defaultsName = "AgentTallyRefreshInterval.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: defaultsName)!
  defaults.removePersistentDomain(forName: defaultsName)

  let preference = RefreshIntervalPreference(
    defaultsKey: "refreshIntervalSeconds",
    defaults: defaults
  )

  try expect(
    preference.selectedInterval() == .oneMinute,
    "missing preference should default to one minute"
  )
  try expect(
    defaults.integer(forKey: "refreshIntervalSeconds")
      == RefreshIntervalOption.oneMinute.rawValue,
    "default interval should be persisted on first read"
  )
}

private func testRefreshIntervalPreferenceLoadsStoredValue() throws {
  let defaultsName = "AgentTallyRefreshInterval.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: defaultsName)!
  defaults.removePersistentDomain(forName: defaultsName)
  defaults.set(RefreshIntervalOption.fiveMinutes.rawValue, forKey: "refreshIntervalSeconds")

  let preference = RefreshIntervalPreference(
    defaultsKey: "refreshIntervalSeconds",
    defaults: defaults
  )

  try expect(
    preference.selectedInterval() == .fiveMinutes,
    "stored interval should be returned"
  )
}

private func testRefreshIntervalPreferenceFallsBackFromInvalidValue() throws {
  let defaultsName = "AgentTallyRefreshInterval.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: defaultsName)!
  defaults.removePersistentDomain(forName: defaultsName)
  defaults.set(999, forKey: "refreshIntervalSeconds")

  let preference = RefreshIntervalPreference(
    defaultsKey: "refreshIntervalSeconds",
    defaults: defaults
  )

  try expect(
    preference.selectedInterval() == .oneMinute,
    "invalid stored values should fall back to one minute"
  )
  try expect(
    defaults.integer(forKey: "refreshIntervalSeconds")
      == RefreshIntervalOption.oneMinute.rawValue,
    "invalid stored values should be repaired to the default"
  )
}

private func testRefreshIntervalOptionProvidesTimerTolerance() throws {
  try expect(
    RefreshIntervalOption.oneMinute.timerTolerance == 6,
    "one-minute refreshes should allow a small timer tolerance"
  )
  try expect(
    RefreshIntervalOption.fiveMinutes.timerTolerance == 30,
    "five-minute refreshes should allow macOS to coalesce timer wakeups"
  )
}
