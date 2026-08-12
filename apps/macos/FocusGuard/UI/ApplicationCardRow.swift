import SwiftUI

public struct AppUsageItem: Identifiable {
    public let id = UUID()
    public let name: String
    public let iconName: String
    public let category: String
    public let usedMinutes: Int
    public let limitMinutes: Int
    public let themeColor: Color

    public init(name: String, iconName: String, category: String, usedMinutes: Int, limitMinutes: Int, themeColor: Color) {
        self.name = name
        self.iconName = iconName
        self.category = category
        self.usedMinutes = usedMinutes
        self.limitMinutes = limitMinutes
        self.themeColor = themeColor
    }

    public var remainingMinutes: Int {
        return max(0, limitMinutes - usedMinutes)
    }

    public var statusText: String {
        if usedMinutes >= limitMinutes {
            return "Limit Reached"
        } else if remainingMinutes <= 5 {
            return "Almost at limit"
        } else {
            return "Active"
        }
    }

    public var statusColor: Color {
        if usedMinutes >= limitMinutes {
            return FocusGuardTheme.Colors.danger
        } else if remainingMinutes <= 5 {
            return FocusGuardTheme.Colors.warning
        } else {
            return FocusGuardTheme.Colors.success
        }
    }
}

public struct ApplicationCardRow: View {
    let item: AppUsageItem

    public init(item: AppUsageItem) {
        self.item = item
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(item.themeColor.opacity(0.16))
                    .frame(width: 42, height: 42)

                Image(systemName: item.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(item.themeColor)
            }

            // App Name & Remaining Time
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(FocusGuardTheme.Colors.textPrimary)

                HStack(spacing: 6) {
                    Text("\(item.usedMinutes)m / \(item.limitMinutes)m")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(FocusGuardTheme.Colors.textSecondary)

                    Text("•")
                        .foregroundColor(FocusGuardTheme.Colors.textMuted)

                    Text("\(item.remainingMinutes)m remaining")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(item.remainingMinutes <= 5 ? FocusGuardTheme.Colors.warning : FocusGuardTheme.Colors.textMuted)
                }
            }

            Spacer()

            // Status Tag
            Text(item.statusText)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(item.statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(item.statusColor.opacity(0.12))
                .cornerRadius(FocusGuardTheme.Radius.small)
                .overlay(
                    RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.small)
                        .stroke(item.statusColor.opacity(0.25), lineWidth: 1)
                )
        }
        .padding(14)
        .background(FocusGuardTheme.Colors.surface)
        .cornerRadius(FocusGuardTheme.Radius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.medium)
                .stroke(FocusGuardTheme.Colors.border, lineWidth: 1)
        )
    }
}
