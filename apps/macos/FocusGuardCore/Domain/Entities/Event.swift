import Foundation

public enum EventType: String, Codable, Equatable, CaseIterable {
    case deviceStarted = "DEVICE_STARTED"
    case deviceStopped = "DEVICE_STOPPED"
    case usageSessionStarted = "USAGE_SESSION_STARTED"
    case usageSessionEnded = "USAGE_SESSION_ENDED"
    case usageLimitWarning = "USAGE_LIMIT_WARNING"
    case limitReached = "LIMIT_REACHED"
    case enforcementTriggered = "ENFORCEMENT_TRIGGERED"
    case enforcementFailed = "ENFORCEMENT_FAILED"
    case policySynced = "POLICY_SYNCED"
    case syncFailed = "SYNC_FAILED"
}

public struct EventEnvelope: Identifiable, Codable, Equatable {
    public let id: String // e.g. "evt_uuid"
    public let eventType: EventType
    public let deviceId: String
    public let target: String
    public let reason: String?
    public let timestamp: Int64
    public let metadata: [String: String]?
    public var retryCount: Int
    public var status: String // "PENDING", "SYNCED", "FAILED"

    public init(
        id: String = "evt_\(UUID().uuidString.lowercased())",
        eventType: EventType,
        deviceId: String,
        target: String,
        reason: String? = nil,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        metadata: [String: String]? = nil,
        retryCount: Int = 0,
        status: String = "PENDING"
    ) {
        self.id = id
        self.eventType = eventType
        self.deviceId = deviceId
        self.target = target
        self.reason = reason
        self.timestamp = timestamp
        self.metadata = metadata
        self.retryCount = retryCount
        self.status = status
    }
}
