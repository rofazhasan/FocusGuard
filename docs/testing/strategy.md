# Testing Strategy & Quality Assurance

FocusGuard enforces a multi-tier testing strategy ensuring zero regressions, zero fake data, and 100% deterministic policy evaluations.

---

## The Testing Pyramid

```
        ┌────────────────────────────────┐
        │  End-to-End Multi-Device Slice │ (Owner -> Pair -> Policy -> Block)
        ├────────────────────────────────┤
        │ Native Platform Verification   │ (Proof A macOS / Proof B Android)
        ├────────────────────────────────┤
        │ Integration & API Contract     │ (HTTP Handlers / WebSocket Broadcasts)
        ├────────────────────────────────┤
        │ Unit Tests (Domain & Logic)    │ (Domain Normalizer / Time-Series Normalizer)
        └────────────────────────────────┘
```

---

## Continuous Verification Matrix

| Component | Target Test Coverage | Verification Command |
|---|---|---|
| Backend Domain Services | > 90% | `cd backend && go test -v ./...` |
| macOS Screen Time Bridge | 100% functional verification | `swiftc -parse-as-library ProofA/ProofAMacOSEnforcement.swift` |
| Android RFC 1035 Parser | 100% functional verification | `go run apps/android/proof/proof_b_android_enforcement.go` |
