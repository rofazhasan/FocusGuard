import Foundation

public enum UsageState: String, Codable, Equatable {
    case noTarget = "NO_TARGET"
    case active = "ACTIVE"
    case idle = "IDLE"
    case paused = "PAUSED"
    case warning = "WARNING"
    case limitReached = "LIMIT_REACHED"
    case restricted = "RESTRICTED"
}
