import SwiftUI

public struct FocusSessionCardView: View {
    @Binding var isFocusActive: Bool
    @Binding var remainingSeconds: Int
    let onStart: (Int) -> Void
    let onStop: () -> Void

    @State private var selectedDurationMinutes: Int = 45
    @State private var isCompleted: Bool = false

    let durationOptions = [15, 30, 45, 60]
    let blockedApps = ["YouTube", "Instagram", "Reddit", "TikTok"]
    let allowedApps = ["Messages", "University", "Xcode", "Notes"]

    public init(
        isFocusActive: Binding<Bool>,
        remainingSeconds: Binding<Int>,
        onStart: @escaping (Int) -> Void,
        onStop: @escaping () -> Void
    ) {
        self._isFocusActive = isFocusActive
        self._remainingSeconds = remainingSeconds
        self.onStart = onStart
        self.onStop = onStop
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isFocusActive {
                // ACTIVE FOCUS SESSION STATE
                VStack(spacing: 16) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(FocusGuardTheme.Colors.accent)
                                .frame(width: 8, height: 8)
                            Text("FOCUS SESSION ACTIVE")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(FocusGuardTheme.Colors.accent)
                        }
                        Spacer()
                        Text("Protected")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(FocusGuardTheme.Colors.success)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(FocusGuardTheme.Colors.success.opacity(0.12))
                            .cornerRadius(6)
                    }

                    Text(formatTime(remainingSeconds))
                        .font(.system(size: 54, weight: .bold, design: .monospaced))
                        .foregroundColor(FocusGuardTheme.Colors.textPrimary)

                    Text("Keep working. Distractions are actively shielded across your devices.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(FocusGuardTheme.Colors.textSecondary)

                    Button(action: {
                        onStop()
                        isCompleted = true
                    }) {
                        Text("End Focus Session")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(FocusGuardTheme.Colors.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(FocusGuardTheme.Colors.danger.opacity(0.12))
                            .cornerRadius(FocusGuardTheme.Radius.medium)
                    }
                    .buttonStyle(.plain)
                }
            } else if isCompleted {
                // FOCUS COMPLETE SUMMARY STATE
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundColor(FocusGuardTheme.Colors.success)

                    Text("FOCUS COMPLETE")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(FocusGuardTheme.Colors.textPrimary)

                    Text("\(selectedDurationMinutes) minutes protected • 0 distraction attempts")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(FocusGuardTheme.Colors.textSecondary)

                    Button(action: {
                        isCompleted = false
                    }) {
                        Text("Start Another Session")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(FocusGuardTheme.Colors.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(FocusGuardTheme.Colors.accent.opacity(0.12))
                            .cornerRadius(FocusGuardTheme.Radius.medium)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // BEFORE STARTING SETUP STATE
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Focus Session")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(FocusGuardTheme.Colors.textPrimary)

                            Text("Lock down non-essential apps for a deep work block")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(FocusGuardTheme.Colors.textSecondary)
                        }
                        Spacer()
                    }

                    // Duration Chips
                    HStack(spacing: 10) {
                        ForEach(durationOptions, id: \.self) { mins in
                            Button(action: {
                                selectedDurationMinutes = mins
                            }) {
                                Text("\(mins) min")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(selectedDurationMinutes == mins ? FocusGuardTheme.Colors.textPrimary : FocusGuardTheme.Colors.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selectedDurationMinutes == mins ? FocusGuardTheme.Colors.accent : FocusGuardTheme.Colors.surfaceElevated)
                                    .cornerRadius(FocusGuardTheme.Radius.medium)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Blocked vs Allowed Lists
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BLOCKED (\(blockedApps.count))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(FocusGuardTheme.Colors.danger)

                            ForEach(blockedApps, id: \.self) { app in
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(FocusGuardTheme.Colors.danger)
                                    Text(app)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(FocusGuardTheme.Colors.textSecondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(FocusGuardTheme.Colors.surfaceElevated.opacity(0.6))
                        .cornerRadius(FocusGuardTheme.Radius.medium)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("ALLOWED (\(allowedApps.count))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(FocusGuardTheme.Colors.success)

                            ForEach(allowedApps, id: \.self) { app in
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(FocusGuardTheme.Colors.success)
                                    Text(app)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(FocusGuardTheme.Colors.textSecondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(FocusGuardTheme.Colors.surfaceElevated.opacity(0.6))
                        .cornerRadius(FocusGuardTheme.Radius.medium)
                    }

                    // START FOCUS Button
                    Button(action: {
                        onStart(selectedDurationMinutes * 60)
                    }) {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("START FOCUS")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [FocusGuardTheme.Colors.accent, FocusGuardTheme.Colors.indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(FocusGuardTheme.Radius.medium)
                        .shadow(color: FocusGuardTheme.Colors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(FocusGuardTheme.Colors.surface)
        .cornerRadius(FocusGuardTheme.Radius.large)
        .overlay(
            RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.large)
                .stroke(FocusGuardTheme.Colors.border, lineWidth: 1)
        )
    }
}
