# Policy Engine & Precedence Architecture

The FocusGuard Policy Engine evaluates candidate application bundle IDs and network domain requests against active user rules.

---

## 1. Six-Tier Deterministic Precedence Matrix

When evaluating whether a candidate request (e.g. `m.youtube.com` or `com.apple.MobileSMS`) should be allowed or blocked, the engine enforces strict hierarchical evaluation:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. SYSTEM SAFETY ALLOWLIST                                  │ (Always ALLOW: localhost, 127.0.0.1, .local)
├─────────────────────────────────────────────────────────────┤
│ 2. EXPLICIT USER ALLOWLIST                                  │ (Always ALLOW: e.g. canvas.university.edu)
├─────────────────────────────────────────────────────────────┤
│ 3. EMERGENCY REMOTE FOCUS LOCKOUT                           │ (BLOCK all distraction categories during active session)
├─────────────────────────────────────────────────────────────┤
│ 4. EXPLICIT DOMAIN / APP POLICY LIMITS                      │ (BLOCK if cumulative usage >= policy limit)
├─────────────────────────────────────────────────────────────┤
│ 5. CATEGORY POLICY LIMITS                                   │ (BLOCK if category usage >= category limit)
├─────────────────────────────────────────────────────────────┤
│ 6. DEFAULT POLICY                                           │ (ALLOW normal state)
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Safe Subdomain Normalization Algorithm

To prevent false positives and bypasses, domain matching uses the following algorithm:

```go
func IsDomainMatch(candidateDomain, targetDomain string) bool {
    candidate := NormalizeDomain(candidateDomain)
    target := NormalizeDomain(targetDomain)

    cleanCandidate := strings.TrimPrefix(candidate, "www.")
    cleanTarget := strings.TrimPrefix(target, "www.")

    // 1. Exact Match (e.g. "youtube.com" == "youtube.com")
    if cleanCandidate == cleanTarget {
        return true
    }

    // 2. Hierarchical Subdomain (e.g. "m.youtube.com" ends with ".youtube.com")
    if strings.HasSuffix(cleanCandidate, "."+cleanTarget) {
        return true
    }

    // 3. Reject substring matches ("notyoutube.com" is NOT "youtube.com")
    return false
}
```
