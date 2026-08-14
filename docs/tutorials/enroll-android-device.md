# Tutorial: Enrolling an Android Device

This tutorial guides you through enrolling a physical or emulated Android device (running Android 10 to Android 15) into an existing FocusGuard account.

---

## Learning Objectives
- Understanding the 6-character pairing code claim protocol.
- Configuring Android `UsageStatsManager` for foreground app tracking.
- Setting up the local `VpnService` network loopback for domain sinkholing.
- Storing synchronized policies in the local Room database for offline enforcement.

---

## Step 1: Issue the Pairing Token

On the Owner machine, execute:
```bash
curl -X POST http://localhost:8080/api/v1/enrollment/create \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <OWNER_TOKEN>" \
  -d '{
    "deviceName": "Child Pixel Tablet",
    "targetRole": "MANAGED_USER"
  }'
```

Output:
```json
{
  "id": "e2e9c20a-5b12-4c9f-b98a-129486c91b5a",
  "pairingCode": "FG-9842HQ",
  "deviceName": "Child Pixel Tablet",
  "targetRole": "MANAGED_USER",
  "expiresAt": "2026-08-14T17:45:00Z",
  "expiresInSec": 300
}
```

---

## Step 2: Claim Pairing Code on Android

The Android client submits the code to the `/enrollment/claim` endpoint:

```bash
curl -X POST http://localhost:8080/api/v1/enrollment/claim \
  -H "Content-Type: application/json" \
  -d '{
    "pairingCode": "FG-9842HQ",
    "deviceName": "Child Pixel Tablet",
    "platform": "ANDROID",
    "osVersion": "Android 15 (API 35)"
  }'
```

### Response:
```json
{
  "deviceId": "4afd6e70-4e07-4033-ae19-7b8b58752cba",
  "userId": "7b8e51b1-2748-433a-bc82-5813589b218f",
  "deviceName": "Child Pixel Tablet",
  "platform": "ANDROID",
  "role": "MANAGED_USER",
  "isManaged": true,
  "policyVersion": 1,
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "status": "ENROLLED_PROTECTED"
}
```

---

## Step 3: Configure Android OS Permissions

### 1. Usage Stats Permission
Open `Settings > Apps > Special app access > Usage access > FocusGuard` and toggle **Allow usage tracking**. This allows the foreground session worker to query:
```kotlin
val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
val events = usageStatsManager.queryEvents(startTime, endTime)
```

### 2. VPN Tunnel Authorization
When prompted by Android's native system dialog (`"FocusGuard wants to set up a VPN connection"`), tap **OK**.
- The VPN interface establishes a local TUN file descriptor (`10.0.0.2`).
- No external network servers are used; DNS packets are inspected locally via the RFC 1035 UDP parser.

---

## Summary
The Android device is now authenticated, running local background enforcement, and actively protected even when completely disconnected from the cloud.
