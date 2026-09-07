import Foundation
import os

public struct AppLogger {
    private static let subsystem = "com.focusguard.macos"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let usage = Logger(subsystem: subsystem, category: "usage")
    public static let policy = Logger(subsystem: subsystem, category: "policy")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let security = Logger(subsystem: subsystem, category: "security")
    public static let database = Logger(subsystem: subsystem, category: "database")
    public static let enforcement = Logger(subsystem: subsystem, category: "enforcement")
}
