import Foundation

public final class UsageService: @unchecked Sendable {
    private let foregroundProvider: ForegroundApplicationProvider
    private let idleDetector: IdleDetector
    private let lockMonitor: LockStateMonitor
    private let usageRepo: UsageRepository
    private let eventRepo: EventQueueRepository
    private let policyService: PolicyService?
    private let enforcementCoordinator: EnforcementCoordinator?
    private let stateMachine: UsageStateMachine
    private let lock = NSLock()

    private var trackedTargets: Set<String> = []
    private var activeSession: UsageSession?
    private var lastMonotonicCheckpoint: UInt64 = 0
    public var deviceIdProvider: (() -> String)?

    public init(
        foregroundProvider: ForegroundApplicationProvider,
        idleDetector: IdleDetector,
        lockMonitor: LockStateMonitor,
        usageRepo: UsageRepository,
        eventRepo: EventQueueRepository,
        policyService: PolicyService? = nil,
        enforcementCoordinator: EnforcementCoordinator? = nil,
        initialTrackedTargets: Set<String> = []
    ) {
        self.foregroundProvider = foregroundProvider
        self.idleDetector = idleDetector
        self.lockMonitor = lockMonitor
        self.usageRepo = usageRepo
        self.eventRepo = eventRepo
        self.policyService = policyService
        self.enforcementCoordinator = enforcementCoordinator
        self.stateMachine = UsageStateMachine()
        self.trackedTargets = Set(initialTrackedTargets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    }

    public func addTrackedTarget(_ bundleIdentifier: String) {
        lock.lock()
        defer { lock.unlock() }
        let clean = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        trackedTargets.insert(clean)
    }

    public func removeTrackedTarget(_ bundleIdentifier: String) {
        lock.lock()
        defer { lock.unlock() }
        let clean = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        trackedTargets.remove(clean)
    }

    public func getTrackedTargets() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return trackedTargets
    }

    public func currentState() -> UsageState {
        lock.lock()
        defer { lock.unlock() }
        return stateMachine.currentState
    }

    public func currentActiveSession() -> UsageSession? {
        lock.lock()
        defer { lock.unlock() }
        return activeSession
    }

