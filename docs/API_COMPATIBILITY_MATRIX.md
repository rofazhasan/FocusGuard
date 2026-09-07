# FocusGuard API Compatibility Matrix & Route Specification

**Document ID**: `FG-API-006`  
**Version**: `1.0.0-PROD`  
**Base URL**: `http://localhost:8080/api/v1`  
**WebSocket URL**: `ws://localhost:8080/ws`  
**Status**: APPROVED SPECIFICATION  

---

## 1. Authentication & Security Scopes

FocusGuard enforces three distinct authentication tiers:
1. **`PUBLIC`**: Unauthenticated endpoints (Registration, Login, Initial Pairing handshake, Liveness checks). Subject to strict IP and token-bucket rate limiting.
2. **`USER_JWT` (`Bearer <userAccessToken>`)**: Account owner operations. Full control over tenant fleet, policy authoring, device pairing approval, and remote revocation.
3. **`DEVICE_JWT` (`Bearer <deviceToken>`)**: Cryptographically enrolled client devices. Strictly scoped to self-telemetry, policy synchronization, heartbeat, and batch event ingestion. Cannot access admin or cross-device routes.

---

## 2. Comprehensive Endpoint Matrix

| Method | Endpoint | Auth Scope | Consumed By | Request Body | Success Response | Error Codes |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **GET** | `/health` | `PUBLIC` | Load Balancers, Monitoring | None | `{ "status": "UP", "version": "1.0.0", "timestamp": "..." }` | `503 Service Unavailable` |
| **GET** | `/ready` | `PUBLIC` | Kubernetes, Docker Healthcheck | None | `{ "status": "READY", "database": "UP" }` | `503 (Database unreachable)` |
| **POST** | `/api/v1/auth/register` | `PUBLIC` (Rate-limited) | Web Dashboard, Onboarding | `{ email, password }` | `201 Created` `{ accessToken, refreshToken, user }` | `400, 409 (Email exists), 429` |
| **POST** | `/api/v1/auth/login` | `PUBLIC` (Rate-limited) | Web Dashboard, Onboarding | `{ email, password }` | `200 OK` `{ accessToken, refreshToken, user }` | `401 (Invalid creds), 429` |
| **POST** | `/api/v1/auth/refresh` | `PUBLIC` | All Clients | `{ refreshToken }` | `200 OK` `{ accessToken, refreshToken }` | `401 (Expired/Invalid)` |
| **POST** | `/api/v1/auth/logout` | `USER_JWT` | Web Dashboard | None | `200 OK` `{ success: true }` | `401 Unauthorized` |
| **GET** | `/api/v1/auth/me` | `USER_JWT` | Web Dashboard | None | `200 OK` `{ id, email, role, createdAt }` | `401 Unauthorized` |
| **POST** | `/api/v1/pairing/sessions` | `USER_JWT` | Web Dashboard | `{ metadata }` (optional) | `201 Created` `{ sessionId, pairingCode, expiresAt }` | `401, 500` |
| **POST** | `/api/v1/pairing/sessions/{id}/request` | `PUBLIC` (Rate-limited) | Win, Mac, Android, Ext | `{ deviceName, platform, clientType, appVersion, publicKey, keyAlgorithm }` | `200 OK` `{ sessionId, status: "PENDING_APPROVAL" }` | `400, 404, 409 (Cancelled), 410 (Consumed)` |
| **POST** | `/api/v1/pairing/request` | `PUBLIC` (Rate-limited) | Win, Mac, Android, Ext | `{ pairingCode, deviceName, platform, clientType, appVersion, publicKey }` | `200 OK` `{ sessionId, status: "PENDING_APPROVAL" }` | `400, 404 (Invalid code), 429` |
| **GET** | `/api/v1/pairing/sessions/{id}/status` | `PUBLIC` | Win, Mac, Android, Ext | None | `200 OK` `{ status, deviceId, deviceToken, serverTime }` | `404 Not Found` |
| **POST** | `/api/v1/pairing/sessions/{id}/approve` | `USER_JWT` | Web Dashboard | None | `200 OK` `{ approved: true, deviceId, deviceToken }` | `403 (Cross-tenant), 404, 409` |
| **POST** | `/api/v1/pairing/sessions/{id}/reject` | `USER_JWT` | Web Dashboard | None | `200 OK` `{ rejected: true }` | `403, 404` |
| **POST** | `/api/v1/pairing/sessions/{id}/cancel` | `USER_JWT` | Web Dashboard | None | `200 OK` `{ cancelled: true }` | `403, 404` |
| **GET** | `/api/v1/devices` | `USER_JWT` | Web Dashboard | None | `200 OK` `[ { id, deviceName, platform, status, lastSeenAt, ... } ]` | `401 Unauthorized` |
| **POST** | `/api/v1/devices/{id}/heartbeat` | `DEVICE_JWT` | Win, Mac, Android, Ext | `{ appVersion, protectionState, policyVersion }` | `200 OK` `{ acknowledged: true, deviceStatus, latestPolicyVersion, serverTime }` | `401, 403 (DEVICE_REVOKED), 404` |
| **POST** | `/api/v1/devices/{id}/revoke` | `USER_JWT` | Web Dashboard | None | `200 OK` `{ success: true, deviceId, status: "REVOKED", revokedAt }` | `403 (Forbidden), 404` |
| **GET** | `/api/v1/device/policies/sync` | `DEVICE_JWT` | Win, Mac, Android, Ext | Query: `?cursor=<cur>` | `200 OK` `{ policyVersion, policies, serverTime, syncCursor, status }` | `401, 403 (DEVICE_REVOKED)` |
| **POST** | `/api/v1/policies` | `USER_JWT` | Web Dashboard | `{ name, limitSeconds, period, enforcementMode, targets, assignedDeviceIds }` | `201 Created` `{ id, version: 1, ... }` | `400 (Bad payload), 401` |
| **GET** | `/api/v1/policies` | `USER_JWT` | Web Dashboard | None | `200 OK` `[ { id, name, version, targets, ... } ]` | `401 Unauthorized` |
| **DELETE** | `/api/v1/policies/{id}` | `USER_JWT` | Web Dashboard | None | `200 OK` `{ status: "DELETED", id }` | `401, 404` |
| **POST** | `/api/v1/usage/sync` | `DEVICE_JWT` | Win, Mac, Android, Ext | `{ deviceId, syncSequence, usageDeltas: [ { targetValue, durationSeconds, date } ] }` | `200 OK` `{ serverTimestamp, syncSequence, aggregatedTotal, limitsReached }` | `401, 403 (DEVICE_REVOKED)` |
| **POST** | `/api/v1/events/batch` | `DEVICE_JWT` | Win, Mac, Android, Ext | `{ events: [ { id, eventType, domain, reason, timestamp, metadata } ] }` | `200 OK` `{ success: true, processed, duplicates }` | `400 (Max 100), 401, 403 (DEVICE_REVOKED)` |
| **POST** | `/api/v1/commands/dispatch` | `USER_JWT` | Web Dashboard | `{ deviceId, commandType, durationSec, payload }` | `201 Created` `{ commandId, deviceId, status: "DISPATCHED", expiresAt }` | `400, 401` |
| **GET** | `/api/v1/health/fleet` | `USER_JWT` | Web Dashboard | None | `200 OK` `[ { deviceId, status, protectionState, protectionScore, ... } ]` | `401 Unauthorized` |
| **POST** | `/api/v1/health/diagnostics` | `USER_JWT` | Web Dashboard | None | `200 OK` `{ overallStatus, passCount, totalCount, tests: [...] }` | `401 Unauthorized` |
| **GET** | `/api/v1/analytics/daily` | `USER_JWT` | Web Dashboard | Query: `?date=YYYY-MM-DD` | `200 OK` `{ totalFocusMinutes, budgetUsedMinutes, topApplications, ... }` | `401 Unauthorized` |
| **POST** | `/api/v1/focus/start` | `USER_JWT` | Web Dashboard | `{ durationMinutes, targetDeviceIds }` | `200 OK` `{ sessionId, isFocusActive: true, expiresAt }` | `400, 401` |
| **POST** | `/api/v1/focus/end` | `USER_JWT` | Web Dashboard | None | `200 OK` `{ isFocusActive: false }` | `401 Unauthorized` |
| **GET** | `/ws` | `TOKEN_QUERY` | Win, Mac, Android, Ext, Web | `?token=<userOrDeviceToken>` | `101 Switching Protocols` (Duplex JSON stream) | `401 (Invalid token), 403 (DEVICE_REVOKED)` |

---

## 3. Platform Client Adoption Matrix

| Platform | Primary Protocols | Heartbeat Period | Offline Persistence | Credential Vault |
| :--- | :--- | :--- | :--- | :--- |
| **Windows Client** | REST (`/api/v1/`) + WSS (`/ws`) | 60 seconds | SQLite WAL (`focusguard_client.db`) | Windows DPAPI / Credential Manager |
| **macOS Client** | REST (`/api/v1/`) + WSS (`/ws`) | 60 seconds | SQLite WAL (`focusguard_macos.db`) | Apple Keychain Services |
| **Android Client** | REST (`/api/v1/`) + WSS (`/ws`) | 90 seconds | Room DB (SQLite) | Android EncryptedSharedPreferences / Keystore |
| **Browser Extension**| REST (`/api/v1/`) + WSS (`/ws`) | 120 seconds | `chrome.storage.local` / IndexedDB | Extension Isolated Storage |
| **Web Dashboard** | REST (`/api/v1/`) + WSS (`/ws`) | N/A (Event Driven) | `localStorage` (Auth tokens only) | Browser Session Context |
