import Foundation

/// Detects the physical network service (e.g. "Wi-Fi") *before* the VPN
/// tunnel takes over the default route, so vpnc-script can configure DNS on
/// the right service via networksetup.
enum NetworkServiceDetector {
    static func activeNetworkService() -> String? {
        guard let iface = run("/sbin/route", ["-n", "get", "default"])
            .split(separator: "\n")
            .first(where: { $0.contains("interface:") })?
            .split(separator: ":").last?
            .trimmingCharacters(in: .whitespaces),
            !iface.isEmpty else { return nil }

        let order = run("/usr/sbin/networksetup", ["-listnetworkserviceorder"])
        let blocks = order.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n")
            guard lines.count >= 2,
                  lines[1].contains("Device: \(iface)") else { continue }
            // "(1) Wi-Fi" -> "Wi-Fi"
            var name = String(lines[0])
            if let range = name.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) {
                name.removeSubrange(range)
            }
            return name.trimmingCharacters(in: .whitespaces)
        }
        return nil
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
            p.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
