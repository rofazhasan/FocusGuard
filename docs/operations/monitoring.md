# Operations: Monitoring & Health Checks

FocusGuard provides native health and liveness endpoints for orchestration systems like Kubernetes and Docker.

---

## 1. Liveness & Readiness Endpoint

```http
GET /health
```

### JSON Response:
```json
{
  "status": "UP",
  "timestamp": "2026-08-14T17:19:53Z",
  "version": "1.0.0"
}
```

---

## 2. Key Operational Metrics to Monitor
- **Active WebSocket Connections**: Track client disconnect churn.
- **SQLite / Postgres Connection Latency**: Track lock acquisition time during bulk delta syncs.
- **REST Request Duration**: P95 latency under 20ms for delta ingestion.
