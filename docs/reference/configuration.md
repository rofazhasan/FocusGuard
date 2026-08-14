# Environment Configuration Reference

FocusGuard services are configured via standard environment variables.

---

## Backend Server Configuration

| Variable | Type | Default | Description |
|---|---|---|---|
| `PORT` | Integer | `8080` | Port for HTTP REST API and WebSocket listener. |
| `JWT_SECRET` | String | `focusguard_super_secret_jwt_key_2026` | Cryptographic secret key used to sign and verify HMAC-SHA256 JWT tokens. |
| `DB_HOST` | String | *(empty)* | PostgreSQL server hostname. If omitted, embedded SQLite is initialized. |
| `DB_PORT` | Integer | `5432` | PostgreSQL server port. |
| `DB_USER` | String | *(empty)* | PostgreSQL database username. |
| `DB_PASSWORD` | String | *(empty)* | PostgreSQL database password. |
| `DB_NAME` | String | *(empty)* | PostgreSQL database name. |

---

## Web Dashboard Configuration

| Variable | Type | Default | Description |
|---|---|---|---|
| `PORT` | Integer | `3001` | Local web server port serving frontend static assets. |
