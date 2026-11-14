import AppKit
import ClosedLidModeCore

/// Reading the world. Spawns processes, so it is kept off the main actor and
/// called from a background task - three process spawns on the main thread
/// every few seconds is a stutter nobody needs.
enum SystemReader {
    static func read() -> PowerState {
        let modeIsOn = PmsetParser.sleepDisabled(inPmsetOutput: Shell.run("/usr/bin/pmset", ["-g"]).out)
        let battery = PmsetParser.battery(inBattOutput: Shell.run("/usr/bin/pmset", ["-g", "batt"]).out)
        return PowerState(modeIsOn: modeIsOn,
                          externalDisplayConnected: Displays.externalConnected,
                          onBattery: battery.onBattery,
                          batteryPercent: battery.percent)
    }

    /// What the app is permitted to do. Each check spawns `sudo`, so this is
    /// cached and refreshed only when it might have changed - not on a timer.
    struct Capabilities: Sendable, Equatable {
        var touchID = false
        var unattendedOff = false
    }

    static func readCapabilities() -> Capabilities {
        Capabilities(touchID: PrivilegedSetup.touchIDEnabled,
                     unattendedOff: PrivilegedSetup.unattendedOffAllowed)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var timer: Timer?

    private(set) var state = PowerState(modeIsOn: false, externalDisplayConnected: false,
                                        onBattery: false, batteryPercent: nil)
    private(set) var settings = Settings.load()
    private(set) var capabilities = SystemReader.Capabilities()

    private(set) var lastAutoOff: String?
    private var lastAutoOffAt: Date?

    /// Auto-off bookkeeping. A display can disappear for a moment while the
    /// Mac wakes or changes resolution, and switching the mode off because of
    /// a flicker while someone is sitting at their desk would be worse than
    /// not having the feature.
    private var conditionHeldSince: Date?
    private var isReading = false

    private let settleBeforeActing: TimeInterval = 15
    private let lastAutoOffVisibleFor: TimeInterval = 600

    // MARK: - lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Built on demand via the delegate rather than reassigned on a timer.
        // Replacing statusItem.menu while it is open can dismiss it mid-click.
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        refreshCapabilities()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            // scheduledTimer fires on the main run loop, so this is genuinely
            // main-actor work rather than an assumption waved through.
            MainActor.assumeIsolated { self?.refresh() }
        }

        // Plugging or unplugging a monitor is acted on at once, not up to ten
        // seconds later.
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: - refreshing

    @objc func refresh() {
        guard !isReading else { return }
        isReading = true
        Task.detached(priority: .utility) {
            let fresh = SystemReader.read()
            await MainActor.run { [weak self] in self?.apply(fresh) }
        }
    }

    func refreshCapabilities() {
        Task.detached(priority: .utility) {
            let caps = SystemReader.readCapabilities()
            await MainActor.run { [weak self] in
                self?.capabilities = caps
                self?.updateButton()
            }
        }
    }

    private func apply(_ fresh: PowerState) {
        isReading = false
        state = fresh
        expireLastAutoOff()
        evaluateAutoOff()
        updateButton()
    }

    private func expireLastAutoOff() {
        guard let at = lastAutoOffAt else { return }
        if Date().timeIntervalSince(at) > lastAutoOffVisibleFor {
            lastAutoOff = nil
            lastAutoOffAt = nil
        }
    }

    /// Why this app grew past a simple switch: the setting is system-wide and
    /// survives reboots, so it is very easy to leave on and walk away with a
    /// Mac that will not sleep.
    private func evaluateAutoOff() {
        guard let reason = AutoOffPolicy.reasonToTurnOff(state: state, settings: settings.autoOff) else {
            conditionHeldSince = nil
            return
        }

        let now = Date()
        guard let since = conditionHeldSince else {
            conditionHeldSince = now
            return
        }
        guard now.timeIntervalSince(since) >= settleBeforeActing else { return }

        // No permission means no attempt at all. Retrying a doomed `sudo`
        // every few seconds would spawn processes forever for nothing; the
        // menu bar warning is what covers this case.
        guard capabilities.unattendedOff else { return }

        Task.detached(priority: .utility) {
            let ok = Shell.runAsRootSilently(["/usr/bin/pmset", "-a", "disablesleep", "0"])
            await MainActor.run { [weak self] in
                guard let self else { return }
                if ok {
                    self.lastAutoOff = "Switched off automatically because \(reason.explanation)."
                    self.lastAutoOffAt = Date()
                    self.conditionHeldSince = nil
                }
                self.refresh()
            }
        }
    }

    // MARK: - the menu bar button

    var warning: RiskWarning? {
        AutoOffPolicy.warning(state: state,
                              settings: settings.autoOff,
                              canActUnattended: capabilities.unattendedOff)
    }

