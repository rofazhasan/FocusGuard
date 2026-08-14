# Security: Idempotent Remote Commands

Remote command execution follows strict cryptographic boundaries to prevent unauthorized or unintended device actions.

---

## 1. Command Verification Pipeline

1. **Owner Authority**: Only requests with an authenticated `OWNER` JWT can dispatch commands.
2. **Time-to-Live Check**: Target nodes verify `NOW() < expiresAt`.
3. **Idempotency Guard**: Target nodes maintain a ring buffer of the last 100 executed `commandId` UUIDs. Duplicate command deliveries are dropped as no-ops.
4. **Audit Immutability**: All dispatches are logged to `audit_logs`.
