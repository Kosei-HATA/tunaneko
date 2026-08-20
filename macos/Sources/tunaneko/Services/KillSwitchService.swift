import Foundation

/// Kill switch helpers. Actual rule loading happens inside the bundled
/// vpnc-script (which already runs as root); this service handles:
/// - prepare(): reference the anchor from the main pf ruleset — must run
///   BEFORE the VPN connects, because reloading the main ruleset flushes
///   pf state and would kill a live tunnel.
/// - status check and manual release.
enum KillSwitchService {
    static let anchor = "com.tunaneko"

    /// Ensure the anchor is referenced in the main ruleset so that rules
    /// loaded into it actually take effect. Safe to call while disconnected.
    /// Also flushes stale rules: after a crash the anchor may still block
    /// everything except the OLD gateway, which would deadlock reconnecting
    /// to a different server. vpnc-script re-adds fresh rules at connect.
    static func prepare() {
        let filter = runSudo(["/sbin/pfctl", "-sr"])
        if !filter.contains(anchor) {
            // rebuild main ruleset: normalization, translation, filtering order
            let scrub = filter.split(separator: "\n").filter { $0.hasPrefix("scrub") }
            let rest = filter.split(separator: "\n").filter { !$0.hasPrefix("scrub") }
            let nat = runSudo(["/sbin/pfctl", "-sn"])
            let composed = (scrub.map(String.init)
                + nat.split(separator: "\n").map(String.init)
                + rest.map(String.init)
                + ["anchor \"\(anchor)\""]).joined(separator: "\n") + "\n"
            feedSudo(composed, ["/sbin/pfctl", "-f", "-"])
        }
        release() // drop stale rules from any crashed previous session
    }

    /// True when our pf anchor still has rules loaded (i.e. traffic blocked).
    static func isActive() -> Bool {
        let out = runSudo(["/sbin/pfctl", "-a", anchor, "-s", "rules"])
        return out.contains("block") || out.contains("pass")
    }

    /// Flush the anchor (manual release button).
    static func release() {
        _ = runSudo(["/sbin/pfctl", "-a", anchor, "-F", "all"])
    }

    /// Whether sudo NOPASSWD+SETENV works for the bundled core.
    /// Functional check: actually execute `sudo -n VAR=1 core --version`,
    /// which validates both NOPASSWD and the SETENV tag at once.
    static func sudoersConfigured(corePath: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", "TUNANEKO_CHECK=1", corePath, "--version"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Whether `sudo -n /bin/kill -INT <pid>` is allowed (needed for
    /// graceful disconnect of the root-owned core).
    static func killRuleConfigured() -> Bool {
        // probe with a non-existent pid: sudo accepts (kill fails with ESRCH)
        // or sudo rejects with "a password is required" / "not allowed"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", "/bin/kill", "-INT", "999999"]
        let err = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return !msg.contains("password") && !msg.contains("not allowed")
        } catch {
            return false
        }
    }

    private static func runSudo(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n"] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func feedSudo(_ input: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n"] + args
        let inPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            try inPipe.fileHandleForWriting.close()
            p.waitUntilExit()
        } catch {
            NSLog("KillSwitchService.feedSudo failed: \(error)")
        }
    }
}
