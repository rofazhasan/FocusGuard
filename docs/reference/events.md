# WebSocket Event Reference

FocusGuard broadcasts real-time system events over persistent WebSocket connections (`ws://localhost:8080/ws`).

---

## Event Catalog

### 1. `USAGE_TICK`
Published when active application or domain usage increments.
```json
{
  "event": "USAGE_TICK",
  "payload": {
    "targetValue": "youtube.com",
    "durationSeconds": 3,
    "currentTotalSeconds": 480
  }
}
```

### 2. `LIMIT_REACHED`
Published when cumulative cross-device usage exhausts a policy budget.
```json
{
  "event": "LIMIT_REACHED",
  "payload": {
    "policyId": "uuid",
    "targetValue": "youtube.com",
    "limitSeconds": 1800,
    "currentUsage": 1803
  }
}
```

### 3. `DEVICE_ENROLLED`
Published when a new managed hardware node completes the claim handshake.
```json
{
  "event": "DEVICE_ENROLLED",
  "payload": {
    "deviceId": "uuid",
    "deviceName": "Student Pixel Tablet",
    "platform": "ANDROID",
    "role": "MANAGED_USER",
    "isManaged": true,
    "status": "ONLINE"
  }
}
```

### 4. `POLICY_UPDATED` / `POLICY_DELETED`
Published when policy rules are modified or removed.
```json
{
  "event": "POLICY_UPDATED",
  "payload": {
    "policyId": "uuid",
    "policyName": "Gaming Restriction",
    "version": 2,
    "limitSeconds": 1200,
    "assignedNodes": ["uuid"]
  }
}
```

### 5. `REMOTE_COMMAND`
Published to deliver immediate actions (e.g. remote focus lockdown) to targeted devices.
```json
{
  "event": "REMOTE_COMMAND",
  "payload": {
    "commandId": "uuid",
    "deviceId": "uuid",
    "commandType": "REMOTE_FOCUS_START",
    "issuedAt": 1786727993,
    "expiresAt": 1786731593,
    "payload": { "durationMinutes": 45 }
  }
}
```
