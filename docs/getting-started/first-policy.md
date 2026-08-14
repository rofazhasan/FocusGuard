# Creating Your First Policy

Attention policies define the rules, budgets, and enforcement actions evaluated across your enrolled devices.

---

## Policy Components

Every FocusGuard policy consists of five core attributes:
1. **Name**: Human-readable label (e.g. *"Gaming & Video Daily Limit"*).
2. **Targets**: Specific apps (`Discord`), website domains (`youtube.com`), or categories (`SOCIAL`, `VIDEO`, `GAMING`).
3. **Limit Duration**: Daily budget in minutes (e.g. `30 minutes`).
4. **Enforcement Mode**:
   - `BLOCK`: Hard shield engagement when the budget is reached.
   - `FOCUS_ONLY`: Blocked only during active remote focus sessions.
   - `SCHEDULED_BLOCK`: Time-of-day scheduled lockouts.
5. **Target Device Scope**:
   - `All Enrolled Devices`: Shared aggregate budget across laptop and mobile.
   - `Specific Device`: Applies only to selected hardware node.

---

## Step-by-Step Instructions

### Via the Web Command Center
1. Click **+ Create Scoped Policy**.
2. Set **Policy Name** to `Social Media Cap`.
3. Set **Target Category or Type** to `Category` and value to `SOCIAL`.
4. Enter **Daily Budget** as `45` minutes.
5. Choose **Target Device Scope** as `All Enrolled Devices (Shared Budget)`.
6. Click **Save & Dispatch Policy**.

### Via the REST API
```bash
curl -X POST http://localhost:8080/api/v1/policies \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <YOUR_ACCESS_TOKEN>" \
  -d '{
    "name": "Social Media Cap",
    "limitSeconds": 2700,
    "period": "DAILY",
    "enforcementMode": "BLOCK",
    "targets": [
      { "targetType": "CATEGORY", "targetValue": "SOCIAL" }
    ],
    "assignedDeviceIds": []
  }'
```

### Verification
The policy version increments (`policyVersion: 2`). The backend broadcasts `POLICY_UPDATED` over the WebSocket connection, causing all connected nodes to synchronize and store the new rule in their local offline cache.
