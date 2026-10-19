import SwiftUI
import Charts
import FocusGuardCore

public struct UsageView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedFilter: String = "ALL"

    public init() {}

    private var filteredWebsites: [AppState.WebsiteUsageItem] {
        switch selectedFilter {
        case "DISTRACTION":
            return appState.websiteUsageList.filter { $0.isDistraction || $0.category.contains("Social") || $0.category.contains("Entertainment") }
        case "WORK":
            return appState.websiteUsageList.filter { $0.category.contains("Development") || $0.category.contains("Engineering") || $0.category.contains("Work") }
        case "ACADEMIC":
            return appState.websiteUsageList.filter { $0.category.contains("Education") || $0.category.contains("Academic") }
        default:
            return appState.websiteUsageList
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header Banner
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Website & Attention Analytics")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Real-time website browsing duration and continuous application attention monitoring")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        appState.fetchWebsiteAnalytics()
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                // Summary Stat Cards
                HStack(spacing: 16) {
                    StatCard(
                        title: "Total Website Time Today",
                        value: appState.totalWebsiteTime.isEmpty ? "0s" : appState.totalWebsiteTime,
                        subtitle: "Aggregated browser activity"
                    )

                    StatCard(
                        title: "Websites Tracked",
                        value: "\(appState.websiteUsageList.count)",
                        subtitle: "Domains visited today"
                    )

                    StatCard(
                        title: "Foreground App Time",
                        value: "\(appState.todayUsageSeconds)s",
                        subtitle: "Active native window"
                    )
                }

                // Swift Charts: Category Attention Breakdown
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Attention Breakdown by Category")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text("Real-time aggregated distribution across productive work, learning, and distraction")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }

                    if appState.categoryUsageBreakdown.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 22))
                                .foregroundColor(.secondary)
                            Text("No category telemetry accumulated yet today. Attention data populates as websites and apps are active.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 16)
                    } else {
                        Chart(appState.categoryUsageBreakdown) { item in
                            BarMark(
                                x: .value("Minutes", item.totalMinutes),
                                y: .value("Category", item.category)
                            )
                            .foregroundStyle(item.isDistraction ? Color.red.gradient : Color.accentColor.gradient)
                            .cornerRadius(4)
                            .annotation(position: .trailing) {
                                Text(String(format: "%.1fm", item.totalMinutes))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 4)
                            }
                        }
                        .frame(height: max(130, CGFloat(appState.categoryUsageBreakdown.count * 38)))
                        .chartXAxis {
                            AxisMarks(position: .bottom)
                        }
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(12)

                // Websites Breakdown Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Websites & Domains Usage")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text("Accurate millisecond telemetry collected live from your browsers")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Filter Picker
                        Picker("", selection: $selectedFilter) {
                            Text("All (\(appState.websiteUsageList.count))").tag("ALL")
                            Text("Distractions").tag("DISTRACTION")
                            Text("Work & Dev").tag("WORK")
                            Text("Academic").tag("ACADEMIC")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 320)
                    }

                    if filteredWebsites.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary)
                            Text(appState.websiteUsageList.isEmpty ? "No website usage recorded yet today. Open any website in your browser to begin monitoring." : "No websites matching this filter.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(filteredWebsites) { item in
                                WebsiteUsageRow(item: item)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(12)

                // Recorded Application Sessions (SQLite WAL)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Native Application Sessions")
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    if appState.recentSessions.isEmpty {
                        Text("No native desktop app sessions recorded yet today.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 14)
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
        .onAppear {
            appState.fetchWebsiteAnalytics()
        }
    }
}

struct WebsiteUsageRow: View {
    let item: AppState.WebsiteUsageItem

    private var categoryColor: Color {
        if item.category.contains("Social") || item.category.contains("Entertainment") {
            return Color.red
        } else if item.category.contains("Development") || item.category.contains("Engineering") {
            return Color.green
        } else if item.category.contains("Education") || item.category.contains("Academic") {
            return Color.blue
        } else if item.category.contains("Work") {
            return Color.purple
        }
        return Color.secondary
    }

    private var categoryIcon: String {
        if item.category.contains("Social") || item.category.contains("Entertainment") {
            return "tv"
        } else if item.category.contains("Development") || item.category.contains("Engineering") {
            return "chevron.left.forwardslash.chevron.right"
        } else if item.category.contains("Education") || item.category.contains("Academic") {
            return "graduationcap"
        } else if item.category.contains("Work") {
            return "briefcase"
        }
        return "safari"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: categoryIcon)
                .foregroundColor(categoryColor)
                .font(.system(size: 18))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(item.domain)
                        .font(.system(size: 13, weight: .semibold))
                    Text(item.category)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor.opacity(0.12))
                        .foregroundColor(categoryColor)
                        .cornerRadius(4)
                }

                if let policy = item.policyName, !policy.isEmpty {
                    Text("Policy: \(policy)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if item.isExceeded {
                Text("BUDGET EXCEEDED")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(4)
            } else if let limit = item.limitSeconds, limit > 0 {
                Text("Cap: \(limit / 60)m")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.formattedTime)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                Text("\(item.totalSeconds)s total")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
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
