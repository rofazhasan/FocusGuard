import Foundation

public final class PolicyEngine: Sendable {
    public init() {}

    /// Pure deterministic policy evaluation.
    /// Free from system APIs, network latency, or I/O calls.
    public static func evaluate(
        usageSeconds: Int,
        policy: Policy,
        deviceState: DeviceState
    ) -> PolicyDecision {
        // Invariant 1: Revoked devices unconditionally lose policy authorization
        if deviceState == .revoked {
            return .revoked
        }

        // Invariant 2: Disabled policies allow unconstrained usage
        guard policy.isEnabled else {
            return .allow
        }

        // Invariant 3: Zero or negative limit implies unconstrained
        guard policy.limitSeconds > 0 else {
            return .allow
        }

        if usageSeconds > policy.limitSeconds {
            return .enforce
        } else if usageSeconds == policy.limitSeconds {
            return .limitReached
        } else if policy.warningThresholdSeconds > 0 && usageSeconds >= policy.warningThresholdSeconds {
            return .warn
        } else {
            return .allow
        }
    }

    /// Verifies whether a candidate bundle identifier matches a policy target
    public static func matchesTarget(policyTarget: PolicyTarget, candidateBundleId: String) -> Bool {
        let cleanCandidate = candidateBundleId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanTarget = policyTarget.targetValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanCandidate.isEmpty, !cleanTarget.isEmpty else { return false }

        switch policyTarget.targetType {
        case .app:
            return cleanCandidate == cleanTarget
        case .website:
            return cleanCandidate == cleanTarget || cleanCandidate.hasSuffix("." + cleanTarget)
        case .category:
            return cleanCandidate == cleanTarget
        }
    }

    /// Validates policy invariants: rejects negative limits, warning > limit, protected targets, empty names.
    public static func validatePolicy(policy: Policy) -> Result<Void, PolicyValidationError> {
        if policy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(.emptyName)
        }

        if policy.limitSeconds < 0 {
            return .failure(.negativeLimit(policy.limitSeconds))
        }

        if policy.warningThresholdSeconds > policy.limitSeconds {
            return .failure(.warningExceedsLimit(warning: policy.warningThresholdSeconds, limit: policy.limitSeconds))
        }

        if policy.targets.isEmpty {
            return .failure(.emptyTargets)
        }

        for target in policy.targets {
            if target.targetType == .app {
                if ProtectedAppDenylist.isProtected(bundleIdentifier: target.targetValue) {
                    return .failure(.protectedSystemTarget(target.targetValue))
                }
            }
        }

        return .success(())
    }
}
