import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var defaultPassword = ""
    @State private var sudoersOK = false
    @State private var killOK = false
    @State private var showSaved = false

    private func statusRow(label: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.red)
            Text(label).font(.caption)
        }
    }

    var body: some View {
        Form {
            Section(L10n.tr("settings.general")) {
                Picker(L10n.tr("settings.language"), selection: $state.language) {
                    Text(L10n.tr("settings.language_auto")).tag("auto")
                    Text("日本語").tag("ja")
                    Text("English").tag("en")
                    Text("中文 (简体)").tag("zh-Hans")
                }
                Toggle(L10n.tr("settings.auto_retry"), isOn: $state.autoRetry)
                Toggle(L10n.tr("settings.kill_switch"), isOn: $state.killSwitch)
            }

            Section(L10n.tr("settings.default_credentials")) {
                TextField(L10n.tr("profile.username"), text: $state.defaultUsername)
                SecureField(L10n.tr("profile.password"), text: $defaultPassword)
                HStack {
                    Button(L10n.tr("action.save")) {
                        CredentialStore.setPassword(defaultPassword, for: "default")
                        showSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSaved = false }
                    }
                    .disabled(defaultPassword.isEmpty)
                    if showSaved {
                        Text(L10n.tr("settings.saved")).foregroundStyle(.green).font(.caption)
                    }
                }
            }

            Section(L10n.tr("settings.privileges")) {
                VStack(alignment: .leading, spacing: 6) {
                    statusRow(label: "openconnect (NOPASSWD+SETENV)", ok: sudoersOK)
                    statusRow(label: "/bin/kill -INT (disconnect)", ok: killOK)
                }
                if !sudoersOK || !killOK {
                    HStack {
                        Label(L10n.tr("settings.sudoers_missing"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(L10n.tr("settings.sudoers_setup")) { installSudoers() }
                    }
                }
                Text(L10n.tr("settings.sudoers_desc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("settings.log")) {
                ScrollView {
                    Text(state.logs.suffix(50).joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 160)
            }

            Section(L10n.tr("licenses.title")) {
                LicensesView()
            }
        }
        .formStyle(.grouped)
        .onAppear { recheckPrivileges() }
    }

    /// Installs the sudoers rule via a single native admin prompt.
    /// SETENV tag is required so `sudo KILLSWITCH=1 ...` env passing works.
    private func installSudoers() {
        let user = NSUserName()
        let core = VPNProcess.bundledCorePath
        let rule1 = "\(user) ALL=(ALL) NOPASSWD: SETENV: \(core)"
        let rule2 = "\(user) ALL=(ALL) NOPASSWD: /sbin/pfctl"
        let rule3 = "\(user) ALL=(ALL) NOPASSWD: /bin/kill -INT *"
        let shell = "printf '%s\\n' '\(rule1)' '\(rule2)' '\(rule3)' > /etc/sudoers.d/tunaneko && chmod 440 /etc/sudoers.d/tunaneko && mkdir -p /etc/pf.anchors && touch /etc/pf.anchors/com.tunaneko"
        let script = "do shell script \"\(shell)\" with administrator privileges"
        var error: NSDictionary?
        if let apple = NSAppleScript(source: script) {
            apple.executeAndReturnError(&error)
        }
        if let error {
            state.logs.append("sudoers setup failed: \(error)")
        }
        recheckPrivileges()
    }

    private func recheckPrivileges() {
        sudoersOK = KillSwitchService.sudoersConfigured(corePath: VPNProcess.bundledCorePath)
        killOK = KillSwitchService.killRuleConfigured()
        state.privilegesMissing = !(sudoersOK && killOK)
        if !state.privilegesMissing, case .failed = state.status {
            state.status = .disconnected
            state.lastError = nil
        }
    }
}
