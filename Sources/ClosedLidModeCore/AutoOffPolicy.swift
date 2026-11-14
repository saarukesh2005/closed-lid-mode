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

    /// A warning to surface when the situation is risky, so the user is never
    /// left unaware.
    ///
    /// `canActUnattended` is what makes this honest. An earlier version
    /// suppressed the warning whenever auto-off *would* fire, without checking
    /// whether it *could*. With no permission to act, the app then sat showing
    /// a calm green indicator while the Mac was awake on battery with no
    /// monitor attached - precisely the situation it exists to catch.
    public static func warning(state: PowerState,
                               settings: AutoOffSettings,
                               canActUnattended: Bool) -> RiskWarning? {
        guard state.modeIsOn else { return nil }

        if let reason = reasonToTurnOff(state: state, settings: settings) {
            // It will be handled in a moment; saying nothing is correct.
            if canActUnattended { return nil }
            return .couldNotSwitchOff(reason)
        }

        // No rule covers this, but it is still worth flagging.
        if !state.externalDisplayConnected { return .onWithoutMonitor }
        if state.onBattery { return .onAndDischarging }
        return nil
    }
}
