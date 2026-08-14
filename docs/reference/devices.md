# Device Model & State Reference

This document specifies the data model and state machine for enrolled hardware nodes.

---

## 1. Device Schema

```json
{
  "id": "uuid",
  "userId": "uuid",
  "deviceName": "MacBook Pro 16\"",
  "platform": "MACOS | ANDROID",
  "osVersion": "macOS 15.0 / Android 15 (API 35)",
  "role": "OWNER | MANAGED_USER | PERSONAL",
  "isManaged": false,
  "status": "ONLINE | OFFLINE | PENDING_PAIRING | REVOKED",
  "policyVersion": 1,
  "lastSeenAt": "2026-08-14T17:19:53Z",
  "createdAt": "2026-08-14T17:19:53Z"
}
```

---

## 2. Device State Lifecycle

```
[ PENDING_PAIRING ]
         │
         ▼ (Pairing Code Claimed via /enrollment/claim)
    [ ONLINE ] ◄── (Heartbeat & Telemetry Active)
         │   ▲
         │   │ (Connection dropped / restored)
         ▼   │
   [ OFFLINE ] (Autonomous Local Enforcement)
         │
         ▼ (Owner initiates deletion)
   [ REVOKED ]
```
