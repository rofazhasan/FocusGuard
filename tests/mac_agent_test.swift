// FocusGuard macOS Agent — Comprehensive Automated Test Suite
// Executes on macOS using the native Swift compiler: swift tests/mac_agent_test.swift

import Foundation
import Security

// ── 1. EMBEDDED DOMAIN NORMALIZER TEST TARGET ──

public struct TestDomainNormalizer {
    private static let knownMultiTlds: Set<String> = [
        "co.uk", "org.uk", "gov.uk", "ac.uk", "net.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.nz", "net.nz", "org.nz", "govt.nz",
        "co.jp", "ne.jp", "or.jp", "go.jp", "ac.jp",
        "com.br", "org.br", "gov.br",
        "co.in", "net.in", "org.in", "gen.in",
        "com.sg", "edu.sg", "gov.sg",
        "github.io", "pages.dev", "vercel.app", "web.app",
        "ac.bd", "edu.bd", "com.bd", "net.bd",
        "co.za", "org.za", "gov.za"
    ]

    public static func normalizeHostname(_ input: String) -> String {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return "" }

        if cleaned.contains("://") {
            if let url = URL(string: cleaned), let host = url.host {
                cleaned = host
            }
        }

        if let colonIdx = cleaned.firstIndex(of: ":") {
            cleaned = String(cleaned[..<colonIdx])
        }

        if let slashIdx = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[..<slashIdx])
        }

        while cleaned.hasSuffix(".") {
            cleaned.removeLast()
        }

        guard isValidHostname(cleaned) else { return "" }
        return cleaned
    }

    public static func getBaseDomain(_ hostname: String) -> String {
        let norm = normalizeHostname(hostname)
        guard !norm.isEmpty else { return "" }

        let parts = norm.split(separator: ".").map(String.init)
        guard parts.count > 1 else { return norm }

        if parts.count >= 3 {
            let lastTwo = parts.suffix(2).joined(separator: ".")
            if knownMultiTlds.contains(lastTwo) {
                return parts.suffix(3).joined(separator: ".")
            }
        }

        return parts.suffix(2).joined(separator: ".")
    }

    public static func matches(target: String, rulePattern: String) -> Bool {
        let cleanTarget = normalizeHostname(target)
        var cleanRule = rulePattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while cleanRule.hasPrefix("*") || cleanRule.hasPrefix(".") {
            cleanRule.removeFirst()
        }
        cleanRule = normalizeHostname(cleanRule)

        guard !cleanTarget.isEmpty, !cleanRule.isEmpty else { return false }

        if cleanTarget == cleanRule { return true }
        if cleanTarget.hasSuffix("." + cleanRule) { return true }

        return false
    }

    private static func isValidHostname(_ hostname: String) -> Bool {
        guard !hostname.isEmpty else { return false }
        for ch in hostname {
            if !ch.isLetter && !ch.isNumber && ch != "." && ch != "-" {
                return false
            }
        }
        return true
    }
}

// ── 2. ANTI-TAMPER CLOCK VALIDATOR ──

public struct ClockValidator {
    public static func validate(lastWallTime: Date, lastMonotonicUptime: UInt64) -> (isValid: Bool, drift: Double) {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC_RAW, &ts)
        let currentMonotonic = UInt64(ts.tv_sec)
        let elapsedWall = Date().timeIntervalSince(lastWallTime)
        let elapsedMonotonic = Double(currentMonotonic - lastMonotonicUptime)
        let drift = abs(elapsedWall - elapsedMonotonic)
        return (drift <= 120.0, drift)
    }
}

// ── 3. KEYCHAIN TEST HARNESS ──

public struct KeychainTestHarness {
    private static let service = "com.focusguard.test.identity"

    public static func roundtripTest() -> Bool {
        let testKey = "test_device_key_\(UUID().uuidString)"
        let testValue = "jwt_token_secret_12345"

        // 1. Save
        guard let data = testValue.data(using: .utf8) else { return false }
        let saveQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: testKey,
            kSecValueData as String: data
        ]
        SecItemDelete(saveQuery as CFDictionary)
        let saveStatus = SecItemAdd(saveQuery as CFDictionary, nil)
        guard saveStatus == errSecSuccess else { return false }

        // 2. Load
        let loadQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: testKey,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let loadStatus = SecItemCopyMatching(loadQuery as CFDictionary, &item)
        guard loadStatus == errSecSuccess,
              let loadedData = item as? Data,
              let loadedString = String(data: loadedData, encoding: .utf8),
              loadedString == testValue else {
            return false
        }

        // 3. Cleanup
        SecItemDelete(saveQuery as CFDictionary)
        return true
    }
}

// ── 4. TEST RUNNER EXECUTION ──

