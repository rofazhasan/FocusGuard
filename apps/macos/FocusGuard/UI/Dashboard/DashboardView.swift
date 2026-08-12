import SwiftUI

public struct DashboardView: View {
    @StateObject private var screenTime = ScreenTimeManager.shared
    @StateObject private var viewModel = DashboardViewModel()

    @State private var isPolicyEditorPresented: Bool = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Greeting
                HeaderGreetingView(screenTime: screenTime, userName: "Rofaz")

                // DEV FIXTURE Diagnostic Indicator
                if viewModel.isDevelopmentFixture {
                    HStack(spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 11))
                            .foregroundColor(FocusGuardTheme.Colors.warning)

                        Text("DEV FIXTURE ACTIVE • Backend unauthenticated, rendering isolated local telemetry fixture")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(FocusGuardTheme.Colors.warning)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(FocusGuardTheme.Colors.warning.opacity(0.12))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(FocusGuardTheme.Colors.warning.opacity(0.3), lineWidth: 1)
                    )
                }

                // Offline Notice (If triggered)
                if viewModel.isOffline {
                    OfflineBannerView()
                }

                // Error Card (If present)
                if let err = viewModel.errorMessage {
                    ErrorStateCardView(message: err) {
                        viewModel.errorMessage = nil
                    }
                }

                // Attention Budget Hero Ring Card
                AttentionBudgetHeroCard(usedMinutes: viewModel.usedMinutes, totalMinutes: viewModel.totalMinutes)

                // Main Content Grid (Top Apps & Focus / Devices)
                HStack(alignment: .top, spacing: 24) {
                    // Left Column: Applications Usage
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Top Applications")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(FocusGuardTheme.Colors.textPrimary)

                            Spacer()

                            Button(action: {
                                isPolicyEditorPresented = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Rule")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(FocusGuardTheme.Colors.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(FocusGuardTheme.Colors.accent.opacity(0.12))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }

                        if viewModel.apps.isEmpty {
                            EmptyStateView(
                                title: "No policies configured yet",
                                description: "Create your first attention rule to begin protecting your focus.",
                                buttonTitle: "CREATE POLICY"
                            ) {
                                isPolicyEditorPresented = true
                            }
                        } else {
                            VStack(spacing: 12) {
                                ForEach(viewModel.apps) { item in
                                    ApplicationCardRow(item: item)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Right Column: Focus Session & Devices
                    VStack(alignment: .leading, spacing: 24) {
                        // Focus Session Card
                        FocusSessionCardView(
                            isFocusActive: $viewModel.isFocusActive,
                            remainingSeconds: $viewModel.focusRemainingSeconds,
                            onStart: { durationSec in
                                viewModel.startFocusSession(durationSeconds: durationSec)
                            },
                            onStop: {
                                viewModel.stopFocusSession()
                            }
                        )

                        // Enrolled Devices Grid
                        DeviceCardGrid(devices: viewModel.devices)
                    }
                    .frame(width: 360)
                }
            }
            .padding(32)
        }
        .background(FocusGuardTheme.Colors.background.edgesIgnoringSafeArea(.all))
        .sheet(isPresented: $isPolicyEditorPresented) {
            PolicyEditorView { name, target, limitSec in
                let newApp = AppUsageItem(
                    name: name,
                    iconName: "app.badge.checkmark.fill",
                    category: "Custom",
                    usedMinutes: 0,
                    limitMinutes: limitSec / 60,
                    themeColor: FocusGuardTheme.Colors.accent
                )
                viewModel.apps.append(newApp)
            }
        }
        .frame(minWidth: 840, minHeight: 680)
    }
}
