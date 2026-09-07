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
