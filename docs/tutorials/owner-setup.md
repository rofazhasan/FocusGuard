# Tutorial: Setting Up an Owner Account

In this tutorial, you will register a primary Account Owner, establish your Fleet Command Center, and configure your primary workstation as the master administrative node.

---

## Learning Objectives
By the end of this tutorial, you will understand:
- How owner credentials and cryptographic JWT tokens are issued.
- How the default owner device record is initialized in the database.
- How the Owner Command Center interacts with the real-time WebSocket event bus.

---

## Prerequisites
- Backend server running on `http://localhost:8080`.
- Web dashboard running on `http://localhost:3001`.

---

## 1. Registering the Owner Account

Account registration creates the root user record in the `users` table and issues a cryptographic JWT bearer token:

```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "owner@focusguard.local",
    "password": "StrongMasterPassword2026!"
  }'
```

### JSON Response:
```json
{
  "user": {
    "id": "7b8e51b1-2748-433a-bc82-5813589b218f",
    "email": "owner@focusguard.local"
  },
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

---

## 2. Registering the Primary Master Workstation

Register your primary workstation (e.g. MacBook Pro) with the `OWNER` role:

```bash
curl -X POST http://localhost:8080/api/v1/devices/register \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{
    "deviceName": "MacBook Pro 16\"",
    "platform": "MACOS",
    "osVersion": "macOS 15.0"
  }'
```

---

## 3. Connecting to the Live Event Bus

To receive real-time notifications when managed devices exceed budgets or enroll, open a WebSocket connection:

```javascript
const token = "<ACCESS_TOKEN>";
const ws = new WebSocket(`ws://localhost:8080/ws?token=${token}`);

ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  console.log("Received fleet event:", msg.event, msg.payload);
};
```

---

## Summary
You have established a secure Account Owner identity. You can now enroll secondary and child devices, author policies, and dispatch fleet commands.
