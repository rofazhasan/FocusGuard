import SwiftUI
import FocusGuardCore

public struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(.accentColor)
                    Text("FocusGuard")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.isEnrolled ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(appState.isEnrolled ? "Enrolled" : "Standalone")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            if appState.extensionTamperDetected {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("EXTENSION MISSING")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.red)
                        Spacer()
                        Text("\(appState.extensionGraceRemainingSeconds)s")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                    }
                    Text("\(appState.tamperBrowserName) will force-quit in \(appState.extensionGraceRemainingSeconds)s if extension is not enabled.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.red.opacity(0.12))
                .cornerRadius(6)

                Divider()
            }

            // Focus Lockdown Quick Action Section
            if appState.isFocusActive {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text("DEEP WORK ACTIVE")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.orange)

                        Spacer()

                        Text(formatCountdown(appState.focusRemainingSeconds))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }

                    Button(action: {
                        Task { await appState.endFocusLockdown() }
                    }) {
                        HStack {
                            Spacer()
                            Text("Release Fleet Lockdown")
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            } else {
                HStack(spacing: 8) {
                    Button(action: {
                        Task { await appState.startFocusLockdown(minutes: 25) }
                    }) {
                        Label("25m Focus", systemImage: "bolt.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)

                    Button(action: {
                        Task { await appState.startFocusLockdown(minutes: 45) }
                    }) {
                        Text("45m")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: {
                        Task { await appState.startFocusLockdown(minutes: 60) }
                    }) {
                        Text("60m")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            // Telemetry Snapshot
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Foreground:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(appState.currentForegroundApp)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }

                HStack {
                    Text("Today's Active:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(formatActiveTime(appState.todayUsageSeconds))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                }
            }

            Divider()

            // Navigation and Actions
            HStack(spacing: 8) {
                Button(action: {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }) {
                    Text("Open Dashboard")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: {
                    appState.syncEventsNow()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .font(.system(size: 11))
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func formatCountdown(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func formatActiveTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 {
            return "\(m)m \(s)s"
        } else {
            return "\(s)s"
        }
    }
}
