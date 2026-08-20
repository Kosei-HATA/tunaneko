import Foundation

/// File-based credential storage (0600 permissions), replacing Keychain.
///
/// Rationale: this app is ad-hoc signed, so macOS Keychain shows an access
/// prompt on *every* build (the signature identity is not stable). For a
/// self-distributed OSS VPN client that is unacceptable UX, so passwords
/// live in `credentials.json` with owner-only permissions, like ~/.netrc.
enum CredentialStore {
    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("tunaneko/credentials.json")
    }

    private static func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func saveAll(_ dict: [String: String]) -> Bool {
        do {
            let dir = storeURL.deletingLastPathComponent()
            // owner-only directory: protects contents regardless of file attrs
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            let data = try JSONEncoder().encode(dict)
            try data.write(to: storeURL, options: .atomic)
            // owner read/write only (atomic write may create 0644 transiently;
            // the 0700 parent dir covers the window)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
            return true
        } catch {
            NSLog("CredentialStore save failed: \(error)")
            return false
        }
    }

    static func password(for account: String) -> String? {
        loadAll()[account]
    }

    @discardableResult
    static func setPassword(_ password: String, for account: String) -> Bool {
        var dict = loadAll()
        dict[account] = password
        return saveAll(dict)
    }

    static func deletePassword(for account: String) {
        var dict = loadAll()
        dict.removeValue(forKey: account)
        _ = saveAll(dict)
    }

    static func hasPassword(for account: String) -> Bool {
        password(for: account) != nil
    }
}
