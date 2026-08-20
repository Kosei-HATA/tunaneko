import Foundation

/// Polls utun interface byte counters to compute up/down throughput.
@MainActor
final class StatsMonitor {
    private(set) var upBytesPerSec: Double = 0
    private(set) var downBytesPerSec: Double = 0
    private(set) var totalUp: UInt64 = 0
    private(set) var totalDown: UInt64 = 0

    private var timer: Timer?
    private var lastSample: (up: UInt64, down: UInt64, at: Date)?
    /// Absolute counter values at connect time; totals are deltas from here
    /// so each connection starts at 0 B.
    private var baseline: (up: UInt64, down: UInt64)?
    var onUpdate: (() -> Void)?

    func start() {
        stop()
        lastSample = nil
        baseline = readCounters()   // per-connection reset
        totalUp = 0
        totalDown = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        upBytesPerSec = 0
        downBytesPerSec = 0
    }

    private func readCounters() -> (up: UInt64, down: UInt64) {
        var up: UInt64 = 0
        var down: UInt64 = 0

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var ptr = first
        while true {
            let ifa = ptr.pointee
            let name = String(cString: ifa.ifa_name)
            if name.hasPrefix("utun"), ifa.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    up += UInt64(data.pointee.ifi_obytes)
                    down += UInt64(data.pointee.ifi_ibytes)
                }
            }
            if let next = ifa.ifa_next { ptr = next } else { break }
        }
        return (up, down)
    }

    private func sample() {
        let counters = readCounters()
        let now = Date()
        if let last = lastSample {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0 {
                // ifi_*bytes are 32-bit and wrap at 4 GiB; correct deltas
                downBytesPerSec = Double(wrap32Delta(new: counters.down, old: last.down)) / dt
                upBytesPerSec = Double(wrap32Delta(new: counters.up, old: last.up)) / dt
                // clamp absurd spikes (interface reset etc.)
                if downBytesPerSec > 10_000_000_000 { downBytesPerSec = 0 }
                if upBytesPerSec > 10_000_000_000 { upBytesPerSec = 0 }
            }
        }
        lastSample = (counters.up, counters.down, now)
        if let base = baseline {
            totalUp = wrap32Delta(new: counters.up, old: base.up)
            totalDown = wrap32Delta(new: counters.down, old: base.down)
        }
        onUpdate?()
    }

    /// 32-bit counter delta with wrap correction.
    private func wrap32Delta(new: UInt64, old: UInt64) -> UInt64 {
        let n = new & 0xFFFF_FFFF
        let o = old & 0xFFFF_FFFF
        return n >= o ? n - o : (UInt64(1) << 32) - o + n
    }

    static func format(bytesPerSec: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytesPerSec
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return String(format: "%.1f %@", value, units[unit])
    }
}
