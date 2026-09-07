import Foundation

public final class PolicyService: @unchecked Sendable {
    private let policyRepo: PolicyRepositoryProtocol
    private let deviceService: DeviceService
    private let lock = NSLock()
    private var cachedActivePolicies: [Policy] = []

    public init(policyRepo: PolicyRepositoryProtocol, deviceService: DeviceService) {
        self.policyRepo = policyRepo
        self.deviceService = deviceService
        try? reloadCache()
    }

    public func reloadCache() throws {
        lock.lock()
        defer { lock.unlock() }
        self.cachedActivePolicies = try policyRepo.getActivePolicies()
    }

    public func savePolicy(_ policy: Policy) throws {
        let validation = PolicyEngine.validatePolicy(policy: policy)
        switch validation {
        case .failure(let err):
            throw err
        case .success:
            try policyRepo.savePolicy(policy)
            try reloadCache()
        }
    }

    public func savePolicies(_ policies: [Policy]) throws {
        for policy in policies {
            let validation = PolicyEngine.validatePolicy(policy: policy)
            if case .failure(let err) = validation {
                throw err
            }
        }
        try policyRepo.savePolicies(policies)
        try reloadCache()
    }

    public func getPolicy(id: UUID) throws -> Policy? {
        return try policyRepo.getPolicy(id: id)
    }

    public func getAllPolicies() throws -> [Policy] {
        return try policyRepo.getAllPolicies()
    }

    public func getActivePolicies() -> [Policy] {
        lock.lock()
        defer { lock.unlock() }
        return cachedActivePolicies
    }

    public func deletePolicy(id: UUID) throws {
        try policyRepo.deletePolicy(id: id)
        try reloadCache()
    }

    public func clearAllPolicies() throws {
        try policyRepo.clearAllPolicies()
        try reloadCache()
    }

    public func findPolicy(for bundleIdentifier: String) -> Policy? {
        lock.lock()
        defer { lock.unlock() }

        for policy in cachedActivePolicies {
            for target in policy.targets {
                if PolicyEngine.matchesTarget(policyTarget: target, candidateBundleId: bundleIdentifier) {
                    return policy
                }
            }
        }
        return nil
    }

    /// Evaluates current active usage against any matching policy for the given bundle identifier.
    public func evaluatePolicy(for bundleIdentifier: String, usageSeconds: Int) -> (policy: Policy?, decision: PolicyDecision) {
        let deviceState = deviceService.currentStatus()

        // If device is revoked, immediately return revoked
        if deviceState == .revoked {
            return (nil, .revoked)
        }

        guard let policy = findPolicy(for: bundleIdentifier) else {
            return (nil, .allow)
        }

        let decision = PolicyEngine.evaluate(usageSeconds: usageSeconds, policy: policy, deviceState: deviceState)
        return (policy, decision)
    }
}
