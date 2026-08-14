# Privacy: Data Model

This document outlines the personal data handled by FocusGuard and its classification under modern privacy frameworks (GDPR / CCPA).

---

## Data Classification Matrix

| Data Item | Sensitivity | Storage Location | Encryption |
|---|---|---|---|
| User Email | Low | SQLite/PostgreSQL `users` | TLS in transit |
| Password Hash | High | `users.password_hash` | `bcrypt` hash (Cost 10) |
| Device Hardware Info | Low | `devices.device_name`, `os_version` | TLS in transit |
| Domain/App Target Label | Low | `usage_aggregates.target_value` | Aggregate sum only |
| Usage Duration | Low | `usage_aggregates.total_duration_seconds` | Aggregated per day |
| Keystrokes / Screen Pixels | Critical | **NEVER COLLECTED** | N/A |
