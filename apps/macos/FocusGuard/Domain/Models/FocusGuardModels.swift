import Foundation

public enum TargetType: String, Codable, CaseIterable {
    case app = "APP"
    case website = "WEBSITE"
    case category = "CATEGORY"
}

public enum EnforcementMode: String, Codable, CaseIterable {
    case block = "BLOCK"
    case focusOnly = "FOCUS_ONLY"
    case scheduledBlock = "SCHEDULED_BLOCK"
}

public enum Period: String, Codable, CaseIterable {
    case daily = "DAILY"
    case weekly = "WEEKLY"
}

public struct PolicyTarget: Identifiable, Codable, Equatable {
    public var id: UUID
    public var policyId: UUID?
    public var targetType: TargetType
    public var targetValue: String

    public init(id: UUID = UUID(), policyId: UUID? = nil, targetType: TargetType, targetValue: String) {
        self.id = id
        self.policyId = policyId
        self.targetType = targetType
        self.targetValue = targetValue
    }
}

public struct Policy: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var limitSeconds: Int
    public var period: Period
    public var scheduleCron: String?
    public var timezone: String
    public var enforcementMode: EnforcementMode
    public var isEnabled: Bool
    public var version: Int
    public var targets: [PolicyTarget]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        limitSeconds: Int,
        period: Period = .daily,
        scheduleCron: String? = nil,
        timezone: String = TimeZone.current.identifier,
        enforcementMode: EnforcementMode = .block,
        isEnabled: Bool = true,
        version: Int = 1,
        targets: [PolicyTarget] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.limitSeconds = limitSeconds
        self.period = period
        self.scheduleCron = scheduleCron
        self.timezone = timezone
        self.enforcementMode = enforcementMode
        self.isEnabled = isEnabled
        self.version = version
        self.targets = targets
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DeviceInfo: Identifiable, Codable, Equatable {
    public var id: UUID
    public var deviceName: String
    public var platform: String
    public var osVersion: String
    public var status: String
    public var lastSeenAt: Date

    public init(id: UUID = UUID(), deviceName: String, platform: String, osVersion: String, status: String = "ONLINE", lastSeenAt: Date = Date()) {
        self.id = id
        self.deviceName = deviceName
        self.platform = platform
        self.osVersion = osVersion
        self.status = status
        self.lastSeenAt = lastSeenAt
    }
}

public struct FocusSession: Identifiable, Codable {
    public var id: UUID
    public var durationMinutes: Int
    public var remainingSeconds: Int
    public var isActive: Bool
    public var startTime: Date?

    public init(id: UUID = UUID(), durationMinutes: Int, remainingSeconds: Int = 0, isActive: Bool = false, startTime: Date? = nil) {
        self.id = id
        self.durationMinutes = durationMinutes
        self.remainingSeconds = remainingSeconds
        self.isActive = isActive
        self.startTime = startTime
    }
}
