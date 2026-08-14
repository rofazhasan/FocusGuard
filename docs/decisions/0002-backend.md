# ADR 0002: Dual-Engine SQLite & PostgreSQL Architecture

- **Status**: Accepted
- **Date**: 2026-08-14
- **Author**: FocusGuard Systems Architecture Team

---

## Context
Developers evaluating FocusGuard locally require zero-friction installation without forcing external Docker or database dependencies, while production deployments require a scalable clustered database engine.

---

## Decision
We implemented a dual-mode persistence architecture in `backend/pkg/database/db.go`:
1. If PostgreSQL environment variables (`DB_HOST`, `DB_USER`) are provided, the backend connects to PostgreSQL with standard connection pooling.
2. If omitted, the backend automatically boots a pure-Go embedded SQLite database (`modernc.org/sqlite`) configured with Write-Ahead Logging (`PRAGMA journal_mode=WAL`) and `PRAGMA busy_timeout=5000`.

---

## Consequences
- **Positive**: 1-click execution for developers (`go run cmd/server/main.go`); production-ready PostgreSQL migration path.
- **Negative**: SQL queries must adhere strictly to ANSI SQL standard syntax supported by both engines.
