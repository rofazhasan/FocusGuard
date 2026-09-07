# FocusGuard Canonical Distributed System Contract

**Document ID**: `FG-CONTRACT-001`  
**Version**: `1.0.0-PROD`  
**Date**: September 7, 2026  
**Status**: NORMATIVE SPECIFICATION  
**Scope**: All Clients (Windows, macOS, Android, Browser Extensions) & Cloud Backend  

---

## 1. Device Identity & Cryptographic Roots

### 1.1 Invariant Rules
1. **No Hardware Identifier as Primary Key**: MAC addresses, IMEIs, serial numbers, and CPU IDs are strictly forbidden as primary device identifiers.
2. **Cryptographic Identity**: Every device generates an **Ed25519 keypair** locally on first launch.
   - Private key is retained exclusively on the local device inside hardware-backed secure storage (macOS Keychain, Windows DPAPI, Android Keystore, Extension crypto storage).
   - Public key is submitted in PEM or Base64 format during enrollment.
3. **Immutable Device UUID**: Upon owner pairing approval, the server assigns an immutable RFC 4122 Version 4 UUID (`deviceId`).
4. **Device Token Claims**:
   The issued JWT `deviceToken` contains:
   ```json
   {
     "sub": "<deviceId>",
     "device_id": "<deviceId>",
     "user_id": "<ownerUserId>",
     "client_type": "WINDOWS_AGENT|MACOS_AGENT|ANDROID_APP|EXTENSION",
     "cred_version": 1,
     "role": "DEVICE",
     "iat": 1788800000,
     "exp": 1820336000
   }
   ```
5. **Least Privilege**: A `deviceToken` can NEVER access tenant admin routes (e.g. user password change, billing, creating other devices).

---

## 2. Canonical Device Lifecycle & Finite State Machine

```
  ┌─────────────────┐
  │  UNREGISTERED   │
  └────────┬────────┘
           │ Generate Keypair & Request Pairing Code
           ▼
  ┌─────────────────┐
  │     PAIRING     │◄─────────┐
  └────────┬────────┘          │
           │ Owner Approves    │ Re-pair Request
           ▼                   │
  ┌─────────────────┐          │
  │     ACTIVE      │          │
  └────┬───────┬────┘          │
Heartbeat Miss │ Reconnect     │
(60s-180s)     │               │
       ▼       │               │
  ┌─────────────────┐          │
  │     OFFLINE     │          │
  └────────┬────────┘          │
Heartbeat >│                   │
10 Minutes │                   │
       ▼   │                   │
  ┌─────────────────┐          │
  │      STALE      │          │
  └────────┬────────┘          │
           │ Owner Revokes     │
           ▼                   │
  ┌─────────────────┐          │
  │     REVOKED     │──────────┘
  └────────┬────────┘
           │ Owner Deletes Device
           ▼
  ┌─────────────────┐
  │     REMOVED     │ (Terminal)
  └─────────────────┘
```

### 2.1 State Definitions & Semantics

| State | Definition | Policy Distribution | Realtime Push | Local Action Required |
| :--- | :--- | :--- | :--- | :--- |
| `UNREGISTERED` | Device initialized locally; has no server relationship. | ❌ Prohibited | ❌ None | Prompt user to initiate pairing flow. |
| `PAIRING` | Temporary state during 4-step handshake or QR scan (TTL: 5 min). | ❌ Prohibited | ❌ None | Poll status or await WebSocket handshake. |
| `ACTIVE` | Device has paired and sent a heartbeat within the last 180 seconds. | ✅ Authorized | ✅ Live WebSocket | Enforce policies; flush usage deltas. |
| `OFFLINE` | No heartbeat received for 180s - 10m; network disconnected. | ⏸️ Queued | ⏸️ Offline Buffer | Client runs locally from cached policies in SQLite. |
| `STALE` | No heartbeat received for > 10 minutes. Dashboard flags warning. | ⏸️ Suspended | ❌ None | Server marks degraded health; holds pending updates. |
| `REVOKED` | Owner revoked authorization or security anomaly detected. | 🚫 Rejected (403) | ⚡ Close & Reject | Wipe local device tokens; cease sync; lock UI. |
| `REMOVED` | Device record deleted from tenant fleet. Terminal state. | 🚫 Discarded | 🚫 Discarded | Device metadata purged; must perform clean install. |

