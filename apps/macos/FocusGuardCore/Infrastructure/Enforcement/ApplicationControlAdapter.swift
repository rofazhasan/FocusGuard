import AppKit
import Foundation

public protocol ApplicationControlProtocol: Sendable {
    @discardableResult
    func terminateApplication(bundleIdentifier: String) -> Bool
}

public final class ApplicationControlAdapter: ApplicationControlProtocol, Sendable {
    public init() {}

    @discardableResult
    public func terminateApplication(bundleIdentifier: String) -> Bool {
        // Critical Invariant: Never terminate protected system apps
        guard !ProtectedAppDenylist.isProtected(bundleIdentifier: bundleIdentifier) else {
            return false
        }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !runningApps.isEmpty else {
            return false
        }

        let allTerminated = true
        for app in runningApps {
            let success = app.terminate()
            if !success {
                _ = app.forceTerminate()
            }
        }
        return allTerminated
    }
}

public final class MockApplicationControlAdapter: ApplicationControlProtocol, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var terminatedBundleIds: [String] = []

    public init() {}

    @discardableResult
    public func terminateApplication(bundleIdentifier: String) -> Bool {
        guard !ProtectedAppDenylist.isProtected(bundleIdentifier: bundleIdentifier) else {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        terminatedBundleIds.append(bundleIdentifier)
        return true
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        terminatedBundleIds.removeAll()
    }
}
