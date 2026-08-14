# Privacy: Data Retention Policies

FocusGuard retains data only as long as necessary to provide attention analytics and budget enforcement.

---

## Retention Schedule

1. **Active Daily Usage Aggregates**: Stored for rolling 90-day periods to compute weekly and monthly adherence trends.
2. **Audit Logs**: Retained for 30 days for security auditing and accountability.
3. **Enrollment Pairing Tokens**: Purged automatically upon expiration (5 minutes).
4. **Deleted Account Data**: Cascades immediately across all foreign keys (`ON DELETE CASCADE`).
