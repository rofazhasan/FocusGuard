import Foundation

public final class SyncService: @unchecked Sendable {
    private let eventRepo: EventQueueRepository
    private let deviceService: DeviceService
    private let policyService: PolicyService?
    private let serverBaseURL: String
    private let urlSession: URLSession
    private let lock = NSLock()

    public init(
        eventRepo: EventQueueRepository,
        deviceService: DeviceService,
        policyService: PolicyService? = nil,
        serverBaseURL: String = "http://localhost:8080",
        urlSession: URLSession = .shared
    ) {
        self.eventRepo = eventRepo
        self.deviceService = deviceService
        self.policyService = policyService
        self.serverBaseURL = serverBaseURL
        self.urlSession = urlSession
    }

    public struct SyncResult: Equatable {
        public let processedCount: Int
        public let isRevoked: Bool
        public let errorMessage: String?
    }

    /// Flushes offline queued events to the backend in batches.
    /// Reconnects safely with idempotent event acknowledgements.
    public func flushPendingEvents(limit: Int = 50) async throws -> SyncResult {
        let events = try eventRepo.getPendingEvents(limit: limit)
        guard !events.isEmpty else {
            return SyncResult(processedCount: 0, isRevoked: false, errorMessage: nil)
        }

        guard let token = try deviceService.getDeviceToken() else {
            return SyncResult(processedCount: 0, isRevoked: false, errorMessage: "Device not enrolled")
        }

        guard let url = URL(string: "\(serverBaseURL)/api/v1/events/batch") else {
            return SyncResult(processedCount: 0, isRevoked: false, errorMessage: "Invalid server URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "events": events.map { event in
                [
                    "id": event.id,
                    "eventType": event.eventType.rawValue,
                    "target": event.target,
                    "reason": event.reason ?? "",
                    "timestamp": event.timestamp,
                    "metadata": event.metadata ?? [:]
                ] as [String: Any]
            }
        ]

        let httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = httpBody

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "FocusGuard.Sync", code: 500, userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response"])
            }

            if httpResponse.statusCode == 403 {
                // Device Revoked! Execute zero-trust revocation wipe
                try deviceService.revokeDevice()
                try policyService?.clearAllPolicies()
                return SyncResult(processedCount: 0, isRevoked: true, errorMessage: "Device revoked by server")
            }

            if httpResponse.statusCode == 200 {
                let eventIds = events.map { $0.id }
                try eventRepo.markEventsSynced(ids: eventIds)
                return SyncResult(processedCount: eventIds.count, isRevoked: false, errorMessage: nil)
            } else {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                for event in events {
                    try eventRepo.incrementRetryCount(id: event.id)
                }
                return SyncResult(processedCount: 0, isRevoked: false, errorMessage: msg)
            }
        } catch {
            for event in events {
                try eventRepo.incrementRetryCount(id: event.id)
            }
            return SyncResult(processedCount: 0, isRevoked: false, errorMessage: error.localizedDescription)
        }
    }

    /// Synchronizes policies from the backend and updates local SQLite cache
    public func syncPolicies() async throws -> (syncedCount: Int, isRevoked: Bool, errorMessage: String?) {
        guard let policyService = self.policyService else {
            return (0, false, "PolicyService not configured")
        }

        guard let token = try deviceService.getDeviceToken() else {
            return (0, false, "Device not enrolled")
        }

        guard let url = URL(string: "\(serverBaseURL)/api/v1/device/policies/sync") else {
            return (0, false, "Invalid server URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "FocusGuard.Sync", code: 500, userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response"])
            }

            if httpResponse.statusCode == 403 {
                try deviceService.revokeDevice()
                try policyService.clearAllPolicies()
                return (0, true, "Device revoked by server")
            }

            guard httpResponse.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                return (0, false, msg)
            }

            // Parse response JSON
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let policiesArr = json["policies"] as? [[String: Any]] {
                var loadedPolicies: [Policy] = []

                for pDict in policiesArr {
                    guard let idStr = pDict["id"] as? String,
                          let id = UUID(uuidString: idStr),
                          let name = pDict["name"] as? String,
                          let limitSec = pDict["limitSeconds"] as? Int else {
                        continue
                    }

                    var targets: [PolicyTarget] = []
                    if let rawTargets = pDict["targets"] as? [[String: Any]] {
                        for tDict in rawTargets {
                            let tTypeStr = (tDict["targetType"] as? String)?.uppercased() ?? "APP"
                            let tVal = (tDict["targetValue"] as? String) ?? ""
                            let tType: TargetType = (tTypeStr == "WEBSITE") ? .website : ((tTypeStr == "CATEGORY") ? .category : .app)
                            targets.append(PolicyTarget(targetType: tType, targetValue: tVal))
                        }
                    }

                    let policy = Policy(
                        id: id,
                        name: name,
                        limitSeconds: limitSec,
                        targets: targets
                    )
                    loadedPolicies.append(policy)
                }

                if !loadedPolicies.isEmpty {
                    try policyService.savePolicies(loadedPolicies)
                }
                return (loadedPolicies.count, false, nil)
            }
            return (0, false, nil)
        } catch {
            return (0, false, error.localizedDescription)
        }
    }
}
