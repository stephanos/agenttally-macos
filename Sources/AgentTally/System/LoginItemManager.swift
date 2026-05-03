import Foundation
import ServiceManagement

public enum StartAtLoginStatus: Equatable {
  case enabled
  case requiresApproval
  case notRegistered
  case notFound
  case unknown
}

public struct StartAtLoginViewState: Equatable {
  public let status: StartAtLoginStatus
  public let message: String?

  public var menuState: MenuCheckState {
    switch status {
    case .enabled:
      return .on
    case .requiresApproval:
      return .mixed
    case .notRegistered, .notFound, .unknown:
      return .off
    }
  }

  public static func make(status: StartAtLoginStatus, errorMessage: String? = nil)
    -> StartAtLoginViewState
  {
    if let errorMessage, !errorMessage.isEmpty {
      return StartAtLoginViewState(
        status: status,
        message: "Open at login unavailable: \(errorMessage)"
      )
    }

    switch status {
    case .enabled, .notRegistered:
      return StartAtLoginViewState(status: status, message: nil)
    case .requiresApproval:
      return StartAtLoginViewState(
        status: status,
        message: "Open at login pending approval in System Settings"
      )
    case .notFound:
      return StartAtLoginViewState(
        status: status,
        message: "Open at login unavailable for this app build"
      )
    case .unknown:
      return StartAtLoginViewState(status: status, message: "Open at login status unknown")
    }
  }
}

public protocol LoginItemService {
  var status: StartAtLoginStatus { get }
  func register() throws
  func unregister() throws
}

public struct MainAppLoginItemService: LoginItemService {
  public var status: StartAtLoginStatus {
    switch SMAppService.mainApp.status {
    case .enabled:
      return .enabled
    case .requiresApproval:
      return .requiresApproval
    case .notRegistered:
      return .notRegistered
    case .notFound:
      return .notFound
    @unknown default:
      return .unknown
    }
  }

  public init() {}

  public func register() throws {
    try SMAppService.mainApp.register()
  }

  public func unregister() throws {
    try SMAppService.mainApp.unregister()
  }
}

public final class LoginItemManager {
  private let defaultsKey: String
  private let defaults: UserDefaults
  private let service: any LoginItemService

  public init(
    defaultsKey: String = "startAtLoginEnabled",
    defaults: UserDefaults = .standard,
    service: any LoginItemService = MainAppLoginItemService()
  ) {
    self.defaultsKey = defaultsKey
    self.defaults = defaults
    self.service = service
  }

  public func configureOnLaunch() -> StartAtLoginViewState {
    let hasStoredPreference = defaults.object(forKey: defaultsKey) != nil
    let shouldStartAtLogin = hasStoredPreference ? defaults.bool(forKey: defaultsKey) : true
    let currentStatus = service.status

    if !hasStoredPreference {
      defaults.set(shouldStartAtLogin, forKey: defaultsKey)
    }

    if currentStatus == .notFound {
      return StartAtLoginViewState.make(status: .notRegistered)
    }

    return setEnabled(shouldStartAtLogin, persist: false)
  }

  public func setEnabled(_ shouldEnable: Bool, persist: Bool = true) -> StartAtLoginViewState {
    if persist {
      defaults.set(shouldEnable, forKey: defaultsKey)
    }

    do {
      let currentStatus = service.status

      switch (shouldEnable, currentStatus) {
      case (true, .enabled), (false, .notRegistered):
        break
      case (true, _):
        try service.register()
      case (false, _):
        try service.unregister()
      }

      return StartAtLoginViewState.make(status: service.status)
    } catch {
      return StartAtLoginViewState.make(
        status: service.status,
        errorMessage: error.localizedDescription
      )
    }
  }
}
