import Foundation
import ClosedLidModeCore

/// Remembers the auto-off preferences between launches.
struct Settings {
    var autoOff: AutoOffSettings

    private enum Key {
        static let monitor = "autoOff.whenMonitorDisconnected"
        static let threshold = "autoOff.batteryThreshold"   // -1 means disabled
    }

    static func load() -> Settings {
        let defaults = UserDefaults.standard
        // Both rules default to on: the failure they prevent (a Mac left awake
        // in a bag) is worse than the inconvenience of them firing.
        defaults.register(defaults: [Key.monitor: true, Key.threshold: 20])
        let threshold = defaults.integer(forKey: Key.threshold)
        return Settings(autoOff: AutoOffSettings(
            whenMonitorDisconnected: defaults.bool(forKey: Key.monitor),
            batteryThreshold: threshold < 0 ? nil : threshold))
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(autoOff.whenMonitorDisconnected, forKey: Key.monitor)
        defaults.set(autoOff.batteryThreshold ?? -1, forKey: Key.threshold)
    }
}
