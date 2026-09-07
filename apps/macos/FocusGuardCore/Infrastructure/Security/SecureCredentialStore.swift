import Foundation
import Security

public protocol SecureCredentialStore: Sendable {
    func save(key: String, data: Data) throws
    func load(key: String) throws -> Data?
    func delete(key: String) throws
    func saveString(key: String, value: String) throws
    func loadString(key: String) throws -> String?
}

public extension SecureCredentialStore {
    func saveString(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw NSError(domain: "FocusGuard.Keychain", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF8 string"])
        }
        try save(key: key, data: data)
    }

    func loadString(key: String) throws -> String? {
        guard let data = try load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public final class KeychainCredentialStore: SecureCredentialStore, @unchecked Sendable {
    public static let shared = KeychainCredentialStore()
    private let serviceName: String
    private let lock = NSLock()

    public init(serviceName: String = "com.focusguard.macos.identity") {
        self.serviceName = serviceName
    }

    public func save(key: String, data: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "FocusGuard.Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to write to Keychain (status: \(status))"])
        }
    }

    public func load(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: "FocusGuard.Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to read from Keychain (status: \(status))"])
        }
        return data
    }

    public func delete(key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NSError(domain: "FocusGuard.Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to delete from Keychain (status: \(status))"])
        }
    }
}

public final class MockCredentialStore: SecureCredentialStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func save(key: String, data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        store[key] = data
    }

    public func load(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return store[key]
    }

    public func delete(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: key)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        store.removeAll()
    }
}
