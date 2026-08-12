package com.focusguard.domain.engine

import android.os.SystemClock

object AndroidPolicyEvaluator {

    /**
     * Validates monotonic uptime to prevent user wall-clock tampering.
     */
    fun validateMonotonicClock(lastWallTimeMs: Long, lastMonotonicUptimeMs: Long): Boolean {
        let currentMonotonicMs = SystemClock.elapsedRealtime()
        val elapsedWallSec = (System.currentTimeMillis() - lastWallTimeMs) / 1000.0
        val elapsedMonotonicSec = (currentMonotonicMs - lastMonotonicUptimeMs) / 1000.0

        val drift = Math.abs(elapsedWallSec - elapsedMonotonicSec)
        return drift <= 120.0
    }

    fun isLimitExceeded(limitSeconds: Int, currentUsageSeconds: Int): Boolean {
        if (limitSeconds <= 0) return false
        return currentUsageSeconds >= limitSeconds
    }

    fun isTargetMatched(targetType: String, targetValue: String, candidate: String): Boolean {
        val cleanCandidate = candidate.trim().lowercase()
        val cleanTarget = targetValue.trim().lowercase()

        if (cleanCandidate.isEmpty() || cleanTarget.isEmpty()) return false

        return when (targetType) {
            "APP" -> cleanCandidate == cleanTarget
            "WEBSITE" -> {
                if (cleanCandidate == cleanTarget) true
                else cleanCandidate.endsWith(".$cleanTarget")
            }
            "CATEGORY" -> cleanCandidate == cleanTarget
            else -> false
        }
    }
}
