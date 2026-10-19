import SwiftUI
import FocusGuardCore

public struct ApplicationsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newAppBundle: String = ""

    private let protectedSystemApps = [
        ("Finder", "com.apple.finder"),
        ("Login Window", "com.apple.loginwindow"),
        ("System Settings", "com.apple.systempreferences"),
        ("Activity Monitor", "com.apple.ActivityMonitor"),
        ("Dock", "com.apple.dock")
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monitored Applications")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Configure targets for focus tracking and view system-level safety guards")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                // Add Target Input
                HStack(spacing: 10) {
                    TextField("Bundle Identifier (e.g. com.google.Chrome)", text: $newAppBundle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button("Add Target") {
                        appState.addTrackedTarget(newAppBundle)
                        newAppBundle = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(10)

                // Discovered Running Applications Picker
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Running Applications Discovery")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text("Live apps running on your Mac. Click '+ Track' to monitor with FocusGuard policies.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            appState.refreshRunningApplications()
                        }) {
                            Label("Refresh Apps", systemImage: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                    }

                    if appState.runningApplicationsList.isEmpty {
                        Text("No running user applications discovered.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(appState.runningApplicationsList) { app in
                                HStack(spacing: 10) {
                                    Image(systemName: "app.window.checkmark")
                                        .foregroundColor(app.isTracked ? .green : .secondary)
                                        .font(.system(size: 16))
                                        .frame(width: 22)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(app.bundleIdentifier)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if app.isProtected {
                                        HStack(spacing: 4) {
                                            Image(systemName: "lock.shield")
                                            Text("System Protected")
                                        }
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.12))
                                        .foregroundColor(.orange)
                                        .cornerRadius(6)
                                    } else if app.isTracked {
                                        Button(action: {
                                            appState.removeTrackedTarget(app.bundleIdentifier)
                                        }) {
                                            Label("Stop Tracking", systemImage: "minus.circle")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.red)
                                    } else {
                                        Button(action: {
                                            appState.addTrackedTarget(app.bundleIdentifier)
                                        }) {
                                            Label("Track", systemImage: "plus.circle.fill")
                                                .font(.system(size: 11, weight: .semibold))
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
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
                .onAppear {
                    appState.refreshRunningApplications()
                }

                // Tracked Applications List
                VStack(alignment: .leading, spacing: 12) {
                    Text("Currently Tracked Applications (\(appState.trackedTargets.count))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    if appState.trackedTargets.isEmpty {
                        Text("No targets currently added. Enter a bundle identifier above.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 16)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(appState.trackedTargets, id: \.self) { bundleId in
                                HStack {
                                    Image(systemName: "checkmark.shield.fill")
                                        .foregroundColor(.green)

                                    Text(bundleId)
                                        .font(.system(size: 13, design: .monospaced))

                                    Spacer()

                                    Button(action: { appState.removeTrackedTarget(bundleId) }) {
                                        Image(systemName: "minus.circle")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
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

                // Protected System Apps (Denylist)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.orange)
                        Text("Protected System Applications (Safety Guard)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }

                    Text("These essential macOS core applications are permanently exempted from policy restriction and process termination to preserve system stability.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    VStack(spacing: 6) {
                        ForEach(protectedSystemApps, id: \.1) { (name, bundle) in
                            HStack {
                                Text(name)
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text(bundle)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text("PROTECTED")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            }
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(16)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(12)
            }
            .padding(24)
        }
    }
}