---

## 3. Capability Negotiation Model

Clients declare their capability set during pairing and heartbeat:
```json
{
  "deviceId": "c88aeef4-e2e6-4f8b-aaa5-bb62f348d272",
  "clientType": "WINDOWS_AGENT",
  "clientVersion": "1.0.0",
  "platformVersion": "Windows 11 Build 22631",
  "capabilities": [
    "USAGE_TRACKING",
    "APP_RESTRICTION",
    "OFFLINE_POLICY",
    "REALTIME_SYNC",
    "NOTIFICATION_ENFORCEMENT"
  ]
}
```

### 3.1 Standard Capability Flags

| Capability | Description | Supported Platforms |
| :--- | :--- | :--- |
| `USAGE_TRACKING` | Accurate foreground application / active tab duration measurement. | Windows, macOS, Android, Extension |
| `APP_RESTRICTION` | Process termination, window minimization, or app block overlay. | Windows, macOS, Android (Accessibility) |
| `DOMAIN_BLOCKING` | Network domain interception via DNR or local DNS sinkhole. | Extension, Android (VpnService) |
| `OFFLINE_POLICY` | Persistent local SQLite/IndexedDB policy engine. | Windows, macOS, Android, Extension |
| `REALTIME_SYNC` | Duplex WebSocket connection for sub-second command delivery. | Windows, macOS, Android, Extension |
| `DEVICE_GROUP_CONTROL` | Participates in multi-device coordinated focus sessions. | Windows, macOS, Android, Extension |
| `NOTIFICATION_ENFORCEMENT` | OS native budget warning notifications (5m, 1m warnings). | Windows, macOS, Android |
| `MANAGED_MODE` | Device locked in focus mode with tamper prevention. | Windows, macOS, Android |

---

## 4. Policy Lifecycle & Conflict Resolution

### 4.1 Monotonic Policy Versioning
- Every policy modification increments an integer `version` ($v_{n+1} > v_n$).
- Every policy payload contains:
  ```json
  {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "name": "Social Media Limit",
    "version": 4,
    "limitSeconds": 1800,
    "period": "DAILY",
    "enforcementMode": "BLOCK",
    "timezone": "UTC",
    "isEnabled": true,
    "targets": [
      { "targetType": "WEBSITE", "targetValue": "youtube.com" },
      { "targetType": "APP", "targetValue": "discord.exe" }
    ],
    "assignedDeviceIds": ["c88aeef4-e2e6-4f8b-aaa5-bb62f348d272"]
  }
  ```
- **Stale Rejection Rule**: If a client receives version $v_{k}$ where $v_k \le v_{\text{current}}$, the client acknowledges receipt without replacing newer state.

### 4.2 Precedence & Conflict Resolution Matrix
When multiple policies apply to the same target:
1. **Specificity Precedence**:
   $$\text{Device-Specific Policy} > \text{Device-Group Policy} > \text{Global Fleet Policy}$$
2. **Action Severity Precedence**:
   $$\text{BLOCK} > \text{SCHEDULED\_BLOCK} > \text{FOCUS\_ONLY} > \text{WARN} > \text{ALLOW}$$
3. **Limit Precedence**:
   $$\text{Lowest Positive } limit\_seconds \text{ Wins}$$
4. **Deterministic Tie-Breaking**: Higher `version` wins; if equal, lexicographically smaller `policyId` breaks ties.

### 4.3 Safe Rollback
When an administrator selects "Rollback to v9", the system does not delete history. It publishes a **new version** (e.g. $v_{11}$) whose configuration mirrors $v_9$ with an audit annotation `rolled_back_from_v10`.

---

## 5. Unified Event Schema & Idempotency Envelope

All system events (analytics, enforcement, health, sync) use the **Canonical Event Envelope**:

```json
{
  "eventId": "evt_7f8a9b1c2d3e",
  "eventType": "USAGE_SESSION_ENDED",
  "deviceId": "c88aeef4-e2e6-4f8b-aaa5-bb62f348d272",
  "userId": "00000000-0000-0000-0000-000000000001",
  "schemaVersion": "1.0.0",
  "timestamp": "2026-09-07T23:30:00.000Z",
  "idempotencyKey": "c88aeef4:USAGE_SESSION_ENDED:1788804600:discord.exe",
  "payload": {
    "targetType": "APP",
    "targetValue": "discord.exe",
    "durationSeconds": 300,
    "startedAt": "2026-09-07T23:25:00.000Z",
    "endedAt": "2026-09-07T23:30:00.000Z"
  }
}
```

