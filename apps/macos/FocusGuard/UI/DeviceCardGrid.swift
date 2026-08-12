import SwiftUI

public struct DeviceItem: Identifiable {
    public let id = UUID()
    public let name: String
    public let platform: String // "MACOS", "ANDROID"
    public let isOnline: Bool
    public let lastSyncedText: String
    public let isProtected: Bool

    public init(name: String, platform: String, isOnline: Bool, lastSyncedText: String, isProtected: Bool) {
        self.name = name
        self.platform = platform
        self.isOnline = isOnline
        self.lastSyncedText = lastSyncedText
        self.isProtected = isProtected
    }
}

public struct DeviceCardGrid: View {
    let devices: [DeviceItem]

    public init(devices: [DeviceItem]) {
        self.devices = devices
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Enrolled Devices")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(FocusGuardTheme.Colors.textPrimary)

                Spacer()

                Text("\(devices.count) Active")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(FocusGuardTheme.Colors.textSecondary)
            }

            VStack(spacing: 10) {
                ForEach(devices) { dev in
                    HStack(spacing: 12) {
                        // Platform Icon
                        ZStack {
                            Circle()
                                .fill(FocusGuardTheme.Colors.surfaceElevated)
                                .frame(width: 36, height: 36)

                            Image(systemName: dev.platform == "MACOS" ? "laptopcomputer" : "iphone")
                                .font(.system(size: 16))
                                .foregroundColor(FocusGuardTheme.Colors.textSecondary)
                        }

                        // Device Name & Sync Status
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dev.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(FocusGuardTheme.Colors.textPrimary)

                            Text(dev.isOnline ? "Synced \(dev.lastSyncedText)" : "Offline • Last seen \(dev.lastSyncedText)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(dev.isOnline ? FocusGuardTheme.Colors.textSecondary : FocusGuardTheme.Colors.warning)
                        }

                        Spacer()

                        // Status Badge
                        if dev.isOnline && dev.isProtected {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(FocusGuardTheme.Colors.success)
                                    .frame(width: 6, height: 6)

                                Text("Protected")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(FocusGuardTheme.Colors.success)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(FocusGuardTheme.Colors.success.opacity(0.12))
                            .cornerRadius(6)
                        } else {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(FocusGuardTheme.Colors.warning)
                                    .frame(width: 6, height: 6)

                                Text("Unsynced")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(FocusGuardTheme.Colors.warning)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(FocusGuardTheme.Colors.warning.opacity(0.12))
                            .cornerRadius(6)
                        }
                    }
                    .padding(12)
                    .background(FocusGuardTheme.Colors.surface)
                    .cornerRadius(FocusGuardTheme.Radius.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: FocusGuardTheme.Radius.medium)
                            .stroke(FocusGuardTheme.Colors.border, lineWidth: 1)
                    )
                }
            }
        }
    }
}
