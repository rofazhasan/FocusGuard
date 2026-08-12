import Foundation

public final class LocalPolicyEvaluator {
    public static let shared = LocalPolicyEvaluator()

    private init() {}

    /// Checks if active monotonic time clock matches wall-clock progression to prevent clock tampering.
    public func validateMonotonicClock(lastWallTime: Date, lastMonotonicUptime: UInt64) -> Bool {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC_RAW, &ts)
        let currentMonotonicUptime = UInt64(ts.tv_sec)

        let elapsedWall = Date().timeIntervalSince(lastWallTime)
        let elapsedMonotonic = Double(currentMonotonicUptime - lastMonotonicUptime)

        let drift = abs(elapsedWall - elapsedMonotonic)
        // Acceptable clock drift threshold: 120 seconds
        return drift <= 120.0
    }

    /// Evaluates if cumulative target usage exceeds policy budget
    public func isLimitExceeded(policy: Policy, cumulativeSeconds: Int) -> Bool {
        guard policy.isEnabled else { return false }
        guard policy.limitSeconds > 0 else { return false }
        return cumulativeSeconds >= policy.limitSeconds
    }

    /// Matches bundle identifier or web domain against policy targets
    public func isTargetMatched(target: PolicyTarget, candidate: String) -> Bool {
        let cleanCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanTarget = target.targetValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !cleanCandidate.isEmpty, !cleanTarget.isEmpty else { return false }

        switch target.targetType {
        case .app:
            return cleanCandidate == cleanTarget
        case .website:
            if cleanCandidate == cleanTarget { return true }
            if cleanCandidate.hasSuffix("." + cleanTarget) { return true }
            return false
        case .category:
            return cleanCandidate == cleanTarget
        }
    }
}
