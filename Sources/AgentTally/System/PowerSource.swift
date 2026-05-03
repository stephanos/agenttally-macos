import Foundation
import IOKit.ps

enum PowerSource {
  static func isOnBatteryPower() -> Bool {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let powerSource = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
    else {
      return false
    }

    return powerSource == kIOPSBatteryPowerValue
  }
}
