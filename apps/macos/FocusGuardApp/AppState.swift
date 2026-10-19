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
    @Published public var isFocusActive: Bool = false
    @Published public var focusRemainingSeconds: Int = 0
    @Published public var activeBlockedTargets: [String] = []
    @Published public var isEmergencyLocked: Bool = false

    public struct WebsiteUsageItem: Identifiable, Codable {
        public var id: String { domain }
        public let domain: String
        public let totalSeconds: Int
        public let formattedTime: String
        public let usedMinutes: Int
        public let category: String
        public let isDistraction: Bool
        public let policyName: String?
        public let limitSeconds: Int?
        public let isExceeded: Bool

        public init(domain: String, totalSeconds: Int, formattedTime: String, usedMinutes: Int, category: String, isDistraction: Bool, policyName: String? = nil, limitSeconds: Int? = nil, isExceeded: Bool = false) {
            self.domain = domain
            self.totalSeconds = totalSeconds
            self.formattedTime = formattedTime
            self.usedMinutes = usedMinutes
            self.category = category
            self.isDistraction = isDistraction
            self.policyName = policyName
            self.limitSeconds = limitSeconds
            self.isExceeded = isExceeded
        }
    }

    @Published public var websiteUsageList: [WebsiteUsageItem] = []
    @Published public var totalWebsiteTime: String = "0s"
    @Published public var totalWebsiteSeconds: Int = 0

    // Discovered Running Applications
    public struct DiscoveredApp: Identifiable, Hashable, Sendable {
        public var id: String { bundleIdentifier }
        public let name: String
        public let bundleIdentifier: String
        public let isTracked: Bool
        public let isProtected: Bool

        public init(name: String, bundleIdentifier: String, isTracked: Bool, isProtected: Bool) {
            self.name = name
            self.bundleIdentifier = bundleIdentifier
            self.isTracked = isTracked
            self.isProtected = isProtected
        }
    }

    @Published public var runningApplicationsList: [DiscoveredApp] = []

    // Categorical Chart Data Point
    public struct CategoryUsagePoint: Identifiable, Sendable {
        public var id: String { category }
        public let category: String
        public let totalMinutes: Double
        public let isDistraction: Bool

        public init(category: String, totalMinutes: Double, isDistraction: Bool) {
            self.category = category
            self.totalMinutes = totalMinutes
            self.isDistraction = isDistraction
        }
    }

    public var categoryUsageBreakdown: [CategoryUsagePoint] {
        var map: [String: (minutes: Double, isDistraction: Bool)] = [:]
        for item in websiteUsageList {
            let cat = item.category.isEmpty ? "Uncategorized" : item.category
            let existing = map[cat] ?? (0.0, item.isDistraction)
            map[cat] = (existing.minutes + (Double(item.totalSeconds) / 60.0), existing.isDistraction || item.isDistraction)
        }
        return map.map { (cat, val) in
            CategoryUsagePoint(category: cat, totalMinutes: round(val.minutes * 10) / 10, isDistraction: val.isDistraction)
        }.sorted { $0.totalMinutes > $1.totalMinutes }
    }

    // Fleet Multi-Device Model
    public struct FleetDevice: Identifiable, Codable, Sendable {
        public let id: String
        public let name: String
        public let platform: String
        public let clientType: String
        public let status: String
        public let protectionState: String?
        public let lastHeartbeat: String?

        public var isLocked: Bool {
            status == "LOCKED" || protectionState == "LOCKED"
        }

        public var platformIcon: String {
            switch platform.uppercased() {
            case "ANDROID": return "phone.fill"
            case "MACOS": return "applelogo"
            case "WINDOWS": return "pc"
            case "WEB_EXTENSION", "BROWSER_EXTENSION": return "puzzlepiece.extension.fill"
            default: return "laptopcomputer"
            }
        }
    }

    @Published public var fleetDevices: [FleetDevice] = []

    // Extension Anti-Tampering & 60s Watchdog
    public static let supportedBrowsers: [(name: String, bundleId: String)] = [
        ("Google Chrome", "com.google.Chrome"),
        ("Brave Browser", "com.brave.Browser"),
        ("Microsoft Edge", "com.microsoft.edgemac"),
        ("Arc", "company.thebrowser.Browser"),
        ("Chromium", "org.chromium.Chromium")
    ]

    @Published public var extensionTamperDetected: Bool = false
    @Published public var extensionGraceRemainingSeconds: Int = 60
    @Published public var tamperBrowserName: String = ""
    @Published public var tamperBrowserBundleId: String = ""
    @Published public var isIncognitoCompliant: Bool = true
    @Published public var isLiveStreaming: Bool = true
    public var lastExtensionHeartbeatTime: Date = Date()

    // Interactive Focus Session Control
    @Published public var selectedFocusPresetMinutes: Int = 45

    // macOS Preferences / Settings
    @Published public var serverBaseUrl: String = UserDefaults.standard.string(forKey: "fg_server_url") ?? "http://localhost:8080"
    @Published public var idleThresholdSeconds: Int = UserDefaults.standard.integer(forKey: "fg_idle_threshold") == 0 ? 60 : UserDefaults.standard.integer(forKey: "fg_idle_threshold")
    @Published public var soundAlertsEnabled: Bool = UserDefaults.standard.object(forKey: "fg_sound_alerts") == nil ? true : UserDefaults.standard.bool(forKey: "fg_sound_alerts")

    public enum NavigationItem: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case usage = "Usage Analytics"
        case policies = "Policies"
        case applications = "Applications"
        case devices = "Devices & Pairing"
        case diagnostics = "Diagnostics & Security"
        case settings = "Settings"

        public var id: String { rawValue }
        public var iconName: String {
            switch self {
            case .dashboard: return "shield.checkered"
            case .usage: return "chart.bar.fill"
            case .policies: return "slider.horizontal.3"
            case .applications: return "app.window.checkmark"
            case .devices: return "laptopcomputer"
            case .diagnostics: return "stethoscope"
            case .settings: return "gearshape.fill"
            }
        }
    }

    public init(container: DependencyContainer) {
        self.container = container
        refreshState()
        refreshRunningApplications()
        setupRealtimeCallbacks()
        startPeriodicTracking()
        startPeriodicSync()
        Task { [weak self] in
            await self?.checkActiveFocusSession()
        }
    }

    private func setupRealtimeCallbacks() {
        container.realtimeService.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.realtimeState = state
            }
        }

        container.realtimeService.onPolicyUpdated = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshState()
                self?.syncEventsNow()
            }
        }

        container.realtimeService.onFocusChanged = { [weak self] active, seconds, targets in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isFocusActive = active
                self.focusRemainingSeconds = seconds
                self.activeBlockedTargets = targets
                if active {
                    self.statusMessage = "⚡ Focus Mode Active: Fleet Lockdown Engaged"
                    self.container.notificationAdapter.notifyLimitReached(
                        appName: "Focus Mode (Fleet)",
                        bundleIdentifier: "fleet.lockdown"
                    )
                } else {
                    self.statusMessage = "Focus Mode Ended • Normal Browsing Restored"
                }
            }
        }

        container.realtimeService.onLockdownChanged = { [weak self] isLocked, command in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isEmergencyLocked = isLocked
                if isLocked {
                    self.statusMessage = "🛑 EMERGENCY STOP: App locked down by administrator"
                    self.container.notificationAdapter.notifyLimitReached(
                        appName: "FocusGuard Administrator",
                        bundleIdentifier: "admin.remote.stop"
                    )
                    // Terminate all tracked target applications immediately
                    for target in self.trackedTargets {
                        self.container.applicationControl.terminateApplication(bundleIdentifier: target)
                    }
                    if !self.currentForegroundBundleId.isEmpty && self.trackedTargets.contains(self.currentForegroundBundleId) {
                        self.container.applicationControl.terminateApplication(bundleIdentifier: self.currentForegroundBundleId)
                    }
                } else {
                    self.statusMessage = "🔓 Protection Resumed: Applications unlocked by administrator"
                }
            }
        }

        container.realtimeService.onExtensionGraceTick = { [weak self] browser, remaining, warning in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.extensionTamperDetected = true
                self.tamperBrowserName = browser
                self.extensionGraceRemainingSeconds = remaining
                self.statusMessage = warning
            }
        }

        container.realtimeService.onExtensionRestored = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.lastExtensionHeartbeatTime = Date()
                if self.extensionTamperDetected {
                    self.extensionTamperDetected = false
                    self.extensionGraceRemainingSeconds = 60
                    self.statusMessage = "✅ FocusGuard Extension verified. Normal browsing active."
                }
            }
        }

        container.realtimeService.onBrowserTerminated = { [weak self] browser, reason in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.extensionTamperDetected = false
                self.extensionGraceRemainingSeconds = 60
                self.statusMessage = "🛑 \(browser) force-closed: \(reason)"
            }
        }

        container.realtimeService.onWebsiteUsageUpdated = { [weak self] in
            Task { @MainActor [weak self] in
                self?.fetchWebsiteAnalytics()
            }
        }
    }

    private var syncTask: Task<Void, Never>?

    public func startPeriodicSync() {
        if container.deviceService.isEnrolled() {
            container.realtimeService.connect()
            syncEventsNow()
        } else {
            Task { [weak self] in
                await self?.autoEnrollWithLocalServer()
            }
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

    public func autoEnrollWithLocalServer() async {
        guard !container.deviceService.isEnrolled() else {
            container.realtimeService.connect()
            syncEventsNow()
            return
        }

        guard let loginUrl = URL(string: "http://localhost:8080/api/v1/auth/login") else { return }
        var req = URLRequest(url: loginUrl)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": "demo@focusguard.local",
            "password": "focusguard123"
        ])

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["accessToken"] as? String {
                let ownerDeviceID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
                try container.deviceService.pairDevice(deviceId: ownerDeviceID, deviceToken: token, deviceName: self.deviceName)
                container.realtimeService.connect()
                refreshState()
                self.statusMessage = "Connected to FocusGuard Fleet Command Center"
                syncEventsNow()
            } else {
                container.realtimeService.connect()
            }
        } catch {
            container.realtimeService.connect()
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
        refreshRunningApplications()
    }

    private var trackingTask: Task<Void, Never>?
    private var trackingTickCount: Int = 0
    private var cachedUserToken: String?

    public func fetchWebsiteAnalytics() {
        Task { [weak self] in
            guard let self = self else { return }

            if self.cachedUserToken == nil {
                guard let loginURL = URL(string: "http://localhost:8080/api/v1/auth/login") else { return }
                var loginReq = URLRequest(url: loginURL)
                loginReq.httpMethod = "POST"
                loginReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: String] = ["email": "demo@focusguard.local", "password": "focusguard123"]
                loginReq.httpBody = try? JSONSerialization.data(withJSONObject: body)

                if let (data, res) = try? await URLSession.shared.data(for: loginReq),
                   let http = res as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tok = json["accessToken"] as? String {
                    self.cachedUserToken = tok
                }
            }

            guard let token = self.cachedUserToken,
                  let webURL = URL(string: "http://localhost:8080/api/v1/analytics/websites") else { return }

            var req = URLRequest(url: webURL)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, res) = try await URLSession.shared.data(for: req)
                guard let http = res as? HTTPURLResponse else { return }
                if http.statusCode == 401 {
                    self.cachedUserToken = nil
                    return
                }
                guard http.statusCode == 200 else { return }

                struct WebResp: Codable {
                    let date: String
                    let totalSeconds: Int
                    let formattedTime: String
                    let websites: [WebsiteUsageItem]
                }

                let decoded = try JSONDecoder().decode(WebResp.self, from: data)
                await MainActor.run {
                    self.websiteUsageList = decoded.websites
                    self.totalWebsiteTime = decoded.formattedTime
                    self.totalWebsiteSeconds = decoded.totalSeconds
                }
            } catch {
                // Silently retain last known data if network offline
            }
        }
    }

    public func startPeriodicTracking() {
        trackingTask?.cancel()
        fetchWebsiteAnalytics()
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self, !Task.isCancelled else { break }
                _ = try? self.container.usageService.tick(deltaSeconds: 1)
                if self.isEmergencyLocked {
                    if !self.currentForegroundBundleId.isEmpty && self.trackedTargets.contains(self.currentForegroundBundleId) {
                        self.container.applicationControl.terminateApplication(bundleIdentifier: self.currentForegroundBundleId)
                    }
                }
                if self.isFocusActive && self.focusRemainingSeconds > 0 {
                    self.focusRemainingSeconds -= 1
                    if self.focusRemainingSeconds <= 0 {
                        self.isFocusActive = false
                        self.statusMessage = "Focus Mode Ended • Normal Browsing Restored"
                    }
                }

                // Extension Anti-Tamper & 60-Second Watchdog
                let runningBrowsers = AppState.supportedBrowsers.filter { b in
                    !NSRunningApplication.runningApplications(withBundleIdentifier: b.bundleId).isEmpty
                }

                if let activeBrowser = runningBrowsers.first {
                    // Supported browser is running! Check extension heartbeat
                    let secondsSinceHeartbeat = Date().timeIntervalSince(self.lastExtensionHeartbeatTime)
                    if secondsSinceHeartbeat > 20.0 {
                        // Extension missing or deleted
                        if !self.extensionTamperDetected {
                            self.extensionTamperDetected = true
                            self.extensionGraceRemainingSeconds = 60
                            self.tamperBrowserName = activeBrowser.name
                            self.tamperBrowserBundleId = activeBrowser.bundleId
                            self.statusMessage = "⚠️ EXTENSION MISSING: \(activeBrowser.name) will force-quit in 60s if not restored."
                            if self.soundAlertsEnabled {
                                NSSound.beep()
                            }
                        } else {
                            if self.extensionGraceRemainingSeconds > 0 {
                                self.extensionGraceRemainingSeconds -= 1
                            }
                            if self.extensionGraceRemainingSeconds <= 0 {
                                // 1 Minute Grace Period Expired: Force close the browser!
                                self.container.applicationControl.terminateApplication(bundleIdentifier: activeBrowser.bundleId)
                                self.statusMessage = "🛑 \(activeBrowser.name) force-closed: Extension was deleted or disabled after 60s."
                                self.extensionTamperDetected = false
                                self.extensionGraceRemainingSeconds = 60
                            }
                        }
                    } else {
                        // Extension heartbeat is healthy
                        if self.extensionTamperDetected {
                            self.extensionTamperDetected = false
                            self.extensionGraceRemainingSeconds = 60
                            self.statusMessage = "✅ FocusGuard Extension verified. Protection active."
                        }
                    }
                } else {
                    // No browser running
                    if self.extensionTamperDetected {
                        self.extensionTamperDetected = false
                        self.extensionGraceRemainingSeconds = 60
                    }
                }

                self.trackingTickCount += 1
                if self.trackingTickCount % 3 == 0 {
                    self.fetchWebsiteAnalytics()
                }
                if self.trackingTickCount % 5 == 0 {
                    Task { [weak self] in
                        await self?.fetchFleetDevices()
                    }
                }
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

    // MARK: - Running Applications Discovery
    public func refreshRunningApplications() {
        let running = NSWorkspace.shared.runningApplications
        var list: [DiscoveredApp] = []
        let currentBundle = Bundle.main.bundleIdentifier ?? "com.focusguard.macos"

        for app in running {
            guard app.activationPolicy == .regular,
                  let bundleId = app.bundleIdentifier,
                  bundleId != currentBundle,
                  !bundleId.isEmpty else {
                continue
            }
            let name = app.localizedName ?? bundleId
            let isTracked = trackedTargets.contains(bundleId)
            let isProtected = ProtectedAppDenylist.isProtected(bundleIdentifier: bundleId)
            list.append(DiscoveredApp(name: name, bundleIdentifier: bundleId, isTracked: isTracked, isProtected: isProtected))
        }

        self.runningApplicationsList = list.sorted { a, b in
            if a.isTracked != b.isTracked { return a.isTracked && !b.isTracked }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Focus Session API
    public func startFocusLockdown(minutes: Int) async {
        guard let token = (try? container.deviceService.getDeviceToken()) ?? cachedUserToken else {
            self.statusMessage = "Cannot start focus: Please pair device first"
            return
        }

        guard let url = URL(string: "\(serverBaseUrl)/api/v1/focus/start") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "durationMinutes": minutes,
            "reason": "macOS Native Deep Work Lockdown"
        ])

        do {
            let (_, res) = try await URLSession.shared.data(for: req)
            if let http = res as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 201 {
                await MainActor.run {
                    self.isFocusActive = true
                    self.focusRemainingSeconds = minutes * 60
                    self.statusMessage = "⚡ Focus Lockdown active: \(minutes)m"
                    if self.soundAlertsEnabled {
                        NSSound.beep()
                    }
                }
            } else {
                await MainActor.run { self.statusMessage = "Failed to start focus session" }
            }
        } catch {
            await MainActor.run { self.statusMessage = "Network error starting focus: \(error.localizedDescription)" }
        }
    }

    public func endFocusLockdown() async {
        guard let token = (try? container.deviceService.getDeviceToken()) ?? cachedUserToken else { return }
        guard let url = URL(string: "\(serverBaseUrl)/api/v1/focus/end") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, res) = try await URLSession.shared.data(for: req)
            if let http = res as? HTTPURLResponse, http.statusCode == 200 {
                await MainActor.run {
                    self.isFocusActive = false
                    self.focusRemainingSeconds = 0
                    self.statusMessage = "Focus Mode Released • Normal Browsing Restored"
                }
            }
        } catch {
            await MainActor.run { self.statusMessage = "Error ending focus: \(error.localizedDescription)" }
        }
    }

    public func checkActiveFocusSession() async {
        guard let token = (try? container.deviceService.getDeviceToken()) ?? cachedUserToken else { return }
        guard let url = URL(string: "\(serverBaseUrl)/api/v1/focus/active") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            if let http = res as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let active = json["active"] as? Bool {
                await MainActor.run {
                    self.isFocusActive = active
                    if active, let session = json["session"] as? [String: Any],
                       let remaining = session["remainingSeconds"] as? Int {
                        self.focusRemainingSeconds = remaining
                    } else if !active {
                        self.focusRemainingSeconds = 0
                    }
                }
            }
        } catch {}
    }

    // MARK: - Preferences & Settings
    public func updateSettings(url: String, idleSeconds: Int, soundAlerts: Bool) {
        self.serverBaseUrl = url
        self.idleThresholdSeconds = idleSeconds
        self.soundAlertsEnabled = soundAlerts
        UserDefaults.standard.set(url, forKey: "fg_server_url")
        UserDefaults.standard.set(idleSeconds, forKey: "fg_idle_threshold")
        UserDefaults.standard.set(soundAlerts, forKey: "fg_sound_alerts")
        self.statusMessage = "Preferences updated successfully."
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
        if let policy = activePolicies.first(where: { $0.id == id }) {
            // Anti-Tampering: Active policies cannot be deleted while enforcement is active
            if isFocusActive || isEmergencyLocked || policy.limitSeconds > 0 {
                self.statusMessage = "🔒 Protected Policy: Active policy '\(policy.name)' cannot be deleted while enforcement is active."
                return
            }
        }

        do {
            try container.policyService.deletePolicy(id: id)
            refreshState()
            self.statusMessage = "Policy deleted."
        } catch {
            self.statusMessage = "Delete error: \(error.localizedDescription)"
        }
    }

    // MARK: - Central Fleet Management & Remote Blocking
    public func fetchFleetDevices() async {
        guard let token = (try? container.deviceService.getDeviceToken()) ?? cachedUserToken else { return }
        guard let url = URL(string: "\(serverBaseUrl)/api/v1/devices") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            guard let http = res as? HTTPURLResponse, http.statusCode == 200 else { return }
            struct FleetResp: Codable {
                let devices: [FleetDevice]
            }
            if let decoded = try? JSONDecoder().decode(FleetResp.self, from: data) {
                await MainActor.run {
                    self.fleetDevices = decoded.devices
                }
            } else if let arr = try? JSONDecoder().decode([FleetDevice].self, from: data) {
                await MainActor.run {
                    self.fleetDevices = arr
                }
            }
        } catch {}
    }

    public func blockDevice(id: String) async {
        await dispatchFleetCommand(deviceId: id, commandType: "STOP_APP", reason: "Blocked by Central Admin from macOS")
    }

    public func unblockDevice(id: String) async {
        await dispatchFleetCommand(deviceId: id, commandType: "RESUME_APP", reason: "Resumed by Central Admin from macOS")
    }

    public func emergencyStopAllFleet() async {
        await dispatchFleetCommand(deviceId: "ALL", commandType: "STOP_APP", reason: "Emergency Block Entire Fleet triggered by Admin")
    }

    private func dispatchFleetCommand(deviceId: String, commandType: String, reason: String) async {
        guard let token = (try? container.deviceService.getDeviceToken()) ?? cachedUserToken else {
            self.statusMessage = "Command failed: Authentication token missing"
            return
        }
        guard let url = URL(string: "\(serverBaseUrl)/api/v1/commands/dispatch") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "deviceId": deviceId,
            "commandType": commandType,
            "reason": reason,
            "payload": ["source": "macOS Central Admin", "timestamp": Date().timeIntervalSince1970]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, res) = try await URLSession.shared.data(for: req)
            if let http = res as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 201 {
                await MainActor.run {
                    if commandType == "STOP_APP" || commandType == "LOCKDOWN_DEVICE" {
                        self.statusMessage = "🚨 Admin Lockdown Dispatched: Device(s) blocked immediately."
                    } else {
                        self.statusMessage = "✅ Admin Resume Dispatched: Device(s) unblocked."
                    }
                }
                await fetchFleetDevices()
            } else {
                await MainActor.run { self.statusMessage = "Failed to dispatch command to device." }
            }
        } catch {
            await MainActor.run { self.statusMessage = "Network error: \(error.localizedDescription)" }
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
