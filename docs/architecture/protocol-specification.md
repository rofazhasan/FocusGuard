# FocusGuard Protocol Specification v1

## 1. Overview

This document defines the complete communication protocol between FocusGuard devices and the FocusGuard Cloud Backend. All communication is either REST/HTTP or WebSocket-based, and every exchange is authenticated, versioned, and timestamped.

**Principle**: The cloud coordinates. The device enforces. No enforcement decision shall be made solely dependent on receiving a real-time command.

---

## 2. REST API

### Base URL
```
https://api.focusguard.app/api/v1
```

### Authentication
All authenticated endpoints require:
```
Authorization: Bearer <access_token>
```

Access tokens are short-lived JWTs. Devices use the token obtained at enrollment (`ClaimEnrollment`) and must handle token expiry.

### Endpoints Summary

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/register` | Public | Register a new owner account |
| POST | `/auth/login` | Public | Authenticate and obtain access token |
| POST | `/enrollment/create` | Owner | Generate short-lived pairing session |
| GET  | `/enrollment/pending` | Owner | List unclaimed pairing sessions |
| POST | `/enrollment/claim` | Public (pairing code) | Managed device claims pairing code |
| GET  | `/devices` | Owner | List all enrolled devices |
| POST | `/devices/register` | Owner | Register a device directly |
| POST | `/policies` | Owner | Create an attention policy |
| GET  | `/policies` | Owner/Device | List all active policies |
| DELETE | `/policies/{id}` | Owner | Delete a policy |
| POST | `/policies/simulate` | Owner | Simulate policy impact before activation |
| POST | `/policies/explain` | Owner | Explain why a target is blocked |
| POST | `/usage/sync` | Device | Submit usage event deltas |
| GET  | `/analytics/daily` | Owner | Daily usage analytics |
| GET  | `/analytics/weekly` | Owner | Weekly analytics |
| GET  | `/analytics/timeline` | Owner | Timeline of usage events |
| GET  | `/analytics/enforcement-timeline` | Owner | Enforcement events over time |
| GET  | `/analytics/recommendations` | Owner | Attention health recommendations |
| POST | `/focus/start` | Owner | Start a remote focus session |
| POST | `/focus/end` | Owner | End the active focus session |
| GET  | `/focus/presets` | Owner | List built-in focus mode presets |
| POST | `/commands/dispatch` | Owner | Dispatch a remote command to a device |
| GET  | `/audit/logs` | Owner | Retrieve audit trail |
| GET  | `/health/fleet` | Owner | Get device fleet health states |
| POST | `/health/diagnostics` | Owner | Run remote diagnostics |
| POST | `/health/tamper` | Device | Report a tamper/protection degradation event |

---

## 3. WebSocket Protocol

### Connection
```
wss://api.focusguard.app/ws
```

Authentication:
```
?token=<access_token>
```

### Message Envelope Format

All messages follow this standardized envelope:

```json
{
  "type": "POLICY_PUSH",
  "correlationId": "cor_1723745834_ab7z9",
  "timestamp": 1723745834000,
  "payload": {}
}
```

### Client → Server Message Types

| Type | Payload | Description |
|------|---------|-------------|
| `AUTH` | `{ token }` | Authenticate the WebSocket connection |
| `HEARTBEAT` | `{ deviceId, policyVersion, protectionState }` | Device liveness ping (every 30s) |
| `REPORT_USAGE` | `{ deviceId, domain, durationSeconds, date }` | Usage event submission |
| `REPORT_EVENT` | `{ eventId, type, deviceId, policyVersion, timestamp, payload }` | Enforcement event |
| `POLICY_PULL` | `{ deviceId, currentVersion }` | Request current policy version |

### Server → Client Message Types

| Type | Payload | Description |
|------|---------|-------------|
| `AUTH_SUCCESS` | `{ deviceId, userId }` | Authentication confirmed |
| `AUTH_ERROR` | `{ reason }` | Authentication rejected |
| `POLICY_PUSH` | `{ version, policies }` | Server-authoritative policy update |
| `HEARTBEAT_ACK` | `{ serverTime }` | Heartbeat acknowledgement |
| `COMMAND` | `{ commandId, type, payload, signature }` | Remote command dispatch |

---

## 4. Enrollment & Pairing Protocol

See [device-enrollment.md](../architecture/device-enrollment.md) for full detail.

### Summary Flow

```
Owner (Dashboard)
  │  POST /enrollment/create → { pairingCode: "FG-AB7Z9C", expiresAt, qrCodeUrl }
  ▼
