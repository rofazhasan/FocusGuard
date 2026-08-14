# Testing: Device Platform Verification

FocusGuard maintains dedicated proof harnesses for macOS and Android platform capabilities.

---

## 1. Proof A: macOS Native Shield Verification

Located at `apps/macos/FocusGuard/ProofA/ProofAMacOSEnforcement.swift`.

### Execution:
```bash
cd apps/macos/FocusGuard
swiftc -parse-as-library ProofA/ProofAMacOSEnforcement.swift -o ProofA_bin
./ProofA_bin
```

### Verified Behaviors:
- Monotonic clock drift validation (< 0.0001s).
- Subdomain matching (`m.youtube.com` $\rightarrow$ `youtube.com`).
- 30-second usage threshold evaluation $\rightarrow$ `ManagedSettingsStore` shield engagement.

---

## 2. Proof B: Android Native Enforcement Verification

Located at `apps/android/proof/proof_b_android_enforcement.go`.

### Execution:
```bash
go run apps/android/proof/proof_b_android_enforcement.go
```

### Verified Behaviors:
- Midnight session split (Splits `23:45 -> 00:15` into two distinct calendar dates).
- RFC 1035 UDP DNS packet parser and `NXDOMAIN` (RCODE 3) synthesizer.
- Transparent pass-through for educational whitelist targets (`canvas.university.edu`).
