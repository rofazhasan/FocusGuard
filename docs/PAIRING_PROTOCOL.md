# FocusGuard Pairing Protocol Specification (Phase 2)

## 1. Overview
The FocusGuard Pairing Protocol establishes a cryptographic trust relationship between a new client device and an account owner without exposing credentials over insecure channels.

## 2. Dashboard Auth & Pairing Service Architecture

```
              ┌────────────────────┐
              │    DASHBOARD       │
              │    USER AUTH       │
              └─────────┬──────────┘
                        │
                        ▼
                   USER SESSION
                        │
       ┌────────────────┼─────────────────┐
       │                                  │
       ▼                                  ▼
 CREATE PAIRING                      MANAGE DEVICES
       │
       ▼
┌───────────────────────────────────────────────┐
│              PAIRING SERVICE                  │
│                                               │
│ CREATED → REQUESTED → PENDING → APPROVED      │
│                         │                     │
│                         ▼                     │
│                     ENROLLED                  │
│                         │                     │
│                         ▼                     │
│                      CONSUMED                 │
└───────────────────────────────────────────────┘
```

### State Machine Lifecycle Transitions
1. **User Authentication & Session Establishment**:
   - Owner authenticates via Argon2id (`POST /api/v1/auth/login`).
   - Server registers an active record in `user_sessions` with rotating refresh token hashes and returns a scoped Access Token (`Role: OWNER`).
2. **Branch A: Pairing Service Execution**:
   - `CREATED`: Dashboard calls `POST /api/v1/pairing/sessions`. Cloud generates a 5-minute session with high-entropy code `FG-XXXXXX` (stored server-side as SHA-256 hash `code_hash`).
   - `REQUESTED`: Client device generates Ed25519 keypair and submits public key with device metadata via `POST /api/v1/pairing/sessions/:id/request`.
   - `PENDING` (`PENDING_APPROVAL`): Cloud updates session status and dispatches `PAIRING_REQUEST_RECEIVED` WebSocket event to the Dashboard with device metadata for owner review.
   - `APPROVED`: Owner explicitly clicks "Approve & Enroll" calling `POST /api/v1/pairing/sessions/:id/approve`.
   - `ENROLLED`: Atomic database transaction commits device insertion into `devices`, stores `device_public_identities`, issues `device_credentials` ($v_1$), initializes `sync_cursors`, and writes audit log `DEVICE_ENROLLED`.
   - `CONSUMED`: Client polls `GET /api/v1/pairing/sessions/:id/status`, receives persistent `deviceToken`, and saves it to local `SecureCredentialStore`. The session is permanently marked `CONSUMED` (HTTP 410 on subsequent requests).
3. **Branch B: Fleet Device Management**:
   - `GET /api/v1/devices`: Live registry of enrolled devices with computed status (`ACTIVE`, `OFFLINE`, `REVOKED`), app version, policy version, and protection status.
   - `POST /api/v1/devices/:id/revoke`: Immediate revocation of device credentials with automatic WebSocket socket severance.

## 3. Core Security Invariants
- **No Permanent Pairing Codes**: Pairing codes are strictly short-lived (5 minutes default) and single-use.
- **Server-Side Hash Storage**: Plaintext pairing codes are never persisted; only their SHA-256 hash (`code_hash`) is stored in the database.
- **Client-Side Key Generation**: Clients generate asymmetric keypairs (Ed25519) on-device. The private key NEVER leaves the client.
- **Mandatory Explicit Owner Approval**: Devices submitting pairing requests enter `PENDING_APPROVAL` and cannot access any protected resource until the account owner explicitly reviews device metadata and approves.
- **Atomic Finalization**: Approval creates device records, links public identity, provisions persistent credentials, marks the session `APPROVED`, logs audit events, and broadcasts over WebSocket in an atomic database transaction.
- **Session Single-Use & Expiry**: Once consumed, subsequent attempts to reuse the session ID or code return HTTP 410 Gone.

## 4. Pairing Flow Sequence


```
Device (Client)                 FocusGuard Cloud                Owner Dashboard
      |                                 |                               |
      |                                 |<-- POST /pairing/sessions ----|
      |                                 |--- Session ID + FG-XXXX Code->|
      |                                 |                               |
  [Generate]                            |                               |
  [Ed25519 Keypair]                     |                               |
      |                                 |                               |
      |--- POST /pairing/sessions/----->|                               |
      |    :id/request (PublicKey, Meta)|                               |
      |                                 |-- WS: PAIRING_REQUEST_REC --->|
      |                                 |    (Review device details)    |
      |                                 |                               |
      |                                 |<-- POST /pairing/sessions/----|
      |                                 |    :id/approve                |
      |                                 |--- 200 OK (APPROVED) -------->|
      |                                 |                               |
      |--- GET /pairing/sessions/------>|                               |
      |    :id/status (Poll)            |                               |
      |<-- 200 OK (DeviceToken, ID) ----|                               |
      |                                 |                               |
  [Save to CredentialStore]             |                               |
  [State: ACTIVE]                       |                               |
      |                                 |                               |
  [REBOOT DEVICE]                       |                               |
  [Load CredentialStore]                |                               |
      |--- POST /devices/:id/heartbeat->| (No re-pairing needed)        |
      |<-- 200 OK (Acknowledged) -------|                               |
```

## 4. API Endpoints

### 4.1 Create Pairing Session
`POST /api/v1/pairing/sessions`
- **Auth**: Bearer User JWT
- **Body**: `{ "deviceName": "Optional expected name" }`
- **Response**:
```json
{
  "sessionId": "a1ef1426-fb04-4909-931f-7410d9070ebf",
  "pairingCode": "FG-T2XSAU",
  "qrPayload": "focusguard://pair?session=a1ef1426-fb04-4909-931f-7410d9070ebf",
  "status": "CREATED",
  "expiresAt": "2026-09-04T08:30:00Z",
  "expiresInSec": 300
}
```

### 4.2 Submit Pairing Request
`POST /api/v1/pairing/sessions/:id/request`
- **Auth**: Public (Rate-limited: 30 req/min)
- **Body**:
```json
{
  "deviceName": "Pixel 8 Pro",
  "platform": "ANDROID",
  "clientType": "ANDROID_APP",
  "appVersion": "2.0.0",
  "publicKey": "-----BEGIN PUBLIC KEY-----\n...",
  "keyAlgorithm": "Ed25519"
}
```
- **Response**: HTTP 200 `{ "sessionId": "...", "status": "PENDING_APPROVAL" }`

### 4.3 Approve Pairing Request
`POST /api/v1/pairing/sessions/:id/approve`
- **Auth**: Bearer User JWT (Owner only)
- **Response**: HTTP 200 `{ "status": "APPROVED", "deviceId": "...", "deviceToken": "..." }`

### 4.4 Reject Pairing Request
`POST /api/v1/pairing/sessions/:id/reject`
- **Auth**: Bearer User JWT (Owner only)
- **Response**: HTTP 200 `{ "status": "REJECTED" }`

### 4.5 Poll Session Status
`GET /api/v1/pairing/sessions/:id/status`
- **Auth**: Public
- **Response**: HTTP 200
```json
{
  "status": "APPROVED",
  "deviceId": "e98abefa-c4eb-46d2-9f98-aefe574ca62f",
  "deviceToken": "eyJhbGciOiJIUzI1Ni...",
  "serverTime": "2026-09-04T08:25:00Z"
}
```
Once retrieved, session transitions to `CONSUMED`.
