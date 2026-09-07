import Foundation

public final class CrashRecoveryService: @unchecked Sendable {
    private let usageRepo: UsageRepository

    public init(usageRepo: UsageRepository) {
        self.usageRepo = usageRepo
    }

    /// Checks for and safely seals any unfinished sessions from a previous unexpected app termination.
    /// Ensures that no unknown downtime between crash and relaunch is falsely counted.
    @discardableResult
    public func recoverUnfinishedSessions() throws -> Int {
        let openSessions = try usageRepo.getOpenSessions()
        var recoveredCount = 0

        for session in openSessions {
            // Calculate endedAt based on startedAt + last duration checkpoint
            let closedAt = session.startedAt.addingTimeInterval(TimeInterval(session.durationSeconds))
            try usageRepo.updateSessionDuration(
                id: session.id,
                durationSeconds: session.durationSeconds,
                endedAt: closedAt,
                isClosed: true
            )
            recoveredCount += 1
        }

        return recoveredCount
    }
}
