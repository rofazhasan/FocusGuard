import Foundation

public struct ClockGuard {
    public static func currentMonotonicSeconds() -> UInt64 {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC_RAW, &ts)
        return UInt64(ts.tv_sec)
    }

    public static func validateMonotonicClock(lastWallTime: Date, lastMonotonicUptime: UInt64, maxAllowedDriftSeconds: Double = 120.0) -> (isValid: Bool, driftSeconds: Double) {
        let currentMonotonic = currentMonotonicSeconds()
        let elapsedWall = abs(Date().timeIntervalSince(lastWallTime))
        let elapsedMonotonic = currentMonotonic >= lastMonotonicUptime ? Double(currentMonotonic - lastMonotonicUptime) : 0.0
        let drift = abs(elapsedWall - elapsedMonotonic)
        return (drift <= maxAllowedDriftSeconds, drift)
    }
}
