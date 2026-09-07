import Foundation
import AppKit

public protocol LockStateMonitor: Sendable {
    func isScreenLocked() -> Bool
    func isSystemSleeping() -> Bool
}

public final class MacLockStateMonitor: LockStateMonitor, @unchecked Sendable {
    private var isLocked: Bool = false
    private var isSleeping: Bool = false
    private let lock = NSLock()

    public init() {
        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(
            self,
            selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        distCenter.addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func screenLocked() {
        lock.lock()
        defer { lock.unlock() }
        isLocked = true
    }

    @objc private func screenUnlocked() {
        lock.lock()
        defer { lock.unlock() }
        isLocked = false
    }

    @objc private func systemWillSleep() {
        lock.lock()
        defer { lock.unlock() }
        isSleeping = true
    }

    @objc private func systemDidWake() {
        lock.lock()
        defer { lock.unlock() }
        isSleeping = false
    }

    public func setSleeping(_ sleeping: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isSleeping = sleeping
    }

    public func setLocked(_ locked: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isLocked = locked
    }

    public func isScreenLocked() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isLocked
    }

    public func isSystemSleeping() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSleeping
    }
}

public final class MockLockStateMonitor: LockStateMonitor, @unchecked Sendable {
    private var locked: Bool = false
    private var sleeping: Bool = false
    private let lock = NSLock()

    public init(initialLocked: Bool = false, initialSleeping: Bool = false) {
        self.locked = initialLocked
        self.sleeping = initialSleeping
    }

    public func setLocked(_ locked: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.locked = locked
    }

    public func setSleeping(_ sleeping: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.sleeping = sleeping
    }

    public func isScreenLocked() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return locked
    }

    public func isSystemSleeping() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sleeping
    }
}
