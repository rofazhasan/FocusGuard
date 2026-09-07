import Foundation

public final class DependencyContainer: @unchecked Sendable {
    public let dbManager: DatabaseManager
    public let credStore: SecureCredentialStore
    public let foregroundProvider: ForegroundApplicationProvider
    public let idleDetector: IdleDetector
    public let lockMonitor: LockStateMonitor

    public let deviceRepo: DeviceRepository
    public let usageRepo: UsageRepository
    public let eventRepo: EventQueueRepository
    public let policyRepo: PolicyRepository

    public let notificationAdapter: NotificationAdapterProtocol
    public let applicationControl: ApplicationControlProtocol

    public let deviceService: DeviceService
    public let policyService: PolicyService
    public let enforcementCoordinator: EnforcementCoordinator
    public let usageService: UsageService
    public let crashRecoveryService: CrashRecoveryService
    public let syncService: SyncService
    public let realtimeService: RealtimeServiceProtocol

    public init(
        dbManager: DatabaseManager,
        credStore: SecureCredentialStore,
        foregroundProvider: ForegroundApplicationProvider,
        idleDetector: IdleDetector,
        lockMonitor: LockStateMonitor,
        notificationAdapter: NotificationAdapterProtocol? = nil,
        applicationControl: ApplicationControlProtocol? = nil,
        serverBaseURL: String = "http://localhost:8080",
        urlSession: URLSession = .shared
    ) {
        self.dbManager = dbManager
        self.credStore = credStore
        self.foregroundProvider = foregroundProvider
        self.idleDetector = idleDetector
        self.lockMonitor = lockMonitor

        self.deviceRepo = DeviceRepository(dbManager: dbManager)
        self.usageRepo = UsageRepository(dbManager: dbManager)
        self.eventRepo = EventQueueRepository(dbManager: dbManager)
        self.policyRepo = PolicyRepository(dbManager: dbManager)

        let notif = notificationAdapter ?? NotificationAdapter()
        let appCtrl = applicationControl ?? ApplicationControlAdapter()
        self.notificationAdapter = notif
        self.applicationControl = appCtrl

        let devService = DeviceService(deviceRepo: deviceRepo, credStore: credStore)
        self.deviceService = devService

        let polService = PolicyService(policyRepo: policyRepo, deviceService: devService)
        self.policyService = polService

        let enfCoordinator = EnforcementCoordinator(
            notificationAdapter: notif,
            applicationControl: appCtrl,
            eventRepo: eventRepo,
            deviceService: devService
        )
        self.enforcementCoordinator = enfCoordinator

        self.usageService = UsageService(
            foregroundProvider: foregroundProvider,
            idleDetector: idleDetector,
            lockMonitor: lockMonitor,
            usageRepo: usageRepo,
            eventRepo: eventRepo,
            policyService: polService,
            enforcementCoordinator: enfCoordinator
        )

        self.crashRecoveryService = CrashRecoveryService(usageRepo: usageRepo)
        self.syncService = SyncService(
            eventRepo: eventRepo,
            deviceService: devService,
            policyService: polService,
            serverBaseURL: serverBaseURL,
            urlSession: urlSession
        )

        self.realtimeService = RealtimeService(
            deviceService: devService,
            policyService: polService,
            serverBaseURL: serverBaseURL,
            urlSession: urlSession
        )

        // Connect deviceId provider to usage service
        self.usageService.deviceIdProvider = { [weak devService] in
            return devService?.currentIdentity?.deviceId?.uuidString ?? "dev_macos_agent"
        }
    }

    public static func createProduction(serverBaseURL: String = "http://localhost:8080") throws -> DependencyContainer {
        let dbPath = DatabaseManager.defaultDatabasePath()
        let db = try DatabaseManager(path: dbPath)
        let credStore = KeychainCredentialStore.shared
        let fgProvider = MacForegroundApplicationProvider()
        let idleDetector = MacIdleDetector()
        let lockMonitor = MacLockStateMonitor()
        let notif = NotificationAdapter()
        let appCtrl = ApplicationControlAdapter()

        return DependencyContainer(
            dbManager: db,
            credStore: credStore,
            foregroundProvider: fgProvider,
            idleDetector: idleDetector,
            lockMonitor: lockMonitor,
            notificationAdapter: notif,
            applicationControl: appCtrl,
            serverBaseURL: serverBaseURL
        )
    }

    public static func createMock(
        databasePath: String? = nil,
        serverBaseURL: String = "http://localhost:8080",
        urlSession: URLSession = .shared
    ) throws -> (
        container: DependencyContainer,
        fgMock: MockForegroundApplicationProvider,
        idleMock: MockIdleDetector,
        lockMock: MockLockStateMonitor,
        credMock: MockCredentialStore
    ) {
        let db = databasePath != nil ? try DatabaseManager(path: databasePath!) : try DatabaseManager.inMemory()
        let credMock = MockCredentialStore()
        let fgMock = MockForegroundApplicationProvider()
        let idleMock = MockIdleDetector()
        let lockMock = MockLockStateMonitor()
        let notifMock = MockNotificationAdapter()
        let appCtrlMock = MockApplicationControlAdapter()

        let container = DependencyContainer(
            dbManager: db,
            credStore: credMock,
            foregroundProvider: fgMock,
            idleDetector: idleMock,
            lockMonitor: lockMock,
            notificationAdapter: notifMock,
            applicationControl: appCtrlMock,
            serverBaseURL: serverBaseURL,
            urlSession: urlSession
        )

        return (container, fgMock, idleMock, lockMock, credMock)
    }
}
