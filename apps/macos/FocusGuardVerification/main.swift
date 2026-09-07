import Foundation
import FocusGuardCore

func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        print("❌ ASSERTION FAILED: \(message)")
        exit(1)
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String) {
    if a != b {
        print("❌ ASSERTION FAILED: \(message) — Expected [\(b)], got [\(a)]")
        exit(1)
    }
}

print("================================================================================")
print("FOCUSGUARD PHASE 4: FIRST MINIMAL MACOS VERTICAL SLICE VERIFICATION")
print("================================================================================")

let tempDir = FileManager.default.temporaryDirectory
let tempDbPath = tempDir.appendingPathComponent("focusguard_slice_\(UUID().uuidString).sqlite").path
defer {
    try? FileManager.default.removeItem(atPath: tempDbPath)
    try? FileManager.default.removeItem(atPath: "\(tempDbPath)-wal")
    try? FileManager.default.removeItem(atPath: "\(tempDbPath)-shm")
}

// --------------------------------------------------------------------------------
// Step 1: Device Initialization & Ed25519 Identity
// --------------------------------------------------------------------------------
print("\n[Step 1] Initializing unregistered macOS device identity...")
let (container, fgMock, idleMock, lockMock, credMock) = try DependencyContainer.createMock(databasePath: tempDbPath)

let initialIdentity = try container.deviceService.initialize()
assertEqual(initialIdentity.status, .unregistered, "Initial device status must be UNREGISTERED")
assertTrue(!initialIdentity.publicKeyPem.isEmpty, "Ed25519 public key must be generated")
assertTrue(!container.deviceService.isEnrolled(), "Device must not be enrolled initially")
print("  ✓ Unregistered macOS agent initialized with Ed25519 public key: \(initialIdentity.publicKeyPem.prefix(16))...")

// --------------------------------------------------------------------------------
// Step 2: Device Pairing & Keychain Storage
// --------------------------------------------------------------------------------
print("\n[Step 2] Simulating device pairing with FocusGuard Backend...")
let testDeviceId = UUID()
let testToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.simulated_macos_device_token"

try container.deviceService.pairDevice(
    deviceId: testDeviceId,
    deviceToken: testToken,
    deviceName: "MacBook Pro M-Series"
)

let storedToken = try credMock.loadString(key: "device_token")
assertEqual(storedToken, testToken, "Device token must be securely stored in Keychain")
let storedDeviceId = try credMock.loadString(key: "device_id")
assertEqual(storedDeviceId, testDeviceId.uuidString, "Device ID must be securely stored in Keychain")

let activeIdentity = try container.deviceRepo.getDeviceIdentity()
assertEqual(activeIdentity?.status, .active, "Device identity status must be ACTIVE in SQLite")
assertEqual(activeIdentity?.deviceId, testDeviceId, "Device ID must be persisted in SQLite")
assertTrue(container.deviceService.isEnrolled(), "Device must report enrolled = true")
print("  ✓ Paired successfully: DeviceID=\(testDeviceId) | Status=ACTIVE | Keychain Secure Token Verified")

// --------------------------------------------------------------------------------
// Step 3: Frontmost Application Detection
// --------------------------------------------------------------------------------
print("\n[Step 3] Foreground Provider detects frontmost application...")
let targetBundle = "com.hnc.discord"
container.usageService.addTrackedTarget(targetBundle)
assertTrue(container.usageService.getTrackedTargets().contains(targetBundle), "Tracked target must be configured")

fgMock.setForeground(bundleIdentifier: targetBundle, localizedName: "Discord", processIdentifier: 4400)
let detectedApp = fgMock.getForegroundApplication()
assertEqual(detectedApp?.bundleIdentifier, targetBundle, "Foreground app must match target bundle")
print("  ✓ Frontmost application detected: \(detectedApp!.localizedName) (\(detectedApp!.bundleIdentifier)) [PID: \(detectedApp!.processIdentifier)]")

