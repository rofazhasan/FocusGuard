# REST API Reference

FocusGuard exposes a versioned RESTful API under `/api/v1`.

---

## Base URLs
- **Local Development**: `http://localhost:8080/api/v1`
- **Health Endpoint**: `http://localhost:8080/health`
- **WebSocket Endpoint**: `ws://localhost:8080/ws`

---

## 1. Authentication Endpoints

### `POST /auth/register`
Creates a new user account and returns JWT credentials.
- **Request Body**:
  ```json
  { "email": "user@example.com", "password": "secure_password" }
  ```
- **Response `201 Created`**:
  ```json
  {
    "user": { "id": "uuid", "email": "user@example.com" },
    "accessToken": "jwt_token",
    "refreshToken": "jwt_token"
  }
  ```

### `POST /auth/login`
Authenticates existing user and issues JWT.

---

## 2. Device Enrollment Endpoints

### `POST /enrollment/create` *(Requires Auth)*
Generates a 6-character pairing code with 5-minute TTL.
- **Request Body**:
  ```json
  { "deviceName": "Student Tablet", "targetRole": "MANAGED_USER" }
  ```
- **Response `201 Created`**:
  ```json
  {
    "id": "uuid",
    "pairingCode": "FG-8492QW",
    "deviceName": "Student Tablet",
    "targetRole": "MANAGED_USER",
    "expiresAt": "2026-08-14T17:45:00Z",
    "expiresInSec": 300,
    "qrCodeUrl": "focusguard://enroll?code=FG-8492QW&owner=user@example.com"
  }
  ```

### `POST /enrollment/claim` *(Public)*
Claims a pairing code from the target hardware.
- **Request Body**:
  ```json
  {
    "pairingCode": "FG-8492QW",
    "deviceName": "Student Tablet",
    "platform": "ANDROID",
    "osVersion": "Android 15"
  }
  ```

---

## 3. Policy Management Endpoints

### `POST /policies` *(Requires Auth)*
Creates a new scoped attention policy.
- **Request Body**:
  ```json
  {
    "name": "Social Media Limit",
    "limitSeconds": 1800,
    "period": "DAILY",
    "timezone": "UTC",
    "enforcementMode": "BLOCK",
    "targets": [
      { "targetType": "CATEGORY", "targetValue": "SOCIAL" }
    ],
    "assignedDeviceIds": ["device_uuid_1"]
  }
  ```

### `GET /policies` *(Requires Auth)*
Lists all policies for the authenticated account.

### `DELETE /policies/{id}` *(Requires Auth)*
Deletes a policy across all assigned devices.

---

## 4. Usage & Analytics Endpoints

### `POST /usage/sync` *(Requires Auth)*
Ingests discrete usage increments from devices.
- **Request Body**:
  ```json
  {
    "deviceId": "device_uuid",
    "syncSequence": 12,
    "usageDeltas": [
      {
        "targetType": "WEBSITE",
        "targetValue": "youtube.com",
        "durationSeconds": 300,
        "date": "2026-08-14"
      }
    ]
  }
  ```

### `GET /analytics/daily` *(Requires Auth)*
Returns aggregated focus minutes, budget utilization, and top applications.

---

## 5. Remote Commands & Audit

### `POST /commands/dispatch` *(Requires Auth)*
Issues an idempotent remote command (`REMOTE_FOCUS_START`, `POLICY_UPDATE`).

### `GET /audit/logs` *(Requires Auth)*
Retrieves immutable event history.
