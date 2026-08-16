package com.focusguard.domain.engine

import android.os.SystemClock

enum class EvaluationResultState {
    ALLOWED,
    WARNING_80,
    WARNING_90,
    EXHAUSTED_BLOCK
}

data class PolicyEvaluationResult(
    val state: EvaluationResultState,
    val reason: String,
    val remainingSeconds: Int,
    val percentageUsed: Int
)

object AndroidPolicyEvaluator {

    /**
     * Validates monotonic uptime to detect wall-clock manipulation.
     * Compares wall-clock elapsed time against SystemClock.elapsedRealtime().
     */
    fun validateMonotonicClock(lastWallTimeMs: Long, lastMonotonicUptimeMs: Long): Boolean {
        val currentMonotonicMs = SystemClock.elapsedRealtime()
        val elapsedWallSec = (System.currentTimeMillis() - lastWallTimeMs) / 1000.0
        val elapsedMonotonicSec = (currentMonotonicMs - lastMonotonicUptimeMs) / 1000.0

        val drift = Math.abs(elapsedWallSec - elapsedMonotonicSec)
        // Max allowable clock drift: 120 seconds
        return drift <= 120.0
    }

    /**
     * Evaluates daily attention budget with progressive warning states.
     */
    fun evaluateBudget(limitSeconds: Int, currentUsageSeconds: Int): PolicyEvaluationResult {
        if (limitSeconds <= 0) {
            return PolicyEvaluationResult(EvaluationResultState.ALLOWED, "Unlimited budget", 0, 0)
        }

        val remaining = Math.max(0, limitSeconds - currentUsageSeconds)
        val percentage = Math.min(100, ((currentUsageSeconds.toDouble() / limitSeconds) * 100).toInt())

        return when {
            currentUsageSeconds >= limitSeconds -> PolicyEvaluationResult(
                state = EvaluationResultState.EXHAUSTED_BLOCK,
                reason = "Daily attention budget reached.",
                remainingSeconds = 0,
                percentageUsed = percentage
            )
            percentage >= 90 -> PolicyEvaluationResult(
                state = EvaluationResultState.WARNING_90,
                reason = "3 minutes remaining (90% budget consumed)",
                remainingSeconds = remaining,
                percentageUsed = percentage
            )
            percentage >= 80 -> PolicyEvaluationResult(
                state = EvaluationResultState.WARNING_80,
                reason = "6 minutes remaining (80% budget consumed)",
                remainingSeconds = remaining,
                percentageUsed = percentage
            )
            else -> PolicyEvaluationResult(
                state = EvaluationResultState.ALLOWED,
                reason = "Under attention budget",
                remainingSeconds = remaining,
                percentageUsed = percentage
            )
        }
    }

    fun isLimitExceeded(limitSeconds: Int, currentUsageSeconds: Int): Boolean {
        if (limitSeconds <= 0) return false
        return currentUsageSeconds >= limitSeconds
    }

    fun isTargetMatched(targetType: String, targetValue: String, candidate: String): Boolean {
        val cleanCandidate = candidate.trim().lowercase()
        val cleanTarget = targetValue.trim().lowercase()

        if (cleanCandidate.isEmpty() || cleanTarget.isEmpty()) return false

        return when (targetType.uppercase()) {
            "APP" -> cleanCandidate == cleanTarget
            "WEBSITE", "DOMAIN" -> {
                val c = if (cleanCandidate.startsWith("www.")) cleanCandidate.substring(4) else cleanCandidate
                val t = if (cleanTarget.startsWith("www.")) cleanTarget.substring(4) else cleanTarget
                c == t || c.endsWith(".$t")
            }
            "CATEGORY" -> cleanCandidate == cleanTarget
            else -> false
        }
    }
}
