import SwiftUI
import FocusGuardCore

public struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var serverUrlInput: String = ""
    @State private var idleSecondsSelection: Int = 60
    @State private var soundAlertsToggle: Bool = true
    @State private var testConnectionStatus: String?
    @State private var isTestingConnection: Bool = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("FocusGuard Settings")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("System preferences, fleet server connection, and attention enforcement rules")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                // Section 1: Fleet Server Connection
                VStack(alignment: .leading, spacing: 14) {
                    Label("Fleet Command Center", systemImage: "server.rack")
                        .font(.system(size: 15, weight: .bold))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server API Base URL")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            TextField("http://localhost:8080", text: $serverUrlInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(size: 13, design: .monospaced))

                            Button(action: {
                                testConnection()
                            }) {
                                if isTestingConnection {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Test")
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        if let status = testConnectionStatus {
                            Text(status)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(status.contains("Online") ? .green : .red)
                                .padding(.top, 2)
                        }
                    }

                    HStack {
                        Circle()
                            .fill(appState.realtimeState == .connected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Real-Time Fleet Sync: \(appState.realtimeState.rawValue)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(18)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

                // Section 2: Attention & Idle Monitoring
                VStack(alignment: .leading, spacing: 14) {
                    Label("Attention Tracking Sensitivity", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .bold))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Idle Inactivity Threshold")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        Picker("", selection: $idleSecondsSelection) {
                            Text("30 seconds (Strict)").tag(30)
                            Text("60 seconds (Recommended)").tag(60)
                            Text("120 seconds (Relaxed)").tag(120)
                            Text("300 seconds (5 minutes)").tag(300)
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 300)

                        Text("If no keyboard or mouse events occur within this duration, FocusGuard automatically pauses active time accumulation.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(18)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

                // Section 3: Alerts & Audio
                VStack(alignment: .leading, spacing: 14) {
                    Label("Notifications & Feedback", systemImage: "bell.badge.fill")
                        .font(.system(size: 15, weight: .bold))

                    Toggle(isOn: $soundAlertsToggle) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sound Alerts")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Play a system alert chime when a focus session starts or limit is reached")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding(18)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

                // Save Action
                HStack {
                    Spacer()
                    Button("Save Preferences") {
                        savePreferences()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(24)
        }
        .onAppear {
            self.serverUrlInput = appState.serverBaseUrl
            self.idleSecondsSelection = appState.idleThresholdSeconds
            self.soundAlertsToggle = appState.soundAlertsEnabled
        }
    }

    private func savePreferences() {
        let cleanUrl = serverUrlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.updateSettings(
            url: cleanUrl.isEmpty ? "http://localhost:8080" : cleanUrl,
            idleSeconds: idleSecondsSelection,
            soundAlerts: soundAlertsToggle
        )
    }

    private func testConnection() {
        isTestingConnection = true
        testConnectionStatus = nil
        let target = serverUrlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(target)/health") else {
            isTestingConnection = false
            testConnectionStatus = "Invalid URL format"
            return
        }

        Task {
            do {
                let (_, res) = try await URLSession.shared.data(from: url)
                await MainActor.run {
                    self.isTestingConnection = false
                    if let http = res as? HTTPURLResponse, http.statusCode == 200 {
                        self.testConnectionStatus = "Online • Fleet Server Reachable (HTTP 200)"
                    } else {
                        self.testConnectionStatus = "Offline • Server returned non-200"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isTestingConnection = false
                    self.testConnectionStatus = "Failed to connect: \(error.localizedDescription)"
                }
            }
        }
    }
}
