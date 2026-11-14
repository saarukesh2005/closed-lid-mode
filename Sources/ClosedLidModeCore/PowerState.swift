import Foundation

/// A snapshot of everything the app needs to decide what to show and whether
/// to switch itself off.
public struct PowerState: Equatable, Sendable {
    /// Closed-Lid Mode itself: is sleep currently disabled?
    public let modeIsOn: Bool
    /// Is a display other than the built-in panel attached?
    public let externalDisplayConnected: Bool
    /// Running on battery rather than mains.
    public let onBattery: Bool
    /// 0-100, or nil when it could not be read.
    public let batteryPercent: Int?

    public init(modeIsOn: Bool,
                externalDisplayConnected: Bool,
                onBattery: Bool,
                batteryPercent: Int?) {
        self.modeIsOn = modeIsOn
        self.externalDisplayConnected = externalDisplayConnected
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
    }
}

/// When the app should switch the mode off without being asked.
public struct AutoOffSettings: Equatable, Sendable {
    public var whenMonitorDisconnected: Bool
    /// Switch off at or below this percentage while on battery. nil disables.
    public var batteryThreshold: Int?

    public init(whenMonitorDisconnected: Bool = true, batteryThreshold: Int? = 20) {
        self.whenMonitorDisconnected = whenMonitorDisconnected
        self.batteryThreshold = batteryThreshold
    }

    public static let `default` = AutoOffSettings()
}

public enum AutoOffReason: Equatable, Sendable {
    case monitorDisconnected
    case batteryBelow(Int)

    /// Wording shown to the user, in the app's plain-language voice.
    public var explanation: String {
        switch self {
        case .monitorDisconnected:
            return "the external monitor was unplugged"
        case .batteryBelow(let percent):
            return "the battery dropped to \(percent)%"
        }
    }
}

/// Why the menu bar should show a warning even though nothing was changed.
public enum RiskWarning: Equatable, Sendable {
    case onWithoutMonitor
    case onAndDischarging
    /// Auto-off wanted to fire and was not permitted to. The most dangerous
    /// state there is: the app knows the Mac should not be awake, and cannot
    /// do anything about it. It must never look calm.
    case couldNotSwitchOff(AutoOffReason)

    public var summary: String {
        switch self {
        case .onWithoutMonitor:
            return "ON with no monitor attached - the Mac cannot sleep"
        case .onAndDischarging:
            return "ON and on battery - the Mac cannot sleep"
        case .couldNotSwitchOff(let reason):
            return "should have switched off (\(reason.explanation)) but is not allowed to"
        }
    }
}
