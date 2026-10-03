import Foundation
import SwiftUI
import Combine
import FocusGuardCore

@MainActor
public final class AppState: ObservableObject {
    public let container: DependencyContainer

    @Published public var selectedTab: NavigationItem = .dashboard

    @Published public var deviceStatus: DeviceState = .unregistered
    @Published public var deviceName: String = "MacBook Pro"
    @Published public var deviceId: String = "Unenrolled"
    @Published public var publicKeyPem: String = ""
    @Published public var isEnrolled: Bool = false

    @Published public var currentForegroundApp: String = "None"
    @Published public var currentForegroundBundleId: String = ""
    @Published public var usageState: UsageState = .noTarget
    @Published public var todayUsageSeconds: Int = 0

    @Published public var pendingEventCount: Int = 0
    @Published public var statusMessage: String = "FocusGuard Ready"
    @Published public var realtimeState: RealtimeConnectionState = .disconnected

    @Published public var activePolicies: [Policy] = []
    @Published public var trackedTargets: [String] = []
    @Published public var recentSessions: [UsageSession] = []

    public enum NavigationItem: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case usage = "Usage Analytics"
        case policies = "Policies"
        case applications = "Applications"
        case devices = "Devices & Pairing"
        case diagnostics = "Diagnostics & Security"

        public var id: String { rawValue }
        public var iconName: String {
            switch self {
            case .dashboard: return "shield.checkered"
            case .usage: return "chart.bar.fill"
            case .policies: return "slider.horizontal.3"
            case .applications: return "app.window.checkmark"
            case .devices: return "laptopcomputer"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    public init(container: DependencyContainer) {
        self.container = container
        refreshState()
        startPeriodicTracking()
        startPeriodicSync()
    }

    private var syncTask: Task<Void, Never>?

    public func startPeriodicSync() {
        if container.deviceService.isEnrolled() {
            container.realtimeService.connect()
            syncEventsNow()
        }

        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self = self, !Task.isCancelled else { break }
                if self.container.deviceService.isEnrolled() {
                    self.syncEventsNow()
                }
            }
        }
    }

    public func refreshState() {
        if let identity = try? container.deviceService.initialize() {
            self.deviceStatus = identity.status
            self.deviceName = identity.deviceName
            self.deviceId = identity.deviceId?.uuidString ?? "Unenrolled"
            self.publicKeyPem = identity.publicKeyPem
            self.isEnrolled = container.deviceService.isEnrolled()
        }

        self.usageState = container.usageService.currentState()
        self.pendingEventCount = (try? container.eventRepo.getPendingEventCount()) ?? 0
        self.realtimeState = container.realtimeService.connectionState

        // Refresh today's usage for active target
        let today = UsageSession.currentDateString()
        if let currentFg = container.foregroundProvider.getForegroundApplication() {
            self.currentForegroundApp = currentFg.localizedName
            self.currentForegroundBundleId = currentFg.bundleIdentifier
            let usage = (try? container.usageRepo.getDailyUsage(date: today, bundleIdentifier: currentFg.bundleIdentifier)) ?? 0
            self.todayUsageSeconds = usage
        } else {
            self.currentForegroundApp = "Desktop / None"
            self.currentForegroundBundleId = ""
        }

        // Active Policies & Targets
        self.activePolicies = (try? container.policyService.getAllPolicies()) ?? []
        self.trackedTargets = Array(container.usageService.getTrackedTargets()).sorted()
        self.recentSessions = (try? container.usageRepo.getRecentSessions(limit: 15)) ?? []
    }

    private var trackingTask: Task<Void, Never>?

