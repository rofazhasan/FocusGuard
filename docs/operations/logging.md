# Operations: Structured Logging

The Go backend outputs structured JSON logs compliant with `log/slog` standards.

---

## Log Format Example

```json
{
  "time": "2026-08-14T23:17:44.284377+06:00",
  "level": "INFO",
  "msg": "FocusGuard Multi-Device Server running",
  "port": "8080"
}
```

### Log Levels:
- `INFO`: Normal lifecycle events, startup, client registration, policy dispatches.
- `WARN`: Recoverable network drops, pairing code expiration.
- `ERROR`: Database transaction failures, unhandled exceptions.
