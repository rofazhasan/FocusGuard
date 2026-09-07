# FocusGuard Phase 4 macOS Test Plan

**Document ID**: FG-TEST-004  
**Version**: 1.0.0-PROD  
**Target Platform**: macOS 13.0+  

---

## 1. Objectives

This test plan defines the automated, manual, and chaos test suites required to validate the FocusGuard macOS Native Client across all lifecycle stages.

---

## 2. Test Suites

### 2.1 Unit Tests (`FocusGuardTests/`)
- **Policy Engine**: Validates evaluation rules (`ALLOW`, `WARN`, `LIMIT_REACHED`, `ENFORCE`), daily seconds limits, schedule cron intervals, and protected system denylist overrides.
- **Usage State Machine**: Tests all state transitions (`NO_TARGET`, `ACTIVE`, `IDLE`, `PAUSED`, `SESSION_ENDED`).
- **Timer Engine**: Tests monotonic time advancement, clock drift detection, and checkpoint dispatch.
- **SQLite Persistence**: Validates WAL database migrations, transaction rollbacks, daily usage queries, and event queue persistence.
- **Keychain Storage**: Tests cryptographic token persistence, update, retrieval, and zero-trust deletion.

### 2.2 Integration Tests
- **Foreground App Switching**: Verifies that switching between applications correctly stops the active session, computes session duration, and resumes tracking when returning.
- **Screen Lock / Sleep Simulation**: Verifies that locking the screen or putting the machine to sleep immediately pauses tracking without recording fictitious idle duration.
- **Crash Recovery**: Verifies that terminating the process abruptly during an active session recovers without corrupted data or missing checkpoints.
- **Offline Event Queue**: Simulates network outage, queues 10+ events, restores connectivity, and asserts exactly-once upload without duplicate insertion.
- **Device Revocation**: Simulates receipt of `DEVICE_REVOKED` over WebSocket or REST 403, asserting credential deletion from Keychain, stopping tracking, and transitioning UI to `REVOKED`.

### 2.3 Usage Tracking Matrix
| Condition | Expected Behavior |
| :--- | :--- |
| Target app running in background | Zero usage counted |
| Target app enters foreground | Session starts, seconds tick |
| User switches to another app | Active session closes & commits |
| User returns to target app | New session starts with accurate cumulative sum |
| User idle > 60 seconds | Tracking pauses, state transitions to `IDLE` |
| Screen locks | Tracking immediately pauses (`PAUSED`) |
| Screen unlocks | State re-evaluates frontmost window |
| System sleeps & wakes | Downtime not counted |
| Application crashes | Session recovered up to last 5s checkpoint |
| System clock rolled back | Monotonic clock prevents time manipulation |
| Midnight crossed | Daily usage rolls over smoothly into new calendar day |

---

## 3. Acceptance Gates
A release build is approved only if:
1. 100% of unit and integration tests pass with zero warnings.
2. The First Vertical Slice end-to-end flow succeeds on a clean macOS environment.
3. Memory leak audit confirms zero retain cycles in timer observers or WebSocket handlers.
4. CPU overhead remains under 0.5% during active foreground monitoring.
