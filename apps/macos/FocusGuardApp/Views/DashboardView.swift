import SwiftUI
import FocusGuardCore

public struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Top Header Banner
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Focus Command Center")
                                .font(.system(size: 24, weight: .bold, design: .rounded))

                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 7, height: 7)
                                Text("LIVE")
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(4)
                        }
                        Text("Active real-time application tracking and focus policy enforcement")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.isEnrolled ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(appState.deviceStatus.rawValue)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(14)

                        Button(action: { appState.syncEventsNow() }) {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Extension Tamper Detection & 60-Second Grace Warning Banner
                if appState.extensionTamperDetected {
                    HStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.red)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("EXTENSION TAMPER ALERT: BROWSER FORCE-CLOSE IMMINENT")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundColor(.red)
                                Spacer()
                                Text("\(appState.extensionGraceRemainingSeconds)s REMAINING")
                                    .font(.system(size: 13, weight: .black, design: .monospaced))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.18))
                                    .cornerRadius(6)
                            }
                            Text("FocusGuard Extension is missing or disabled while \(appState.tamperBrowserName) is running! If not restored immediately, \(appState.tamperBrowserName) will FORCE QUIT in \(appState.extensionGraceRemainingSeconds) seconds.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(14)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.red.opacity(0.4), lineWidth: 1.5)
                    )
                }

                if appState.isEmergencyLocked {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ADMIN EMERGENCY STOP ACTIVE")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(.red)
                            Text("This device was remotely stopped by your administrator. Protected applications and distracting sites are locked down.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
                }

                // Focus Lockdown Control Panel
                FocusLockdownControlCard()

                // Telemetry Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    // Current Foreground
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Foreground App", systemImage: "macwindow")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(appState.currentForegroundApp)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        HStack {
                            Circle()
                                .fill(appState.usageState == .active ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                            Text("State: \(appState.usageState.rawValue)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                    // Daily Active Time
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Today's Tracked Usage", systemImage: "hourglass")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(formatTime(appState.todayUsageSeconds))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.accentColor)
                        Text("\(appState.todayUsageSeconds) seconds active today")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                    // Active Policies Count
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Active Policies", systemImage: "shield.lefthalf.filled")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("\(appState.activePolicies.count) Rules")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("\(appState.trackedTargets.count) applications monitored")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }

                // Top Websites & Recent Sessions Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Top Websites Visited Today")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Spacer()
                        if !appState.totalWebsiteTime.isEmpty && appState.totalWebsiteTime != "0s" {
                            Text("Total: \(appState.totalWebsiteTime)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }

                    if appState.websiteUsageList.isEmpty && appState.recentSessions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                            Text("No website or application usage recorded yet today")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else if !appState.websiteUsageList.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(appState.websiteUsageList.prefix(5)) { item in
                                HStack {
                                    Image(systemName: item.isDistraction ? "tv" : "globe")
                                        .foregroundColor(item.isDistraction ? .red : .accentColor)
                                        .font(.system(size: 15))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.domain)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(item.category)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if item.isExceeded {
                                        Text("EXCEEDED")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.red.opacity(0.15))
                                            .foregroundColor(.red)
                                            .cornerRadius(4)
                                    }

                                    Text(item.formattedTime)
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            ForEach(appState.recentSessions.prefix(5), id: \.id) { session in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.bundleIdentifier)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("Started: \(session.startedAt.formatted(date: .omitted, time: .standard))")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Text("\(session.durationSeconds)s")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(12)
            }
            .padding(24)
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let hrs = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60
        if hrs > 0 {
            return String(format: "%dh %02dm %02ds", hrs, mins, secs)
        } else {
            return String(format: "%02dm %02ds", mins, secs)
        }
    }
}

struct FocusLockdownControlCard: View {
    @EnvironmentObject var appState: AppState
    private let presets = [15, 25, 45, 60, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: appState.isFocusActive ? "bolt.fill" : "bolt.shield")
                        .font(.system(size: 18))
                        .foregroundColor(appState.isFocusActive ? .orange : .accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.isFocusActive ? "DEEP WORK LOCKDOWN ACTIVE" : "Fleet Deep Work Lockdown")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(appState.isFocusActive ? .orange : .primary)
                        Text(appState.isFocusActive
                             ? "Distraction blocking is enforced across this Mac and all enrolled fleet devices."
                             : "Arm scheduled distraction suppression across all paired devices.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if appState.isFocusActive {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text(formatCountdown(appState.focusRemainingSeconds))
                            .font(.system(size: 18, weight: .heavy, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(8)
                }
            }

            Divider()

            if appState.isFocusActive {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session Time Remaining")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Ends automatically in \(appState.focusRemainingSeconds / 60) minutes")
                            .font(.system(size: 12))
                    }

                    Spacer()

                    Button(action: {
                        Task { await appState.endFocusLockdown() }
                    }) {
                        Label("Release Fleet Lockdown", systemImage: "xmark.shield")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Duration Preset:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            ForEach(presets, id: \.self) { minutes in
                                Button(action: {
                                    appState.selectedFocusPresetMinutes = minutes
                                }) {
                                    Text("\(minutes)m")
                                        .font(.system(size: 12, weight: appState.selectedFocusPresetMinutes == minutes ? .bold : .regular))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(appState.selectedFocusPresetMinutes == minutes ? Color.accentColor : Color.secondary.opacity(0.12))
                                        .foregroundColor(appState.selectedFocusPresetMinutes == minutes ? .white : .primary)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer()

                        Button(action: {
                            Task {
                                await appState.startFocusLockdown(minutes: appState.selectedFocusPresetMinutes)
                            }
                        }) {
                            Label("Enforce Fleet Lockdown", systemImage: "bolt.fill")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(appState.isFocusActive ? Color.orange.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(appState.isFocusActive ? Color.orange.opacity(0.3) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func formatCountdown(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

