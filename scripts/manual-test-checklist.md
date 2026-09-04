# FocusGuard Phase 1 — Real Browser Test Checklist

This checklist defines the manual validation protocol for FocusGuard Phase 1 on Google Chrome (Developer Mode unpacked extension), Brave, and Microsoft Edge.

## Pre-requisites
- [ ] Backend server running on `http://localhost:8080` (Verify `curl http://localhost:8080/health`)
- [ ] Dashboard running on `http://localhost:3001` (or `http://localhost:3000`)
- [ ] Chrome opened with a clean profile or developer mode enabled

---

## Extension Installation & Authentication
- [ ] 1. Navigate to `chrome://extensions`.
- [ ] 2. Toggle **Developer mode** ON (top right).
- [ ] 3. Click **Load unpacked** and select `FocusGuard/apps/extension`.
- [ ] 4. Confirm extension icon appears in the toolbar with status popup.
- [ ] 5. Click extension icon, verify default authentication completes with `demo@focusguard.local`.
- [ ] 6. Confirm WebSocket connection indicator shows **Connected**.

---

## Policy Creation & Real-Time Sync
- [ ] 7. Open Dashboard at `http://localhost:3001`.
- [ ] 8. Click **Create Scoped Attention Policy**.
- [ ] 9. Enter Target: `youtube.com`, Daily Budget: `0.5` minutes (30 seconds), Mode: `BLOCK`.
- [ ] 10. Click **Save Policy**.
- [ ] 11. Inspect extension service worker console (`chrome://extensions` -> Inspect background worker).
- [ ] 12. Confirm log: `[FocusGuard Extension] Synchronized policy ... with native DNR rules.`

---

## Active Usage Accounting & Tab Switching
- [ ] 13. Open a new tab and navigate to `https://www.youtube.com`.
- [ ] 14. Watch usage timer in extension popup or service worker console: verify timer starts counting.
- [ ] 15. Actively browse YouTube for 10 seconds (Usage: ~10s / 30s).
- [ ] 16. Switch to another tab (e.g. `https://google.com` or `chrome://extensions`).
- [ ] 17. Wait 15 seconds on Google tab.
- [ ] 18. Return to YouTube tab and verify usage did **not** accumulate while inactive.
- [ ] 19. Open a second YouTube tab (`https://www.youtube.com/feed/trending`).
- [ ] 20. Confirm `currentTabId` seamlessly updates to Tab 2 without double-counting.

---

## Enforcement & Block Page Verification
- [ ] 21. Continue browsing YouTube until 30 seconds total active time is reached.
- [ ] 22. At 30 seconds, confirm immediate redirection to `pages/block.html`.
- [ ] 23. Verify Block Page content:
  - Blocked Target: `youtube.com`
  - Reason: `Daily attention budget reached.`
  - Policy Scope: `YouTube Daily Budget`
  - Ratio: `30 / 30 seconds` (or minutes equivalent)
  - Next Reset: `12:00 AM`
- [ ] 24. Test button **Return to Focus**: closes tab or navigates to safe page.
- [ ] 25. Test button **View Policy**: opens extension options page.

---

## Event Sync & Dashboard Real-Time Feed
- [ ] 26. Check Dashboard: verify Live Enforcement Timeline automatically records `DOMAIN_BLOCKED on youtube.com`.
- [ ] 27. Verify Today's Focus analytics update with the blocked event count.

---

## Offline & Browser Restart Resilience
- [ ] 28. Disconnect network (turn off Wi-Fi or set Chrome DevTools Network to Offline).
- [ ] 29. Restart Chrome completely (`Cmd+Q` / `Alt+F4` and relaunch).
- [ ] 30. Open `https://www.youtube.com`: confirm local declarativeNetRequest / cached policy blocks immediately.
- [ ] 31. Reconnect network.
- [ ] 32. Confirm extension flushes offline events via `POST /api/v1/events/batch` with zero duplicate entries.

---

## Policy Update & Deletion Lifecycle
- [ ] 33. On Dashboard, edit policy or delete policy `youtube.com`.
- [ ] 34. Confirm extension service worker receives WebSocket update and clears DNR blocking rules.
- [ ] 35. Navigate to `https://www.youtube.com`: confirm website is immediately accessible again.
- [ ] 36. Run extension diagnostics popup: verify 0 rule leaks and healthy sync state.
