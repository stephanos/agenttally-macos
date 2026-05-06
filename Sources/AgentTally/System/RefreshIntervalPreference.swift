import Foundation

public enum RefreshIntervalOption: Int, CaseIterable, Equatable, Sendable {
  case oneMinute = 60
  case twoMinutes = 120
  case fiveMinutes = 300
  case tenMinutes = 600

  public static let defaultValue: RefreshIntervalOption = .oneMinute

  public var duration: TimeInterval {
    TimeInterval(rawValue)
  }

  public var menuTitle: String {
    switch self {
    case .oneMinute:
      return "1 min"
    case .twoMinutes:
      return "2 min"
    case .fiveMinutes:
      return "5 min"
    case .tenMinutes:
      return "10 min"
    }
  }
}

public final class RefreshIntervalPreference {
  private let defaultsKey: String
  private let defaults: UserDefaults

  public init(
    defaultsKey: String = "refreshIntervalSeconds",
    defaults: UserDefaults = .standard
  ) {
    self.defaultsKey = defaultsKey
    self.defaults = defaults
  }

  public func selectedInterval() -> RefreshIntervalOption {
    if let storedValue = defaults.object(forKey: defaultsKey) as? Int,
      let option = RefreshIntervalOption(rawValue: storedValue)
    {
      return option
    }

    defaults.set(RefreshIntervalOption.defaultValue.rawValue, forKey: defaultsKey)
    return .defaultValue
  }

  public func setSelectedInterval(_ option: RefreshIntervalOption) {
    defaults.set(option.rawValue, forKey: defaultsKey)
  }
}