### 5.1 Ingestion Idempotency Invariants
1. Database enforces `UNIQUE(id)` or `UNIQUE(idempotencyKey)`.
2. Duplicate submissions return `HTTP 200 OK` with `{ "success": true, "processed": 0, "duplicates": 1 }`.
3. Safe retry: Clients retrying offline batches will never inflate daily totals or trigger duplicate alerts.

---

## 6. Realtime Gateway & WebSocket Protocol

### 6.1 Connection Handshake
- Endpoint: `GET /ws?token=<deviceToken>`
- Verification: Middleware checks token signature, extracts `deviceId`, queries DB to ensure `status != 'REVOKED'`.
- Subprotocol: Binary or UTF-8 JSON envelopes.

### 6.2 Standard Frames

#### Client $\to$ Server:
- `HEARTBEAT`: `{ "type": "HEARTBEAT", "payload": { "appVersion": "1.0.0", "policyVersion": 4 } }`
- `ACK`: `{ "type": "COMMAND_ACK", "payload": { "commandId": "...", "status": "SUCCEEDED" } }`

#### Server $\to$ Client:
- `POLICY_UPDATED`: `{ "event": "POLICY_UPDATED", "payload": { "policyId": "...", "version": 5 } }`
- `LIMIT_REACHED`: `{ "event": "LIMIT_REACHED", "payload": { "targetValue": "youtube.com", "limitSeconds": 1800 } }`
- `REMOTE_COMMAND`: `{ "event": "REMOTE_COMMAND", "payload": { "commandId": "...", "commandType": "START_FOCUS" } }`
- `DEVICE_REVOKED`: `{ "event": "DEVICE_REVOKED", "payload": { "deviceId": "...", "revokedAt": "..." } }`

---

## 7. Command Delivery & State Machine

```
  ┌───────────┐
  │  CREATED  │
  └─────┬─────┘
        │ Persisted to DB & Enqueued
        ▼
  ┌───────────┐
  │   SENT    │
  └─────┬─────┘
        ├──────────────────────────┐
        │ Delivery Timeout         │ Client Receives
        ▼                          ▼
  ┌───────────┐             ┌──────────────┐
  │  EXPIRED  │             │ ACKNOWLEDGED │
  └───────────┘             └──────┬───────┘
                                   │ Executes Locally
                                   ▼
                            ┌──────────────┐
                            │  EXECUTING   │
                            └──────┬───────┘
                     ┌─────────────┴─────────────┐
                     ▼                           ▼
              ┌─────────────┐             ┌─────────────┐
              │  SUCCEEDED  │             │   FAILED    │
              └─────────────┘             └─────────────┘
```

Every command requires:
- `commandId`: RFC 4122 UUID.
- `expiresAt`: Absolute UTC timestamp after which the command must be ignored.
- `idempotencyKey`: Prevents re-execution on reconnection.

---

## 8. Standard Error Format & Taxonomy

All error responses from any FocusGuard API return the standard error envelope:
```json
{
  "error": {
    "code": "DEVICE_REVOKED",
    "message": "Device authorization has been permanently revoked by tenant owner",
    "requestId": "req_609a39ec8859",
    "timestamp": "2026-09-07T23:30:15.120Z",
    "retryable": false
  }
}
```

---

## 9. Time & Clock Strategy

1. **Storage Invariant**: All timestamps in databases, logs, and APIs are stored and transmitted in **UTC ISO-8601** (`YYYY-MM-DDTHH:mm:ss.sssZ`).
2. **Clock Skew Invariant**: Server tracks `serverTime` on every response. Clients calculate drift $\Delta t = t_{\text{server}} - t_{\text{client}}$.
3. **Monotonic Duration Invariant**: Usage duration is calculated via monotonic clocks (`CLOCK_MONOTONIC_RAW` on macOS/Linux, `QueryPerformanceCounter` on Windows). Rolling back wall time does not alter elapsed session seconds.
4. **Daily Rollover Rule**: Midnight boundary rollovers are evaluated according to the **Policy's configured timezone** (e.g. `America/New_York`), not client local time.
