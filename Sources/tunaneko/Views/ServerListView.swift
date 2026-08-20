import SwiftUI
import UniformTypeIdentifiers

struct ServerListView: View {
    @EnvironmentObject var state: AppState
    @State private var search = ""
    @State private var sortByLatency = false
    @State private var editing: ServerProfile?
    @State private var showAdd = false
    @State private var showImport = false
    @State private var showExport = false
    @State private var deleteTarget: ServerProfile?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField(L10n.tr("servers.search"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Toggle(L10n.tr("servers.sort_latency"), isOn: $sortByLatency)
                    .toggleStyle(.checkbox)
                Spacer()
                if state.isMeasuring {
                    ProgressView().scaleEffect(0.7)
                    Text(L10n.tr("servers.measuring")).font(.caption)
                }
                Button(L10n.tr("servers.measure_all")) { state.measureAll() }
                    .disabled(state.isMeasuring)
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                }
                .help(L10n.tr("servers.add"))
                Menu {
                    Button(L10n.tr("servers.import")) { showImport = true }
                    Button(L10n.tr("servers.export")) { showExport = true }
                } label: {
                    Image(systemName: "square.and.arrow.up.on.square")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help(L10n.tr("servers.import_export"))
            }

            // "auto" row
            autoRow

            List {
                ForEach(filtered) { profile in
                    row(for: profile)
                }
            }
        }
        .sheet(item: $editing) { p in
            ProfileEditView(profile: p)
                .environmentObject(state)
        }
        .sheet(isPresented: $showAdd) {
            ServerEditSheet(profile: nil)
                .environmentObject(state)
        }
        .fileImporter(isPresented: $showImport,
                      allowedContentTypes: [.json, .plainText],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                importServers(from: url)
            }
        }
        .fileExporter(isPresented: $showExport,
                      document: ProfilesDocument(profiles: state.profiles),
                      contentType: .json,
                      defaultFilename: "tunaneko-servers.json") { _ in }
        .alert(item: $deleteTarget) { p in
            Alert(
                title: Text(L10n.tr("servers.delete_confirm_title")),
                message: Text(String(format: L10n.tr("servers.delete_confirm_body"), p.name, p.host)),
                primaryButton: .destructive(Text(L10n.tr("servers.delete"))) { delete(p) },
                secondaryButton: .cancel(Text(L10n.tr("action.cancel")))
            )
        }
    }

    private var filtered: [ServerProfile] {
        var list = state.profiles
        if !search.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(search) ||
                $0.host.localizedCaseInsensitiveContains(search)
            }
        }
        if sortByLatency {
            list.sort { ($0.latencyMs ?? .max) < ($1.latencyMs ?? .max) }
        }
        return list
    }

    private var autoRow: some View {
        HStack {
            Image(systemName: state.selectedProfileID == nil ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(.tint)
            Label(L10n.tr("home.auto"), systemImage: "bolt.fill")
            Spacer()
            Text(L10n.tr("servers.auto_desc"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.selectedProfileID = nil }
        .padding(.horizontal, 4)
    }

    private func row(for profile: ServerProfile) -> some View {
        HStack {
            Image(systemName: state.selectedProfileID == profile.id ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(.tint)
                .onTapGesture { state.selectedProfileID = profile.id }

            VStack(alignment: .leading) {
                Text(profile.name)
                Text(profile.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            latencyBadge(profile.latencyMs)

            Button { editing = profile } label: {
                Image(systemName: "pencil.circle")
            }
            .buttonStyle(.plain)

            Button { deleteTarget = profile } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.selectedProfileID = profile.id }
    }

    private func delete(_ profile: ServerProfile) {
        CredentialStore.deletePassword(for: profile.id.uuidString)
        state.profiles.removeAll { $0.id == profile.id }
        if state.selectedProfileID == profile.id { state.selectedProfileID = nil }
        ProfileStore.shared.save(state.profiles)
    }

    private func importServers(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }

        var imported: [ServerProfile] = []

        // 1) JSON export format
        if let profiles = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            imported = profiles.map {
                // regenerate ids to avoid collisions with existing entries
                var p = $0
                p.id = UUID()
                return p
            }
        } else if let text = String(data: data, encoding: .utf8) {
            // 2) plain text: "name host [protocol]" per line
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") { continue }
                let parts = t.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard parts.count >= 2 else { continue }
                imported.append(ServerProfile(
                    name: parts[0],
                    host: parts[1],
                    vpnProtocol: parts.count >= 3 ? parts[2] : "anyconnect"
                ))
            }
        }

        guard !imported.isEmpty else { return }
        state.profiles.append(contentsOf: imported)
        ProfileStore.shared.save(state.profiles)
        state.logs.append("imported \(imported.count) server(s)")
    }

    private func latencyBadge(_ ms: Int?) -> some View {
        Group {
            if let ms {
                Text("\(ms) ms")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(latencyColor(ms).opacity(0.2))
                    .foregroundStyle(latencyColor(ms))
                    .clipShape(Capsule())
            } else {
                Text("--")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func latencyColor(_ ms: Int) -> Color {
        switch ms {
        case ..<80: return .green
        case ..<200: return .orange
        default: return .red
        }
    }
}

/// Sheet for adding a new server (editing existing uses ProfileEditView).
struct ServerEditSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let profile: ServerProfile?

    @State private var name = ""
    @State private var host = ""
    @State private var proto = "anyconnect"
    @State private var group: ServerGroup = .ipv4

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("servers.add")).font(.title2)
            TextField(L10n.tr("profile.name"), text: $name).textFieldStyle(.roundedBorder)
            TextField(L10n.tr("profile.host"), text: $host)
                .textFieldStyle(.roundedBorder)
                .onChange(of: host) { _, newValue in
                    // auto-detect IP type from the host format
                    group = newValue.hasPrefix("[") || newValue.contains(":") ? .ipv6 : .ipv4
                }
            Picker(L10n.tr("profile.protocol"), selection: $proto) {
                Text(L10n.tr("anyconnect")).tag("anyconnect")
                Text(L10n.tr("gp")).tag("gp")
                Text(L10n.tr("pulse")).tag("pulse")
            }
            Picker(L10n.tr("profile.iptype"), selection: $group) {
                ForEach(ServerGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Spacer()
                Button(L10n.tr("action.cancel")) { dismiss() }
                Button(L10n.tr("action.save")) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || host.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    private func save() {
        var p = ServerProfile(name: name, host: host, vpnProtocol: proto, group: group)
        if let existing = profile { p.id = existing.id }
        if let idx = state.profiles.firstIndex(where: { $0.id == p.id }) {
            state.profiles[idx] = p
        } else {
            state.profiles.append(p)
        }
        ProfileStore.shared.save(state.profiles)
        dismiss()
    }
}

/// JSON document for exporting profiles.
struct ProfilesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var profiles: [ServerProfile]

    init(profiles: [ServerProfile]) { self.profiles = profiles }
    init(configuration: ReadConfiguration) throws {
        profiles = (try? JSONDecoder().decode([ServerProfile].self, from: configuration.file.regularFileContents ?? Data())) ?? []
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: (try? JSONEncoder().encode(profiles)) ?? Data())
    }
}
