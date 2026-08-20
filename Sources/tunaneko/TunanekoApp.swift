import SwiftUI

/// Ensures the VPN is torn down before the app exits; otherwise the
/// root-owned core keeps running and leaves a ghost tunnel (and, with the
/// kill switch on, a blocked network).
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state = appState, state.status.isConnected || state.status.isBusy else {
            return .terminateNow
        }
        state.disconnect()
        // vpnc-script do_disconnect runs quickly; give it a grace period
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct TunanekoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(state)
                .frame(minWidth: 640, minHeight: 460)
                .onAppear { appDelegate.appState = state }
        }
        .defaultSize(width: 720, height: 520)

        MenuBarExtra {
            TrayMenuView()
                .environmentObject(state)
        } label: {
            Image(systemName: trayIcon)
        }
        .menuBarExtraStyle(.menu)
    }

    private var trayIcon: String {
        switch state.status {
        case .connected: return "fish.fill"
        case .connecting: return "fish.circle"
        case .blockedByKillSwitch: return "shield.slash.fill"
        default: return "fish"
        }
    }
}

enum SidebarItem: String, Hashable, Identifiable {
    case home, servers, settings
    var id: String { rawValue }
}

/// Sidebar navigation (System Settings / WireGuard style).
struct MainView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.sidebar) {
                Label(L10n.tr("tab.home"), systemImage: "house")
                    .tag(SidebarItem.home)
                Label(L10n.tr("tab.servers"), systemImage: "server.rack")
                    .tag(SidebarItem.servers)
                Label(L10n.tr("tab.settings"), systemImage: "gear")
                    .tag(SidebarItem.settings)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch state.sidebar {
            case .home:
                HomeView()
            case .servers:
                ServerListView()
                    .padding()
            case .settings:
                SettingsView()
                    .padding()
            }
        }
    }
}
