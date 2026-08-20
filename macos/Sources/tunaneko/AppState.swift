import Foundation
import SwiftUI

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting(server: String)
    case connected(server: String)
    case failed(server: String, reason: String)
    case blockedByKillSwitch

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    var isBusy: Bool {
        if case .connecting = self { return true }
        return false
    }
}

@MainActor
final class AppState: ObservableObject {
    // profiles & selection
    @Published var profiles: [ServerProfile] = []
    /// nil = "自動" (fastest)
    @Published var selectedProfileID: UUID?

    /// Sidebar selection shared with MainView so views can navigate.
    @Published var sidebar: SidebarItem = .home

    // connection
    @Published var status: ConnectionStatus = .disconnected
    @Published var connectStartedAt: Date?
    @Published var logs: [String] = []

    // settings (persisted)
    @AppStorage("autoRetry") var autoRetry = true
    @AppStorage("killSwitch") var killSwitch = false
    @AppStorage("defaultUsername") var defaultUsername = ""

    /// UI language: "auto" follows the system; otherwise a fixed code.
    /// Changing it re-renders all views observing AppState.
    var language: String {
        get { L10n.language }
        set {
            L10n.language = newValue
            objectWillChange.send()
        }
    }

    // runtime
    @Published var killSwitchActive = false
    @Published var isMeasuring = false
    /// true when sudoers is not configured — drives the launch dialog.
    @Published var privilegesMissing = false
    /// last connection failure message for the error banner.
    @Published var lastError: String?

    let stats = StatsMonitor()
    private let vpn = VPNProcess()
    private let networkWatcher = NetworkWatcher()
    private let latencyTester = LatencyTester()
    private var retryQueue: [ServerProfile] = []
    private var retryCount = 0
    private let maxRetries = 5
    /// Delayed cert-pin reconnect; cancelled when the user disconnects.
    private var pendingReconnect: DispatchWorkItem?
    private var durationTimer: Timer?
    /// Suppresses failure handling for a process we killed intentionally
    /// (certificate-pin retry, auth retry).
    private var intentionalKill = false

    init() {
        profiles = ProfileStore.shared.load()
        vpn.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        stats.onUpdate = { [weak self] in self?.objectWillChange.send() }
        refreshKillSwitchStatus()
        recheckPrivileges()
        networkWatcher.onPhysicalChange = { [weak self] in self?.handleNetworkChange() }
        networkWatcher.start()
    }

    func recheckPrivileges() {
        privilegesMissing = !KillSwitchService.sudoersConfigured(corePath: VPNProcess.bundledCorePath)
            || !KillSwitchService.killRuleConfigured()
    }

    var selectedProfile: ServerProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    /// Profile whose connection is currently in flight or established.
    private(set) var connectingProfile: ServerProfile?

    private func hostSuffix() -> String {
        guard let host = connectingProfile?.host else { return "" }
        return " (\(host))"
    }

    var statusText: String {
        switch status {
        case .disconnected: return L10n.tr("status.disconnected")
        case .connecting(let s): return L10n.tr("status.connecting") + " \(s)" + hostSuffix()
        case .connected(let s): return L10n.tr("status.connected") + " \(s)" + hostSuffix()
        case .failed(let s, let r): return L10n.tr("status.failed") + " \(s): \(r)"
        case .blockedByKillSwitch: return L10n.tr("status.blocked")
        }
    }

