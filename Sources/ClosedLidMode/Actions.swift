import AppKit
import ClosedLidModeCore

@MainActor
extension AppDelegate {

    // MARK: - the main switch

    @objc func toggleTapped() {
        let target = stateIsOn ? "0" : "1"

        // Touch ID when it is set up, otherwise the password dialog. Only one
        // prompt either way - sudo is attempted only when it can actually
        // succeed without a terminal.
        let result: Shell.AuthResult
        if PrivilegedSetup.touchIDEnabled || PrivilegedSetup.unattendedOffAllowed {
            if Shell.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", target]).code == 0 {
                result = .ok
            } else {
                result = Shell.runAsRoot("/usr/bin/pmset -a disablesleep \(target)")
            }
        } else {
            result = Shell.runAsRoot("/usr/bin/pmset -a disablesleep \(target)")
        }

        switch result {
        case .cancelled:
            return
        case .failed(let message):
            alert("Could not change the setting", message, style: .warning)
        case .ok:
            clearLastAutoOff()
        }
        // Give pmset a moment to settle before reading the value back.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self?.refreshNow()
        }
    }

    // MARK: - auto-off preferences

    @objc func toggleAutoOffMonitor() {
        mutateSettings { $0.autoOff.whenMonitorDisconnected.toggle() }
    }

    @objc func toggleAutoOffBattery() {
        mutateSettings { $0.autoOff.batteryThreshold = $0.autoOff.batteryThreshold == nil ? 20 : nil }
    }

    @objc func unattendedTapped() {
        if PrivilegedSetup.unattendedOffAllowed {
            handle(PrivilegedSetup.revokeUnattendedOff(),
                   failureTitle: "Could not remove the permission")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Let Closed-Lid Mode switch itself off"
        alert.informativeText = """
        Switching the setting off needs administrator rights. While you are \
        away from the Mac there is nobody to approve that, so the app can \
        currently only warn you - it cannot act.

        This adds one narrow permission: the app may turn the sleep override \
        OFF without asking. Turning it ON still requires your password or \
        fingerprint.

        So the worst this can do is make your Mac more willing to sleep. It \
        cannot keep it awake, and it grants nothing else.

        You can undo it from this menu at any time.
        """
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        handle(PrivilegedSetup.allowUnattendedOff(),
               failureTitle: "Could not add the permission")
    }

    // MARK: - Touch ID, without going near a terminal

    @objc func touchIDTapped() {
        if PrivilegedSetup.touchIDEnabled {
            handle(PrivilegedSetup.disableTouchID(), failureTitle: "Could not turn Touch ID off")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Use Touch ID instead of a password"
        alert.informativeText = """
        macOS can accept your fingerprint anywhere it would ask for your \
        password on the command line, including in this app. It is switched \
        off by default.

        Turning it on writes Apple's own sudo_local file, which exists so the \
        setting survives macOS updates. You will be asked for your password \
        once to authorise it - and that is the last time you will need it.

        You can turn it off again from this menu.
        """
        alert.addButton(withTitle: "Turn on Touch ID")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        switch PrivilegedSetup.enableTouchID() {
        case .cancelled:
            return
        case .failed(let message):
            self.alert("Could not turn Touch ID on", message, style: .warning)
        case .ok:
            if PrivilegedSetup.touchIDEnabled {
                self.alert("Touch ID is on",
                           "Closed-Lid Mode will ask for your fingerprint from now on. "
                           + "So will anything else that needs your password in Terminal.",
                           style: .informational)
            } else {
                self.alert("It did not take effect",
                           "macOS accepted the change but Touch ID still is not active. "
                           + "Check \(PrivilegedSetup.pamPath).",
                           style: .warning)
            }
        }
        refreshNow()
    }

    @objc func loginItemTapped() {
        if let error = LoginItem.set(!LoginItem.isEnabled) {
            alert("Could not change the login item", error, style: .warning)
        }
        refreshNow()
    }

    // MARK: - help and diagnostics

    @objc func showHelp() {
        alert("Closed-Lid Mode", """
        Normally a MacBook sleeps when you shut the lid on battery. Plugged in \
        it stays awake and keeps driving an external monitor. Apple gives you \
        no setting to change that.

        Turning this ON lifts the restriction, so you can shut the lid on \
        battery and your monitor keeps working.

        While it is ON the Mac will not sleep at all - not on battery, not \
        plugged in. That is why the app can switch itself off when you unplug \
        the monitor or the battery runs low, and why it warns you when it \
        cannot.

        It stays on after a restart until you turn it off. Quitting the app \
        does not turn it off.
        """, style: .informational)
    }

    @objc func copyDiagnostics() {
        let text = diagnosticsText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        alert("Copied", "Diagnostics are on the clipboard.\n\n" + text, style: .informational)
    }

    @objc func quitTapped() {
        if stateIsOn {
            let alert = NSAlert()
            alert.messageText = "Closed-Lid Mode is still ON"
            alert.informativeText = "Quitting only removes the menu bar icon. The Mac will still "
                + "refuse to sleep, and nothing will be watching to switch it off. "
                + "Turn it OFF first if that is not what you want."
            alert.addButton(withTitle: "Quit anyway")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        NSApplication.shared.terminate(nil)
    }

    // MARK: - helpers

    private func handle(_ result: Shell.AuthResult, failureTitle: String) {
        if case .failed(let message) = result {
            alert(failureTitle, message, style: .warning)
        }
        refreshNow()
    }

    private func alert(_ title: String, _ body: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
