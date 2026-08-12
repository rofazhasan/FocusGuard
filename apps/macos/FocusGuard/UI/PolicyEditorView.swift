import SwiftUI

public struct PolicyEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var ruleName: String = "YouTube Limit"
    @State private var targetValue: String = "youtube.com"
    @State private var limitMinutes: Int = 30
    @State private var scheduleOption: String = "Every day"
    @State private var targetDeviceOption: String = "All enrolled devices"

    let onSave: (String, String, Int) -> Void

    public init(onSave: @escaping (String, String, Int) -> Void) {
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CREATE ATTENTION RULE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(FocusGuardTheme.Colors.accent)

                    Text("Guided Policy Builder")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(FocusGuardTheme.Colors.textPrimary)
                }
                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(FocusGuardTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .background(FocusGuardTheme.Colors.border)

            // Step 1: Target App/Domain
            VStack(alignment: .leading, spacing: 6) {
                Text("1. TARGET PLATFORM / WEBSITE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(FocusGuardTheme.Colors.textSecondary)

                TextField("e.g. YouTube / youtube.com / instagram.com", text: $targetValue)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(FocusGuardTheme.Colors.surfaceElevated)
                    .cornerRadius(FocusGuardTheme.Radius.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.medium)
                            .stroke(FocusGuardTheme.Colors.border, lineWidth: 1)
                    )
            }

            // Step 2: Daily Budget Limit
            VStack(alignment: .leading, spacing: 6) {
                Text("2. DAILY ATTENTION LIMIT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(FocusGuardTheme.Colors.textSecondary)

                HStack {
                    Slider(value: Binding(
                        get: { Double(limitMinutes) },
                        set: { limitMinutes = Int($0) }
                    ), in: 5...120, step: 5)

                    Text("\(limitMinutes) min/day")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(FocusGuardTheme.Colors.accent)
                        .frame(width: 90, alignment: .trailing)
                }
            }

            // Live Preview Box
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill")
                        .foregroundColor(FocusGuardTheme.Colors.info)
                        .font(.system(size: 12))

                    Text("LIVE CONSEQUENCE PREVIEW")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(FocusGuardTheme.Colors.info)
                }

                Text("When cumulative attention on '\(targetValue.isEmpty ? "target" : targetValue)' reaches \(limitMinutes) minutes in a day, FocusGuard will automatically shield access on \(targetDeviceOption.lowercased()).")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FocusGuardTheme.Colors.textSecondary)
            }
            .padding(14)
            .background(FocusGuardTheme.Colors.info.opacity(0.1))
            .cornerRadius(FocusGuardTheme.Radius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.medium)
                    .stroke(FocusGuardTheme.Colors.info.opacity(0.25), lineWidth: 1)
            )

            // Submit Button
            Button(action: {
                onSave(ruleName, targetValue, limitMinutes * 60)
                dismiss()
            }) {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                    Text("CREATE RULE")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(FocusGuardTheme.Colors.accent)
                .cornerRadius(FocusGuardTheme.Radius.medium)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(FocusGuardTheme.Colors.surface)
        .frame(width: 440)
    }
}
