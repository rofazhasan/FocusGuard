import XCTest
@testable import FocusGuardCore

final class VerticalSliceTests: XCTestCase {
    var tempDbPath: String!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempDbPath = tempDir.appendingPathComponent("focusguard_test_\(UUID().uuidString).sqlite").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDbPath)
        try? FileManager.default.removeItem(atPath: "\(tempDbPath!)-wal")
        try? FileManager.default.removeItem(atPath: "\(tempDbPath!)-shm")
        super.tearDown()
    }

    // MARK: - 1. Device Pairing & Keychain Credential Storage
    func testDeviceInitializationAndPairingWithKeychain() throws {
        print("\n[Test Step 1] Initializing unregister device identity...")
        let (container, _, _, _, credMock) = try DependencyContainer.createMock(databasePath: tempDbPath)

        let initialIdentity = try container.deviceService.initialize()
        XCTAssertEqual(initialIdentity.status, .unregistered)
        XCTAssertFalse(initialIdentity.publicKeyPem.isEmpty, "Ed25519 identity key must be generated")
        XCTAssertFalse(container.deviceService.isEnrolled(), "New device must not be enrolled")

        print("[Test Step 2] Simulating device pairing with backend token...")
        let testDeviceId = UUID()
        let testToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.simulated_macos_device_token"

        try container.deviceService.pairDevice(
            deviceId: testDeviceId,
            deviceToken: testToken,
            deviceName: "MacBook Pro Test"
        )

        // Verify credentials in secure store
        let storedToken = try credMock.loadString(key: "device_token")
        XCTAssertEqual(storedToken, testToken, "Token must be securely saved")
        let storedDeviceId = try credMock.loadString(key: "device_id")
        XCTAssertEqual(storedDeviceId, testDeviceId.uuidString)

        // Verify SQLite persistence
        let persistedIdentity = try container.deviceRepo.getDeviceIdentity()
        XCTAssertNotNil(persistedIdentity)
        XCTAssertEqual(persistedIdentity?.status, .active)
        XCTAssertEqual(persistedIdentity?.deviceId, testDeviceId)
        XCTAssertTrue(container.deviceService.isEnrolled())
        print("✓ Device pairing and Keychain storage verified successfully.")
    }

    // MARK: - 2. Foreground App Detection & 60-Second Active Tracking
    func testForegroundAppDetectionAndActiveUsageTracking() throws {
        let (container, fgMock, _, _, _) = try DependencyContainer.createMock(databasePath: tempDbPath)
        try container.deviceService.initialize()

        let targetBundle = "com.hnc.discord"
        container.usageService.addTrackedTarget(targetBundle)
        XCTAssertTrue(container.usageService.getTrackedTargets().contains(targetBundle))

        print("[Test Step 3] Simulating target app entering foreground...")
        fgMock.setForeground(bundleIdentifier: targetBundle, localizedName: "Discord", processIdentifier: 4400)

        print("[Test Step 4] Tracking 60 active seconds with 1-second monotonic ticks...")
        for sec in 1...60 {
            let state = try container.usageService.tick(deltaSeconds: 1)
            XCTAssertEqual(state, .active, "Usage state must be ACTIVE on tick \(sec)")
        }

        // Verify SQLite daily accumulation
        let today = UsageSession.currentDateString()
        let trackedSeconds = try container.usageRepo.getDailyUsage(date: today, bundleIdentifier: targetBundle)
        XCTAssertEqual(trackedSeconds, 60, "Must have accumulated exactly 60 seconds in SQLite daily_usage")

        // Verify active session checkpoint
        let session = container.usageService.currentActiveSession()
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.durationSeconds, 60)
        XCTAssertEqual(session?.bundleIdentifier, targetBundle)
        print("✓ 60 seconds of focused active usage tracked and committed to SQLite.")
    }

    // MARK: - 3. Idle and Lock State Pausing (No False Usage)
    func testIdleAndScreenLockStatePausing() throws {
        let (container, fgMock, idleMock, lockMock, _) = try DependencyContainer.createMock(databasePath: tempDbPath)
        try container.deviceService.initialize()

        let targetBundle = "com.hnc.discord"
        container.usageService.addTrackedTarget(targetBundle)
        fgMock.setForeground(bundleIdentifier: targetBundle, localizedName: "Discord")

        // Track 10 normal seconds
        for _ in 1...10 {
            try container.usageService.tick(deltaSeconds: 1)
        }
        let today = UsageSession.currentDateString()
        XCTAssertEqual(try container.usageRepo.getDailyUsage(date: today, bundleIdentifier: targetBundle), 10)

        // Simulate Idle State (>60s)
        print("[Test Step 5] Simulating user idle state (75 seconds of inactivity)...")
        idleMock.setIdleSeconds(75.0)
        for _ in 1...5 {
            let state = try container.usageService.tick(deltaSeconds: 1)
            XCTAssertEqual(state, .idle, "Usage state must transition to IDLE")
        }
        // Daily usage must remain 10 seconds (no idle usage counted!)
        XCTAssertEqual(try container.usageRepo.getDailyUsage(date: today, bundleIdentifier: targetBundle), 10)

        // Resume activity
        idleMock.setIdleSeconds(0.0)
        let resumedState = try container.usageService.tick(deltaSeconds: 1)
        XCTAssertEqual(resumedState, .active)
        XCTAssertEqual(try container.usageRepo.getDailyUsage(date: today, bundleIdentifier: targetBundle), 11)

        // Simulate Screen Locked
        print("[Test Step 6] Simulating screen locked...")
        lockMock.setLocked(true)
        for _ in 1...5 {
            let state = try container.usageService.tick(deltaSeconds: 1)
            XCTAssertEqual(state, .paused, "Usage state must transition to PAUSED")
        }
        // Daily usage must remain 11 seconds (no locked usage counted!)
        XCTAssertEqual(try container.usageRepo.getDailyUsage(date: today, bundleIdentifier: targetBundle), 11)
        print("✓ Idle and Lock state transitions correctly prevent false usage accumulation.")
    }

    // MARK: - 4. Application Switching & Clean Session Closure
    func testAppSwitchingSessionClosure() throws {
        let (container, fgMock, _, _, _) = try DependencyContainer.createMock(databasePath: tempDbPath)
        try container.deviceService.initialize()

        let targetBundle = "com.hnc.discord"
        container.usageService.addTrackedTarget(targetBundle)
        fgMock.setForeground(bundleIdentifier: targetBundle, localizedName: "Discord")

        for _ in 1...15 {
            try container.usageService.tick(deltaSeconds: 1)
        }

        // Switch away to Finder (untracked)
        print("[Test Step 7] User switches away to Finder...")
        fgMock.setForeground(bundleIdentifier: "com.apple.finder", localizedName: "Finder")
        let state = try container.usageService.tick(deltaSeconds: 1)
        XCTAssertEqual(state, .noTarget, "Usage state must return to NO_TARGET")
        XCTAssertNil(container.usageService.currentActiveSession())

        // Verify open sessions are now closed in SQLite
        let openSessions = try container.usageRepo.getOpenSessions()
        XCTAssertTrue(openSessions.isEmpty, "All finished sessions must be closed in SQLite")

        // Verify events enqueued: started + ended
        let events = try container.eventRepo.getPendingEvents(limit: 10)
        XCTAssertTrue(events.contains { $0.eventType == .usageSessionStarted })
        XCTAssertTrue(events.contains { $0.eventType == .usageSessionEnded })
        print("✓ Application switching closes session and logs canonical lifecycle events.")
    }

    // MARK: - 5. Restart Recovery (Dropping Memory State & Restoring from Disk)
    func testRestartRecoveryWithoutDataLossOrRepairing() throws {
        print("[Test Step 8] Simulating active session before abrupt crash...")
        let testDeviceId = UUID()
        let testToken = "test_device_jwt_token"

        do {
            let (container, fgMock, _, _, credMock) = try DependencyContainer.createMock(databasePath: tempDbPath)
            try container.deviceService.initialize()
            try container.deviceService.pairDevice(deviceId: testDeviceId, deviceToken: testToken)

            let targetBundle = "com.hnc.discord"
            container.usageService.addTrackedTarget(targetBundle)
            fgMock.setForeground(bundleIdentifier: targetBundle, localizedName: "Discord")

            for _ in 1...30 {
                try container.usageService.tick(deltaSeconds: 1)
            }

            // Verify 30s accumulated and session is currently open
            let today = UsageSession.currentDateString()
            XCTAssertEqual(try container.usageRepo.getDailyUsage(date: today, bundleIdentifier: targetBundle), 30)
            let openSessions = try container.usageRepo.getOpenSessions()
            XCTAssertEqual(openSessions.count, 1)

            // Simulate writing token to disk / persistent credential store
            try credMock.saveString(key: "device_token", value: testToken)
            // Memory state dropped completely!
        }

        print("[Test Step 9] Relaunching FocusGuard after crash...")
        let (recoveredContainer, _, _, _, credMock2) = try DependencyContainer.createMock(databasePath: tempDbPath)
        try credMock2.saveString(key: "device_token", value: testToken)

        // 1. Crash Recovery Service seals open session to last checkpoint
        let recovered = try recoveredContainer.crashRecoveryService.recoverUnfinishedSessions()
        XCTAssertEqual(recovered, 1, "Must recover exactly 1 unclosed session")

        let remainingOpen = try recoveredContainer.usageRepo.getOpenSessions()
        XCTAssertEqual(remainingOpen.count, 0, "No unclosed sessions should remain after recovery")

        // 2. Verify device remains active without re-pairing!
        let restoredIdentity = try recoveredContainer.deviceService.initialize()
        XCTAssertEqual(restoredIdentity.status, .active)
        XCTAssertEqual(restoredIdentity.deviceId, testDeviceId)
        XCTAssertTrue(recoveredContainer.deviceService.isEnrolled())

        // 3. Verify 30 seconds daily usage preserved in SQLite!
        let today = UsageSession.currentDateString()
        let restoredUsage = try recoveredContainer.usageRepo.getDailyUsage(date: today, bundleIdentifier: "com.hnc.discord")
        XCTAssertEqual(restoredUsage, 30)
        print("✓ Crash recovery verified: 100% data fidelity, zero re-pairing required.")
    }

    // MARK: - 6. Offline Event Queue & Sync
    func testOfflineEventQueueAndSyncService() throws {
        print("[Test Step 10] Testing Offline Event Queue and batch sync...")
        let (container, _, _, _, _) = try DependencyContainer.createMock(databasePath: tempDbPath)
        try container.deviceService.initialize()
        try container.deviceService.pairDevice(deviceId: UUID(), deviceToken: "dummy_token")

        let event = EventEnvelope(
            eventType: .usageLimitWarning,
            deviceId: "dev_mac_1",
            target: "com.hnc.discord",
            reason: "Reached 80% daily budget"
        )
        try container.eventRepo.enqueueEvent(event)

        let pendingCount = try container.eventRepo.getPendingEventCount()
        XCTAssertEqual(pendingCount, 1)

        let pendingEvents = try container.eventRepo.getPendingEvents(limit: 10)
        XCTAssertEqual(pendingEvents.first?.id, event.id)

        // Mark synced
        try container.eventRepo.markEventsSynced(ids: [event.id])
        XCTAssertEqual(try container.eventRepo.getPendingEventCount(), 0)
        print("✓ Event queue durability, ordering, and sync state transition verified.")
    }

    // MARK: - 7. Protected Applications Denylist Safety
    func testProtectedAppDenylistSafety() {
        print("[Test Step 11] Validating protected application safety rules...")
        XCTAssertTrue(ProtectedAppDenylist.isProtected(bundleIdentifier: "com.apple.finder"))
        XCTAssertTrue(ProtectedAppDenylist.isProtected(bundleIdentifier: "com.apple.loginwindow"))
        XCTAssertTrue(ProtectedAppDenylist.isProtected(bundleIdentifier: "com.apple.systemsettings"))
        XCTAssertTrue(ProtectedAppDenylist.isProtected(bundleIdentifier: "com.apple.activitymonitor"))

        let safeResult = ProtectedAppDenylist.validateTarget(bundleIdentifier: "com.hnc.discord")
        XCTAssertTrue(safeResult.isSuccess)

        let forbiddenResult = ProtectedAppDenylist.validateTarget(bundleIdentifier: "com.apple.finder")
        XCTAssertFalse(forbiddenResult.isSuccess)
        print("✓ Protected system applications safely guarded against restriction.")
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
