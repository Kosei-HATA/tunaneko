import Foundation

/// Persists per-host server certificate pins (pin-sha256) so that subsequent
/// connections skip the interactive certificate prompt.
final class CertPinStore: @unchecked Sendable {
    static let shared = CertPinStore()

    private var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("tunaneko/cert-pins.json")
    }

    private var pins: [String: String] = [:]

    private init() { load() }

    func pin(for host: String) -> String? { pins[host] }

    func setPin(_ pin: String, for host: String) {
        pins[host] = pin
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        pins = dict
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(pins)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            NSLog("CertPinStore save failed: \(error)")
        }
    }
}