// --------------------------------------------------------------------------------
// Step 4: Tracking 60 Active Seconds
// --------------------------------------------------------------------------------
print("\n[Step 4] Tracking 60 active seconds with 1-second monotonic checkpoints...")
for sec in 1...60 {
    let state = try container.usageService.tick(deltaSeconds: 1)
    assertEqual(state, .active, "Usage state must be ACTIVE on tick \(sec)")
}
print("  ✓ 60 monotonic checkpoints recorded.")

// --------------------------------------------------------------------------------
// Step 5: Persistent SQLite Storage Verification
// --------------------------------------------------------------------------------
print("\n[Step 5] Verifying persistent SQLite daily usage checkpoint...")
let today = UsageSession.currentDateString()
let trackedSeconds = try container.usageRepo.getDailyUsage(date: today, bundleIdentifier: targetBundle)
assertEqual(trackedSeconds, 60, "Must have accumulated exactly 60 seconds in SQLite daily_usage table")

let session = container.usageService.currentActiveSession()
assertTrue(session != nil, "Active session must exist")
assertEqual(session?.durationSeconds, 60, "Session duration must equal 60 seconds")
print("  ✓ SQLite daily_usage verified: Exactly \(trackedSeconds)s committed for \(targetBundle)")

// --------------------------------------------------------------------------------
// Step 6: Idle State & Screen Lock Pausing (No False Usage)
// --------------------------------------------------------------------------------
print("\n[Step 6] Testing Idle & Screen Lock State awareness...")
idleMock.setIdleSeconds(75.0) // User idle > 60s
for _ in 1...5 {
    let state = try container.usageService.tick(deltaSeconds: 1)
    assertEqual(state, .idle, "State must transition to IDLE when user is inactive")
}
let usageAfterIdle = try container.usageRepo.getDailyUsage(date: today, bundleIdentifier: targetBundle)
assertEqual(usageAfterIdle, 60, "No usage should accumulate while user is IDLE")
print("  ✓ User Idle: 75s elapsed with 0s added to daily usage.")

idleMock.setIdleSeconds(0.0) // User returns
lockMock.setLocked(true) // Screen locked
for _ in 1...5 {
    let state = try container.usageService.tick(deltaSeconds: 1)
    assertEqual(state, .paused, "State must transition to PAUSED when screen is locked")
}
let usageAfterLock = try container.usageRepo.getDailyUsage(date: today, bundleIdentifier: targetBundle)
assertEqual(usageAfterLock, 60, "No usage should accumulate while screen is LOCKED")
print("  ✓ Screen Locked: 5 ticks elapsed with 0s added to daily usage.")
lockMock.setLocked(false)

// --------------------------------------------------------------------------------
// Step 7: Application Switching & Clean Session Closure
// --------------------------------------------------------------------------------
print("\n[Step 7] Testing application switching & session closure...")
fgMock.setForeground(bundleIdentifier: "com.apple.finder", localizedName: "Finder")
let switchState = try container.usageService.tick(deltaSeconds: 1)
assertEqual(switchState, .noTarget, "State must transition to NO_TARGET when switching away")
assertTrue(container.usageService.currentActiveSession() == nil, "Active session must be cleared")

let openSessions = try container.usageRepo.getOpenSessions()
assertTrue(openSessions.isEmpty, "All finished sessions must be closed (is_closed = 1)")

let pendingEvents = try container.eventRepo.getPendingEvents(limit: 10)
assertTrue(pendingEvents.contains { $0.eventType == .usageSessionStarted }, "Must log USAGE_SESSION_STARTED")
assertTrue(pendingEvents.contains { $0.eventType == .usageSessionEnded }, "Must log USAGE_SESSION_ENDED")
print("  ✓ Session closed cleanly: USAGE_SESSION_STARTED and USAGE_SESSION_ENDED logged.")

