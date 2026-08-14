# Synchronization Protocol

FocusGuard implements an **event-driven synchronization protocol** combining WebSocket instant push notifications with REST delta reconciliation.

---

## 1. Real-Time WebSocket Events

The server exposes `ws://localhost:8080/ws?token=<JWT>`. The event protocol uses structured JSON payloads:

```json
{
  "event": "EVENT_NAME",
  "payload": { ... }
}
```

### Core Event Definitions:
- `USAGE_TICK`: Emitted when an active window/app updates usage duration.
- `LIMIT_REACHED`: Emitted when cumulative cross-device usage exceeds a policy budget.
- `DEVICE_ENROLLED`: Emitted when a new managed device joins the account.
- `POLICY_UPDATED`: Emitted when a policy rule is created, modified, or assigned.
- `REMOTE_COMMAND`: Dispatches remote focus actions or emergency lockdown commands.
- `FOCUS_STARTED` / `FOCUS_ENDED`: Notifies all connected devices of focus mode transitions.

---

## 2. Idempotent Usage Delta Syncing

When syncing usage from local devices to the server:
- Devices maintain a monotonic sequence number `syncSequence`.
- Ingestion queries use upsert syntax:
  ```sql
  INSERT INTO usage_aggregates (id, user_id, device_id, target_value, date, total_duration_seconds, updated_at)
  VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP)
  ON CONFLICT (user_id, device_id, target_value, date)
  DO UPDATE SET total_duration_seconds = usage_aggregates.total_duration_seconds + EXCLUDED.total_duration_seconds;
  ```
- This prevents double-counting if network drops cause request retries.
