import SwiftUI
import FocusGuardCore

@main
struct FocusGuardApp: App {
    @StateObject private var appState: AppState

    init() {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let bundleId = Bundle.main.bundleIdentifier ?? "com.focusguard.macos"
        let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if runningInstances.count > 1 {
            if let existing = runningInstances.first(where: { $0.processIdentifier != currentPid }) {
                existing.activate(options: .activateIgnoringOtherApps)
            }
            exit(0)
        }

        let container = (try? DependencyContainer.createProduction()) ?? {
            let mock = try! DependencyContainer.createMock()
            return mock.container
        }()
        _appState = StateObject(wrappedValue: AppState(container: container))
    }

    var body: some Scene {
        WindowGroup {
            MainAppView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)

        MenuBarExtra("FocusGuard", systemImage: "shield.checkered") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 520, height: 420)
        }
    }
}