    public func startPeriodicTracking() {
        trackingTask?.cancel()
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self, !Task.isCancelled else { break }
                try? self.container.usageService.tick(deltaSeconds: 1)
                self.refreshState()
            }
        }
    }

    public func stopPeriodicTracking() {
        trackingTask?.cancel()
        trackingTask = nil
    }

    public func pairDevice(deviceId: UUID, deviceToken: String) {
        do {
            try container.deviceService.pairDevice(deviceId: deviceId, deviceToken: deviceToken)
            container.realtimeService.connect()
            refreshState()
            self.statusMessage = "Device successfully paired!"
        } catch {
            self.statusMessage = "Pairing error: \(error.localizedDescription)"
        }
    }

    public func pairWithCode(code: String) async {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCode.isEmpty else {
            self.statusMessage = "Please enter a valid pairing code."
            return
        }

        self.statusMessage = "Submitting pairing code to FocusGuard Cloud..."
        guard let url = URL(string: "http://localhost:8080/api/v1/pairing/request") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "pairingCode": cleanCode,
            "deviceName": self.deviceName,
            "platform": "MACOS",
            "clientType": "DESKTOP",
            "appVersion": "1.0.0",
            "publicKey": self.publicKeyPem,
            "keyAlgorithm": "Ed25519"
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else { return }
        req.httpBody = httpBody

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 || httpResp.statusCode == 201 else {
                await MainActor.run { self.statusMessage = "Pairing failed: Invalid or expired code." }
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = json["sessionId"] as? String else {
                await MainActor.run { self.statusMessage = "Invalid session response from server." }
                return
            }

            await MainActor.run { self.statusMessage = "Request pending: Please click 'Approve' in your web dashboard..." }

            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let pollUrl = URL(string: "http://localhost:8080/api/v1/pairing/sessions/\(sessionId)/status") else { break }
                if let (pData, pResp) = try? await URLSession.shared.data(from: pollUrl),
                   let pHttp = pResp as? HTTPURLResponse, pHttp.statusCode == 200,
                   let pJson = try? JSONSerialization.jsonObject(with: pData) as? [String: Any],
                   let status = pJson["status"] as? String, status == "APPROVED",
                   let devIdStr = pJson["deviceId"] as? String,
                   let devUuid = UUID(uuidString: devIdStr),
                   let token = pJson["deviceToken"] as? String {
                    await MainActor.run {
                        self.pairDevice(deviceId: devUuid, deviceToken: token)
                        self.statusMessage = "Device enrolled & synchronized with FocusGuard Cloud!"
                    }
                    return
                }
            }
            await MainActor.run { self.statusMessage = "Pairing timed out. Please try again." }
        } catch {
            await MainActor.run { self.statusMessage = "Connection error: \(error.localizedDescription)" }
        }
    }

    public func revokeCurrentDevice() {
        do {
            try container.deviceService.revokeDevice()
            container.realtimeService.disconnect()
            try container.policyService.clearAllPolicies()
            refreshState()
            self.statusMessage = "Device credentials wiped securely."
        } catch {
            self.statusMessage = "Revocation error: \(error.localizedDescription)"
        }
    }

    public func addTrackedTarget(_ bundleId: String) {
        guard !bundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        container.usageService.addTrackedTarget(bundleId)
        self.statusMessage = "Added tracking for: \(bundleId)"
        refreshState()
    }

    public func removeTrackedTarget(_ bundleId: String) {
        container.usageService.removeTrackedTarget(bundleId)
        self.statusMessage = "Stopped tracking: \(bundleId)"
        refreshState()
    }

    public func savePolicy(name: String, limitMinutes: Int, warningMinutes: Int, targetBundle: String, action: EnforcementAction) {
        guard !name.isEmpty, limitMinutes > 0, !targetBundle.isEmpty else {
            self.statusMessage = "Invalid policy fields"
            return
        }

        let policy = Policy(
            name: name,
            limitSeconds: limitMinutes * 60,
            warningThresholdSeconds: warningMinutes * 60,
            enforcementAction: action,
            targets: [PolicyTarget(targetType: .app, targetValue: targetBundle)]
        )

        do {
            try container.policyService.savePolicy(policy)
            container.usageService.addTrackedTarget(targetBundle)
            refreshState()
            self.statusMessage = "Policy '\(name)' saved."
        } catch {
            self.statusMessage = "Policy error: \(error.localizedDescription)"
        }
    }

    public func deletePolicy(id: UUID) {
        do {
            try container.policyService.deletePolicy(id: id)
            refreshState()
            self.statusMessage = "Policy deleted."
        } catch {
            self.statusMessage = "Delete error: \(error.localizedDescription)"
        }
    }

    public func syncEventsNow() {
        Task {
            do {
                let res = try await self.container.syncService.flushPendingEvents()
                let polRes = try? await self.container.syncService.syncPolicies()
                await MainActor.run {
                    self.statusMessage = "Synced \(res.processedCount) events • \(polRes?.syncedCount ?? 0) policies"
                    self.refreshState()
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Sync failed: \(error.localizedDescription)"
                }
            }
        }
    }

    deinit {
        trackingTask?.cancel()
        syncTask?.cancel()
    }
}
