import Foundation

public final class DeviceService: @unchecked Sendable {
    private let deviceRepo: DeviceRepository
    private let credStore: SecureCredentialStore
    private let lock = NSLock()
    public private(set) var currentIdentity: DeviceIdentity?

    public init(deviceRepo: DeviceRepository, credStore: SecureCredentialStore) {
        self.deviceRepo = deviceRepo
        self.credStore = credStore
    }

    @discardableResult
    public func initialize() throws -> DeviceIdentity {
        lock.lock()
        defer { lock.unlock() }

        if let existing = try deviceRepo.getDeviceIdentity() {
            // Check if credentials exist in Keychain
            let token = try credStore.loadString(key: "device_token")
            var identity = existing
            if token != nil && identity.status != .revoked {
                identity.status = .active
                try deviceRepo.updateStatus(.active)
            }
            self.currentIdentity = identity
            return identity
        }

        // Generate Ed25519 identity key
        let keypair = CryptoService.generateEd25519Keypair()
        try credStore.save(key: "ed25519_private_key", data: keypair.privateKeyRaw)

        let hostName = Host.current().localizedName ?? "MacBook Pro"
        let newIdentity = DeviceIdentity(
            deviceId: nil,
            deviceName: hostName,
            status: .unregistered,
            publicKeyPem: keypair.publicKeyBase64
        )

        try deviceRepo.saveDeviceIdentity(newIdentity)
        self.currentIdentity = newIdentity
        return newIdentity
    }

    public func pairDevice(
        deviceId: UUID,
        deviceToken: String,
        userId: UUID? = nil,
        deviceName: String? = nil
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard var identity = currentIdentity ?? (try? deviceRepo.getDeviceIdentity()) else {
            throw NSError(domain: "FocusGuard.DeviceService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Device identity not initialized"])
        }

        // Save credentials to Keychain
        try credStore.saveString(key: "device_id", value: deviceId.uuidString)
        try credStore.saveString(key: "device_token", value: deviceToken)

        identity.deviceId = deviceId
        identity.status = .active
        identity.registeredAt = Date()
        if let customName = deviceName {
            identity.deviceName = customName
        }

        try deviceRepo.saveDeviceIdentity(identity)
        self.currentIdentity = identity
    }

    public func revokeDevice() throws {
        lock.lock()
        defer { lock.unlock() }

        try credStore.delete(key: "device_token")
        try credStore.delete(key: "device_id")

        if var identity = currentIdentity {
            identity.status = .revoked
            try deviceRepo.saveDeviceIdentity(identity)
            self.currentIdentity = identity
        }
    }

    public func getDeviceToken() throws -> String? {
        return try credStore.loadString(key: "device_token")
    }

    public func isEnrolled() -> Bool {
        guard let identity = currentIdentity else { return false }
        return identity.status == .active && (try? credStore.loadString(key: "device_token")) != nil
    }

    public func currentStatus() -> DeviceState {
        lock.lock()
        defer { lock.unlock() }
        return currentIdentity?.status ?? .unregistered
    }

    public func getDeviceIdentity() throws -> DeviceIdentity? {
        lock.lock()
        defer { lock.unlock() }
        if let current = currentIdentity {
            return current
        }
        let existing = try deviceRepo.getDeviceIdentity()
        self.currentIdentity = existing
        return existing
    }
}
