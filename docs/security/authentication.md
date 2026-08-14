# Security: Authentication

FocusGuard implements stateless token-based authentication using RFC 7519 JWT standards.

---

## 1. Token Issuance Lifecycle

1. Client sends credentials via `POST /api/v1/auth/login`.
2. Server verifies `bcrypt` hash in `users` table.
3. Server generates:
   - **Access Token**: Short-lived (15 minutes).
   - **Refresh Token**: Long-lived (30 days).
4. Protected API endpoints validate token signature and expiration via Chi middleware.
