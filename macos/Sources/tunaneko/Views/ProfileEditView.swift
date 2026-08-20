import SwiftUI

struct ProfileEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let profile: ServerProfile

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var useOwnCredentials = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(profile.name).font(.title2)
            Text(profile.host).font(.caption).foregroundStyle(.secondary)

            Toggle(L10n.tr("profile.own_credentials"), isOn: $useOwnCredentials)

            Group {
                TextField(L10n.tr("profile.username"), text: $username)
                SecureField(L10n.tr("profile.password"), text: $password)
            }
            .textFieldStyle(.roundedBorder)
            .disabled(!useOwnCredentials)

            if !useOwnCredentials {
                Text(L10n.tr("profile.using_default"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(L10n.tr("action.cancel")) { dismiss() }
                Button(L10n.tr("action.save")) { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            useOwnCredentials = profile.username != nil || profile.hasOwnPassword
            username = profile.username ?? ""
        }
    }

    private func save() {
        guard let idx = state.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var p = state.profiles[idx]

        if useOwnCredentials {
            p.username = username.isEmpty ? nil : username
            if !password.isEmpty {
                CredentialStore.setPassword(password, for: p.id.uuidString)
                p.hasOwnPassword = true
            }
        } else {
            p.username = nil
            CredentialStore.deletePassword(for: p.id.uuidString)
            p.hasOwnPassword = false
        }

        state.profiles[idx] = p
        ProfileStore.shared.save(state.profiles)
        dismiss()
    }
}
