import Foundation
import AppKit

public struct ForegroundAppInfo: Equatable, Sendable {
    public let bundleIdentifier: String
    public let localizedName: String
    public let processIdentifier: pid_t
    public let timestamp: Date

    public init(
        bundleIdentifier: String,
        localizedName: String,
        processIdentifier: pid_t = 0,
        timestamp: Date = Date()
    ) {
        self.bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
        self.timestamp = timestamp
    }
}

public protocol ForegroundApplicationProvider: Sendable {
    func getForegroundApplication() -> ForegroundAppInfo?
}

public final class MacForegroundApplicationProvider: ForegroundApplicationProvider, @unchecked Sendable {
    private var observer: NSObjectProtocol?
    public var onForegroundAppChanged: (@Sendable (ForegroundAppInfo) -> Void)?

    public init() {
        self.observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                let info = Self.resolveAppInfo(from: app)
                self.onForegroundAppChanged?(info)
            }
        }
    }

    deinit {
        if let obs = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    public func getForegroundApplication() -> ForegroundAppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return Self.resolveAppInfo(from: app)
    }

    public static func resolveAppInfo(from app: NSRunningApplication) -> ForegroundAppInfo {
        let rawBundle = app.bundleIdentifier
        let bundleId: String

        if let bId = rawBundle, !bId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bundleId = bId
        } else if let execURL = app.executableURL {
            bundleId = "exec." + execURL.lastPathComponent.lowercased()
        } else if let bundleURL = app.bundleURL {
            bundleId = "bundle." + bundleURL.deletingPathExtension().lastPathComponent.lowercased()
        } else {
            bundleId = "app." + (app.localizedName?.lowercased() ?? "unknown")
        }

        return ForegroundAppInfo(
            bundleIdentifier: bundleId,
            localizedName: app.localizedName ?? bundleId,
            processIdentifier: app.processIdentifier,
            timestamp: Date()
        )
    }
}

public final class MockForegroundApplicationProvider: ForegroundApplicationProvider, @unchecked Sendable {
    private var currentApp: ForegroundAppInfo?
    private let lock = NSLock()
    public var onForegroundAppChanged: (@Sendable (ForegroundAppInfo) -> Void)?

    public init(initialApp: ForegroundAppInfo? = nil) {
        self.currentApp = initialApp
    }

    public func setForeground(bundleIdentifier: String, localizedName: String, processIdentifier: pid_t = 1234) {
        lock.lock()
        defer { lock.unlock() }
        let info = ForegroundAppInfo(
            bundleIdentifier: bundleIdentifier,
            localizedName: localizedName,
            processIdentifier: processIdentifier,
            timestamp: Date()
        )
        self.currentApp = info
        onForegroundAppChanged?(info)
    }

    public func clearForeground() {
        lock.lock()
        defer { lock.unlock() }
        self.currentApp = nil
    }

    public func getForegroundApplication() -> ForegroundAppInfo? {
        lock.lock()
        defer { lock.unlock() }
        return currentApp
    }
}
