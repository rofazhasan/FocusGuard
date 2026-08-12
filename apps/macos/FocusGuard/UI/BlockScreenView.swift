import SwiftUI

public struct BlockScreenView: View {
    let appName: String
    let usedMinutes: Int
    let limitMinutes: Int
    let nextResetTimeText: String
    let onDismiss: () -> Void

    public init(
        appName: String = "YouTube",
        usedMinutes: Int = 30,
        limitMinutes: Int = 30,
        nextResetTimeText: String = "12:00 AM",
        onDismiss: @escaping () -> Void = {}
    ) {
        self.appName = appName
        self.usedMinutes = usedMinutes
        self.limitMinutes = limitMinutes
        self.nextResetTimeText = nextResetTimeText
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header Tagline
            Text("FOCUSGUARD")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(FocusGuardTheme.Colors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(FocusGuardTheme.Colors.accent.opacity(0.12))
                .cornerRadius(8)

            // Shield Icon
            ZStack {
                Circle()
                    .fill(FocusGuardTheme.Colors.danger.opacity(0.12))
                    .frame(width: 90, height: 90)

                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 40))
                    .foregroundColor(FocusGuardTheme.Colors.danger)
            }

            VStack(spacing: 8) {
                Text("Time's up.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(FocusGuardTheme.Colors.textPrimary)

                Text("You've reached your \(appName) attention budget.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(FocusGuardTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Metric Tag
            HStack(spacing: 6) {
                Text("\(usedMinutes)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(FocusGuardTheme.Colors.danger)

                Text("/ \(limitMinutes) min")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(FocusGuardTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(FocusGuardTheme.Colors.surfaceElevated)
            .cornerRadius(FocusGuardTheme.Radius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.medium)
                    .stroke(FocusGuardTheme.Colors.border, lineWidth: 1)
            )

            // Reset Time Notice
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(FocusGuardTheme.Colors.textMuted)

                Text("Next budget reset at \(nextResetTimeText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(FocusGuardTheme.Colors.textMuted)
            }

            Spacer()

            Button(action: onDismiss) {
                Text("Close Application")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FocusGuardTheme.Colors.textPrimary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(FocusGuardTheme.Colors.surfaceElevated)
                    .cornerRadius(FocusGuardTheme.Radius.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.medium)
                            .stroke(FocusGuardTheme.Colors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FocusGuardTheme.Colors.background.edgesIgnoringSafeArea(.all))
    }
}
