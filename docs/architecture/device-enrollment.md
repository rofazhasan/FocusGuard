# Consent-Based Device Enrollment Architecture

FocusGuard replaces hidden MDM installation profiles with a **transparent, consent-driven cryptographic enrollment protocol**.

---

## 1. Enrollment Security Requirements

1. **Explicit Consent**: A device can only be bound to an account if an operator physically enters the ephemeral pairing code on that device.
2. **Short-Lived Cryptographic Tokens**: Pairing codes are 6 alphanumeric characters prefixed by `FG-` (e.g. `FG-8492QW`), generated via secure random bytes (`crypto/rand`), and expire strictly after 300 seconds (5 minutes).
3. **Single-Claim Guarantee**: Once a pairing code is claimed, `is_claimed` is set to `1` in an atomic SQL transaction to prevent race conditions and replay attacks.

---

## 2. Protocol Sequence Diagram

```mermaid
sequenceDiagram
    autonumber
    actor Owner as Account Owner
    participant Web as Web Dashboard
    participant API as FocusGuard API
    participant DB as SQLite / Postgres
    participant Hub as WebSocket Hub
    actor Device as Managed Device (Android/Mac)

    Owner->>Web: Click "+ Pair New Device"
    Web->>API: POST /api/v1/enrollment/create { deviceName, role }
    API->>DB: INSERT into enrollment_tokens (pairing_code, TTL 300s)
    API-->>Web: Return pairingCode ("FG-8492") & expiresAt
    Web-->>Owner: Display Code & QR Code

    Owner->>Device: Enters "FG-8492" on Managed Device
    Device->>API: POST /api/v1/enrollment/claim { pairingCode, platform, osVersion }
    API->>DB: Verify code, TTL, and mark is_claimed = 1
    API->>DB: INSERT into devices (role, is_managed, status: ONLINE)
    API->>Hub: Broadcast DEVICE_ENROLLED { deviceId, deviceName, role }
    Hub-->>Web: Live notification: "New device enrolled"
    API-->>Device: Return Device JWT Access Token & PolicyBundle
    Device->>Device: Cache policy in local Room/CoreData DB
```