Managed Device
  │  Scans QR or enters code
  │  POST /enrollment/claim { pairingCode, platform, osVersion }
  │  → { deviceId, accessToken, policyVersion, status: "ENROLLED_PROTECTED" }
  ▼
Server
  │  Stores device record with cryptographic deviceId
  │  Broadcasts DEVICE_ENROLLED event to Owner via WebSocket
  ▼
Device persists: deviceId, accessToken, policyVersion
```

**Critical properties:**
- Pairing code is a short-lived (5 minute) bootstrap credential only.
- After enrollment, device identity persists via `deviceId` + JWT.
- Reconnection after network change does not require re-pairing.
- Pairing code is one-time use — immediately invalidated upon claim.

---

## 5. Policy Version Protocol

Every policy update receives a monotonically increasing version number:

```
v40 → v41 → v42
```

**Rules:**
- A device MUST reject policy updates where `incomingVersion < currentVersion`.
- Devices store the current policy version locally.
- On reconnection, device sends `currentVersion` in heartbeat; server responds with `POLICY_PUSH` if server version is higher.
- Policy evaluation always uses the locally stored version when offline.

---

## 6. Usage Synchronization

Devices submit usage deltas via `POST /usage/sync`:

```json
{
  "deviceId": "dev_abc123",
  "usageDeltas": [
    {
      "targetValue": "youtube.com",
      "durationSeconds": 300,
      "date": "2026-08-15"
    }
  ]
}
```

**Idempotency:**
- Each delta may include an optional `eventId` for deduplication.
- Server uses `(deviceId, targetValue, date, eventId)` as uniqueness key.
- Duplicate submissions (e.g. after offline sync) are silently ignored.

---

## 7. Remote Command Security

Every command dispatched via `POST /commands/dispatch` or WebSocket `COMMAND` message is validated on the receiving device:

| Field | Validation Rule |
|-------|----------------|
| `commandId` | Unique UUID; checked for replay |
| `deviceId` | Must match enrolled device |
| `timestamp` | Must be within ±5 minutes of current time |
| `policyVersion` | Must match or be greater than device's current version |
| `type` | Must be one of the allowed predefined command types |
| `payload` | Validated against type-specific schema |
| `signature` | HMAC-SHA256 verified against device secret key |

**Allowed command types (closed set — no arbitrary shell execution):**
- `START_FOCUS`
- `STOP_FOCUS`
- `UPDATE_POLICY`
- `SYNC_POLICY`
- `REQUEST_STATUS`
- `REQUEST_DIAGNOSTICS`
- `REVOKE_DEVICE`

---

## 8. Offline Behavior Contract

When the device loses network connectivity:
1. Local policy continues to be enforced using the last-synchronized policy store.
2. Usage events are accumulated in the local event queue.
3. On reconnection, all queued events are submitted via `/usage/sync`.
4. Policy version is checked; if server has a newer version, `POLICY_PUSH` is received.
5. **The device NEVER pauses enforcement during offline periods.**

> [!IMPORTANT]
> Shared cross-device limits cannot be perfectly enforced when multiple devices are offline simultaneously. This is a documented limitation — see [offline-first.md](../architecture/offline-first.md).

---

## 9. Protection States & Health Reporting

Devices report their current state via `HEARTBEAT`:

| State | Meaning |
|-------|---------|
| `PROTECTED` | All enforcement subsystems active |
| `DEGRADED` | One or more subsystems inactive (e.g. VPN stopped) |
| `OFFLINE` | Device cannot reach server |
| `PERMISSION_REQUIRED` | A critical OS permission has been revoked |
| `POLICY_OUTDATED` | Device policy version is behind server |
| `REVOKED` | Device has been revoked by owner |
| `ERROR` | Unexpected runtime failure |

**Dashboard Rule**: A device must NEVER display `PROTECTED` when enforcement is actually unavailable.

---

## 10. Security Properties

| Property | Implementation |
|----------|---------------|
| Transport | TLS (WSS + HTTPS) in production |
| Authentication | Short-lived JWT access tokens |
| Device Credentials | 32-byte high-entropy device keys stored in platform Keystore/Keychain |
| Command Integrity | HMAC-SHA256 signed payloads |
| Replay Protection | Timestamp validation (±5 min) + commandId deduplication |
| Policy Integrity | Monotonic version checks prevent rollback attacks |
| Audit Trail | All significant events logged to `audit_logs` table |
| Privacy | Only hostnames, app IDs, and durations collected — never keystrokes, passwords, or content |
