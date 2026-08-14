# Quick Start Guide

Spin up a complete FocusGuard multi-device environment locally in under 2 minutes.

---

## Step 1: Start the Backend Server

Open a terminal window and start the Go server:

```bash
cd backend
go run cmd/server/main.go
```

**Expected Output**:
```
{"level":"INFO","msg":"Starting FocusGuard Multi-Device Production Server..."}
{"level":"INFO","msg":"FocusGuard persistent SQLite database initialized successfully","path":".../focusguard.db"}
{"level":"INFO","msg":"Starting Real macOS Activity Collector daemon","platform":"darwin"}
{"level":"INFO","msg":"FocusGuard Multi-Device Server running","port":"8080"}
```

---

## Step 2: Start the Web Command Center

Open a second terminal window:

```bash
cd apps/web
PORT=3001 node server.js
```

**Expected Output**:
```
FocusGuard Web Application running at http://localhost:3001
```

---

## Step 3: Access the Fleet Command Center

1. Open your browser and navigate to **[http://localhost:3001](http://localhost:3001)**.
2. The dashboard automatically authenticates with the local development instance (`demo@focusguard.local`).
3. Observe the **Fleet Command Center** showing:
   - **Enrolled Devices**: MacBook Pro (Owner Node) & Student Pixel Tablet (Managed Node).
   - **Live Active Target**: Real-time foreground application tracking on macOS.
   - **Active Policies**: Initial 30-minute YouTube daily budget.

---

## Step 4: Verify Cross-Device Enforcement Ingestion

1. In the **Shared Attention Limit & Ingestion Test** section:
   - Click **+ 5m YouTube** under *MacBook Pro*.
   - Click **+ 5m YouTube** under *Student Pixel Tablet*.
2. Observe the **Combined Attention Budget** progress bar incrementing in real-time.
3. Repeat until the total reaches **30 minutes**.
4. The system will broadcast `LIMIT_REACHED` over WebSockets and display the **FocusGuard Lockout Screen**, demonstrating simultaneous multi-device restriction.
