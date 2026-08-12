import SwiftUI

// MARK: - Skeleton Loading View Placeholder
public struct SkeletonCardView: View {
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(FocusGuardTheme.Colors.surfaceElevated)
                .frame(width: 120, height: 14)

            RoundedRectangle(cornerRadius: 6)
                .fill(FocusGuardTheme.Colors.surfaceElevated)
                .frame(width: 180, height: 28)

            RoundedRectangle(cornerRadius: 4)
                .fill(FocusGuardTheme.Colors.surfaceElevated)
                .frame(maxWidth: .infinity, height: 8)
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

// MARK: - Empty State Component
public struct EmptyStateView: View {
    let title: String
    let description: String
    let buttonTitle: String?
    let onAction: () -> Void

    public init(title: String, description: String, buttonTitle: String? = nil, onAction: @escaping () -> Void = {}) {
        self.title = title
        self.description = description
        self.buttonTitle = buttonTitle
        self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.fill")
                .font(.system(size: 32))
                .foregroundColor(FocusGuardTheme.Colors.textMuted)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(FocusGuardTheme.Colors.textPrimary)

            Text(description)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(FocusGuardTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            if let btn = buttonTitle {
                Button(action: onAction) {
                    Text(btn)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FocusGuardTheme.Colors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(FocusGuardTheme.Colors.accent.opacity(0.12))
                        .cornerRadius(FocusGuardTheme.Radius.medium)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(FocusGuardTheme.Colors.surface)
        .cornerRadius(FocusGuardTheme.Radius.large)
        .overlay(
            RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.large)
                .stroke(FocusGuardTheme.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Offline Banner Indicator
public struct OfflineBannerView: View {
    public init() {}
    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .foregroundColor(FocusGuardTheme.Colors.warning)
                .font(.system(size: 14))

            Text("Offline • Cached policies continue to protect this device.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(FocusGuardTheme.Colors.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(FocusGuardTheme.Colors.warning.opacity(0.12))
        .cornerRadius(FocusGuardTheme.Radius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.medium)
                .stroke(FocusGuardTheme.Colors.warning.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Error Alert Component
public struct ErrorStateCardView: View {
    let message: String
    let onRetry: () -> Void

    public init(message: String = "FocusGuard couldn't sync your latest usage.", onRetry: @escaping () -> Void) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(FocusGuardTheme.Colors.danger)
                .font(.system(size: 18))

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(FocusGuardTheme.Colors.textPrimary)

            Spacer()

            Button(action: onRetry) {
                Text("TRY AGAIN")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(FocusGuardTheme.Colors.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(FocusGuardTheme.Colors.danger.opacity(0.12))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(FocusGuardTheme.Colors.surface)
        .cornerRadius(FocusGuardTheme.Radius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.medium)
                .stroke(FocusGuardTheme.Colors.danger.opacity(0.3), lineWidth: 1)
        )
    }
}
