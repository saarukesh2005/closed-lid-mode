import Foundation

/// Decides when Closed-Lid Mode should switch itself off, and when it should
/// merely warn.
///
/// The problem this exists to solve: the setting is system-wide and survives
/// reboots, so it is very easy to leave it on, walk away, and have the Mac
/// sit awake in a bag draining the battery. Leaving that to the user's memory
/// has already failed in practice.
public enum AutoOffPolicy {

    /// Returns why the mode should be switched off now, or nil to leave it be.
    public static func reasonToTurnOff(state: PowerState,
                                       settings: AutoOffSettings) -> AutoOffReason? {
        // Nothing to switch off.
        guard state.modeIsOn else { return nil }

        if settings.whenMonitorDisconnected && !state.externalDisplayConnected {
            return .monitorDisconnected
        }

        // Only meaningful on battery: plugged in, a low percentage is just a
        // battery that is still charging.
        if let threshold = settings.batteryThreshold,
           state.onBattery,
           let percent = state.batteryPercent,
           percent <= threshold {
            return .batteryBelow(threshold)
        }

        return nil
    }

    /// A warning to surface when the situation is risky but auto-off is not
    /// configured to act on it - so the user is never left unaware.
    public static func warning(state: PowerState,
                               settings: AutoOffSettings) -> RiskWarning? {
        guard state.modeIsOn else { return nil }
        // If auto-off will handle it, the warning would be redundant noise.
        guard reasonToTurnOff(state: state, settings: settings) == nil else { return nil }

        if !state.externalDisplayConnected { return .onWithoutMonitor }
        if state.onBattery { return .onAndDischarging }
        return nil
    }
}
