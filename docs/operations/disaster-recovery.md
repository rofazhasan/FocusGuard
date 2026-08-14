# Operations: Disaster Recovery & State Recovery

Procedures for recovering fleet operations in the event of cloud server failure.

---

## 1. Client Autonomy During Cloud Outage
- Enrolled devices continue enforcing their cached policies offline.
- Usage is queued locally up to 10,000 delta records per device.

---

## 2. Server Rebuilding Procedure
1. Deploy a new server instance from git repository or container image.
2. Restore database from latest backup:
   ```bash
   # For SQLite
   cp backups/focusguard_latest.db backend/focusguard.db
   ```
3. Start backend services.
4. When clients reconnect, they synchronize queued deltas automatically.
