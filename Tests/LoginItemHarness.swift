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
