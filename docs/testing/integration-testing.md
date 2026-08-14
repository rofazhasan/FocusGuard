# Testing: Integration Tests

Integration tests validate the HTTP router, database transactions, and WebSocket event fan-out.

---

## 1. Running Integration Tests

```bash
cd backend
go test -v ./internal/health ./internal/devices ./internal/focus ./internal/analytics
```

---

## 2. Tested Integration Flows
- User registration $\rightarrow$ JWT generation $\rightarrow$ Authenticated route access.
- Usage delta sync $\rightarrow$ SQLite upsert $\rightarrow$ Threshold calculation $\rightarrow$ WebSocket `LIMIT_REACHED` emission.
- Remote command dispatch $\rightarrow$ Persistence in `remote_commands` $\rightarrow$ Audit logging in `audit_logs`.
