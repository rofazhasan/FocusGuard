import Foundation

public struct UsageSession: Identifiable, Codable, Equatable {
    public let id: UUID
    public let targetId: UUID?
    public let bundleIdentifier: String
    public let startedAt: Date
    public var endedAt: Date?
    public var durationSeconds: Int
    public let date: String // YYYY-MM-DD local format
    public var isClosed: Bool

    public init(
        id: UUID = UUID(),
        targetId: UUID? = nil,
        bundleIdentifier: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        durationSeconds: Int = 0,
        date: String = Self.currentDateString(),
        isClosed: Bool = false
    ) {
        self.id = id
        self.targetId = targetId
        self.bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.date = date
        self.isClosed = isClosed
    }

    public static func currentDateString(from date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}

public struct DailyUsageRecord: Codable, Equatable {
    public let date: String
    public let bundleIdentifier: String
    public var totalSeconds: Int
    public var lastUpdated: Date

    public init(date: String, bundleIdentifier: String, totalSeconds: Int, lastUpdated: Date = Date()) {
        self.date = date
        self.bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.totalSeconds = totalSeconds
        self.lastUpdated = lastUpdated
    }
}
