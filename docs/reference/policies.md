# Policy Schema & Target Reference

This document defines the schema for policy objects, target enumerations, and enforcement actions.

---

## 1. Policy JSON Schema

```json
{
  "id": "uuid",
  "userId": "uuid",
  "name": "string",
  "limitSeconds": 1800,
  "period": "DAILY | WEEKLY",
  "scheduleCron": "string (optional)",
  "timezone": "UTC | America/New_York | Asia/Dhaka",
  "enforcementMode": "BLOCK | FOCUS_ONLY | SCHEDULED_BLOCK",
  "isEnabled": true,
  "version": 1,
  "targets": [
    {
      "id": "uuid",
      "policyId": "uuid",
      "targetType": "WEBSITE | APP | CATEGORY",
      "targetValue": "string"
    }
  ],
  "assignedDeviceIds": ["uuid"],
  "createdAt": "2026-08-14T17:19:53Z",
  "updatedAt": "2026-08-14T17:19:53Z"
}
```

---

## 2. Target Types & Supported Values

| `targetType` | Example `targetValue` | Matching Behavior |
|---|---|---|
| `WEBSITE` | `youtube.com` | Matches `youtube.com`, `www.youtube.com`, `m.youtube.com`. Never matches `notyoutube.com`. |
| `APP` | `com.discord` / `Discord` | Matches Android application package name or macOS application bundle ID / display name. |
| `CATEGORY` | `SOCIAL`, `VIDEO`, `GAMING` | Evaluates against built-in domain and application category taxonomy. |
