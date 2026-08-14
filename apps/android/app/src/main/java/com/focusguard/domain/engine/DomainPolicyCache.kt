package com.focusguard.domain.engine

/**
 * High-performance Trie-based Domain Policy Cache for the Android VPN / DNS Sinkhole.
 * Provides O(k) lookup time (where k is domain label depth) without linearly scanning rules.
 */
class DomainPolicyCache {

    private class TrieNode {
        val children = mutableMapOf<String, TrieNode>()
        var isBlocked: Boolean = false
        var isAllowed: Boolean = false
        var category: String? = null
        var policyId: String? = null
    }

    private val root = TrieNode()
    private val categoryRules = mutableMapOf<String, Boolean>() // Category -> isBlocked

    /**
     * Normalizes hostname by stripping protocol, path, port, and trailing dots.
     */
    fun normalizeDomain(raw: String): String {
        var str = raw.trim().lowercase()
        val protoIdx = str.indexOf("://")
        if (protoIdx != -1) {
            str = str.substring(protoIdx + 3)
        }
        val pathIdx = str.indexOfAny(charArrayOf('/', '?', '#', ':'))
        if (pathIdx != -1) {
            str = str.substring(0, pathIdx)
        }
        return str.trimEnd('.')
    }

    /**
     * Inserts a target domain rule into the Trie in reverse domain label order.
     * E.g. "youtube.com" is stored as root -> "com" -> "youtube"
     */
    fun insertRule(domain: String, isBlocked: Boolean, policyId: String? = null, category: String? = null) {
        val clean = normalizeDomain(domain)
        if (clean.isEmpty()) return

        val parts = clean.split('.').reversed()
        var current = root
        for (part in parts) {
            current = current.children.getOrPut(part) { TrieNode() }
        }

        if (isBlocked) {
            current.isBlocked = true
        } else {
            current.isAllowed = true
        }
        current.policyId = policyId
        current.category = category
    }

    fun setCategoryRule(category: String, isBlocked: Boolean) {
        categoryRules[category.uppercase()] = isBlocked
    }

    /**
     * Determines whether a candidate domain should be blocked according to deterministic precedence:
     * 1. Explicit ALLOW rule -> false (ALLOW)
     * 2. Explicit BLOCK rule -> true (BLOCK)
     * 3. Category BLOCK rule -> true (BLOCK)
     * 4. Default -> false (ALLOW)
     */
    fun shouldBlock(candidate: String, domainCategory: String? = null): Boolean {
        val clean = normalizeDomain(candidate)
        if (clean.isEmpty()) return false

        val parts = clean.split('.').reversed()
        var current = root
        var matchedBlocked = false
        var matchedAllowed = false

        for (part in parts) {
            val next = current.children[part] ?: break
            current = next
            if (current.isAllowed) matchedAllowed = true
            if (current.isBlocked) matchedBlocked = true
        }

        // Precedence 1: Explicit allow wins
        if (matchedAllowed) {
            return false
        }

        // Precedence 2: Explicit block
        if (matchedBlocked) {
            return true
        }

        // Precedence 3: Category rule
        if (domainCategory != null && categoryRules[domainCategory.uppercase()] == true) {
            return true
        }

        return false
    }

    fun clear() {
        root.children.clear()
        categoryRules.clear()
    }
}
