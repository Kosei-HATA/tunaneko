import Foundation

/// Loads / persists server profiles in
/// ~/Library/Application Support/tunaneko/profiles.json
/// On first launch, imports the legacy ~/.config/vpn/servers list.
final class ProfileStore: @unchecked Sendable {
    static let shared = ProfileStore()

    private var storeDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("tunaneko", isDirectory: true)
    }
    private var profilesURL: URL { storeDir.appendingPathComponent("profiles.json") }

    private init() {}

    func load() -> [ServerProfile] {
        if let data = try? Data(contentsOf: profilesURL) {
            if let profiles = try? JSONDecoder().decode([ServerProfile].self, from: data) {
                return profiles
            }
            // file exists but is corrupt: back it up instead of overwriting
            let backup = profilesURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: profilesURL, to: backup)
            NSLog("ProfileStore: corrupt profiles.json backed up to \(backup.lastPathComponent)")
            return []
        }
        // no profiles file at all: try the legacy import (first launch)
        let imported = importLegacyServers()
        if !imported.isEmpty {
            save(imported)
        }
        return imported
    }

    func save(_ profiles: [ServerProfile]) {
        do {
            try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: profilesURL, options: .atomic)
        } catch {
            NSLog("ProfileStore save failed: \(error)")
        }
    }

    // MARK: - Legacy import (~/.config/vpn/servers: "name host protocol")

    private func importLegacyServers() -> [ServerProfile] {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/vpn/servers")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var result: [ServerProfile] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }
            let name = parts[0]
            let host = parts[1]
            let proto = parts.count >= 3 ? parts[2] : "anyconnect"

            result.append(ServerProfile(name: name, host: host, vpnProtocol: proto))
        }
        return result
    }
}
