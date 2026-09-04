# FocusGuard Phase 2 Operational Runbook

## 1. Quick Start

### 1.1 Local Server Startup (SQLite Mode)
FocusGuard backend automatically runs in embedded SQLite WAL mode if PostgreSQL environment variables are not provided:
```bash
cd backend
go build -o bin/server cmd/server/main.go
./bin/server
```

Server endpoints will be active on `http://localhost:8080`.
- Health check: `GET http://localhost:8080/health`
- Readiness probe: `GET http://localhost:8080/ready`
- Real-time Gateway: `ws://localhost:8080/ws`

### 1.2 Running with PostgreSQL
```bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=focusguard
export DB_PASSWORD=focusguard_secret
export DB_NAME=focusguard_db
./scripts/db-reset.sh
./scripts/db-seed.sh
./backend/bin/server
```

## 2. Testing Procedures

### 2.1 Comprehensive Master Test Battery (All 8 Suites)
Runs all unit, cross-platform proof, and E2E verification suites:
```bash
bash tests/run_all_tests.sh
```

### 2.2 Adversarial QA Test Battery
Runs 13 hostile edge cases (domain spoofing, tab-switch rapid thrashing, conflict precedence):
```bash
node tests/qa_adversarial_suite.js
```

### 2.3 Phase 2 Master Vertical Slice E2E Test
Validates the complete 11-step pairing, reboot, reconnection, and revocation lifecycle:
```bash
node tests/e2e/pairing_e2e_test.js
```

### 2.4 Simulated Device Client Commands
Run the device test client against a running server:
```bash
# Check client status
node apps/device-test-client/index.js --status

# Start pairing with a session ID or 6-character code
node apps/device-test-client/index.js --pair FG-ABC123

# Send heartbeat with health telemetry
node apps/device-test-client/index.js --heartbeat

# Sync assigned attention policies
node apps/device-test-client/index.js --sync

# Clear stored credentials
node apps/device-test-client/index.js --clear
```

## 3. Database Operations

### 3.1 Health Check
```bash
bash scripts/db-healthcheck.sh
```

### 3.2 Reset & Migration Execution
```bash
bash scripts/db-reset.sh
```

### 3.3 Default Demo Seeding
```bash
bash scripts/db-seed.sh
```

## 4. Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| `HTTP 401 AUTH_INVALID` on `/auth/me` | Missing or expired JWT token | Call `/auth/login` or `/auth/refresh` to obtain a fresh access token. |
| `HTTP 403 DEVICE_REVOKED` | Device was revoked by account owner | Device cannot self-reactivate. Account owner must initiate a new pairing session. |
| `HTTP 409 PAIRING_INVALID_STATE` | Pairing session is not in `CREATED` or `PENDING_APPROVAL` | Generate a new pairing code via Dashboard. |
| `HTTP 410 PAIRING_EXPIRED` | 5-minute session expired | Generate a new pairing session code. |
| `HTTP 429 RATE_LIMIT_EXCEEDED` | Client exceeded login or pairing rate limits | Wait 60 seconds before retrying. |
| WebSocket connection dropped immediately | Revoked device connected to `/ws` | Verify device credentials against database registry. |
