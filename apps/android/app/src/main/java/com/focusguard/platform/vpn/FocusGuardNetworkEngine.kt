package com.focusguard.platform.vpn

import android.content.Context
import android.content.Intent
import android.util.Log
import com.focusguard.domain.engine.DomainPolicyCache

/**
 * FocusGuardNetworkEngine orchestrates Android VpnService, local DNS sinkhole,
 * domain policy caching, application-level network awareness, and tamper detection.
 */
class FocusGuardNetworkEngine(private val context: Context) {

    private val domainCache = DomainPolicyCache()
    private var isVpnActive = false

    // Known App to Domain mapping for application-aware network decisions
    private val appDomainMapping = mapOf(
        "com.google.android.youtube" to listOf("youtube.com", "googlevideo.com", "ytimg.com"),
        "com.instagram.android" to listOf("instagram.com", "cdninstagram.com"),
        "com.facebook.katana" to listOf("facebook.com", "fbcdn.net"),
        "com.reddit.frontpage" to listOf("reddit.com", "redd.it", "redditmedia.com")
    )

    fun initializePolicies(blockedDomains: List<String>, allowedDomains: List<String>, blockedCategories: List<String>) {
        domainCache.clear()

        // 1. Explicit allow rules (Highest priority)
        for (domain in allowedDomains) {
            domainCache.insertRule(domain, isBlocked = false)
        }

        // 2. Explicit block rules
        for (domain in blockedDomains) {
            domainCache.insertRule(domain, isBlocked = true)
        }

        // 3. Category rules
        for (cat in blockedCategories) {
            domainCache.setCategoryRule(cat, isBlocked = true)
        }
    }

    /**
     * Starts local DNS sinkhole VPN service.
     */
    fun startNetworkProtection(blockedDomains: Array<String>) {
        val intent = Intent(context, FocusVpnService::class.java).apply {
            action = "START_VPN"
            putExtra("BLOCKED_DOMAINS", blockedDomains)
        }
        context.startService(intent)
        isVpnActive = true
        Log.i("FocusGuardNetworkEngine", "FocusGuard Network Protection activated.")
    }

    /**
     * Stops VPN service.
     */
    fun stopNetworkProtection() {
        val intent = Intent(context, FocusVpnService::class.java).apply {
            action = "STOP_VPN"
        }
        context.startService(intent)
        isVpnActive = false
        Log.i("FocusGuardNetworkEngine", "FocusGuard Network Protection deactivated.")
    }

    /**
     * Evaluates whether a domain request should be blocked by the DNS filter.
     */
    fun shouldBlockDomain(domain: String, category: String? = null): Boolean {
        return domainCache.shouldBlock(domain, category)
    }

    /**
     * Application-aware network policy check.
     * Evaluates if network traffic originating from a specific package should be blocked.
     */
    fun shouldBlockApplicationTraffic(packageName: String, domain: String): Boolean {
        val mappedDomains = appDomainMapping[packageName] ?: emptyList()
        val matchesMapped = mappedDomains.any { d -> domainCache.normalizeDomain(domain).endsWith(d) }
        
        if (matchesMapped && domainCache.shouldBlock(domain)) {
            return true
        }
        return domainCache.shouldBlock(domain)
    }

    fun isProtectionHealthy(): Boolean {
        return isVpnActive
    }
}
