import SwiftUI

/// Native macOS home: status header + connect button + stats row.
/// Design blend: Tunnelblick (status), AnyConnect (picker + connect),
/// Karing (traffic stats), WireGuard (sidebar navigation).
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State private var showCredentials = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let error = state.lastError {
                    errorBanner(error)
                }
                statusHeader
                connectButton

                if case .blockedByKillSwitch = state.status {
                    GroupBox {
                        VStack(spacing: 10) {
                            Label(L10n.tr("killswitch.active"), systemImage: "shield.slash.fill")
                                .font(.headline)
                                .foregroundStyle(.red)
                            Text(L10n.tr("killswitch.blocked_desc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(L10n.tr("action.release_killswitch")) { state.releaseKillSwitch() }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.large)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }

                statsRow
                killSwitchRow
                credentialsRow
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .sheet(isPresented: $showCredentials) {
            DefaultCredentialsView()
                .environmentObject(state)
        }
        .alert(L10n.tr("setup.required_title"), isPresented: $state.privilegesMissing) {
            Button(L10n.tr("setup.required_go_settings")) { state.sidebar = .settings }
            Button(L10n.tr("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("setup.required_message"))
        }
    }

    // MARK: - error banner

    private func errorBanner(_ message: String) -> some View {
        GroupBox {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    state.lastError = nil
                    if case .failed = state.status { state.status = .disconnected }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .backgroundStyle(Color.red.opacity(0.08))
    }

    // MARK: - status header (Tunnelblick-ish)

    private var statusHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: statusIcon)
                .font(.system(size: 40))
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, isActive: state.status.isBusy)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.isMeasuring ? L10n.tr("home.measuring") : state.statusText)
                    .font(.title2.bold())
                serverPicker
            }
            Spacer()
            if state.killSwitchActive {
                Image(systemName: "shield.slash.fill")
                    .foregroundStyle(.red)
                    .help(L10n.tr("killswitch.active"))
            }
        }
    }

    private var serverPicker: some View {
        Picker(L10n.tr("home.select_server"), selection: $state.selectedProfileID) {
            Text(L10n.tr("home.auto")).tag(UUID?.none)
            ForEach(state.profiles) { p in
                Text("\(p.name)  (\(p.host))").tag(UUID?.some(p.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 320, alignment: .leading)
        .disabled(state.status.isConnected || state.status.isBusy)
    }

    // MARK: - connect button (AnyConnect-ish)

    private var connectButton: some View {
        Button {
            if state.status.isConnected || state.status.isBusy {
                state.disconnect()
            } else {
                state.connect()
            }
        } label: {
            ZStack {
                Text(state.status.isConnected || state.status.isBusy
                     ? L10n.tr("action.disconnect")
                     : L10n.tr("action.connect"))
                    .font(.headline)
                    .opacity(isWorking ? 0.35 : 1)
                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        if state.isMeasuring {
                            Text(L10n.tr("home.measuring"))
                                .font(.subheadline)
                        }
                    }
                    .foregroundStyle(.white)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            // explicit background: .borderedProminent + tint greys out
            // when the window is inactive (e.g. connecting from the tray)
            .background(buttonColor.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return)
        .disabled(state.isMeasuring)
    }

    private var isWorking: Bool {
        state.isMeasuring || state.status.isBusy
    }

    // MARK: - stats (Karing-ish)

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(title: L10n.tr("home.uptime"),
                     value: state.connectedDuration, icon: "clock")
            StatCard(title: L10n.tr("home.total_traffic"),
                     value: "↓\(formatBytes(state.stats.totalDown)) ↑\(formatBytes(state.stats.totalUp))",
                     icon: "arrow.up.arrow.down")
            StatCard(title: L10n.tr("home.speed"),
                     value: "↓\(StatsMonitor.format(bytesPerSec: state.stats.downBytesPerSec)) ↑\(StatsMonitor.format(bytesPerSec: state.stats.upBytesPerSec))",
                     icon: "speedometer")
        }
    }

    // MARK: - toggles & links

    private var killSwitchRow: some View {
        GroupBox {
            Toggle(L10n.tr("settings.kill_switch"), isOn: $state.killSwitch)
        }
    }

    private var credentialsRow: some View {
        GroupBox {
            Button {
                showCredentials = true
            } label: {
                LabeledContent {
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                } label: {
                    Label(L10n.tr("home.default_credentials"), systemImage: "person.badge.key")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - helpers

    private var statusIcon: String {
        switch state.status {
        case .connected: return "checkmark.shield.fill"
        case .connecting: return "shield"
        case .failed: return "exclamationmark.shield.fill"
        case .blockedByKillSwitch: return "shield.slash.fill"
        default: return "shield"
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .connected: return .green
        case .connecting: return .orange
        case .failed, .blockedByKillSwitch: return .red
        default: return .secondary
        }
    }

    private var buttonColor: Color {
        switch state.status {
        case .connected: return .red
        case .connecting: return .orange
        default: return .accentColor
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return String(format: "%.1f %@", value, units[unit])
    }
}

// MARK: - reusable components

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Compact editor for the default (global) credentials.
struct DefaultCredentialsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("settings.default_credentials")).font(.title2)
            TextField(L10n.tr("profile.username"), text: $state.defaultUsername)
                .textFieldStyle(.roundedBorder)
            SecureField(L10n.tr("profile.password"), text: $password)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                if saved { Text(L10n.tr("settings.saved")).foregroundStyle(.green) }
                Button(L10n.tr("action.cancel")) { dismiss() }
                Button(L10n.tr("action.save")) {
                    CredentialStore.setPassword(password, for: "default")
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}
