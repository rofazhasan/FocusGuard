// FocusGuard macOS Agent — Sync Engine
// WebSocket client + REST synchronization engine for macOS using URLSession.
// Implements the FocusGuard client protocol:
//   - Connects to ws://localhost:8080/ws?token=<deviceToken>
//   - Receives POLICY_PUSH (monotonic version check)
//   - Receives COMMAND (START_FOCUS, STOP_FOCUS, etc.)
//   - Heartbeat every 30 seconds
//   - Reconnect with exponential backoff
//   - Flushes offline usage deltas to POST /api/v1/usage/sync

import Foundation

public struct UsageDelta: Codable, Equatable {
    public let deviceId: String
    public let target: String
    public let targetType: String
    public let deltaSeconds: Int
    public let date: String

    public init(deviceId: String, target: String, targetType: String, deltaSeconds: Int, date: String) {
        self.deviceId = deviceId
        self.target = target
        self.targetType = targetType
        self.deltaSeconds = deltaSeconds
        self.date = date
    }
}

public struct SyncEnvelope<T: Codable>: Codable {
    public let type: String
    public let correlationId: String
    public let timestamp: Int64
    public let payload: T?

    public init(type: String, correlationId: String = "cor_\(Int64(Date().timeIntervalSince1970 * 1000))", timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000), payload: T? = nil) {
        self.type = type
        self.correlationId = correlationId
        self.timestamp = timestamp
        self.payload = payload
    }
}

public final class MacSyncEngine: NSObject, URLSessionWebSocketDelegate {
    public static let shared = MacSyncEngine()

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected: Bool = false
    private var reconnectAttempt: Int = 0
    private let maxBackoffSeconds: Double = 60.0

    private var serverBaseURL: String = "http://localhost:8080/api/v1"
    private var wsBaseURL: String = "ws://localhost:8080/ws"

    private var pendingUsageQueue: [UsageDelta] = []
    private let queueLock = NSLock()

    public var onPolicyPushReceived: (([Policy], Int) -> Void)?
    public var onCommandReceived: ((String, [String: Any]) -> Void)?
    public var onConnectionStateChanged: ((Bool) -> Void)?

    private var heartbeatTimer: Timer?
    private var flushTimer: Timer?

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    }

    public func configure(serverBase: String, wsBase: String) {
        self.serverBaseURL = serverBase
        self.wsBaseURL = wsBase
    }

    public func start(deviceToken: String, deviceId: String) {
        connectWebSocket(token: deviceToken)
        startTimers(deviceId: deviceId)
    }

    public func stop() {
        heartbeatTimer?.invalidate()
        flushTimer?.invalidate()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        onConnectionStateChanged?(false)
    }

    // ── WebSocket Lifecycle ──

    private func connectWebSocket(token: String) {
        guard let url = URL(string: "\(wsBaseURL)?token=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)") else { return }

        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncomingJSON(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingJSON(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()

            case .failure(let error):
                print("[MacSyncEngine] WebSocket receive error: \(error.localizedDescription)")
                self.handleDisconnect()
            }
        }
    }

    private func handleIncomingJSON(_ json: String) {
        guard let data = json.data(using: .utf8),
              let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = jsonObj["type"] as? String else { return }

        switch type {
        case "POLICY_PUSH":
            if let payload = jsonObj["payload"] as? [String: Any],
               let version = payload["version"] as? Int,
               let policiesData = try? JSONSerialization.data(withJSONObject: payload["policies"] ?? []),
               let policies = try? JSONDecoder().decode([Policy].self, from: policiesData) {
                print("[MacSyncEngine] Received POLICY_PUSH v\(version)")
                self.onPolicyPushReceived?(policies, version)
            }

        case "COMMAND":
            if let payload = jsonObj["payload"] as? [String: Any],
               let commandType = payload["type"] as? String {
                print("[MacSyncEngine] Received COMMAND: \(commandType)")
                self.onCommandReceived?(commandType, payload)
            }

        case "HEARTBEAT_ACK":
            print("[MacSyncEngine] Heartbeat acknowledged by server")

        default:
            break
        }
    }

    private func handleDisconnect() {
        isConnected = false
        onConnectionStateChanged?(false)
        let delay = min(pow(2.0, Double(reconnectAttempt)), maxBackoffSeconds)
        reconnectAttempt += 1
        print("[MacSyncEngine] Disconnected. Reconnecting in \(delay)s (attempt \(reconnectAttempt))...")

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if let token = KeychainStorage.shared.loadString(key: "device_token") {
                self.connectWebSocket(token: token)
            }
        }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
        reconnectAttempt = 0
        print("[MacSyncEngine] WebSocket connected successfully")
        onConnectionStateChanged?(true)
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        handleDisconnect()
    }

    // ── Timers & Usage Ingestion ──

    private func startTimers(deviceId: String) {
        DispatchQueue.main.async {
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
                self?.sendHeartbeat(deviceId: deviceId)
            }

            self.flushTimer?.invalidate()
            self.flushTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
                self?.flushUsageQueue(deviceId: deviceId)
            }
        }
    }

    private func sendHeartbeat(deviceId: String) {
        guard isConnected else { return }
        let envelope = SyncEnvelope(type: "HEARTBEAT", payload: ["deviceId": deviceId, "platform": "MACOS"])
        if let data = try? JSONEncoder().encode(envelope), let jsonStr = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(jsonStr)) { error in
                if let error = error {
                    print("[MacSyncEngine] Heartbeat send failed: \(error)")
                }
            }
        }
    }

    public func queueUsage(deviceId: String, target: String, targetType: String, deltaSeconds: Int) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let dateStr = formatter.string(from: Date())

        let delta = UsageDelta(deviceId: deviceId, target: target, targetType: targetType, deltaSeconds: deltaSeconds, date: dateStr)

        queueLock.lock()
        pendingUsageQueue.append(delta)
        queueLock.unlock()
    }

    public func flushUsageQueue(deviceId: String) {
        queueLock.lock()
        guard !pendingUsageQueue.isEmpty else {
            queueLock.unlock()
            return
        }
        let itemsToFlush = pendingUsageQueue
        queueLock.unlock()

        guard let url = URL(string: "\(serverBaseURL)/usage/sync") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = KeychainStorage.shared.loadString(key: "device_token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "deviceId": deviceId,
            "usageDeltas": itemsToFlush.map { [
                "targetValue": $0.target,
                "durationSeconds": $0.deltaSeconds,
                "date": $0.date
            ]}
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                self.queueLock.lock()
                // Remove flushed items
                self.pendingUsageQueue.removeFirst(itemsToFlush.count)
                self.queueLock.unlock()
                print("[MacSyncEngine] Successfully synced \(itemsToFlush.count) usage deltas")
            }
        }.resume()
    }
}
