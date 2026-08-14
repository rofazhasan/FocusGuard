# How-To: Create a Shared Cross-Device Time Limit

This guide explains how FocusGuard calculates and aggregates attention limits across multiple enrolled devices.

---

## 1. How Shared Time Budgets Work

When a policy is scoped to `All Devices`, usage deltas from every enrolled device are combined in the cloud:

```
MacBook Pro (15m YouTube) ──┐
                            ├─► Server Aggregation (30m / 30m) ──► BROADCAST LIMIT_REACHED
Pixel Phone (15m YouTube) ──┘
```

1. **MacBook Pro** reports `15 minutes` of active window time.
2. **Pixel Phone** reports `15 minutes` of foreground app time.
3. The total aggregated time reaches `30 minutes` (the daily limit).
4. The server emits `LIMIT_REACHED`.
5. **Both** devices engage their local shields immediately.

---

## 2. Setting a Shared Limit via Web Dashboard

1. Open **[http://localhost:3001](http://localhost:3001)**.
2. Click **+ Create Scoped Policy**.
3. Set **Daily Budget (Minutes)** to `30`.
4. Leave **Target Device Scope** as `All Enrolled Devices (Shared Budget)`.
5. Click **Save & Dispatch Policy**.

---

## 3. Reconciling Midnight Timezone Resets

All usage aggregates are partitioned by calendar date (`YYYY-MM-DD`) in the user's configured timezone:
- At `00:00:00 local time`, daily aggregate totals reset to `0 seconds`.
- Active shields disengage automatically without requiring manual owner intervention.
