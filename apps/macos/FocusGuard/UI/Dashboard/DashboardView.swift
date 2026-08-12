import SwiftUI

public struct DashboardView: View {
    @StateObject private var screenTime = ScreenTimeManager.shared
    @State private var totalFocusMinutes: Int = 137 // 2h 17m
    @State private var budgetUsedMinutes: Int = 71
    @State private var budgetTotalMinutes: Int = 90
    @State private var isFocusActive: Bool = false
    @State private var focusRemainingSeconds: Int = 2700 // 45m
    @State private var timer: Timer? = nil

    let topApps = [
        ("YouTube", "28m", Color.red),
        ("Instagram", "17m", Color.purple),
        ("Browser", "41m", Color.blue)
    ]

    let devices = [
        ("MacBook Pro", "Protected", true),
        ("Android Phone", "Protected", true)
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FOCUSGUARD")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("Today's Attention")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                    Spacer()

                    Button(action: {
                        Task {
                            await screenTime.requestAuthorization()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(screenTime.isAuthorized ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(screenTime.isAuthorized ? "Protected" : "Setup Authorization")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }

                // Metric Cards Grid
                HStack(spacing: 16) {
                    // Total Focus Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Total Focus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("2h 17m")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                    // Attention Budget Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Attention Budget")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(budgetUsedMinutes)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(budgetUsedMinutes >= budgetTotalMinutes ? .red : .primary)
                            Text("/ \(budgetTotalMinutes) min")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        ProgressView(value: Double(budgetUsedMinutes), total: Double(budgetTotalMinutes))
                            .accentColor(budgetUsedMinutes >= budgetTotalMinutes ? .red : .blue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }

                // Top Apps & Devices Columns
                HStack(alignment: .top, spacing: 16) {
                    // Top Apps Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Top Apps")
                            .font(.system(size: 16, weight: .semibold))

                        VStack(spacing: 12) {
                            ForEach(topApps, id: \.0) { app in
                                HStack {
                                    Circle()
                                        .fill(app.2)
                                        .frame(width: 10, height: 10)
                                    Text(app.0)
                                        .font(.system(size: 14, weight: .medium))
                                    Spacer()
                                    Text(app.1)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                    // Devices Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Devices")
                            .font(.system(size: 16, weight: .semibold))

                        VStack(spacing: 12) {
                            ForEach(devices, id: \.0) { dev in
                                HStack {
                                    Image(systemName: dev.0.contains("Mac") ? "laptopcomputer" : "phone")
                                        .foregroundColor(.secondary)
                                    Text(dev.0)
                                        .font(.system(size: 14, weight: .medium))
                                    Spacer()
                                    Text(dev.1)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.12))
                                        .cornerRadius(8)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }

                // Focus Action Bar
                VStack(spacing: 16) {
                    if isFocusActive {
                        VStack(spacing: 8) {
                            Text("FOCUS SESSION ACTIVE")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)

                            Text(formatSeconds(focusRemainingSeconds))
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)

                            Button(action: stopFocusSession) {
                                Text("End Focus Session")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button(action: startFocusSession) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                Text("START FOCUS")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(14)
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
            .padding(32)
        }
        .frame(minWidth: 720, minHeight: 600)
    }

    private func startFocusSession() {
        isFocusActive = true
        focusRemainingSeconds = 2700 // 45 mins
        screenTime.applyShields(applications: ["com.google.android.youtube", "com.instagram.main"], webDomains: ["youtube.com", "instagram.com"])
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if focusRemainingSeconds > 0 {
                focusRemainingSeconds -= 1
            } else {
                stopFocusSession()
            }
        }
    }

    private func stopFocusSession() {
        timer?.invalidate()
        timer = nil
        isFocusActive = false
        screenTime.removeShields()
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
