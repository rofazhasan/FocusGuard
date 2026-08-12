import SwiftUI

@main
struct FocusGuardApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .navigationTitle("FocusGuard")
        }
        .windowStyle(.hiddenTitleBar)
    }
}
