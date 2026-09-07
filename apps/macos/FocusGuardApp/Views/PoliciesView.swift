import SwiftUI
import FocusGuardCore

public struct PoliciesView: View {
    @EnvironmentObject var appState: AppState

    @State private var policyName: String = "Discord Limit"
    @State private var targetBundle: String = "com.hnc.discord"
    @State private var limitMinutes: Int = 30
    @State private var warningMinutes: Int = 20
    @State private var selectedAction: EnforcementAction = .closeApplication
    @State private var isCreating: Bool = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Focus Policies")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Deterministic focus rules, daily limits, and enforcement actions")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { isCreating.toggle() }) {
                        Label(isCreating ? "Cancel" : "Add Policy", systemImage: isCreating ? "xmark" : "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Add Policy Form
                if isCreating {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Create Focus Rule")
                            .font(.system(size: 15, weight: .bold))

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rule Name")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                TextField("e.g. Gaming Limit", text: $policyName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Target Bundle Identifier")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                TextField("e.g. com.hnc.discord", text: $targetBundle)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Daily Limit (Minutes)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                TextField("Minutes", value: $limitMinutes, formatter: NumberFormatter())
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Warning Threshold (Minutes)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                TextField("Minutes", value: $warningMinutes, formatter: NumberFormatter())
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Action")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Picker("", selection: $selectedAction) {
                                    Text("Close App").tag(EnforcementAction.closeApplication)
                                    Text("Notify").tag(EnforcementAction.notify)
                                    Text("Overlay").tag(EnforcementAction.focusGuardOverlay)
                                    Text("Pause Tracking").tag(EnforcementAction.pauseTracking)
                                }
                                .labelsHidden()
                            }
                        }

                        HStack {
                            Spacer()
                            Button("Save Policy") {
                                appState.savePolicy(
                                    name: policyName,
                                    limitMinutes: limitMinutes,
                                    warningMinutes: warningMinutes,
                                    targetBundle: targetBundle,
                                    action: selectedAction
                                )
                                isCreating = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(12)
                }

                // Policy List
                VStack(alignment: .leading, spacing: 12) {
                    Text("Active Policy Rules (\(appState.activePolicies.count))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    if appState.activePolicies.isEmpty {
                        Text("No policies configured. Click 'Add Policy' or sync from FocusGuard Cloud.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 24)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(appState.activePolicies, id: \.id) { policy in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(policy.name)
                                            .font(.system(size: 14, weight: .bold))
                                        HStack(spacing: 8) {
                                            let targets = policy.targets.map { $0.targetValue }.joined(separator: ", ")
                                            Text("Targets: \(targets.isEmpty ? "None" : targets)")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                            Text("•")
                                                .foregroundColor(.secondary)
                                            Text("Limit: \(policy.limitSeconds / 60)m")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.accentColor)
                                            Text("•")
                                                .foregroundColor(.secondary)
                                            Text("Action: \(policy.enforcementAction.rawValue)")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Button(action: { appState.deletePolicy(id: policy.id) }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(12)
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
