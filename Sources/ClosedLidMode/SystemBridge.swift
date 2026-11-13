import AppKit
import CoreGraphics
import ServiceManagement

/// Running commands, including as root.
enum Shell {

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (out: String, code: Int32) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        // No stdin: without this, sudo could sit waiting for a password that
        // nothing will type, hanging the app. With it, sudo fails fast.
        proc.standardInput = FileHandle.nullDevice
        do { try proc.run() } catch { return ("", -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", proc.terminationStatus)
    }

    enum AuthResult { case ok, cancelled, failed(String) }

    /// Runs a command as root via the standard macOS authentication dialog.
    /// The user authorises each one; nothing is stored.
    static func runAsRoot(_ command: String) -> AuthResult {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let result = run("/usr/bin/osascript",
                         ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
        if result.code == 0 { return .ok }
        // Cancelling the dialog exits non-zero with nothing on stdout.
        if result.out.isEmpty { return .cancelled }
        return .failed(result.out)
    }

    /// Attempts a privileged command with no prompt at all. Succeeds only when
    /// a sudoers rule permits it. Used for automatic switch-off, which has to
    /// work when nobody is at the keyboard.
    static func runAsRootSilently(_ args: [String]) -> Bool {
        run("/usr/bin/sudo", ["-n"] + args).code == 0
    }
}

/// Which displays are attached.
enum Displays {
    /// True when something other than the built-in panel is connected.
    ///
    /// Counting screens is not enough: with the lid shut in clamshell there is
    /// one screen (the external), and with no monitor attached there is also
    /// one screen (the built-in). Only asking which is built-in tells them
    /// apart.
    static var externalConnected: Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
}

/// Start-at-login, through Apple's own service rather than a hand-written
/// LaunchAgent.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
