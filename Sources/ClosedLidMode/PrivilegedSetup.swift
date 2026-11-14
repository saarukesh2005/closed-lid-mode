import Foundation

/// Two optional system changes the app can make for you, each behind one
/// standard macOS authentication prompt, each undoable from the same menu.
///
/// Both write their file by building the complete contents here, as you, and
/// then having root `install` it. Nothing is assembled out of shell quoting,
/// and the sudoers rule is syntax-checked with `visudo -c` before it is put in
/// place - an invalid sudoers file breaks `sudo` for the whole machine.
enum PrivilegedSetup {

    // MARK: - Touch ID for sudo

    static let pamPath = "/etc/pam.d/sudo_local"
    private static let pamLine = "auth       sufficient     pam_tid.so"

    /// Apple ships `sudo_local` precisely so this survives macOS updates.
    static var touchIDEnabled: Bool {
        guard let text = try? String(contentsOfFile: pamPath, encoding: .utf8) else { return false }
        return activeLines(text).contains { $0.contains("pam_tid.so") }
    }

    static func enableTouchID() -> Shell.AuthResult {
        let existing = (try? String(contentsOfFile: pamPath, encoding: .utf8)) ?? ""
        guard !activeLines(existing).contains(where: { $0.contains("pam_tid.so") }) else { return .ok }

        var contents = existing
        if !contents.isEmpty && !contents.hasSuffix("\n") { contents += "\n" }
        if contents.isEmpty {
            contents = "# Enables Touch ID for sudo. Added by Closed-Lid Mode.\n"
        }
        contents += pamLine + "\n"

        return install(contents: contents, to: pamPath, mode: "0644", validateAsSudoers: false)
    }

    static func disableTouchID() -> Shell.AuthResult {
        guard let existing = try? String(contentsOfFile: pamPath, encoding: .utf8) else { return .ok }

        let kept = existing
            .components(separatedBy: "\n")
            .filter { !$0.contains("pam_tid.so") }
            .joined(separator: "\n")

        // Nothing meaningful left: take the file away rather than leave a husk.
        if activeLines(kept).isEmpty {
            return Shell.runAsRoot("/bin/rm -f \(pamPath)")
        }
        return install(contents: kept, to: pamPath, mode: "0644", validateAsSudoers: false)
    }

    // MARK: - letting auto-off work without a prompt

    static let sudoersPath = "/etc/sudoers.d/closed-lid-mode"

    /// Deliberately grants ONLY `disablesleep 0` - switching the mode *off*.
    /// Turning it on still needs authentication. So the worst this rule can do
    /// is make the Mac more willing to sleep, never less.
    private static func sudoersContents() -> String {
        """
        # Installed by Closed-Lid Mode so it can switch itself off unattended.
        #
        # This grants exactly one command: turning the sleep override OFF.
        # Turning it ON is NOT granted and still requires authentication, so
        # this rule can only ever make the Mac more likely to sleep.
        #
        # Remove it from the app's menu, or with:
        #   sudo rm \(sudoersPath)
        \(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0

        """
    }

    static var unattendedOffAllowed: Bool {
        // Both checks are needed. `sudo -n -l` alone lies: for five minutes
        // after any sudo, cached credentials make it succeed with no rule
        // present at all - and believing that would suppress the safety
        // warning while the app in fact could not act. The file alone is not
        // enough either, since sudo might not be honouring it.
        guard FileManager.default.fileExists(atPath: sudoersPath) else { return false }
        return Shell.run("/usr/bin/sudo",
                         ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"]).code == 0
    }

    static func allowUnattendedOff() -> Shell.AuthResult {
        install(contents: sudoersContents(), to: sudoersPath, mode: "0440", validateAsSudoers: true)
    }

    static func revokeUnattendedOff() -> Shell.AuthResult {
        Shell.runAsRoot("/bin/rm -f \(sudoersPath)")
    }

    // MARK: - plumbing

    private static func activeLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Writes `contents` to a temp file as the current user, then has root
    /// validate (if asked) and install it with the right owner and mode.
    private static func install(contents: String,
                                to destination: String,
                                mode: String,
                                validateAsSudoers: Bool) -> Shell.AuthResult {
        // A path with no spaces or shell metacharacters, so the command below
        // needs no quoting at all.
        let temp = NSTemporaryDirectory() + "closedlidmode-" + UUID().uuidString.prefix(8)
        do {
            try contents.write(toFile: temp, atomically: true, encoding: .utf8)
        } catch {
            return .failed("Could not write a temporary file: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(atPath: temp) }

        var command = ""
        if validateAsSudoers {
            // If this check fails nothing is installed, so a malformed rule can
            // never reach /etc/sudoers.d and break sudo.
            command += "/usr/sbin/visudo -c -f \(temp) && "
        }
        command += "/usr/bin/install -m \(mode) -o root -g wheel \(temp) \(destination)"

        return Shell.runAsRoot(command)
    }
}
