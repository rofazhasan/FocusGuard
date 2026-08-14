# How-To: Manage Fleet Devices & Roles

This guide explains how to view enrolled hardware, inspect device roles, and scope individual policies.

---

## 1. Device Roles

FocusGuard defines three distinct device roles:

| Role | Description | Capabilities |
|---|---|---|
| `OWNER` | Master administrative workstation | Can create/edit/delete policies, generate pairing codes, dispatch remote commands, and view fleetwide analytics. |
| `MANAGED_USER` | Enrolled child, student, or supervised device | Receives and strictly enforces remote policies. Shows transparent status (*"This device is managed by FocusGuard"*). Cannot delete cloud policies. |
| `PERSONAL` | Secondary personal device | Shares aggregate budget with owner's account. Allows local preferences while adhering to global limits. |

---

## 2. Listing Enrolled Devices

Query all enrolled devices for your account:

```bash
curl -s http://localhost:8080/api/v1/devices \
  -H "Authorization: Bearer <OWNER_TOKEN>" | jq .
```

### Example Response:
```json
[
  {
    "id": "00000000-0000-0000-0000-000000000002",
    "deviceName": "MacBook Pro 16\"",
    "platform": "MACOS",
    "osVersion": "macOS 15.0",
    "role": "OWNER",
    "isManaged": false,
    "status": "ONLINE",
    "policyVersion": 2
  },
  {
    "id": "4afd6e70-4e07-4033-ae19-7b8b58752cba",
    "deviceName": "Student Pixel Tablet",
    "platform": "ANDROID",
    "osVersion": "Android 15 (API 35)",
    "role": "MANAGED_USER",
    "isManaged": true,
    "status": "ONLINE",
    "policyVersion": 2
  }
]
```

---

## 3. Scoping a Policy to a Single Device

To apply a restriction to *only* the student tablet while leaving the owner's workstation unaffected:

```bash
curl -X POST http://localhost:8080/api/v1/policies \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <OWNER_TOKEN>" \
  -d '{
    "name": "Tablet Bedtime Lockout",
    "limitSeconds": 0,
    "period": "DAILY",
    "enforcementMode": "BLOCK",
    "targets": [
      { "targetType": "CATEGORY", "targetValue": "GAMING" }
    ],
    "assignedDeviceIds": ["4afd6e70-4e07-4033-ae19-7b8b58752cba"]
  }'
```
