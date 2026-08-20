import Foundation

/// Manages a single openconnect child process (run as root via sudo).
/// Parses its output line by line and reports state changes / log lines.
///
/// Each connect() call bumps `generation`; events carry the generation so
/// callers can ignore late events from a killed previous attempt.
///
/// @unchecked Sendable: `buffer` is only touched from the pipe's serial
/// readability handler, and `process` from the main thread / termination
/// handler, so no data race occurs in practice.
final class VPNProcess: @unchecked Sendable {
    enum EventKind {
        case log(String)
        case connected
        case authFailed
        case certificatePin(String)
        /// sudo refused to run (password required / not allowed) — never retriable
        case sudoError(String)
        case exited(Int32)
    }
    typealias Event = (generation: Int, kind: EventKind)

    var onEvent: ((Event) -> Void)?
    private(set) var generation = 0

    private var process: Process?
    private var buffer = Data()

    /// Path of the openconnect binary bundled inside this .app.
    static var bundledCorePath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/openconnect").path
    }

    static var bundledScriptPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/vpnc-script").path
    }

    func connect(profile: ServerProfile,
                 username: String,
                 password: String,
                 killSwitch: Bool) {
        terminate()

        generation += 1
        let gen = generation

        // `sudo -n VAR=value cmd` requires the SETENV tag in the sudoers rule.
        var args = ["-n"]
        if let service = NetworkServiceDetector.activeNetworkService() {
            args.append("ACTIVE_NETWORK_SERVICE=\(service)")
        }
        if killSwitch {
            args.append("KILLSWITCH=1")
        }
        args.append(Self.bundledCorePath)
        args.append(contentsOf: [
            "--protocol=\(profile.vpnProtocol)",
            "--user=\(username)",
            "--passwd-on-stdin",
            "--script=\(Self.bundledScriptPath)",
        ])
        if let pin = CertPinStore.shared.pin(for: profile.host) {
            args.append("--servercert")
            args.append(pin)
        }
        args.append(profile.host)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = args

        let outPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        process.standardInput = inPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.consume(data, generation: gen)
        }

        process.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            self?.emit(.exited(status), generation: gen)
        }

        do {
            try process.run()
            self.process = process
            // --passwd-on-stdin: first line on stdin is the password
            inPipe.fileHandleForWriting.write(Data((password + "\n").utf8))
        } catch {
            emit(.log("failed to launch sudo: \(error.localizedDescription)"), generation: gen)
            emit(.exited(-1), generation: gen)
        }
    }

    func terminate() {
        guard let p = process, p.isRunning else { return }
        // The openconnect child is root-owned: a plain kill() from this
        // user process gets EPERM. Signal via `sudo /bin/kill -INT`
        // (allowed by the sudoers rule) targeting ONLY the openconnect
        // child — signalling sudo's other descendants (vpnc-script) could
        // interrupt route/kill-switch cleanup mid-run.
        let children = childPIDs(of: p.processIdentifier)
        if children.isEmpty {
            signalViaSudo(p.processIdentifier) // fallback: sudo relays to child
        } else {
            for pid in children {
                signalViaSudo(pid)
            }
        }
    }

    private func childPIDs(of parent: Int32) -> [Int32] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-P", String(parent)]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .split(separator: "\n")
                .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) } ?? []
        } catch {
            return []
        }
    }

    private func signalViaSudo(_ pid: Int32) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", "/bin/kill", "-INT", String(pid)]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    var isRunning: Bool { process?.isRunning ?? false }

    private func emit(_ kind: EventKind, generation: Int) {
        DispatchQueue.main.async {
            self.onEvent?((generation, kind))
        }
    }

    // MARK: - output parsing

    private func consume(_ data: Data, generation gen: Int) {
        buffer.append(data)
        while let idx = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer.prefix(upTo: idx)
            buffer.removeSubrange(...idx)
            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty else { continue }
            parse(line, generation: gen)
        }
    }

    private func parse(_ line: String, generation gen: Int) {
        // sudo failures are fatal for the whole attempt — never retry these
        if line.hasPrefix("sudo: a password is required")
            || line.hasPrefix("sudo: sorry")
            || line.hasPrefix("sudo: no tty present") {
            emit(.sudoError(line), generation: gen)
            return
        }
        // certificate pin offered by the server
        if let range = line.range(of: #"pin-sha256:[A-Za-z0-9+/=]+"#, options: .regularExpression) {
            emit(.certificatePin(String(line[range])), generation: gen)
            return
        }
        if line.contains("CSTP connected") || line.contains("Established DTLS connection") {
            // may appear twice (CSTP then DTLS); AppState deduplicates
            emit(.connected, generation: gen)
        } else if line.contains("Login failed") || line.contains("401 Authentication failed") {
            emit(.authFailed, generation: gen)
        }
        emit(.log(line), generation: gen)
    }
}
