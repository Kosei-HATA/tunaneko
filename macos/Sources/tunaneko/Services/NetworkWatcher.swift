import Foundation
import Network

/// Watches for physical network changes (Wi-Fi ⇔ Ethernet, network loss)
/// via NWPathMonitor and notifies when the available-interface signature
/// changes. The VPN tunnel itself (utun) is ignored.
final class NetworkWatcher: @unchecked Sendable {
    var onPhysicalChange: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "net.watcher")
    private var lastSignature = ""
    private var lastFiredAt = Date.distantPast
    /// events before this time are ignored (set right after connect/disconnect,
    /// because tunnel setup/teardown itself changes the interface list)
    private var mutedUntil = Date.distantPast

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handle(path)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    /// Re-record the current interface signature (call after VPN state changes).
    func rebaseline(muteSeconds: TimeInterval = 8) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lastSignature = self.signature(of: self.monitor.currentPath)
            self.mutedUntil = Date().addingTimeInterval(muteSeconds)
        }
    }

    private func signature(of path: NWPath) -> String {
        path.availableInterfaces
            .filter { !$0.name.hasPrefix("utun") }
            .map { "\($0.name):\($0.type)" }
            .sorted()
            .joined(separator: ",")
    }

    private func handle(_ path: NWPath) {
        let sig = signature(of: path)
        guard !sig.isEmpty else { return }

        if lastSignature.isEmpty {
            lastSignature = sig
            return
        }
        guard sig != lastSignature else { return }
        lastSignature = sig

        guard Date() >= mutedUntil else { return }   // post-connect/disconnect grace

        let now = Date()
        guard now.timeIntervalSince(lastFiredAt) > 3 else { return }
        lastFiredAt = now

        DispatchQueue.main.async {
            self.onPhysicalChange?()
        }
    }
}
