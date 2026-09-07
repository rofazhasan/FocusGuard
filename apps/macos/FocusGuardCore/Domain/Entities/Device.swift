import Foundation

public enum DeviceState: String, Codable, Equatable {
    case unregistered = "UNREGISTERED"
    case pairing = "PAIRING"
    case active = "ACTIVE"
    case offline = "OFFLINE"
    case revoked = "REVOKED"
}

public struct DeviceIdentity: Codable, Equatable {
    public var deviceId: UUID?
    public var deviceName: String
    public var platform: String
    public var clientType: String
    public var osVersion: String
    public var appVersion: String
    public var status: DeviceState
    public var publicKeyPem: String
    public var registeredAt: Date?

    public init(
        deviceId: UUID? = nil,
        deviceName: String,
        platform: String = "MACOS",
        clientType: String = "MACOS_AGENT",
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        appVersion: String = "1.0.0",
        status: DeviceState = .unregistered,
        publicKeyPem: String = "",
        registeredAt: Date? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.platform = platform
        self.clientType = clientType
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.status = status
        self.publicKeyPem = publicKeyPem
        self.registeredAt = registeredAt
    }
}

public struct DeviceCredentials: Codable, Equatable {
    public let deviceId: UUID
    public let userId: UUID?
    public let deviceToken: String
    public let credentialVersion: Int
    public let createdAt: Date
    public let expiresAt: Date?

    public init(
        deviceId: UUID,
        userId: UUID? = nil,
        deviceToken: String,
        credentialVersion: Int = 1,
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.deviceId = deviceId
        self.userId = userId
        self.deviceToken = deviceToken
        self.credentialVersion = credentialVersion
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}
