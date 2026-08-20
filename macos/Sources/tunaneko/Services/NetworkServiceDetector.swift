import Foundation

/// Detects the physical network service (e.g. "Wi-Fi", "USB 10/100/1000 LAN")
/// *before* the VPN tunnel takes over the default route, so vpnc-script can
/// configure DNS on the right service via networksetup.
enum NetworkServiceDetector {
    static func activeNetworkService() -> String? {
        guard let iface = run("/sbin/route", ["-n", "get", "default"])
            .split(separator: "\n")
            .first(where: { $0.contains("interface:") })?
            .split(separator: ":").last?
            .trimmingCharacters(in: .whitespaces),
            !iface.isEmpty else { return nil }

        let services = parseServices(run("/usr/sbin/networksetup", ["-listnetworkserviceorder"]))

        // 1) exact device match ("Device: en5" must not match "Device: en50")
        if let hit = services.first(where: { $0.device == iface }) {
            return hit.name
        }
        // 2) fallback: first service whose device currently has an IPv4 address
        for s in services {
            let out = run("/sbin/ifconfig", [s.device])
            if out.range(of: #"inet \d+\.\d+\.\d+\.\d+"#, options: .regularExpression) != nil {
                return s.name
            }
        }
        return nil
    }

    private struct Service {
        let name: String
        let device: String
    }

    /// Parses `networksetup -listnetworkserviceorder` output:
    ///   (1) Wi-Fi
    ///   (Hardware Port: Wi-Fi, Device: en0)
    private static func parseServices(_ text: String) -> [Service] {
        var result: [Service] = []
        var currentName: String?
        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine)
            if let m = line.range(of: #"^\*?\(\d+\)\s*(.+)$"#, options: .regularExpression) {
                currentName = String(line[m]).replacingOccurrences(
                    of: #"^\*?\(\d+\)\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            } else if let m = line.range(of: #"Device: ([A-Za-z0-9]+)\)"#, options: .regularExpression),
                      let name = currentName {
                let device = String(line[m])
                    .replacingOccurrences(of: "Device: ", with: "")
                    .replacingOccurrences(of: ")", with: "")
                result.append(Service(name: name, device: device))
                currentName = nil
            }
        }
        return result
    }

    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            // read before waiting to avoid pipe-buffer deadlock on large output
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