// --------------------------------------------------------------------------------
// Step 8: Restart Recovery (Dropping In-Memory State & Restoring from Disk)
// --------------------------------------------------------------------------------
print("\n[Step 8] Simulating abrupt application termination & restart recovery...")
// Create an unclosed session to simulate a sudden crash
let unclosedSession = UsageSession(
    id: UUID(),
    targetId: nil,
    bundleIdentifier: targetBundle,
    startedAt: Date().addingTimeInterval(-45),
    endedAt: nil,
    durationSeconds: 45,
    date: today,
    isClosed: false
)
try container.usageRepo.insertUsageSession(unclosedSession)
let beforeRecoveryCount = try container.usageRepo.getOpenSessions().count
assertTrue(beforeRecoveryCount >= 1, "Simulated crash must leave unclosed session")

// REOPEN FRESH CONTAINER FROM DISK (Memory state completely dropped!)
let (recoveredContainer, _, _, _, credMock2) = try DependencyContainer.createMock(databasePath: tempDbPath)
try credMock2.saveString(key: "device_token", value: testToken)
try credMock2.saveString(key: "device_id", value: testDeviceId.uuidString)

let recoveredCount = try recoveredContainer.crashRecoveryService.recoverUnfinishedSessions()
assertTrue(recoveredCount >= 1, "Crash recovery must seal unclosed sessions")
let remainingOpen = try recoveredContainer.usageRepo.getOpenSessions().count
assertEqual(remainingOpen, 0, "Zero unclosed sessions should remain after crash recovery")

let restoredIdentity = try recoveredContainer.deviceService.initialize()
assertEqual(restoredIdentity.status, .active, "Device must remain ACTIVE after restart without re-pairing")
assertEqual(restoredIdentity.deviceId, testDeviceId, "Device ID must match original paired ID")
assertTrue(recoveredContainer.deviceService.isEnrolled(), "Device must remain enrolled without prompt")

let restoredUsage = try recoveredContainer.usageRepo.getDailyUsage(date: today, bundleIdentifier: targetBundle)
assertEqual(restoredUsage, 60, "SQLite daily usage must remain 100% intact across crash and restart")
print("  ✓ Crash Recovery Verified: Sessions sealed, zero re-pairing required, 60s usage preserved.")

// --------------------------------------------------------------------------------
// Step 9: Offline Event Queue & Idempotent Sync
// --------------------------------------------------------------------------------
print("\n[Step 9] Verifying offline event queue and batch sync acknowledgement...")
let initialEventCount = try recoveredContainer.eventRepo.getPendingEventCount()
assertTrue(initialEventCount >= 2, "Pending event count must reflect logged events")

let allEvents = try recoveredContainer.eventRepo.getPendingEvents(limit: 50)
let eventIds = allEvents.map { $0.id }
try recoveredContainer.eventRepo.markEventsSynced(ids: eventIds)
let syncedEventCount = try recoveredContainer.eventRepo.getPendingEventCount()
assertEqual(syncedEventCount, 0, "Pending event count must be 0 after sync acknowledgement")
print("  ✓ Event queue synced successfully: \(eventIds.count) events marked SYNCED.")

// --------------------------------------------------------------------------------
// Step 10: Protected System Applications Denylist Safety
// --------------------------------------------------------------------------------
print("\n[Step 10] Validating protected system applications denylist...")
assertTrue(ProtectedAppDenylist.isProtected(bundleIdentifier: "com.apple.finder"), "Finder must be protected")
assertTrue(ProtectedAppDenylist.isProtected(bundleIdentifier: "com.apple.loginwindow"), "loginwindow must be protected")
assertTrue(ProtectedAppDenylist.isProtected(bundleIdentifier: "com.apple.systemsettings"), "System Settings must be protected")

let safeValidation = ProtectedAppDenylist.validateTarget(bundleIdentifier: "com.hnc.discord")
assertTrue(safeValidation.isSuccess, "User app must be permitted")

let dangerousValidation = ProtectedAppDenylist.validateTarget(bundleIdentifier: "com.apple.finder")
assertTrue(!dangerousValidation.isSuccess, "Finder must be blocked by safety filter")
print("  ✓ Protected system applications safely guarded against restriction.")

print("\n================================================================================")
print("STATUS: FIRST MINIMAL MACOS VERTICAL SLICE 100% VERIFIED & PASSING!")
print("================================================================================")

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