    var connectedDuration: String {
        guard let start = connectStartedAt, status.isConnected else { return "--:--" }
        let s = Int(Date().timeIntervalSince(start))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    // MARK: - credentials

    private func credentials(for profile: ServerProfile) -> (user: String, pass: String)? {
        let user = profile.username ?? defaultUsername
        let account = profile.hasOwnPassword ? profile.id.uuidString : "default"
        guard let pass = CredentialStore.password(for: account), !pass.isEmpty else { return nil }
        return (user, pass)
    }

    // MARK: - connect / disconnect

    func connect() {
        guard !status.isBusy, !isMeasuring else { return }

        // --- preflight checks: fail fast instead of retry-looping 104 servers ---
        guard CredentialStore.password(for: "default") != nil
                || profiles.contains(where: { $0.hasOwnPassword }) else {
            lastError = L10n.tr("error.no_credentials")
            status = .failed(server: "-", reason: lastError!)
            log("preflight: no password stored. Set one in Settings.")
            return
        }
        guard KillSwitchService.sudoersConfigured(corePath: VPNProcess.bundledCorePath) else {
            lastError = L10n.tr("error.no_sudoers")
            status = .failed(server: "-", reason: lastError!)
            privilegesMissing = true
            log("preflight: sudoers not configured. Use Settings > Set up.")
            return
        }

        // Auto mode needs latency data; measure first, then connect to the fastest.
        if selectedProfileID == nil && profiles.contains(where: { $0.latencyMs == nil }) {
            log("auto: measuring latency before connecting…")
            measureAll { [weak self] in self?.connectNow() }
            return
        }
        connectNow()
    }

    private func connectNow() {
        retryQueue = []
        retryCount = 0
        // cancel a pending cert-pin reconnect so it can't hijack this session
        pendingReconnect?.cancel()
        pendingReconnect = nil

        let target: ServerProfile?
        if let sel = selectedProfile {
            target = sel
        } else {
            target = fastestProfile()
        }
        guard let profile = target else {
            log("no profiles; add a server first")
            return
        }
        if autoRetry {
            retryQueue = profiles
                .filter { $0.id != profile.id }
                .sorted { ($0.latencyMs ?? .max) < ($1.latencyMs ?? .max) }
        }
        // Reference the pf anchor BEFORE connecting — reloading the main
        // ruleset flushes pf state and would kill a live tunnel.
        if killSwitch {
            KillSwitchService.prepare()
        }
        startConnection(to: profile)
    }

    private func startConnection(to profile: ServerProfile) {
        guard let cred = credentials(for: profile) else {
            if autoRetry, retryCount < maxRetries, !retryQueue.isEmpty {
                log("no password stored for \(profile.name); skipping")
                tryNext()
            } else {
                lastError = String(format: L10n.tr("error.no_credentials_for"), profile.name)
                status = .failed(server: profile.name, reason: lastError!)
                log("no password stored for \(profile.name)")
            }
            return
        }
        intentionalKill = false
        connectingProfile = profile
        status = .connecting(server: profile.name)
        log("connecting to \(profile.name) (\(profile.host)) as \(cred.user)")
        vpn.connect(profile: profile, username: cred.user, password: cred.pass, killSwitch: killSwitch)
    }

    func disconnect() {
        intentionalKill = true
        pendingReconnect?.cancel()
        pendingReconnect = nil
        vpn.terminate()
        networkWatcher.rebaseline()   // teardown also changes the interface list
        // do_disconnect hook restores routes and flushes the kill switch anchor
    }

    /// Physical underlay changed (Wi-Fi ⇔ Ethernet): reconnect the SAME profile.
    func handleNetworkChange() {
        guard case .connected = status, let profile = connectingProfile else { return }
        log("network changed — reconnecting \(profile.name)")
        intentionalKill = true
        pendingReconnect?.cancel()
        pendingReconnect = nil
        retryQueue = []          // same server, not the next one
        vpn.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, case .disconnected = self.status else { return }
            self.intentionalKill = false
            self.startConnection(to: profile)
        }
    }

    func releaseKillSwitch() {
        KillSwitchService.release()
        refreshKillSwitchStatus()
        if case .blockedByKillSwitch = status { status = .disconnected }
    }

    func refreshKillSwitchStatus() {
        killSwitchActive = KillSwitchService.isActive()
        if killSwitchActive, !killSwitch, !status.isBusy, !status.isConnected {
            // stale rules while the kill switch setting is OFF (e.g. an older
            // session crashed with it on): self-heal instead of trapping the user
            KillSwitchService.release()
            killSwitchActive = false
            log("kill switch: flushed stale rules (setting is off)")
        }
        if killSwitchActive, case .disconnected = status {
            status = .blockedByKillSwitch
        }
    }

    // MARK: - latency

