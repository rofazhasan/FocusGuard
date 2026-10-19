import Foundation

public enum RealtimeConnectionState: String, Sendable, Equatable {
    case disconnected = "DISCONNECTED"
    case connecting = "CONNECTING"
    case connected = "CONNECTED"
    case revoked = "REVOKED"
}

public protocol RealtimeServiceProtocol: AnyObject, Sendable {
    var connectionState: RealtimeConnectionState { get }
    var onStateChange: (@Sendable (RealtimeConnectionState) -> Void)? { get set }
    var onRevocationReceived: (@Sendable () -> Void)? { get set }
    var onFocusChanged: (@Sendable (Bool, Int, [String]) -> Void)? { get set }
    var onPolicyUpdated: (@Sendable () -> Void)? { get set }
    var onLockdownChanged: (@Sendable (Bool, String) -> Void)? { get set }
    var onExtensionGraceTick: (@Sendable (String, Int, String) -> Void)? { get set }
    var onExtensionRestored: (@Sendable () -> Void)? { get set }
    var onBrowserTerminated: (@Sendable (String, String) -> Void)? { get set }
    var onWebsiteUsageUpdated: (@Sendable () -> Void)? { get set }
    func connect()
    func disconnect()
    func sendHeartbeat()
}

public final class RealtimeService: RealtimeServiceProtocol, @unchecked Sendable {
    private let deviceService: DeviceService
    private let policyService: PolicyService
    private let serverBaseURL: String
    private let urlSession: URLSession
    private let lock = NSLock()

    private var webSocketTask: URLSessionWebSocketTask?
    private var isRunning = false
    private var reconnectAttempt = 0
    private var _connectionState: RealtimeConnectionState = .disconnected

    public var onStateChange: (@Sendable (RealtimeConnectionState) -> Void)?
    public var onRevocationReceived: (@Sendable () -> Void)?
    public var onFocusChanged: (@Sendable (Bool, Int, [String]) -> Void)?
    public var onPolicyUpdated: (@Sendable () -> Void)?
    public var onLockdownChanged: (@Sendable (Bool, String) -> Void)?
    public var onExtensionGraceTick: (@Sendable (String, Int, String) -> Void)?
    public var onExtensionRestored: (@Sendable () -> Void)?
    public var onBrowserTerminated: (@Sendable (String, String) -> Void)?
    public var onWebsiteUsageUpdated: (@Sendable () -> Void)?

    public var connectionState: RealtimeConnectionState {
        lock.lock()
        defer { lock.unlock() }
        return _connectionState
    }

    public init(
        deviceService: DeviceService,
        policyService: PolicyService,
        serverBaseURL: String = "http://localhost:8080",
        urlSession: URLSession = .shared
    ) {
        self.deviceService = deviceService
        self.policyService = policyService
        self.serverBaseURL = serverBaseURL
        self.urlSession = urlSession
    }

    public func connect() {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }

        let token = (try? deviceService.getDeviceToken()) ?? ""
        isRunning = true
        _connectionState = .connecting
        lock.unlock()

