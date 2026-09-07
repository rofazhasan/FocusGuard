import SwiftUI
import FocusGuardCore

public struct UsageView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Usage Analytics")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Historical usage logs and continuous session breakdown")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                // Summary Stats
                HStack(spacing: 16) {
                    StatCard(
                        title: "Total Tracked Today",
                        value: "\(appState.todayUsageSeconds)s",
                        subtitle: "Active foreground time"
                    )

                    StatCard(
                        title: "Sessions Recorded",
                        value: "\(appState.recentSessions.count)",
                        subtitle: "Stored in SQLite WAL"
                    )

                    StatCard(
                        title: "Tracked Apps",
                        value: "\(appState.trackedTargets.count)",
                        subtitle: "Active target filters"
                    )
                }

                // Session Log Table
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recorded Application Sessions")
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    if appState.recentSessions.isEmpty {
                        Text("No sessions recorded yet today.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 24)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(appState.recentSessions, id: \.id) { session in
                                HStack {
                                    Image(systemName: "app.fill")
                                        .foregroundColor(.accentColor)
                                        .font(.system(size: 16))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.bundleIdentifier)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("Date: \(session.date) • \(session.isClosed ? "Closed" : "Open Session")")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Text("\(session.durationSeconds)s")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 10)
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
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}
