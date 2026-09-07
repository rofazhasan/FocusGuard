import Foundation

public enum TargetType: String, Codable, CaseIterable, Equatable {
    case app = "APP"
    case website = "WEBSITE"
    case category = "CATEGORY"
}

public enum EnforcementAction: String, Codable, CaseIterable, Equatable {
    case notify = "NOTIFY"
    case focusGuardOverlay = "FOCUSGUARD_OVERLAY_OR_WARNING_UI"
    case closeApplication = "CLOSE_APPLICATION"
    case pauseTracking = "PAUSE_TRACKING"
}

public struct PolicyTarget: Identifiable, Codable, Equatable {
    public let id: UUID
    public let policyId: UUID?
    public let targetType: TargetType
    public let targetValue: String

    public init(id: UUID = UUID(), policyId: UUID? = nil, targetType: TargetType, targetValue: String) {
        self.id = id
        self.policyId = policyId
        self.targetType = targetType
        self.targetValue = targetValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct Policy: Identifiable, Codable, Equatable {
    public let id: UUID
    public let userId: UUID?
    public var name: String
    public var limitSeconds: Int
    public var warningThresholdSeconds: Int
    public var enforcementAction: EnforcementAction
    public var isEnabled: Bool
    public var version: Int
    public var targets: [PolicyTarget]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        name: String,
        limitSeconds: Int,
        warningThresholdSeconds: Int = 0,
        enforcementAction: EnforcementAction = .notify,
        isEnabled: Bool = true,
        version: Int = 1,
        targets: [PolicyTarget] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.limitSeconds = limitSeconds
        self.warningThresholdSeconds = warningThresholdSeconds
        self.enforcementAction = enforcementAction
        self.isEnabled = isEnabled
        self.version = version
        self.targets = targets
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum PolicyDecision: String, Codable, Equatable {
    case allow = "ALLOW"
    case warn = "WARN"
    case limitReached = "LIMIT_REACHED"
    case enforce = "ENFORCE"
    case revoked = "REVOKED"
}

public enum PolicyValidationError: Error, Equatable, LocalizedError {
    case negativeLimit(Int)
    case warningExceedsLimit(warning: Int, limit: Int)
    case emptyTargets
    case protectedSystemTarget(String)
    case emptyName

    public var errorDescription: String? {
        switch self {
        case .negativeLimit(let limit):
            return "Policy limit cannot be negative: \(limit)s"
        case .warningExceedsLimit(let warning, let limit):
            return "Warning threshold (\(warning)s) cannot exceed daily limit (\(limit)s)"
        case .emptyTargets:
            return "Policy must have at least one valid target configured"
        case .protectedSystemTarget(let target):
            return "Cannot target protected system application: '\(target)'"
        case .emptyName:
            return "Policy name cannot be empty"
        }
    }
}
