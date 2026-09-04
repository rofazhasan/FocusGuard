# FocusGuard Phase 2 Jira Board Specification

**Epic Key**: `FG-BE-200`  
**Epic Name**: FocusGuard Phase 2: Backend + Authentication + Device Identity + Secure Pairing  
**Project**: FocusGuard Core Engineering (`FG`)  
**Status**: IN PROGRESS  

---

## Work Breakdown Structure & Task Register

| Issue Key | Summary | Component | Priority | Status |
| :--- | :--- | :--- | :--- | :--- |
| **FG-BE-200** | **FocusGuard Phase 2 Master Epic: Core Trust & Pairing** | Architecture | Blocker | **IN PROGRESS** |
| FG-BE-201 | Phase 1 Backend & Security Audit (`PHASE2_AUDIT.md`) | Documentation | High | **DONE** |
| FG-BE-202 | Device Architecture & Trust Boundary Specs (`DEVICE_ARCHITECTURE.md`) | Architecture | High | **DONE** |
| FG-BE-203 | User Authentication Upgrade (Argon2id, Password Rules, Rate Limits) | Auth | Critical | READY |
| FG-BE-204 | Device Domain Model & Shared Types Extension | Shared Packages | High | READY |
| FG-BE-205 | Device State Machine & Invalid Transition Enforcement | Shared Packages | Critical | READY |
| FG-BE-206 | Device Identity & Asymmetric Key Protocol | Security | Critical | READY |
| FG-BE-207 | Device Registration Handler & Validations | Devices | High | READY |
| FG-BE-208 | Pairing Session Generation & Short-Lived Hashed Codes | Pairing | Critical | READY |
| FG-BE-209 | Pairing Enrollment Request & Client Metadata Ingestion | Pairing | Critical | READY |
| FG-BE-210 | Explicit Owner Approval Flow & Reject/Cancel Routes | Pairing / UI | Critical | READY |
| FG-BE-211 | Atomic Pairing Finalization & Database Transactions | Database / Pairing| Blocker | READY |
| FG-BE-212 | Persistent Device Credential & Scoped Token Issuer | Security / Auth | Critical | READY |
| FG-BE-213 | Device Authentication Middleware & Revocation Guard | Middleware | Blocker | READY |
| FG-BE-214 | Device Heartbeat Handler & Offline State Evaluator | Health / Fleet | Medium | READY |
| FG-BE-215 | Device Revocation Endpoint & WebSocket Teardown | Security | Blocker | READY |
| FG-BE-216 | Policy Synchronization Upgrade with Device Scoping | Policies | High | READY |
| FG-BE-217 | Event Ingestion Upgrade with Device Auth & Idempotency | Events / Ingest | High | READY |
| FG-BE-218 | Realtime WebSocket Authentication & Revocation Teardown | Realtime Gateway | Critical | READY |
| FG-BE-219 | Web Dashboard Device Management UI (Add, Approve, Revoke) | Dashboard | High | READY |
| FG-BE-220 | Immutable Audit Logging Engine | Audit | High | READY |
| FG-BE-221 | Security Test Battery (Anti-Replay, Tamper, Bypass Attempts) | QA / Security | Critical | READY |
| FG-BE-222 | Concurrency & Race Condition Test Battery | QA / Concurrency | High | READY |
| FG-BE-223 | End-to-End Pairing Lifecycle Verification Test | E2E Testing | Blocker | READY |
| FG-BE-224 | Chaos & Failure Resilience Test Suite | QA / Chaos | High | READY |
| FG-BE-225 | Latency & Performance Benchmark Battery | DevOps / Perf | Medium | READY |
| FG-BE-226 | CI/CD Pipeline Workflow Upgrade & Automated Matrix | DevOps | High | READY |
| FG-BE-227 | Staging Environment Deployment & Verification | DevOps | High | READY |
| FG-BE-228 | Production Deployment & Smoke Testing | DevOps | Blocker | READY |
| FG-BE-229 | Phase 2 Documentation Suite (API, Pairing, Protocols, Runbooks) | Documentation | High | READY |
| FG-BE-230 | Final QA Certification & Phase 3 Handover Readiness | QA / Leadership | Blocker | READY |

---

## Definition of Done (DoD) for Every Subtask
- [ ] Code implemented to production standard (no mocks in production path).
- [ ] Strict typecheck & lint pass with zero errors.
- [ ] Unit & integration tests pass with 100% coverage on core security paths.
- [ ] No secrets logged or committed.
- [ ] Documented in architecture & API references.
