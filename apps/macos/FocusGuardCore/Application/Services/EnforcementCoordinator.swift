import Foundation

public final class EnforcementCoordinator: @unchecked Sendable {
    private let notificationAdapter: NotificationAdapterProtocol
    private let applicationControl: ApplicationControlProtocol
    private let eventRepo: EventQueueRepository
    private let deviceService: DeviceService
    private let lock = NSLock()
    private var lastEnforcedSession: [String: PolicyDecision] = [:]

    public init(
        notificationAdapter: NotificationAdapterProtocol,
        applicationControl: ApplicationControlProtocol,
        eventRepo: EventQueueRepository,
        deviceService: DeviceService
    ) {
        self.notificationAdapter = notificationAdapter
        self.applicationControl = applicationControl
        self.eventRepo = eventRepo
        self.deviceService = deviceService
    }

    public func handlePolicyDecision(
        target: ForegroundAppInfo,
        policy: Policy,
        decision: PolicyDecision,
        usageSeconds: Int
    ) {
        lock.lock()
        let previousDecision = lastEnforcedSession[target.bundleIdentifier]
        if previousDecision == decision {
            lock.unlock()
            return // Skip repeated handling of the same state to avoid spam
        }
        lastEnforcedSession[target.bundleIdentifier] = decision
        lock.unlock()

        let deviceId = (try? deviceService.getDeviceIdentity()?.deviceId?.uuidString) ?? "unknown_device"

        switch decision {
        case .warn:
            let remaining = max(0, policy.limitSeconds - usageSeconds)
            notificationAdapter.notifyWarning(
                appName: target.localizedName,
                bundleIdentifier: target.bundleIdentifier,
                remainingSeconds: remaining
            )
            let event = EventEnvelope(
                eventType: .usageLimitWarning,
                deviceId: deviceId,
                target: target.bundleIdentifier,
                reason: "WARNING_THRESHOLD_REACHED",
                metadata: ["usageSeconds": "\(usageSeconds)", "limitSeconds": "\(policy.limitSeconds)"]
            )
            try? eventRepo.enqueueEvent(event)

        case .limitReached:
            notificationAdapter.notifyLimitReached(
                appName: target.localizedName,
                bundleIdentifier: target.bundleIdentifier
            )
            let event = EventEnvelope(
                eventType: .limitReached,
                deviceId: deviceId,
                target: target.bundleIdentifier,
                reason: "DAILY_LIMIT_REACHED",
                metadata: ["limitSeconds": "\(policy.limitSeconds)"]
            )
            try? eventRepo.enqueueEvent(event)

        case .enforce:
            notificationAdapter.notifyEnforcement(
                appName: target.localizedName,
                bundleIdentifier: target.bundleIdentifier,
                action: policy.enforcementAction
            )

            if policy.enforcementAction == .closeApplication {
                let terminated = applicationControl.terminateApplication(bundleIdentifier: target.bundleIdentifier)
                let event = EventEnvelope(
                    eventType: terminated ? .enforcementTriggered : .enforcementFailed,
                    deviceId: deviceId,
                    target: target.bundleIdentifier,
                    reason: terminated ? "CLOSE_APPLICATION_SUCCESS" : "CLOSE_APPLICATION_FAILED",
                    metadata: ["action": policy.enforcementAction.rawValue]
                )
                try? eventRepo.enqueueEvent(event)
            } else {
                let event = EventEnvelope(
                    eventType: .enforcementTriggered,
                    deviceId: deviceId,
                    target: target.bundleIdentifier,
                    reason: "POLICY_ENFORCED_\(policy.enforcementAction.rawValue)",
                    metadata: ["action": policy.enforcementAction.rawValue]
                )
                try? eventRepo.enqueueEvent(event)
            }

        case .allow, .revoked:
            break
        }
    }

    public func resetDecision(for bundleIdentifier: String) {
        lock.lock()
        defer { lock.unlock() }
        lastEnforcedSession.removeValue(forKey: bundleIdentifier)
    }
}
