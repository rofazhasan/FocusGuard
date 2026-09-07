import Foundation

public struct ProtectedAppDenylist {
    public static let criticalBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.loginwindow",
        "com.apple.systempreferences",
        "com.apple.systemsettings",
        "com.apple.activitymonitor",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.securityagent"
    ]

    public static func isProtected(bundleIdentifier: String) -> Bool {
        let clean = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return criticalBundleIdentifiers.contains(clean)
    }

    public static func validateTarget(bundleIdentifier: String) -> Result<String, Error> {
        let clean = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isProtected(bundleIdentifier: clean) {
            return .failure(NSError(
                domain: "FocusGuard.Safety",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Target '\(bundleIdentifier)' is a protected system application and cannot be restricted."]
            ))
        }
        return .success(clean)
    }
}
