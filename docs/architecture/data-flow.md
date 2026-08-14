# Data Flow & Synchronization Architecture

This document details the lifecycle of usage metrics, policy distribution, and remote command fan-out.

---

## 1. Real Usage Ingestion Flow

```
[ Active Window / App Session ]
               │
               ▼ (Every 3 seconds)
   [ Local Activity Collector ]
               │
               ▼ (Accumulate into discrete 5-minute batches or delta ticks)
   [ Client Usage Delta Queue ]
               │
               ▼ (POST /api/v1/usage/sync)
  [ Backend Usage Ingestion Handler ]
               │
               ├──► [ Upsert into usage_aggregates ]
               │    (UNIQUE: user_id, device_id, target_value, date)
               │
               ├──► [ Evaluate Thresholds in Evaluator ]
               │
               ▼ (If aggregated total >= limit)
     [ Broadcast LIMIT_REACHED ]
               │
   ┌───────────┴───────────┐
   ▼                       ▼
[ macOS Shield On ]   [ Android VPN Sinkhole On ]
```

---

## 2. Policy Distribution & Versioning Flow

1. **Authoring**: The owner modifies a policy (e.g. changing daily budget from 30m to 45m).
2. **Persistence**: The backend executes an atomic transaction updating `policies` and increments `version = version + 1`.
3. **Event Dispatch**: The backend publishes `POLICY_UPDATED` with payload `{ policyId, version, limitSeconds, assignedNodes }` over the WebSocket connection.
4. **Local Reconciliation**: Connected nodes update their local offline cache and evaluate their current usage against the new threshold immediately.

---

## 3. Remote Command Fan-Out

Remote commands (`REMOTE_FOCUS_START`, `POLICY_UPDATE`, `SYNC_REQUEST`) flow through an idempotent, signed pipeline:
1. Command generated with UUID and `expiresAt = NOW() + TTL`.
2. Stored in database table `remote_commands` with status `DISPATCHED`.
3. Sent directly over WebSocket to targeted device ID.
4. If device is offline, command is delivered upon next heartbeat reconnection before `expiresAt`.
