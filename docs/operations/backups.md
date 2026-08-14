# Operations: Backup Strategies

Procedures for snapshotting and restoring FocusGuard state.

---

## 1. SQLite Database Backup

Because FocusGuard operates SQLite in Write-Ahead Log (WAL) mode, online backups can be executed safely using the `.backup` command without stopping the server:

```bash
sqlite3 backend/focusguard.db ".backup 'backups/focusguard_$(date +%Y%m%d_%H%M%S).db'"
```

---

## 2. PostgreSQL Backup

```bash
pg_dump -U focusguard -h localhost -d focusguard_db -F c -b -v -f "backups/focusguard_pg_$(date +%Y%m%d_%H%M%S).dump"
```
