import SwiftUI

public struct HeaderGreetingView: View {
    @ObservedObject var screenTime: ScreenTimeManager
    let userName: String

    public init(screenTime: ScreenTimeManager = ScreenTimeManager.shared, userName: String = "User") {
        self.screenTime = screenTime
        self.userName = userName
    }

    private var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    public var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("FOCUSGUARD")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(FocusGuardTheme.Colors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FocusGuardTheme.Colors.accent.opacity(0.12))
                        .cornerRadius(6)

                    Text("•")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(FocusGuardTheme.Colors.textMuted)

                    Text(timeBasedGreeting)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(FocusGuardTheme.Colors.textSecondary)
                }

                Text("Your attention today")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(FocusGuardTheme.Colors.textPrimary)
            }

            Spacer()

            Button(action: {
                Task {
                    await screenTime.requestAuthorization()
                }
            }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(screenTime.isAuthorized ? FocusGuardTheme.Colors.success : FocusGuardTheme.Colors.warning)
                        .frame(width: 8, height: 8)

                    Text(screenTime.isAuthorized ? "Protected" : "Grant Authorization")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FocusGuardTheme.Colors.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(FocusGuardTheme.Colors.surfaceElevated)
                .cornerRadius(FocusGuardTheme.Radius.full)
                .overlay(
                    RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.full)
                        .stroke(screenTime.isAuthorized ? FocusGuardTheme.Colors.success.opacity(0.3) : FocusGuardTheme.Colors.warning.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