        notifyStateChange(.connecting)
        establishWebSocketConnection(token: token)
    }

    public func disconnect() {
        lock.lock()
        isRunning = false
        _connectionState = .disconnected
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        lock.unlock()

        notifyStateChange(.disconnected)
    }

    public func sendHeartbeat() {
        lock.lock()
        guard _connectionState == .connected, let task = webSocketTask else {
            lock.unlock()
            return
        }
        lock.unlock()

        let heartbeatPayload: [String: Any] = [
            "type": "HEARTBEAT",
            "platform": "MACOS",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]

        if let data = try? JSONSerialization.data(withJSONObject: heartbeatPayload),
           let str = String(data: data, encoding: .utf8) {
            task.send(.string(str)) { _ in }
        }
    }

    private func establishWebSocketConnection(token: String) {
        var wsUrlString = serverBaseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
            + "/ws"
        if !token.isEmpty {
            wsUrlString += "?token=" + token
        }

        guard let url = URL(string: wsUrlString) else {
            handleDisconnect()
            return
        }

        var request = URLRequest(url: url)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let task = urlSession.webSocketTask(with: request)
        lock.lock()
        self.webSocketTask = task
        lock.unlock()

        task.resume()

        lock.lock()
        self._connectionState = .connected
        self.reconnectAttempt = 0
        lock.unlock()

        notifyStateChange(.connected)
        listenForMessages(task: task)
    }

    private func listenForMessages(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure:
                self.handleDisconnect()

            case .success(let message):
                switch message {
                case .string(let text):
                    self.processIncomingMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.processIncomingMessage(text)
                    }
                @unknown default:
                    break
                }

                // Continue listening if still running
                self.lock.lock()
                let running = self.isRunning
                self.lock.unlock()
                if running {
                    self.listenForMessages(task: task)
                }
            }
        }
    }

    public func processIncomingMessage(_ rawText: String) {
        guard let data = rawText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventName = (json["event"] as? String) ?? (json["type"] as? String) else {
            return
        }

        switch eventName {
        case "DEVICE_REVOKED":
            handleDeviceRevocation()

        case "POLICY_UPDATED", "POLICY_CREATED", "POLICY_DELETED":
            try? policyService.reloadCache()
            onPolicyUpdated?()

        case "FOCUS_STARTED", "FOCUS_SESSION_STARTED":
            let payload = json["payload"] as? [String: Any] ?? json
            let durationMinutes = payload["durationMinutes"] as? Int ?? 45
            let targets = payload["blockedTargets"] as? [String] ?? ["youtube.com", "instagram.com", "reddit.com", "tiktok.com"]
            onFocusChanged?(true, durationMinutes * 60, targets)

        case "FOCUS_ENDED", "FOCUS_SESSION_ENDED":
            onFocusChanged?(false, 0, [])

        case "REMOTE_COMMAND":
            let payload = json["payload"] as? [String: Any] ?? [:]
            let commandType = (json["commandType"] as? String) ?? (payload["commandType"] as? String) ?? ""
            let targetDeviceId = (json["deviceId"] as? String) ?? (payload["deviceId"] as? String) ?? "ALL"
            let protectionState = (json["protectionState"] as? String) ?? ""

            let currentDeviceId = (try? deviceService.getDeviceIdentity())?.deviceId?.uuidString ?? ""
            let isTargeted = targetDeviceId == "ALL" || targetDeviceId.isEmpty || (
                !currentDeviceId.isEmpty && targetDeviceId.caseInsensitiveCompare(currentDeviceId) == .orderedSame
            )

            if isTargeted {
                let isLockdown = commandType == "STOP_APP" || commandType == "LOCKDOWN_DEVICE" || protectionState == "LOCKED"
                onLockdownChanged?(isLockdown, commandType)
            }

        case "EXTENSION_GRACE_TICK":
            let payload = json["payload"] as? [String: Any] ?? json
            let browser = payload["browserName"] as? String ?? "Browser"
            let remaining = payload["remainingSeconds"] as? Int ?? 60
            let warning = payload["warning"] as? String ?? "FocusGuard extension missing!"
            onExtensionGraceTick?(browser, remaining, warning)

        case "EXTENSION_RESTORED", "HEARTBEAT":
            onExtensionRestored?()

        case "BROWSER_TERMINATED":
            let payload = json["payload"] as? [String: Any] ?? json
            let browser = payload["browserName"] as? String ?? "Browser"
            let reason = payload["reason"] as? String ?? "Extension deleted or disabled."
            onBrowserTerminated?(browser, reason)

        case "WEBSITE_USAGE_TICK", "USAGE_SYNCED":
            onWebsiteUsageUpdated?()

        default:
            if let platform = json["platform"] as? String, platform == "WEB_EXTENSION" {
                onExtensionRestored?()
            }
            break
        }
    }

    public func handleDeviceRevocation() {
        lock.lock()
        _connectionState = .revoked
        isRunning = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        lock.unlock()

        // 1. Zero-trust local wipe
        try? deviceService.revokeDevice()

        // 2. Clear all cached policies
        try? policyService.clearAllPolicies()

        notifyStateChange(.revoked)
        onRevocationReceived?()
    }

    private func handleDisconnect() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        _connectionState = .disconnected
        webSocketTask = nil
        reconnectAttempt += 1
        let delay = min(30.0, pow(2.0, Double(min(reconnectAttempt, 5))))
        lock.unlock()

        notifyStateChange(.disconnected)

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let shouldReconnect = self.isRunning
            self.lock.unlock()
            if shouldReconnect {
                if let token = try? self.deviceService.getDeviceToken() {
                    self.establishWebSocketConnection(token: token)
                }
            }
        }
    }

    private func notifyStateChange(_ state: RealtimeConnectionState) {
        onStateChange?(state)
    }
}

public final class MockRealtimeService: RealtimeServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: RealtimeConnectionState = .disconnected
    public var sentHeartbeatsCount = 0
    private let deviceService: DeviceService
    private let policyService: PolicyService

    public var onStateChange: (@Sendable (RealtimeConnectionState) -> Void)?
    public var onRevocationReceived: (@Sendable () -> Void)?
    public var onFocusChanged: (@Sendable (Bool, Int, [String]) -> Void)?
    public var onPolicyUpdated: (@Sendable () -> Void)?
    public var onLockdownChanged: (@Sendable (Bool, String) -> Void)?
    public var onExtensionGraceTick: (@Sendable (String, Int, String) -> Void)?
    public var onExtensionRestored: (@Sendable () -> Void)?
    public var onBrowserTerminated: (@Sendable (String, String) -> Void)?
    public var onWebsiteUsageUpdated: (@Sendable () -> Void)?

    public var connectionState: RealtimeConnectionState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    public init(deviceService: DeviceService, policyService: PolicyService) {
        self.deviceService = deviceService
        self.policyService = policyService
    }

    public func connect() {
        lock.lock()
        defer { lock.unlock() }
        _state = .connected
    }

    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        _state = .disconnected
    }

    public func sendHeartbeat() {
        lock.lock()
        defer { lock.unlock() }
        sentHeartbeatsCount += 1
    }

    public func simulateRevocationPush() {
        lock.lock()
        _state = .revoked
        lock.unlock()

        try? deviceService.revokeDevice()
        try? policyService.clearAllPolicies()
    }

    public func simulatePolicyUpdatedPush() {
        try? policyService.reloadCache()
    }
}
