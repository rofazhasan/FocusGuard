# FocusGuard Phase 1 Architecture Audit & Phase 2 Migration Assessment

**Document ID**: FG-AUDIT-002  
**Date**: September 4, 2026  
**Author**: Principal Systems Architect & Security Engineering Team  
**Status**: APPROVED BASELINE  

---

## 1. Executive Summary

FocusGuard Phase 1 proved the fundamental cross-platform enforcement, active window tracking, declarative network rules (DNR), macOS Screen Time ManagedSettings shields, and Android VpnService DNS sinkholing across isolated clients.

However, Phase 1 relied on prototype-grade assumptions regarding identity, credentials, and pairing. This audit provides an exhaustive evaluation of the existing backend, shared packages, client extensions, and databases to prepare the foundation for Phase 2: **Backend + Authentication + Device Identity + Secure Pairing**.

---

## 2. Inventory of Audited Components

| Subsystem | Location | Language / Tech | Primary Function |
| :--- | :--- | :--- | :--- |
| **Go Cloud Backend** | `backend/` | Go 1.25, Chi v5, Gorilla WS | Core API server, analytics, usage aggregator, WebSocket hub |
| **Database Engines** | `backend/pkg/database` | PostgreSQL 16+ & SQLite WAL | Persistent relational storage with auto SQLite fallback |
| **Web Dashboard** | `apps/web/` | Vanilla JS, HTML5, CSS3, SSE/WS | Owner management console, policy definitions, live charts |
| **Browser Extension** | `apps/extension/` | Chrome MV3 (DNR, PSL, Alarm) | Tab visibility tracker, local cache, offline sync, block page |
| **Shared Domain Packages**| `packages/*` | Node.js (CommonJS) | DomainEngine, PolicyCore, EventModel, Crypto, DeviceModel |
| **macOS Native Agent** | `apps/macos/` | Swift 5.10, ManagedSettings | Anti-tamper monotonic clock, ScreenTime shield proof |
| **Android Agent** | `apps/android/` | Go (Simulation), Kotlin | VpnService DNS sinkhole, midnight session partitioner |
| **Master Test Battery** | `tests/run_all_tests.sh` | Bash, Node, Swift, Go | 7 integrated suites verifying all Phase 1 milestones |

---

## 3. Existing Architecture & Data Flow

In Phase 1, the architecture operated under a single logical user assumption:
```
                               ┌───────────────┐
                               │ Web Dashboard │
                               └───────┬───────┘
                                       │ (Bearer User JWT)
                                       ▼
┌──────────────────┐           ┌───────────────┐           ┌──────────────────┐
│ Chrome Extension │──────────▶│  Go Backend   │◀──────────│ macOS Native App │
└──────────────────┘           │  (Port 8080)  │           └──────────────────┘
  (Bearer User JWT)            └───────┬───────┘            (Simulated Device)
                                       │
                         ┌─────────────┴─────────────┐
                         ▼                           ▼
                  PostgreSQL 16+               Embedded SQLite
                 (Production DB)             (Zero-Config Fallback)
```

### 3.1 Existing Authentication Model
- **Algorithm**: `bcrypt` default cost (`backend/internal/auth/service.go`).
- **Token Format**: HS256 JWT containing `sub` (user UUID) and `email`.
- **Token Lifespans**: Access Token (15 minutes), Refresh Token (30 days).
- **Default Hardcoded Bootstrap**: User `00000000-0000-0000-0000-000000000001` (`demo@focusguard.local` / `focusguard123`) and Device `00000000-0000-0000-0000-000000000002` are seeded on boot.
- **WebSocket Upgrade**: If an incoming WebSocket connection lacks an Authorization token or fails validation, `backend/internal/events/hub.go` silently assigns the connection to the default demo user.

### 3.2 Existing Pairing & Enrollment Mechanism
- `POST /api/v1/enrollment/create`: Generates a random 6-character alphanumeric code (`FG-XXXXXX`) with 5-minute TTL. Stored **in plaintext** in `enrollment_tokens`.
- `POST /api/v1/enrollment/claim`: Accepts `pairingCode`, `deviceName`, and `platform`.
  - Atomically marks `is_claimed = 1`.
  - Automatically inserts an active device record in `devices`.
  - Immediately generates and returns a **full User JWT token** (`tokenService.GenerateTokens(userID, ...)`).
  - Broadcasts `DEVICE_ENROLLED` over WebSocket to the dashboard.

---

## 4. Existing Security Weaknesses & Technical Debt

### 🔴 Critical Security Weaknesses
1. **No Distinction Between User Identity and Device Identity**:
   When a device claims a pairing code, the server issues a standard User JWT. A compromised client or malicious device could use this token to access the user's dashboard endpoints, delete other devices, or modify policies.
2. **Lack of Cryptographic Device Identity**:
   Devices do not generate private/public keypairs. Device identity is purely an application-generated UUID stored in client storage.
3. **No Owner Approval Step**:
   Any party that learns or guesses the 6-character pairing code can invoke `POST /api/v1/enrollment/claim` and instantly achieve full device enrollment without the owner reviewing or confirming the request.
4. **Plaintext Pairing Code Storage**:
   Pairing codes are stored in plaintext in the database table `enrollment_tokens`. An internal breach or SQL dump exposes all active pairing codes.
5. **No Token Revocation Enforcement on Device Revocation**:
   In Phase 1, there is no device credential revocation mechanism. Even if a device row status is marked `OFFLINE`, existing issued JWTs remain valid until expiration (up to 15 minutes / 30 days).
6. **Anonymous WebSocket Fallback**:
   The WebSocket endpoint `/ws` defaults unauthenticated connections to the hardcoded demo user, allowing unauthorized telemetry eavesdropping.
7. **No Device Request ID & Error Schema Standardization**:
   Error responses are inconsistent (`{"error":"..."}` strings without error codes or correlation IDs).

---

## 5. Migration Requirements & Backward Compatibility Guarantees

To ensure Phase 2 succeeds without breaking Phase 1 or disrupting continuous verification:

1. **API Backward Compatibility**:
   - Existing endpoints (`POST /api/v1/auth/login`, `POST /api/v1/auth/register`, `GET /api/v1/policies`, `POST /api/v1/usage/sync`, `POST /api/v1/events/batch`) MUST remain operational.
   - Legacy `/api/v1/enrollment/*` will remain functional as a legacy bridge while new devices use `/api/v1/pairing/*` and `/api/v1/devices/*`.
2. **Dual Database Engine Support**:
   - Both PostgreSQL and embedded SQLite schema migrations must be maintained synchronously.
3. **Password Hash Transparent Migration**:
   - Phase 2 introduces Argon2id for all new registrations and password updates. Existing bcrypt hashes will be verified seamlessly and re-hashed to Argon2id upon successful login.
4. **Test Suite Integrity**:
   - All 7 existing master test suites in `tests/run_all_tests.sh` and the adversarial suite `tests/qa_adversarial_suite.js` must continue to pass with 100% success.

---

## 6. Audit Conclusion & Readiness

Phase 1 provides a clean, well-tested core domain engine and reliable enforcement primitives. The architectural debt is concentrated exclusively in identity, authentication, credential lifecycles, and pairing verification. Phase 2 directly solves these issues by establishing a production-grade cryptographic trust architecture.
