import Foundation

/// IP address family of the server. Location-based grouping was dropped:
/// users can be anywhere, so the only meaningful grouping is IPv4/IPv6.
enum ServerGroup: String, Codable, CaseIterable {
    case ipv4 = "IPv4"
    case ipv6 = "IPv6"
}

struct ServerProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var vpnProtocol: String = "anyconnect"
    var group: ServerGroup = .ipv4
    /// Per-server username override. nil = use the global default credentials.
    var username: String?
    /// Whether a per-server password is stored in CredentialStore (account = id).
    var hasOwnPassword: Bool = false

    /// Transient, not persisted.
    var latencyMs: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, host, vpnProtocol, group, username, hasOwnPassword
    }

    init(id: UUID = UUID(), name: String, host: String,
         vpnProtocol: String = "anyconnect", group: ServerGroup? = nil,
         username: String? = nil, hasOwnPassword: Bool = false) {
        self.id = id
        self.name = name
        self.host = host
        self.vpnProtocol = vpnProtocol
        self.group = group ?? (host.hasPrefix("[") ? .ipv6 : .ipv4)
        self.username = username
        self.hasOwnPassword = hasOwnPassword
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        vpnProtocol = try c.decodeIfPresent(String.self, forKey: .vpnProtocol) ?? "anyconnect"
        username = try c.decodeIfPresent(String.self, forKey: .username)
        hasOwnPassword = try c.decodeIfPresent(Bool.self, forKey: .hasOwnPassword) ?? false
        // migrate legacy location groups (Japan/Overseas/Custom/…) to IP type.
        // decode via String: an unknown raw value must not throw.
        let rawGroup = try c.decodeIfPresent(String.self, forKey: .group)
        group = rawGroup.flatMap(ServerGroup.init(rawValue:))
            ?? (host.hasPrefix("[") ? .ipv6 : .ipv4)
    }

    var isIPv6: Bool { group == .ipv6 }

    /// Host stripped of IPv6 brackets, for display / NWConnection.
    var bareHost: String {
        host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }
}
