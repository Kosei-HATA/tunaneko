import SwiftUI

struct TrayMenuView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Text(state.statusText)

        // Kill switch active: show the release action prominently at the top.
        if state.killSwitchActive {
            Label(L10n.tr("killswitch.active"), systemImage: "shield.slash.fill")
            Button("⚠️ " + L10n.tr("action.release_killswitch")) {
                state.releaseKillSwitch()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }

        Divider()

        if state.status.isConnected || state.status.isBusy {
            Button(L10n.tr("action.disconnect")) { state.disconnect() }
        } else if !state.killSwitchActive {
            Button(L10n.tr("action.connect")) { state.connect() }
        }

        Divider()

        Button(L10n.tr("tray.open")) {
            NSApp.activate(ignoringOtherApps: true)
            openMainWindow()
        }

        Divider()

        Button(L10n.tr("tray.quit")) { NSApp.terminate(nil) }
    }

    private func openMainWindow() {
        for window in NSApp.windows where window.title.isEmpty || !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
