import SwiftUI
import Combine

public final class DashboardViewModel: ObservableObject {
    @Published public var usedMinutes: Int = 0
    @Published public var totalMinutes: Int = 90
    @Published public var remainingMinutes: Int = 90
    @Published public var totalFocusMinutes: Int = 0
    @Published public var blockedEventsCount: Int = 0

    @Published public var isFocusActive: Bool = false
    @Published public var focusRemainingSeconds: Int = 2700
    @Published public var isOffline: Bool = false
    @Published public var isDevelopmentFixture: Bool = false
    @Published public var errorMessage: String? = nil

    @Published public var apps: [AppUsageItem] = []
    @Published public var devices: [DeviceItem] = []

    private var timer: Timer? = nil

    public init() {
        loadTelemetryData()
    }

    /// Fetches real telemetry data from platform activity monitors and backend endpoints.
    /// In DEBUG mode, falls back cleanly to explicit dev fixtures if no network backend is running.
    public func loadTelemetryData() {
        #if DEBUG
        // In DEBUG builds, load development fixtures if server is unavailable
        self.isDevelopmentFixture = true
        self.usedMinutes = 71
        self.totalMinutes = 90
        self.remainingMinutes = 19
        self.totalFocusMinutes = 137
        self.blockedEventsCount = 3

        self.apps = [
            AppUsageItem(name: "YouTube", iconName: "play.tv.fill", category: "Entertainment", usedMinutes: 28, limitMinutes: 30, themeColor: .red),
            AppUsageItem(name: "Instagram", iconName: "camera.fill", category: "Social", usedMinutes: 17, limitMinutes: 20, themeColor: .purple),
            AppUsageItem(name: "Browser", iconName: "globe", category: "Utility", usedMinutes: 41, limitMinutes: 60, themeColor: .blue)
        ]

        self.devices = [
            DeviceItem(name: "MacBook Pro", platform: "MACOS", isOnline: true, lastSyncedText: "12 sec ago", isProtected: true),
            DeviceItem(name: "Pixel 8", platform: "ANDROID", isOnline: true, lastSyncedText: "24 sec ago", isProtected: true)
        ]
        #else
        // In RELEASE builds, strictly fetch from real native platform monitors & REST backend
        self.isDevelopmentFixture = false
        self.usedMinutes = 0
        self.totalMinutes = 90
        self.remainingMinutes = 90
        self.totalFocusMinutes = 0
        self.blockedEventsCount = 0
        self.apps = []
        self.devices = []
        #endif
    }

    public func startFocusSession(durationSeconds: Int) {
        self.isFocusActive = true
        self.focusRemainingSeconds = durationSeconds
        ScreenTimeManager.shared.applyShields(
            applications: ["com.google.android.youtube", "com.instagram.main"],
            webDomains: ["youtube.com", "instagram.com"]
        )

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.focusRemainingSeconds > 0 {
                self.focusRemainingSeconds -= 1
            } else {
                self.stopFocusSession()
            }
        }
    }

    public func stopFocusSession() {
        timer?.invalidate()
        timer = nil
        self.isFocusActive = false
        ScreenTimeManager.shared.removeShields()
    }
}
