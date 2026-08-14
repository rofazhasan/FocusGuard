# How-To: Work in Offline Autonomous Mode

FocusGuard is designed as an **offline-first platform**: devices never stop enforcing active attention rules simply because the internet is unavailable.

---

## 1. Local Offline Caching

When a device enrolls or receives a policy update, it caches the complete policy payload in local persistent storage:
- **macOS**: Encrypted CoreData store in the Application Support sandbox.
- **Android**: Local Room SQLite database (`focusguard_local.db`).

---

## 2. Autonomous Local Enforcement

When offline:
1. The local policy evaluation engine evaluates usage deltas against cached rules.
2. If the local daily threshold is reached (e.g. 30 minutes of YouTube on Android), the local shield engages immediately.
3. Usage increments are buffered in an internal FIFO queue (`pending_deltas`).

---

## 3. Reconnection & Delta Reconciliation

When internet connectivity is restored:
1. The device transmits all accumulated usage deltas via `POST /api/v1/usage/sync`.
2. The server incorporates the deltas using idempotent upserts (`ON CONFLICT (user_id, device_id, target_value, date) DO UPDATE`).
3. If new cloud policies were published while the device was offline (detected via `policyVersion`), the client fetches the latest policy bundle.
