import Foundation
import UserNotifications

public protocol NotificationAdapterProtocol: Sendable {
    func notifyWarning(appName: String, bundleIdentifier: String, remainingSeconds: Int)
    func notifyLimitReached(appName: String, bundleIdentifier: String)
    func notifyEnforcement(appName: String, bundleIdentifier: String, action: EnforcementAction)
}

public final class NotificationAdapter: NotificationAdapterProtocol, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let lock = NSLock()
    private var lastNotifiedTimes: [String: Date] = [:]
    private let throttleIntervalSeconds: TimeInterval

    public init(
        center: UNUserNotificationCenter = .current(),
        throttleIntervalSeconds: TimeInterval = 60.0
    ) {
        self.center = center
        self.throttleIntervalSeconds = throttleIntervalSeconds
    }

    public func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func shouldThrottle(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let last = lastNotifiedTimes[key] {
            if now.timeIntervalSince(last) < throttleIntervalSeconds {
                return true
            }
        }
        lastNotifiedTimes[key] = now
        return false
    }

    public func notifyWarning(appName: String, bundleIdentifier: String, remainingSeconds: Int) {
        let key = "warn_\(bundleIdentifier)"
        guard !shouldThrottle(key: key) else { return }

        let content = UNMutableNotificationContent()
        content.title = "FocusGuard Warning"
        let minutes = max(1, remainingSeconds / 60)
        content.body = "\(appName) limit approaching (\(minutes)m remaining today)."
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    public func notifyLimitReached(appName: String, bundleIdentifier: String) {
        let key = "limit_\(bundleIdentifier)"
        guard !shouldThrottle(key: key) else { return }

        let content = UNMutableNotificationContent()
        content.title = "FocusGuard Limit Reached"
        content.body = "You have reached your daily limit for \(appName)."
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    public func notifyEnforcement(appName: String, bundleIdentifier: String, action: EnforcementAction) {
        let key = "enforce_\(bundleIdentifier)"
        guard !shouldThrottle(key: key) else { return }

        let content = UNMutableNotificationContent()
        content.title = "FocusGuard Policy Enforced"
        switch action {
        case .closeApplication:
            content.body = "\(appName) was closed per your focus policy."
        case .focusGuardOverlay:
            content.body = "\(appName) has been restricted by FocusGuard."
        case .pauseTracking:
            content.body = "Tracking for \(appName) has been paused."
        case .notify:
            content.body = "\(appName) daily limit reached."
        }
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }
}

public final class MockNotificationAdapter: NotificationAdapterProtocol, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var notificationsSent: [(type: String, bundleId: String)] = []

    public init() {}

    public func notifyWarning(appName: String, bundleIdentifier: String, remainingSeconds: Int) {
        lock.lock()
        defer { lock.unlock() }
        notificationsSent.append(("WARN", bundleIdentifier))
    }

    public func notifyLimitReached(appName: String, bundleIdentifier: String) {
        lock.lock()
        defer { lock.unlock() }
        notificationsSent.append(("LIMIT_REACHED", bundleIdentifier))
    }

    public func notifyEnforcement(appName: String, bundleIdentifier: String, action: EnforcementAction) {
        lock.lock()
        defer { lock.unlock() }
        notificationsSent.append(("ENFORCE_\(action.rawValue)", bundleIdentifier))
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        notificationsSent.removeAll()
    }
}