    @discardableResult
    public func tick(deltaSeconds: Int = 1) throws -> UsageState {
        lock.lock()
        defer { lock.unlock() }

        let isLocked = lockMonitor.isScreenLocked()
        let isSleeping = lockMonitor.isSystemSleeping()

        // 1. Check Screen Lock / Sleep
        if isLocked || isSleeping {
            stateMachine.transition(with: .screenLocked)
            return stateMachine.currentState
        }

        // 2. Check User Idle
        let idleStatus = idleDetector.getIdleStatus(thresholdSeconds: 60.0)
        if idleStatus == .idle {
            stateMachine.transition(with: .userBecameIdle)
            return stateMachine.currentState
        } else if stateMachine.currentState == .idle {
            stateMachine.transition(with: .userResumedActivity)
        }

        // 3. Inspect Foreground Window
        let currentForeground = foregroundProvider.getForegroundApplication()
        let bundleId = currentForeground?.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let isTracked = bundleId != nil && trackedTargets.contains(bundleId!)

        if isTracked, let targetBundle = bundleId {
            // Target is foreground
            let today = UsageSession.currentDateString()

            if var session = activeSession {
                if session.bundleIdentifier == targetBundle {
                    if session.date != today {
                        // Midnight crossed: seal previous day's session and start fresh for today
                        try closeActiveSession(session)
                        try startNewSession(bundleIdentifier: targetBundle)
                        if var newSession = activeSession {
                            newSession.durationSeconds += deltaSeconds
                            activeSession = newSession
                            try usageRepo.updateSessionDuration(id: newSession.id, durationSeconds: newSession.durationSeconds)
                            try usageRepo.incrementDailyUsage(date: today, bundleIdentifier: targetBundle, deltaSeconds: deltaSeconds)
                        }
                    } else {
                        // Continuing existing session on same calendar day
                        session.durationSeconds += deltaSeconds
                        activeSession = session

                        try usageRepo.updateSessionDuration(id: session.id, durationSeconds: session.durationSeconds)
                        try usageRepo.incrementDailyUsage(date: today, bundleIdentifier: targetBundle, deltaSeconds: deltaSeconds)
                    }
                } else {
                    // Switched from one tracked target to another tracked target
                    try closeActiveSession(session)
                    try startNewSession(bundleIdentifier: targetBundle)
                    if var newSession = activeSession {
                        newSession.durationSeconds += deltaSeconds
                        activeSession = newSession
                        try usageRepo.updateSessionDuration(id: newSession.id, durationSeconds: newSession.durationSeconds)
                        try usageRepo.incrementDailyUsage(date: today, bundleIdentifier: targetBundle, deltaSeconds: deltaSeconds)
                    }
                }
            } else {
                // Starting brand new session
                try startNewSession(bundleIdentifier: targetBundle)
                if var session = activeSession {
                    session.durationSeconds += deltaSeconds
                    activeSession = session
                    try usageRepo.updateSessionDuration(id: session.id, durationSeconds: session.durationSeconds)
                    try usageRepo.incrementDailyUsage(date: today, bundleIdentifier: targetBundle, deltaSeconds: deltaSeconds)
                }
            }
            stateMachine.transition(with: .targetEnteredForeground(bundleId: targetBundle))

            // 4. Policy Evaluation & Enforcement
            let todayUsage = (try? usageRepo.getDailyUsage(date: today, bundleIdentifier: targetBundle)) ?? 0
            if let result = policyService?.evaluatePolicy(for: targetBundle, usageSeconds: todayUsage) {
                if let policy = result.policy {
                    switch result.decision {
                    case .warn:
                        stateMachine.transition(with: .warningThresholdReached)
                    case .limitReached, .enforce:
                        stateMachine.transition(with: .limitReached)
                    default:
                        break
                    }

                    if let currentApp = currentForeground {
                        enforcementCoordinator?.handlePolicyDecision(
                            target: currentApp,
                            policy: policy,
                            decision: result.decision,
                            usageSeconds: todayUsage
                        )
                    }
                }
            }
        } else {
            // No tracked target in foreground
            if let session = activeSession {
                try closeActiveSession(session)
                activeSession = nil
            }
            stateMachine.transition(with: .targetLeftForeground)
        }

        return stateMachine.currentState
    }

    private func startNewSession(bundleIdentifier: String) throws {
        let newSession = UsageSession(
            id: UUID(),
            targetId: nil,
            bundleIdentifier: bundleIdentifier,
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: 0,
            date: UsageSession.currentDateString(),
            isClosed: false
        )
        try usageRepo.insertUsageSession(newSession)
        self.activeSession = newSession

        let devId = deviceIdProvider?() ?? "dev_macos_agent"
        let startEvent = EventEnvelope(
            eventType: .usageSessionStarted,
            deviceId: devId,
            target: bundleIdentifier,
            reason: "App entered foreground",
            metadata: ["bundleIdentifier": bundleIdentifier]
        )
        try eventRepo.enqueueEvent(startEvent)
    }

    private func closeActiveSession(_ session: UsageSession) throws {
        let closedAt = Date()
        try usageRepo.updateSessionDuration(
            id: session.id,
            durationSeconds: session.durationSeconds,
            endedAt: closedAt,
            isClosed: true
        )

        let devId = deviceIdProvider?() ?? "dev_macos_agent"
        let endEvent = EventEnvelope(
            eventType: .usageSessionEnded,
            deviceId: devId,
            target: session.bundleIdentifier,
            reason: "App left foreground",
            metadata: [
                "durationSeconds": "\(session.durationSeconds)",
                "bundleIdentifier": session.bundleIdentifier
            ]
        )
        try eventRepo.enqueueEvent(endEvent)
    }

    public func forceCloseCurrentSession() throws {
        lock.lock()
        defer { lock.unlock() }
        if let session = activeSession {
            try closeActiveSession(session)
            activeSession = nil
        }
        stateMachine.transition(with: .sessionClosed)
    }
}
