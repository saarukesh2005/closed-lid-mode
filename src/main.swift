// Closed-Lid Mode - menu bar indicator
//
// Sits in the menu bar and always shows whether the Mac is allowed to stay
// awake with the lid shut. Click it to turn the mode on or off.
//
// Underlying setting: `sudo pmset -a disablesleep 0|1`, which macOS reports
// as "SleepDisabled" in `pmset -g`. It is system-wide and survives reboots.

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var isOn = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh()
        // Re-check every 5s so the display stays right even if the setting is
        // changed from Terminal or by another app.
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - reading / writing the setting

    private func run(_ path: String, _ args: [String]) -> (out: String, code: Int32) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        // No stdin. Without this, `sudo` could sit waiting for a password that
        // nothing will ever type, hanging the app. With it, sudo fails fast.
        proc.standardInput = FileHandle.nullDevice
        do { try proc.run() } catch { return ("", -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", proc.terminationStatus)
    }

    // MARK: - authentication

    /// True when Touch ID is wired into sudo, i.e. /etc/pam.d/sudo_local holds
    /// an active `auth sufficient pam_tid.so` line. Apple provides that file
    /// specifically so the setting survives macOS updates.
    private func touchIDForSudoEnabled() -> Bool {
        guard let text = try? String(contentsOfFile: "/etc/pam.d/sudo_local", encoding: .utf8) else {
            return false
        }
        return text.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("#") && trimmed.contains("pam_tid.so")
        }
    }

    /// Applies the setting using the least intrusive authentication available.
    ///
    /// With Touch ID wired into sudo, plain `sudo` shows a fingerprint prompt.
    /// Otherwise we fall back to the AppleScript admin dialog, which types a
    /// password. We only try sudo when Touch ID is actually configured, so the
    /// user never sees two prompts in a row.
    private func applySetting(_ target: String) -> (ok: Bool, cancelled: Bool) {
        if touchIDForSudoEnabled() {
            let result = run("/usr/bin/sudo", ["-p", "", "/usr/bin/pmset", "-a", "disablesleep", target])
            // Non-zero here means the fingerprint prompt was dismissed or
            // failed. Treat that as a cancellation rather than surprising the
            // user with a password dialog straight afterwards.
            return (result.code == 0, result.code != 0)
        }

        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(target)\" with administrator privileges"
        let result = run("/usr/bin/osascript", ["-e", script])
        // Non-zero with no output = the password sheet was cancelled.
        return (result.code == 0, result.code != 0 && result.out.isEmpty)
    }

    private func readState() -> Bool {
        let result = run("/usr/bin/pmset", ["-g"])
        for line in result.out.split(separator: "\n") where line.contains("SleepDisabled") {
            return line.contains("1")
        }
        return false
    }

    private func refresh() {
        isOn = readState()
        updateMenuBar()
    }

    // MARK: - what you see

    private func updateMenuBar() {
        guard let button = statusItem.button else { return }

        // Deliberately NO NSImage / SF Symbol here.
        //
        // An SF Symbol is a template image: macOS tints it to match the menu
        // bar, and if that tinting goes wrong it renders dark-on-dark and
        // vanishes in Dark Mode. An attributed title without an explicit
        // .foregroundColor has the same failure - it defaults to black.
        //
        // A colour emoji is immune to both. It is drawn as a colour bitmap,
        // identically in Light Mode, Dark Mode and under any tint, so the
        // indicator cannot silently disappear again.
        button.image = nil
        button.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        button.title = isOn ? "🟢 LID ON" : "🔴 LID OFF"
        button.toolTip = isOn
            ? "Closed-Lid Mode is ON - you can shut the lid and the monitor keeps working, on battery too."
            : "Closed-Lid Mode is OFF - shutting the lid on battery puts the Mac to sleep."

        rebuildMenu()
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let header = disabledItem(isOn ? "Closed-Lid Mode:  ON" : "Closed-Lid Mode:  OFF")
        header.attributedTitle = NSAttributedString(
            string: isOn ? "Closed-Lid Mode:  ON" : "Closed-Lid Mode:  OFF",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: isOn ? NSColor.systemGreen : NSColor.secondaryLabelColor
            ]
        )
        menu.addItem(header)

        menu.addItem(disabledItem(isOn
            ? "Lid can stay shut - monitor stays on"
            : "Lid shut on battery = Mac sleeps"))

        if isOn {
            menu.addItem(disabledItem("The Mac will not sleep until you turn this off"))
        }

        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: isOn ? "Turn OFF  (back to normal)" : "Turn ON  (keep awake, lid shut)",
            action: #selector(toggleTapped),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        if touchIDForSudoEnabled() {
            menu.addItem(disabledItem("Unlocks with Touch ID"))
        } else {
            let enable = NSMenuItem(
                title: "Use Touch ID instead of a password…",
                action: #selector(showTouchIDSetup),
                keyEquivalent: ""
            )
            enable.target = self
            menu.addItem(enable)
        }

        let help = NSMenuItem(title: "What is this?", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - actions

    @objc private func toggleTapped() {
        let target = isOn ? "0" : "1"
        let (_, cancelled) = applySetting(target)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.refresh()
            if !cancelled && self.isOn != (target == "1") {
                let alert = NSAlert()
                alert.messageText = "macOS did not apply the change"
                alert.informativeText = "Closed-Lid Mode is still \(self.isOn ? "ON" : "OFF"). "
                    + "You can set it by hand in Terminal with:\n\nsudo pmset -a disablesleep \(target)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    /// Touch ID for sudo means editing /etc/pam.d/, which is system
    /// authentication config. The app deliberately does not write that itself -
    /// it shows the one command and lets you run it, so nothing changes your
    /// Mac's authentication behind your back.
    @objc private func showTouchIDSetup() {
        let command = "sudo tee /etc/pam.d/sudo_local <<< 'auth sufficient pam_tid.so'"

        let alert = NSAlert()
        alert.messageText = "Use Touch ID instead of a password"
        alert.informativeText = """
        macOS can accept your fingerprint anywhere it would ask for your \
        password on the command line. It is off by default.

        To switch it on, paste this one line into Terminal and press Return. \
        It will ask for your password once - the last time you will need it:

        \(command)

        This writes Apple's own `sudo_local` file, which exists specifically so \
        the setting survives macOS updates. To undo it later:

        sudo rm /etc/pam.d/sudo_local

        Once it is on, this app will ask for your fingerprint instead. Every \
        other command that needs your password will too.
        """
        alert.addButton(withTitle: "Copy the command")
        alert.addButton(withTitle: "Close")

        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Closed-Lid Mode"
        alert.informativeText = """
        Normally a MacBook goes to sleep when you shut the lid while running \
        on battery. Plugged in it stays awake and keeps driving an external \
        monitor. Apple gives you no setting to change this.

        Turning this ON removes that restriction, so you can shut the lid on \
        battery and your monitor keeps working.

        Worth knowing while it is ON:
        • The Mac will not sleep at all - not on battery, not plugged in. \
        Turn it off when you leave the desk, or it will keep running in your bag.
        • It stays on after a restart until you turn it off.
        • You need an external keyboard and mouse to use the Mac lid-shut.
        • A shut lid traps heat, and the Air has no fan, so heavy work will \
        run warm.

        The screen still blanks when idle - that is separate and unchanged.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitTapped() {
        if isOn {
            let alert = NSAlert()
            alert.messageText = "Closed-Lid Mode is still ON"
            alert.informativeText = "Quitting only removes the menu bar icon. "
                + "The Mac will still refuse to sleep. Turn it OFF first if that is not what you want."
            alert.addButton(withTitle: "Quit anyway")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