    func measureAll(completion: (() -> Void)? = nil) {
        guard !isMeasuring else {
            completion?()
            return
        }
        isMeasuring = true
        let targets = profiles.map { ($0.id, $0.bareHost) }
        Task {
            await latencyTester.measure(hosts: targets) { [weak self] id, ms in
                Task { @MainActor in
                    guard let self, let idx = self.profiles.firstIndex(where: { $0.id == id }) else { return }
                    self.profiles[idx].latencyMs = ms
                }
            }
            await MainActor.run {
                self.isMeasuring = false
                completion?()
            }
        }
    }

    private func fastestProfile() -> ServerProfile? {
        let reachable = profiles.filter { $0.latencyMs != nil }
        return reachable.min { ($0.latencyMs ?? .max) < ($1.latencyMs ?? .max) } ?? profiles.first
    }

    // MARK: - VPN events

    private func handle(_ event: VPNProcess.Event) {
        // ignore late events from a killed previous attempt
        guard event.generation == vpn.generation else { return }

        switch event.kind {
        case .log(let line):
            log(line)
            if line.contains("Kill switch enabled") { killSwitchActive = true }
            if line.contains("Kill switch disabled") { killSwitchActive = false }

        case .connected:
            guard case .connecting(let server) = status else { return }
            status = .connected(server: server)
            networkWatcher.rebaseline()   // tunnel-up changed the interface list
            lastError = nil
            connectStartedAt = Date()
            stats.start()
            startDurationTimer()
            log("connected: \(server)")

        case .authFailed:
            guard case .connecting(let server) = status else { return }
            log("auth failed on \(server)")
            intentionalKill = true
            vpn.terminate()
            lastError = L10n.tr("error.auth")
            status = .failed(server: server, reason: lastError!)
            tryNext()

        case .sudoError(let line):
            guard case .connecting(let server) = status else { return }
            log(line)
            lastError = L10n.tr("error.no_sudoers")
            status = .failed(server: server, reason: lastError!)
            privilegesMissing = true

        case .certificatePin(let pin):
            guard case .connecting = status, let profile = connectingProfile else { return }
            if CertPinStore.shared.pin(for: profile.host) == nil {
                // first contact (TOFU): save pin and reconnect with --servercert
                log("saving certificate pin for \(profile.host)")
                CertPinStore.shared.setPin(pin, for: profile.host)
                intentionalKill = true
                vpn.terminate()
                let work = DispatchWorkItem { [weak self] in
                    self?.startConnection(to: profile)
                }
                pendingReconnect = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
            } else {
                // a pin line appeared while a pin is already stored:
                // the server certificate does NOT match the stored pin.
                // Never silently re-pin — that would defeat pinning (MITM).
                log("certificate pin mismatch for \(profile.host)")
                intentionalKill = true
                vpn.terminate()
                retryQueue = []
                lastError = String(format: L10n.tr("error.cert_mismatch"), profile.host)
                status = .failed(server: profile.name, reason: lastError!)
            }

        case .exited(let code):
            let intentional = intentionalKill
            intentionalKill = false
            stats.stop()
            stopDurationTimer()
            connectStartedAt = nil
            if case .connected(let server) = status {
                status = .disconnected
                log("disconnected from \(server) (exit \(code))")
                refreshKillSwitchStatus()
            } else if !intentional, case .connecting(let server) = status {
                log("connection to \(server) failed (exit \(code))")
                status = .failed(server: server, reason: "exit \(code)")
                refreshKillSwitchStatus()
                tryNext()
            } else if intentional, case .connecting = status {
                // user (or pin-retry) cancelled mid-handshake
                status = .disconnected
                refreshKillSwitchStatus()
            } else {
                refreshKillSwitchStatus()
            }
        }
    }

    private func tryNext() {
        guard autoRetry, retryCount < maxRetries, !retryQueue.isEmpty else {
            if retryCount >= maxRetries {
                log("gave up after \(maxRetries) retries")
            }
            return
        }
        retryCount += 1
        let next = retryQueue.removeFirst()
        log("retrying with \(next.name) (\(retryCount)/\(maxRetries))")
        startConnection(to: next)
    }

    // MARK: - misc

    private func log(_ message: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(ts)] \(message)")
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }

    private func startDurationTimer() {
        stopDurationTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.objectWillChange.send() }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
