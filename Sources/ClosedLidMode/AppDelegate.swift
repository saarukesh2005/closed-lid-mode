import AppKit
import ClosedLidModeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var timer: Timer?

    private(set) var state = PowerState(modeIsOn: false, externalDisplayConnected: false,
                                   onBattery: false, batteryPercent: nil)
    private(set) var settings = Settings.load()
    private(set) var lastAutoOff: String?

    // MARK: - lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            // scheduledTimer fires on the main run loop, so this is genuinely
            // main-actor work, not an assumption being waved through.
            MainActor.assumeIsolated { self?.refresh() }
        }

        // Plugging or unplugging a monitor should be acted on at once, not up
        // to five seconds later.
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: - reading the world

    private func readState() -> PowerState {
        let modeIsOn = PmsetParser.sleepDisabled(inPmsetOutput: Shell.run("/usr/bin/pmset", ["-g"]).out)
        let battery = PmsetParser.battery(inBattOutput: Shell.run("/usr/bin/pmset", ["-g", "batt"]).out)
        return PowerState(modeIsOn: modeIsOn,
                          externalDisplayConnected: Displays.externalConnected,
                          onBattery: battery.onBattery,
                          batteryPercent: battery.percent)
    }

    @objc private func refresh() {
        state = readState()
        runAutoOffIfNeeded()
        updateMenuBar()
    }

    /// The reason this app grew past a simple switch: the mode is system-wide
    /// and survives reboots, so it is very easy to leave on and walk away with
    /// a Mac that will not sleep.
    private func runAutoOffIfNeeded() {
        guard let reason = AutoOffPolicy.reasonToTurnOff(state: state, settings: settings.autoOff)
        else { return }

        // Must work with nobody at the keyboard, so no prompt is attempted.
        // Without the sudoers rule this fails and the menu bar warns loudly
        // instead - which is still better than silently draining.
        if Shell.runAsRootSilently(["/usr/bin/pmset", "-a", "disablesleep", "0"]) {
            lastAutoOff = "Switched off automatically because \(reason.explanation)."
            state = readState()
        }
    }

    // MARK: - the menu bar

    private var warning: RiskWarning? {
        AutoOffPolicy.warning(state: state, settings: settings.autoOff)
    }

    private func updateMenuBar() {
        guard let button = statusItem.button else { return }
        // A colour emoji, not an image or a styled string: both of those can
        // render dark-on-dark and vanish on a dark menu bar. Emoji are colour
        // bitmaps and cannot.
        button.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        if !state.modeIsOn {
            button.title = "🔴 LID OFF"
            button.toolTip = "Closed-Lid Mode is OFF - shutting the lid on battery puts the Mac to sleep."
        } else if warning != nil {
            button.title = "⚠️ LID ON"
            button.toolTip = "Closed-Lid Mode is ON - " + (warning?.summary ?? "")
        } else {
            button.title = "🟢 LID ON"
            button.toolTip = "Closed-Lid Mode is ON - the lid can stay shut and the monitor keeps working."
        }
        statusItem.menu = buildMenu()
    }

    private func label(_ title: String, bold: Bool = false, colour: NSColor? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: bold ? 13 : 12, weight: bold ? .bold : .regular)
        ]
        if let colour { attributes[.foregroundColor] = colour }
        item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        return item
    }

    private func action(_ title: String, _ selector: Selector, on: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        if let on { item.state = on ? .on : .off }
        return item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(label(state.modeIsOn ? "Closed-Lid Mode:  ON" : "Closed-Lid Mode:  OFF",
                           bold: true,
                           colour: state.modeIsOn ? .systemGreen : .secondaryLabelColor))
        menu.addItem(label(state.modeIsOn ? "Lid can stay shut - monitor stays on"
                                          : "Lid shut on battery = Mac sleeps"))
        if let warning {
            menu.addItem(label("⚠  " + warning.summary, colour: .systemOrange))
        }
        if let lastAutoOff {
            menu.addItem(label("ℹ  " + lastAutoOff, colour: .secondaryLabelColor))
        }

        menu.addItem(.separator())
        var power = "Monitor: " + (state.externalDisplayConnected ? "connected" : "not connected")
        if let percent = state.batteryPercent {
            power += "    Battery: \(percent)%" + (state.onBattery ? ", on battery" : ", charging")
        }
        menu.addItem(label(power, colour: .secondaryLabelColor))

        menu.addItem(.separator())
        menu.addItem(action(state.modeIsOn ? "Turn OFF  (back to normal)"
                                           : "Turn ON  (keep awake, lid shut)",
                            #selector(toggleTapped)))

        menu.addItem(.separator())
        menu.setSubmenu(autoOffMenu(), for: {
            let item = NSMenuItem(title: "Switch off automatically", action: nil, keyEquivalent: "")
            menu.addItem(item)
            return item
        }())

        menu.addItem(action(PrivilegedSetup.touchIDEnabled ? "Unlock with Touch ID"
                                                           : "Unlock with Touch ID",
                            #selector(touchIDTapped),
                            on: PrivilegedSetup.touchIDEnabled))
        menu.addItem(action("Start at login", #selector(loginItemTapped), on: LoginItem.isEnabled))

        menu.addItem(.separator())
        menu.addItem(action("What is this?", #selector(showHelp)))
        menu.addItem(action("Copy diagnostics", #selector(copyDiagnostics)))
        menu.addItem(action("Quit", #selector(quitTapped)))
        return menu
    }

    private func autoOffMenu() -> NSMenu {
        let sub = NSMenu()
        sub.addItem(action("When the monitor is unplugged",
                           #selector(toggleAutoOffMonitor),
                           on: settings.autoOff.whenMonitorDisconnected))
        sub.addItem(action("When the battery drops below 20%",
                           #selector(toggleAutoOffBattery),
                           on: settings.autoOff.batteryThreshold != nil))
        sub.addItem(.separator())

        let allowed = PrivilegedSetup.unattendedOffAllowed
        sub.addItem(action(allowed ? "Allowed to switch off without a password"
                                   : "Allow switching off without a password…",
                           #selector(unattendedTapped),
                           on: allowed))
        if !allowed {
            sub.addItem(label("Without this, it can only warn you -", colour: .secondaryLabelColor))
            sub.addItem(label("it cannot act while you are away.", colour: .secondaryLabelColor))
        }
        return sub
    }
}


// MARK: - the surface Actions.swift drives

@MainActor
extension AppDelegate {

    var stateIsOn: Bool { state.modeIsOn }

    func refreshNow() { refresh() }

    func clearLastAutoOff() { lastAutoOff = nil }

    func mutateSettings(_ change: (inout Settings) -> Void) {
        change(&settings)
        settings.save()
        refreshNow()
    }

    /// Everything someone would otherwise have to ask for one question at a
    /// time. This app was slow to debug precisely because it said nothing
    /// about itself.
    func diagnosticsText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let lidShut = Shell.run("/usr/bin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "4"])
            .out.contains("\"AppleClamshellState\" = Yes")
        return """
        Closed-Lid Mode \(version)
        macOS: \(os)
        Mode: \(state.modeIsOn ? "ON" : "OFF")
        External monitor: \(state.externalDisplayConnected ? "connected" : "not connected")
        Lid: \(lidShut ? "shut" : "open")
        Power: \(state.onBattery ? "battery" : "mains")\(state.batteryPercent.map { ", \($0)%" } ?? "")
        Auto-off on unplug: \(settings.autoOff.whenMonitorDisconnected)
        Auto-off battery threshold: \(settings.autoOff.batteryThreshold.map(String.init) ?? "disabled")
        Can switch off unattended: \(PrivilegedSetup.unattendedOffAllowed)
        Touch ID for sudo: \(PrivilegedSetup.touchIDEnabled)
        Start at login: \(LoginItem.isEnabled)
        """
    }
}
