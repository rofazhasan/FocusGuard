# FocusGuard API & Event Specification

## 1. REST API Endpoints

### Authentication
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`

### Devices
- `POST /api/v1/devices/register`
- `GET /api/v1/devices`
- `DELETE /api/v1/devices/{id}`

### Policies
- `POST /api/v1/policies`
- `GET /api/v1/policies`
- `PUT /api/v1/policies/{id}`
- `DELETE /api/v1/policies/{id}`

### Usage & Synchronization
- `POST /api/v1/usage/sessions`
- `POST /api/v1/usage/sync`

### Analytics
- `GET /api/v1/analytics/daily`
- `GET /api/v1/analytics/weekly`

### System Health
- `GET /health`

---

## 2. WebSocket Real-Time Event Protocol

Connecting endpoint: `/ws`

### Client -> Server Handshake
Headers: `Authorization: Bearer <JWT_ACCESS_TOKEN>`

### Downstream Server Events

#### 1. `POLICY_UPDATED`
```json
{
  "event": "POLICY_UPDATED",
  "payload": {
    "policyId": "uuid",
    "version": 2,
    "name": "Social Media Limit",
    "limitSeconds": 1800,
    "enforcementMode": "BLOCK"
  }
}
```

#### 2. `LIMIT_REACHED`
```json
{
  "event": "LIMIT_REACHED",
  "payload": {
    "policyId": "uuid",
    "targetValue": "com.google.android.youtube",
    "currentUsageSeconds": 1800,
    "limitSeconds": 1800
  }
}
```

#### 3. `SYNC_REQUIRED`
```json
{
  "event": "SYNC_REQUIRED",
  "payload": {
    "reason": "STALE_LOCAL_POLICY_VERSION"
  }
}
```