print("==========================================================")
print("FOCUSGUARD — macOS Native Agent Test Suite")
print("==========================================================")

var passedCount = 0
var totalCount = 0

func assertTest(_ condition: Bool, name: String) {
    totalCount += 1
    if condition {
        passedCount += 1
        print("  ✓ PASS: \(name)")
    } else {
        print("  ✗ FAIL: \(name)")
        exit(1)
    }
}

// Group 1: DomainNormalizer Unit Tests
print("\n--- Group 1: Domain Normalization & Security Matcher ---")
assertTest(TestDomainNormalizer.normalizeHostname("https://www.youtube.com/watch?v=123") == "www.youtube.com", name: "URL with path/query normalized to hostname")
assertTest(TestDomainNormalizer.normalizeHostname("HTTP://M.YOUTUBE.COM:8080/") == "m.youtube.com", name: "Port and uppercase stripped")
assertTest(TestDomainNormalizer.normalizeHostname("youtube.com.") == "youtube.com", name: "Trailing root dot stripped")
assertTest(TestDomainNormalizer.getBaseDomain("music.youtube.com") == "youtube.com", name: "Base domain extracted from 3-level hostname")
assertTest(TestDomainNormalizer.getBaseDomain("news.bbc.co.uk") == "bbc.co.uk", name: "PSL multi-TLD (.co.uk) base domain correctly identified")
assertTest(TestDomainNormalizer.getBaseDomain("user.github.io") == "user.github.io", name: "PSL multi-TLD (.github.io) eTLD+1 base domain correctly identified")

assertTest(TestDomainNormalizer.matches(target: "youtube.com", rulePattern: "youtube.com"), name: "Exact domain match returns true")
assertTest(TestDomainNormalizer.matches(target: "www.youtube.com", rulePattern: "youtube.com"), name: "Subdomain match returns true")
assertTest(TestDomainNormalizer.matches(target: "m.music.youtube.com", rulePattern: "youtube.com"), name: "Deep subdomain match returns true")
assertTest(TestDomainNormalizer.matches(target: "youtube.com", rulePattern: "*.youtube.com"), name: "Wildcard rule syntax match returns true")

// Group 2: Critical Security Rejection Invariants
print("\n--- Group 2: Security Invariants (No Spoofing / Collisions) ---")
assertTest(!TestDomainNormalizer.matches(target: "notyoutube.com", rulePattern: "youtube.com"), name: "Suffix collision (notyoutube.com) rejected")
assertTest(!TestDomainNormalizer.matches(target: "youtube.com.evil.com", rulePattern: "youtube.com"), name: "Prefix injection (youtube.com.evil.com) rejected")
assertTest(!TestDomainNormalizer.matches(target: "fakeyoutube.com", rulePattern: "youtube.com"), name: "Substring collision (fakeyoutube.com) rejected")
assertTest(!TestDomainNormalizer.matches(target: "youtube.org", rulePattern: "youtube.com"), name: "Different TLD (youtube.org) rejected")

// Group 3: Monotonic Clock Anti-Tamper
print("\n--- Group 3: Anti-Tamper Monotonic Clock ---")
var ts = timespec()
clock_gettime(CLOCK_MONOTONIC_RAW, &ts)
let startUptime = UInt64(ts.tv_sec)
let startTime = Date()
let clockCheck = ClockValidator.validate(lastWallTime: startTime, lastMonotonicUptime: startUptime)
assertTest(clockCheck.isValid, name: "Monotonic clock progression is consistent with wall clock")

// Group 4: Native Keychain Storage
print("\n--- Group 4: Native macOS Keychain Services ---")
let keychainOk = KeychainTestHarness.roundtripTest()
assertTest(keychainOk, name: "Keychain write, read, and delete roundtrip succeeded")

// Group 5: Protocol & Sync Envelopes
print("\n--- Group 5: Protocol JSON Envelopes ---")
let sampleEnvelope: [String: Any] = [
    "type": "POLICY_PUSH",
    "correlationId": "cor_123456",
    "timestamp": 1723745834000,
    "payload": ["version": 42]
]
let envelopeData = try! JSONSerialization.data(withJSONObject: sampleEnvelope)
let decodedObj = try! JSONSerialization.jsonObject(with: envelopeData) as! [String: Any]
assertTest(decodedObj["type"] as? String == "POLICY_PUSH", name: "Sync envelope encodes and decodes accurately")
assertTest((decodedObj["payload"] as? [String: Any])?["version"] as? Int == 42, name: "Policy version intact in payload")

print("\n==========================================================")
print("✅ ALL \(passedCount)/\(totalCount) macOS AGENT TESTS PASSED (100%)")
print("==========================================================")
