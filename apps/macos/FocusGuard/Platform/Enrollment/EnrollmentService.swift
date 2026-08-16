// FocusGuard macOS Agent — Enrollment Service
// Handles claiming 6-character pairing codes from the FocusGuard owner dashboard
// and persisting device identity & access tokens in Keychain.

import Foundation

public struct ClaimResponse: Codable {
    public let deviceId: String
    public let userId: String
    public let deviceName: String
    public let platform: String
    public let role: String
    public let isManaged: Bool
    public let policyVersion: Int
    public let accessToken: String
    public let status: String
}

public final class MacEnrollmentService {
    public static let shared = MacEnrollmentService()
    private var serverBaseURL: String = "http://localhost:8080/api/v1"

    private init() {}

    public func configure(serverBase: String) {
        self.serverBaseURL = serverBase
    }

    /// Claims a pairing code from the backend server
    public func claimPairingCode(code: String, deviceName: String = Host.current().localizedName ?? "MacBook Pro") async throws -> ClaimResponse {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCode.isEmpty else {
            throw NSError(domain: "FocusGuard", code: 400, userInfo: [NSLocalizedDescriptionKey: "Pairing code cannot be empty"])
        }

        guard let url = URL(string: "\(serverBaseURL)/enrollment/claim") else {
            throw NSError(domain: "FocusGuard", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "pairingCode": cleanCode,
            "deviceName": deviceName,
            "platform": "MACOS",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "FocusGuard", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Enrollment failed"
            throw NSError(domain: "FocusGuard", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        let claimResponse = try JSONDecoder().decode(ClaimResponse.self, from: data)

        // Persist to Keychain
        KeychainStorage.shared.saveString(key: "device_id", value: claimResponse.deviceId)
        KeychainStorage.shared.saveString(key: "device_token", value: claimResponse.accessToken)
        KeychainStorage.shared.saveString(key: "device_name", value: claimResponse.deviceName)
        KeychainStorage.shared.saveString(key: "policy_version", value: "\(claimResponse.policyVersion)")

        print("[MacEnrollmentService] Successfully enrolled device \(claimResponse.deviceId)")
        return claimResponse
    }

    /// Checks if device is already paired
    public func isEnrolled() -> Bool {
        return KeychainStorage.shared.loadString(key: "device_token") != nil
    }

    /// Revokes enrollment and clears Keychain credentials
    public func unenroll() {
        KeychainStorage.shared.delete(key: "device_id")
        KeychainStorage.shared.delete(key: "device_token")
        KeychainStorage.shared.delete(key: "device_name")
        KeychainStorage.shared.delete(key: "policy_version")
        print("[MacEnrollmentService] Cleared enrollment credentials from Keychain")
    }
}
