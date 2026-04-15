import Foundation

private final class FakeLoginItemService: LoginItemService {
  var status: StartAtLoginStatus
  var didRegister = false
  var registerError: Error?

  init(status: StartAtLoginStatus) {
    self.status = status
  }

  func register() throws {
    didRegister = true
    if let registerError {
      throw registerError
    }
    status = .enabled
  }

  func unregister() throws {
    status = .notRegistered
  }
}

private struct FakeError: Error, LocalizedError {
  let errorDescription: String? = "fake failure"
}

func testLoginItemManager() throws {
  try testConfigureOnLaunchDefaultsToEnabled()
  try testConfigureOnLaunchSuppressesTransientNotFound()
  try testSetEnabledAttemptsRegistrationFromNotFound()
  try testSetEnabledSurfacesRegistrationErrors()
}

private func testConfigureOnLaunchDefaultsToEnabled() throws {
  let defaultsName = "ClaudeCostTestHarness.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: defaultsName)!
  defaults.removePersistentDomain(forName: defaultsName)

  let service = FakeLoginItemService(status: .notRegistered)
  let manager = LoginItemManager(
    defaultsKey: "startAtLoginEnabled",
    defaults: defaults,
    service: service
  )

  let state = manager.configureOnLaunch()
  try expect(defaults.bool(forKey: "startAtLoginEnabled"), "first launch should default to enabled")
  try expect(service.didRegister, "first launch should register login item")
  try expect(state.status == .enabled, "configured state should become enabled")
}

private func testConfigureOnLaunchSuppressesTransientNotFound() throws {
  let defaultsName = "ClaudeCostTestHarness.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: defaultsName)!
  defaults.removePersistentDomain(forName: defaultsName)

  let service = FakeLoginItemService(status: .notFound)
  let manager = LoginItemManager(
    defaultsKey: "startAtLoginEnabled",
    defaults: defaults,
    service: service
  )

  let state = manager.configureOnLaunch()

  try expect(defaults.bool(forKey: "startAtLoginEnabled"), "first launch should still store preference")
  try expect(!service.didRegister, "launch should not attempt registration from transient notFound")
  try expect(state.status == .notRegistered, "transient notFound should be suppressed on launch")
  try expect(state.message == nil, "suppressed notFound should not show an error message")
}

private func testSetEnabledAttemptsRegistrationFromNotFound() throws {
  let defaultsName = "ClaudeCostTestHarness.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: defaultsName)!
  defaults.removePersistentDomain(forName: defaultsName)

  let service = FakeLoginItemService(status: .notFound)
  let manager = LoginItemManager(
    defaultsKey: "startAtLoginEnabled",
    defaults: defaults,
    service: service
  )

  let state = manager.setEnabled(true)

  try expect(defaults.bool(forKey: "startAtLoginEnabled"), "enabling should persist the preference")
  try expect(service.didRegister, "explicit enable should attempt registration")
  try expect(state.status == .enabled, "successful registration should enable start at login")
}

private func testSetEnabledSurfacesRegistrationErrors() throws {
  let defaultsName = "ClaudeCostTestHarness.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: defaultsName)!
  defaults.removePersistentDomain(forName: defaultsName)

  let failingService = FakeLoginItemService(status: .notRegistered)
  failingService.registerError = FakeError()
  let failingManager = LoginItemManager(
    defaultsKey: "startAtLoginEnabled",
    defaults: defaults,
    service: failingService
  )
  let failedState = failingManager.setEnabled(true)
  try expect(
    failedState.message == "Open at login unavailable: fake failure",
    "registration errors should surface"
  )
}
