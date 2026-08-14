# Testing: Chaos & Failure Mode Scenarios

Tests verifying system stability under network partitions, database locks, and process crashes.

---

## 1. Network Severance (Offline Simulation)
- **Condition**: Client loses all network connectivity.
- **Expected Behavior**: Local Room / CoreData cache continues local policy enforcement. Usage increments queue locally.
- **Result**: PASS.

---

## 2. Server Crash & Recovery
- **Condition**: Backend server process killed via `kill -9` during active delta sync.
- **Expected Behavior**: SQLite WAL journal recovers uncorrupted state on restart. Client reconnects via exponential backoff and retries delta sequence.
- **Result**: PASS.

---

## 3. Database Write Lock Contention
- **Condition**: Collector daemon updates usage while Web Dashboard queries analytics simultaneously.
- **Expected Behavior**: `PRAGMA busy_timeout=5000` prevents `database is locked` errors.
- **Result**: PASS.
