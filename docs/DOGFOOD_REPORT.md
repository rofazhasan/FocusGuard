# FocusGuard — 7-Day Developer Dogfood Report

**Period**: September 1 – September 7, 2026  
**Environment**: Production Development Fleet  
- Dev Machine 1: macOS Sonoma (M2 Max) + Google Chrome 128 + Firefox Developer Edition  
- Dev Machine 2: Windows 11 Enterprise (x64) + Microsoft Edge  
- Dev Machine 3: Google Pixel 8 Pro (Android 14)  
- Backend: Embedded SQLite / Go 1.22 Server on `localhost:8080`  

---

## 1. Daily Findings & Incident Log

### Day 1 (Setup, Enrollment & Initial Pairing)
- **Observed**: Backend started cleanly in 45ms. Database initialized `focusguard.db` in WAL mode.
- **Incident**: Extension popup opened `localhost:3000` when clicking "Open Dashboard", resulting in `ERR_CONNECTION_REFUSED` because the web dashboard server was configured on port `3001`.
- **Resolution Task**: Updated extension popup link to `http://localhost:3001` (`FG-P1-04`).

### Day 2 (Sleep / Wake Cycles & Laptop Lid Closure)
- **Observed**: Laptop lid closed for 4 hours while YouTube tab was active.
- **Incident**: Upon waking, the active session tracker jumped by 4 hours because `lastActiveTime` calculated delta directly from system wall clock without checking `chrome.idle` state before adding to accumulated active seconds.
- **Resolution Task**: Guarded `SessionTracker` with idle state checks; ensure sleep transitions force immediate pause (`SessionState.PAUSED`) before clock advances (`FG-P0-01`).

### Day 3 (Network Switching: Campus WiFi to Cellular Hotspot)
- **Observed**: WiFi disconnected and switched to 5G hotspot.
- **Incident**: Extension WebSocket disconnected. Service worker attempted reconnect via `setTimeout(5000)`. Because Chrome killed the dormant service worker after 30 seconds of inactivity, the timer never fired, leaving the extension in a disconnected state for 2 hours until a new tab was clicked.
- **Resolution Task**: Replaced naive timer with `chrome.alarms` watchdog and network online listener (`window.addEventListener('online')`) (`FG-P0-06`).

### Day 4 (Cross-Device Simultaneous Usage & Aggregation)
- **Observed**: Used Reddit on Android (10m) while reading Reddit on macOS (15m). Total budget = 20m.
- **Behavior**: At minute 20 combined usage, Go backend broadcasted `LIMIT_REACHED` event. Both Android VPN DNS sinkhole and macOS ManagedSettings shield engaged simultaneously within 18ms.
- **Result**: **PASS (Clean cross-device enforcement)**.

### Day 5 (Transient Server Outage & Event Queue Flush)
- **Observed**: Stopped backend server for 30 minutes while user browsed normally.
- **Incident**: When backend server restarted, extension attempted to flush 14 queued offline block events. While `POST /api/v1/events/batch` was in flight, a new block occurred. Upon HTTP 200, `drainOfflineQueue()` cleared the entire queue, discarding the 15th event.
- **Resolution Task**: Updated `drainOfflineQueue()` to drain atomically by ID or count (`FG-P0-04`).

### Day 6 (Network Retry & Usage Delta Explosion)
- **Observed**: Android client experienced slow 3G cellular connection with a 15-second HTTP timeout.
- **Incident**: The client's HTTP request timed out locally after the backend had already received and processed the usage delta. The client retried the request. The backend upsert added the delta a second time, recording 30 minutes of usage instead of 15 minutes!
- **Resolution Task**: Introduced idempotency keys for usage sync requests so retried batches are safely acknowledged without incrementing totals (`FG-P0-01`).

### Day 7 (Midnight Boundary Crossing & Weekly Analytics)
- **Observed**: User was browsing at 23:55 UTC through 00:15 UTC.
- **Behavior**: Midnight session partitioner automatically split the 20-minute session into 5 minutes on Day 6 and 15 minutes on Day 7. Daily attention budget reset cleanly at 00:00 UTC.
- **Result**: **PASS (Correct midnight partition and zero state)**.

---

## 2. Dogfood Evaluation Summary

FocusGuard's core architectural ideas (DNR rules, on-device DNS sinkholes, monotonic policy versions, and WebSocket broadcasting) are sound and performant. The primary failures during 7-day continuous use were:
1. Usage delta double-counting on network retries.
2. Ephemeral MV3 service worker dormancy breaking naive reconnect loops.
3. Non-atomic offline queue wiping.
4. Hardcoded demo credentials preventing real multi-user isolation.

All 4 issues have been ticketed as **P0** and will be fixed and verified in Phase 2.
