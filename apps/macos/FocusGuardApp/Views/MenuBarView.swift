import SwiftUI
import FocusGuardCore

public struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("FocusGuard", systemImage: "shield.checkered")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Circle()
                    .fill(appState.isEnrolled ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Frontmost: \(appState.currentForegroundApp)")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("Status: \(appState.usageState.rawValue)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Today's Active Time: \(appState.todayUsageSeconds)s")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.accentColor)
            }

            Divider()

            HStack {
                Button("Sync") {
                    appState.syncEventsNow()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
        }
        .padding(14)
        .frame(width: 240)
    }
}
