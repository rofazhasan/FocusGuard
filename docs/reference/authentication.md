# Authentication & Authorization Reference

FocusGuard secures API endpoints using JSON Web Tokens (JWT) compliant with RFC 7519.

---

## 1. Token Structure & Claims

Tokens use the `HS256` signing algorithm.

### Claims Payload:
```json
{
  "sub": "00000000-0000-0000-0000-000000000001",
  "email": "owner@focusguard.local",
  "role": "OWNER",
  "iat": 1786727993,
  "exp": 1786728893
}
```

- `sub`: Unique UUID of the authenticated user or device.
- `role`: Authorization scope (`OWNER`, `MANAGED_USER`, `DEVICE`).
- `exp`: Expiration timestamp (Access tokens: 15 minutes; Refresh tokens: 30 days).

---

## 2. Authorization Header

All protected REST requests must include the bearer token:
```http
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

For WebSocket connections, pass the token as a query parameter during the HTTP upgrade handshake:
```
ws://localhost:8080/ws?token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```
