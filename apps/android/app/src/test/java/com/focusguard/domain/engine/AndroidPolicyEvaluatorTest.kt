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
}
