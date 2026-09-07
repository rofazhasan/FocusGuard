import Foundation
import CoreGraphics

public enum IdleStatus: String, Equatable, Sendable {
    case active = "ACTIVE"
    case idle = "IDLE"
    case unknown = "UNKNOWN"
}

public protocol IdleDetector: Sendable {
    func getIdleStatus(thresholdSeconds: Double) -> IdleStatus
    func getIdleSeconds() -> Double
}

public final class MacIdleDetector: IdleDetector, @unchecked Sendable {
    public init() {}

    public func getIdleSeconds() -> Double {
        let anyInputType = CGEventType(rawValue: ~0) ?? .null
        let idleSec = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputType)
        return idleSec >= 0 ? idleSec : 0
    }

    public func getIdleStatus(thresholdSeconds: Double = 60.0) -> IdleStatus {
        let seconds = getIdleSeconds()
        if seconds >= thresholdSeconds {
            return .idle
        }
        return .active
    }
}

public final class MockIdleDetector: IdleDetector, @unchecked Sendable {
    private var simulatedIdleSeconds: Double = 0.0
    private let lock = NSLock()

    public init(initialIdleSeconds: Double = 0.0) {
        self.simulatedIdleSeconds = initialIdleSeconds
    }

    public func setIdleSeconds(_ seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        self.simulatedIdleSeconds = seconds
    }

    public func getIdleSeconds() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return simulatedIdleSeconds
    }

    public func getIdleStatus(thresholdSeconds: Double = 60.0) -> IdleStatus {
        let seconds = getIdleSeconds()
        return seconds >= thresholdSeconds ? .idle : .active
    }
}
