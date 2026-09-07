# FocusGuard Phase 6 Master Verification & Test Plan

**Document ID**: `FG-TEST-006`  
**Version**: `1.0.0-PROD`  
**Date**: September 7, 2026  
**Status**: APPROVED TEST PLAN  
**Epic**: `FG-INTEGRATION-600`  

---

## 1. Executive Summary & Verification Philosophy

FocusGuard Phase 6 transforms independently audited components into a unified, distributed production product. Testing is not an afterthought or a superficial check:
1. **Real Data Invariant**: Tests must run against real database instances (SQLite WAL / PostgreSQL) and real network servers. Mocking is restricted to external third-party hardware boundaries.
2. **No Regression Rule**: All 9 existing test suites (Package tests, Extension tests, Vertical slice, Swift native tests, Proof A, Proof B, Go backend tests, Pairing E2E, 20-Attack Adversarial Security Breaker) must remain 100% green.
3. **Contract First**: Every endpoint and message envelope must pass strict schema validation before integration tests run.

---

## 2. Test Pyramid & Execution Battery

```
                    ┌─────────────────────────┐
                    │  52-Step Acceptance E2E │
                    ├─────────────────────────┤
                    │  Offline Chaos Battery  │
                    ├─────────────────────────┤
                    │   Cross-Device Journeys │
                    ├─────────────────────────┤
                    │    Contract Validation  │
                    ├─────────────────────────┤
                    │  Unit & Domain Packages │
                    └─────────────────────────┘
```

| Tier | Scope | Target Path | Target Count | Execution Frequency |
| :--- | :--- | :--- | :---: | :--- |
| **Tier 1: Unit & Domain** | Pure domain models, crypto, policy evaluation, interval union algorithm | `packages/test_all_packages.js`, `backend/...` | 50+ Tests | Pre-commit / CI PR Gate |
| **Tier 2: Contracts** | Schema validation, envelope compliance, error taxonomy, state machine transitions | `tests/contract/` | 25+ Tests | CI PR Gate |
| **Tier 3: E2E Journeys** | Authentication, pairing, policy sync, offline queue, focus sessions, revocation | `tests/e2e/` | 15+ Tests | Daily / Nightly CI |
| **Tier 4: Adversarial QA**| 20-Attack security breaker battery (race conditions, cross-tenant leaks, token tampering) | `tests/qa_security_breaker_suite.js` | 20 Tests | Nightly / Pre-Release |
| **Tier 5: Chaos & Resilience**| Network drops, cold reboots, database crash recovery, clock skew | `tests/qa_adversarial_suite.js` | 10 Tests | Pre-Release Gate |

---

## 3. Detailed Verification Scenarios

### Scenario 1: Cryptographic Device Pairing & Cold Reboot
- **Objective**: Verify that a device generating an Ed25519 keypair can submit an enrollment request, receive approval from the owner, retrieve a persistent JWT `deviceToken`, and resume synchronization after a cold process restart without re-pairing.
- **Assertion**: `pairingStatus == APPROVED` $\to$ `deviceToken` persisted $\to$ Process rebooted $\to$ `POST /api/v1/devices/:id/heartbeat` returns `HTTP 200 OK`.

### Scenario 2: Cross-Device Policy Orchestration & Capability Filtering
- **Objective**: Verify that a policy targeting both `youtube.com` (Domain) and `discord.exe` (App) is properly routed and filtered:
  - Browser Extension receives and enforces `youtube.com` via `declarativeNetRequest`.
  - Windows Client receives and enforces `discord.exe` via Win32 process tracker.
  - Neither client crashes or reports false failure on unsupported targets.
- **Assertion**: Both clients report `POLICY_APPLIED` with their respective supported target counts.

### Scenario 3: Offline Queue Replay & Idempotency Guarantee
- **Objective**: Verify that an offline client queues 10 usage events in local SQLite. Upon reconnecting, it flushes the batch. A network timeout is simulated after the server commits the batch. The client retries the exact same 10 events.
- **Assertion**: Server returns `HTTP 200 OK` with `{ processed: 0, duplicates: 10 }`. Database usage records remain exact with 0 double counting.

### Scenario 4: Interval Union Usage Deduplication
- **Objective**: User uses YouTube on Windows (10:00 - 10:30) and YouTube in Chrome on macOS (10:10 - 10:40).
- **Assertion**:
  - `PER_DEVICE` mode: Windows = 30m, macOS = 30m.
  - `CROSS_DEVICE_UNION` mode: Exactly 40 minutes (10:00 - 10:40).
  - Complexity: Must execute in $O(n \log n)$ time.

### Scenario 5: Instant Zero-Trust Device Revocation
- **Objective**: Account owner clicks "Revoke Device" on Dashboard for an active Windows PC.
- **Assertion**:
  - Backend marks `status = 'REVOKED'`, revokes credential in DB.
  - WebSocket hub dispatches `DEVICE_REVOKED` and severs connection.
  - Windows client immediately clears local DPAPI vault, transitions UI to locked state.
  - Any subsequent heartbeat attempt returns `HTTP 403 Forbidden (DEVICE_REVOKED)`.

---

## 4. Release Blocker Quality Gates

A release is **STRICTLY BLOCKED** if any of the following occur:
1. **Security Vulnerability**: Any cross-tenant authorization leak (User B seeing User A devices or policies).
2. **Credential Leak**: Cleartext passwords, JWT secrets, or private keys printed in server logs or client logs.
3. **Data Loss / Corruption**: Offline queue dropping events or double-counting usage upon replay.
4. **Enforcement Bypass**: Revoked device able to fetch policies or continue reporting heartbeats.
5. **System Crash**: Unhandled panic in Go backend or uncaught exception in native clients.
6. **Failed Contract Test**: Any client or server endpoint deviating from `SYSTEM_CONTRACT.md`.
