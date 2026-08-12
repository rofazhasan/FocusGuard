import SwiftUI

public struct AttentionBudgetHeroCard: View {
    let usedMinutes: Int
    let totalMinutes: Int
    let categoryName: String

    public init(usedMinutes: Int, totalMinutes: Int, categoryName: String = "Entertainment Budget") {
        self.usedMinutes = usedMinutes
        self.totalMinutes = totalMinutes
        self.categoryName = categoryName
    }

    private var progressFraction: Double {
        guard totalMinutes > 0 else { return 0 }
        return min(1.0, Double(usedMinutes) / Double(totalMinutes))
    }

    private var remainingMinutes: Int {
        return max(0, totalMinutes - usedMinutes)
    }

    private var statusColor: Color {
        if progressFraction >= 1.0 {
            return FocusGuardTheme.Colors.danger
        } else if progressFraction >= 0.8 {
            return FocusGuardTheme.Colors.warning
        } else {
            return FocusGuardTheme.Colors.accent
        }
    }

    public var body: some View {
        HStack(spacing: 32) {
            // Circular Ring Progress Gauge
            ZStack {
                Circle()
                    .stroke(FocusGuardTheme.Colors.border, lineWidth: 12)
                    .frame(width: 130, height: 130)

                Circle()
                    .trim(from: 0, to: CGFloat(progressFraction))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [statusColor, FocusGuardTheme.Colors.violet]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 130, height: 130)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progressFraction)

                VStack(spacing: 2) {
                    Text("\(Int(progressFraction * 100))%")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(FocusGuardTheme.Colors.textPrimary)
                    Text("consumed")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(FocusGuardTheme.Colors.textMuted)
                }
            }

            // Budget Numeric Overview
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("ATTENTION BUDGET")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(FocusGuardTheme.Colors.textSecondary)

                    Text("•")
                        .foregroundColor(FocusGuardTheme.Colors.textMuted)

                    Text(categoryName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FocusGuardTheme.Colors.textMuted)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(usedMinutes)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(statusColor)

                    Text("/ \(totalMinutes) min")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(FocusGuardTheme.Colors.textSecondary)
                }

                HStack(spacing: 8) {
                    Image(systemName: remainingMinutes == 0 ? "exclamationmark.octagon.fill" : "hourglass.bottomhalf.filled")
                        .foregroundColor(statusColor)
                        .font(.system(size: 13))

                    Text(remainingMinutes == 0 ? "Budget exhausted — Shields active" : "\(remainingMinutes)m remaining today")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(remainingMinutes == 0 ? FocusGuardTheme.Colors.danger : FocusGuardTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.12))
                .cornerRadius(6)
            }

            Spacer()
        }
        .padding(24)
        .background(FocusGuardTheme.Colors.surface)
        .cornerRadius(FocusGuardTheme.Radius.large)
        .overlay(
            RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.large)
                .stroke(FocusGuardTheme.Colors.border, lineWidth: 1)
        )
    }
}
