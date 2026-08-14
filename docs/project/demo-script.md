# Demonstration & Evaluation Script

This script provides an exact 5-minute walkthrough for academic supervisors and evaluators to test and verify FocusGuard live.

---

## 1. System Initialization (0:00 - 1:00)
1. Start the Go backend:
   ```bash
   cd backend && go run cmd/server/main.go
   ```
2. Start the web server:
   ```bash
   cd apps/web && PORT=3001 node server.js
   ```
3. Open `http://localhost:3001` in your browser.
4. Point out the live **Fleet Command Center**, showing authenticated owner status and real-time macOS active application monitoring in the top banner.

---

## 2. Consent-Based Device Pairing (1:00 - 2:00)
1. Click **📱 + Pair New Device**.
2. Explain the 6-character cryptographic token generation with the 5-minute countdown timer.
3. Click **Simulate Device Claim** to execute the simulated Android claim handshake.
4. Point out the live `DEVICE_ENROLLED` alert and observe the newly enrolled device appear under **Enrolled Fleet Devices**.

---

## 3. Cross-Device Quota Aggregation & Shared Lockout (2:00 - 3:30)
1. In the **Shared Attention Limit & Ingestion Test** section:
   - Click **+ 5m YouTube** on *MacBook Pro*.
   - Click **+ 5m YouTube** on *Student Pixel Tablet*.
2. Show that both devices contribute to the unified cloud aggregation ledger.
3. Continue clicking until the combined total reaches 30 minutes.
4. Demonstrate the simultaneous **FocusGuard Lockout Screen** triggered across all enrolled nodes.

---

## 4. Remote Focus Lockdown Dispatch (3:30 - 4:30)
1. Select **45m** under **Dispatch Remote Focus Session**.
2. Click **DISPATCH REMOTE FOCUS (45m)**.
3. Observe the live timer engagement, WebSocket fan-out, and the audit ledger recording the action.
4. Toggle to the **📱 Managed Device View** to show how the student tablet renders active policy status transparently.

---

## 5. Technical Proofs & Test Suite (4:30 - 5:00)
Run the automated test suite in the terminal to demonstrate 100% test passing:
```bash
cd backend && go test -v ./...
```