    func updateButton() {
        guard let button = statusItem.button else { return }
        // A colour emoji, not an image or a styled string: both of those can
        // render dark-on-dark and vanish on a dark menu bar. Emoji cannot.
        button.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        if !state.modeIsOn {
            button.title = "🔴 LID OFF"
            button.toolTip = "Closed-Lid Mode is OFF - shutting the lid on battery puts the Mac to sleep."
        } else if let warning {
            button.title = "⚠️ LID ON"
            button.toolTip = "Closed-Lid Mode is " + warning.summary
        } else {
            button.title = "🟢 LID ON"
            button.toolTip = "Closed-Lid Mode is ON - the lid can stay shut and the monitor keeps working."
        }
    }

    // MARK: - the menu, built only when it is about to be shown

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshCapabilities()
        rebuild(menu)
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

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(label(state.modeIsOn ? "Closed-Lid Mode:  ON" : "Closed-Lid Mode:  OFF",
                           bold: true,
                           colour: state.modeIsOn ? .systemGreen : .secondaryLabelColor))
        menu.addItem(label(state.modeIsOn ? "Lid can stay shut - monitor stays on"
                                          : "Lid shut on battery = Mac sleeps"))
        if let warning {
            menu.addItem(label("⚠  " + warning.summary, colour: .systemOrange))
            if case .couldNotSwitchOff = warning {
                menu.addItem(label("    Allow it below, and it will handle this itself.",
                                   colour: .secondaryLabelColor))
            }
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
        let autoOff = NSMenuItem(title: "Switch off automatically", action: nil, keyEquivalent: "")
        menu.addItem(autoOff)
        menu.setSubmenu(autoOffMenu(), for: autoOff)

        menu.addItem(action(capabilities.touchID ? "Unlock with Touch ID"
                                                 : "Use Touch ID instead of a password…",
                            #selector(touchIDTapped),
                            on: capabilities.touchID))
        menu.addItem(action("Start at login", #selector(loginItemTapped), on: LoginItem.isEnabled))

        menu.addItem(.separator())
        menu.addItem(action("What is this?", #selector(showHelp)))
        menu.addItem(action("Copy diagnostics", #selector(copyDiagnostics)))
        menu.addItem(action("Quit", #selector(quitTapped)))
    }

    private func autoOffMenu() -> NSMenu {
        let sub = NSMenu()
        sub.addItem(action("When the monitor is unplugged",
                           #selector(toggleAutoOffMonitor),
                           on: settings.autoOff.whenMonitorDisconnected))
        let threshold = settings.autoOff.batteryThreshold ?? 20
        sub.addItem(action("When the battery drops below \(threshold)%",
                           #selector(toggleAutoOffBattery),
                           on: settings.autoOff.batteryThreshold != nil))
        sub.addItem(.separator())

        sub.addItem(action(capabilities.unattendedOff
                               ? "Allowed to switch off without a password"
                               : "Allow switching off without a password…",
                           #selector(unattendedTapped),
                           on: capabilities.unattendedOff))
        if !capabilities.unattendedOff {
            sub.addItem(label("Without this it can only warn you -", colour: .secondaryLabelColor))
            sub.addItem(label("it cannot act while you are away.", colour: .secondaryLabelColor))
        }
        return sub
    }
}

// MARK: - the surface Actions.swift drives

@MainActor
extension AppDelegate {

    var stateIsOn: Bool { state.modeIsOn }

    func refreshNow() {
        refreshCapabilities()
        refresh()
    }

    func clearLastAutoOff() {
        lastAutoOff = nil
        lastAutoOffAt = nil
        conditionHeldSince = nil
    }

    func mutateSettings(_ change: (inout Settings) -> Void) {
        change(&settings)
        settings.save()
        conditionHeldSince = nil
        refreshNow()
    }

    /// Everything someone would otherwise have to ask for one question at a
    /// time. This app was slow to debug precisely because it said nothing
    /// about itself.
    func diagnosticsText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let lidShut = Shell.run("/usr/bin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "4"])
            .out.contains("\"AppleClamshellState\" = Yes")
        return """
        Closed-Lid Mode \(version)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Mode: \(state.modeIsOn ? "ON" : "OFF")
        External monitor: \(state.externalDisplayConnected ? "connected" : "not connected")
        Lid: \(lidShut ? "shut" : "open")
        Power: \(state.onBattery ? "battery" : "mains")\(state.batteryPercent.map { ", \($0)%" } ?? "")
        Warning: \(warning?.summary ?? "none")
        Auto-off on unplug: \(settings.autoOff.whenMonitorDisconnected)
        Auto-off battery threshold: \(settings.autoOff.batteryThreshold.map(String.init) ?? "disabled")
        Can switch off unattended: \(capabilities.unattendedOff)
        Touch ID for sudo: \(capabilities.touchID)
        Start at login: \(LoginItem.isEnabled)
        """
    }
}
