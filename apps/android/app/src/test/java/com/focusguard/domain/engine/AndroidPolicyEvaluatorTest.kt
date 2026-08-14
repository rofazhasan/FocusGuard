package com.focusguard.domain.engine

import org.junit.Assert.*
import org.junit.Test

class AndroidPolicyEvaluatorTest {

    @Test
    fun testTargetMatchingAppPackage() {
        val appMatched = AndroidPolicyEvaluator.isTargetMatched("APP", "com.google.android.youtube", "com.google.android.youtube")
        assertTrue("Package name should match exactly", appMatched)

        val appMismatch = AndroidPolicyEvaluator.isTargetMatched("APP", "com.google.android.youtube", "com.instagram.android")
        assertFalse("Different package names should not match", appMismatch)
    }

    @Test
    fun testTargetMatchingWebsiteSubdomain() {
        val exactMatch = AndroidPolicyEvaluator.isTargetMatched("WEBSITE", "instagram.com", "instagram.com")
        assertTrue("Exact domain should match", exactMatch)

        val subdomainMatch = AndroidPolicyEvaluator.isTargetMatched("WEBSITE", "instagram.com", "www.instagram.com")
        assertTrue("Subdomain should match parent domain target", subdomainMatch)

        val invalidMatch = AndroidPolicyEvaluator.isTargetMatched("WEBSITE", "instagram.com", "fakeinstagram.com")
        assertFalse("Non-subdomain prefix should not match", invalidMatch)
    }

    @Test
    fun testLimitExceededCalculation() {
        assertFalse("1200 seconds should not exceed 1800 second limit", AndroidPolicyEvaluator.isLimitExceeded(1800, 1200))
        assertTrue("1800 seconds should exceed 1800 second limit", AndroidPolicyEvaluator.isLimitExceeded(1800, 1800))
        assertTrue("2000 seconds should exceed 1800 second limit", AndroidPolicyEvaluator.isLimitExceeded(1800, 2000))
    }

    @Test
    fun testProgressiveWarningStates() {
        val limit = 1800 // 30m

        // Under 80% (10m = 600s) -> ALLOWED
        val res1 = AndroidPolicyEvaluator.evaluateBudget(limit, 600)
        assertEquals(EvaluationResultState.ALLOWED, res1.state)

        // 80% (24m = 1440s) -> WARNING_80
        val res2 = AndroidPolicyEvaluator.evaluateBudget(limit, 1440)
        assertEquals(EvaluationResultState.WARNING_80, res2.state)
        assertEquals(360, res2.remainingSeconds)

        // 90% (27m = 1620s) -> WARNING_90
        val res3 = AndroidPolicyEvaluator.evaluateBudget(limit, 1620)
        assertEquals(EvaluationResultState.WARNING_90, res3.state)

        // 100% (30m = 1800s) -> EXHAUSTED_BLOCK
        val res4 = AndroidPolicyEvaluator.evaluateBudget(limit, 1800)
        assertEquals(EvaluationResultState.EXHAUSTED_BLOCK, res4.state)
    }

    @Test
    fun testDomainPolicyCacheTrieLookupAndPrecedence() {
        val cache = DomainPolicyCache()

        // Configure rules
        cache.insertRule("youtube.com", isBlocked = true)
        cache.insertRule("docs.google.com", isBlocked = false) // Explicit Allow
        cache.setCategoryRule("SOCIAL", isBlocked = true)

        // 1. YouTube exact & subdomain blocked
        assertTrue(cache.shouldBlock("youtube.com"))
        assertTrue(cache.shouldBlock("m.youtube.com"))
        assertTrue(cache.shouldBlock("www.youtube.com"))
        assertFalse("Unrelated domain should not match", cache.shouldBlock("notyoutube.com"))

        // 2. Explicit Allow precedence
        assertFalse("Explicit allow must override category or other rules", cache.shouldBlock("docs.google.com"))

        // 3. Category blocking
        assertTrue("Domain classified as SOCIAL should be blocked", cache.shouldBlock("instagram.com", domainCategory = "SOCIAL"))
        assertFalse("Domain classified as EDUCATION should be allowed", cache.shouldBlock("github.com", domainCategory = "EDUCATION"))
    }
}
