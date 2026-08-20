import Foundation
import Network

/// Measures TCP connect latency to host:443 for many servers in parallel.
@MainActor
final class LatencyTester {
    /// Result callback: profile id → latency in ms (nil = unreachable).
    func measure(hosts: [(id: UUID, host: String)],
                 timeout: TimeInterval = 2.0,
                 concurrency: Int = 32,
                 progress: @escaping (UUID, Int?) -> Void) async {
        await withTaskGroup(of: (UUID, Int?).self) { group in
            var iterator = hosts.makeIterator()
            var inFlight = 0

            func enqueue() {
                while inFlight < concurrency, let item = iterator.next() {
                    inFlight += 1
                    group.addTask {
                        let ms = await Self.tcpLatency(host: item.host, timeout: timeout)
                        return (item.id, ms)
                    }
                }
            }

            enqueue()
            while let (id, ms) = await group.next() {
                progress(id, ms)
                inFlight -= 1
                enqueue()
            }
        }
    }

    private nonisolated static func tcpLatency(host: String, timeout: TimeInterval) async -> Int? {
        final class State: @unchecked Sendable {
            private let lock = NSLock()
            private var _resumed = false
            func tryResume() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if _resumed { return false }
                _resumed = true
                return true
            }
        }

        return await withCheckedContinuation { continuation in
            let state = State()
            let endpoint = NWEndpoint.Host(host)
            let conn = NWConnection(host: endpoint, port: 443, using: .tcp)
            let start = Date()

            let finish: @Sendable (Int?) -> Void = { ms in
                guard state.tryResume() else { return }
                // break the retain cycle conn → handler → finish → conn
                conn.stateUpdateHandler = nil
                conn.cancel()
                continuation.resume(returning: ms)
            }

            conn.stateUpdateHandler = { connState in
                switch connState {
                case .ready:
                    finish(Int(Date().timeIntervalSince(start) * 1000))
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
        }
    }
}
