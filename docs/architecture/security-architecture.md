# Security Architecture

FocusGuard is built upon a defense-in-depth security model designed to resist tampering, replay attacks, and unauthorized device management.

---

## 1. Authentication & Token Hierarchy

```
[ User Master Credentials ]
             │
             ▼ (POST /api/v1/auth/login)
   [ Account Owner JWT ] (HS256 / Ed25519)
             │
             ├──► [ Issue Pairing Token ] (5m TTL, 6-char cryptographically random)
             │                 │
             │                 ▼
             │       [ Device Claim (POST /api/v1/enrollment/claim) ]
             │                 │
             └─────────────────┼────────► [ Device Access Token ]
                                          - Scoped to device ID
                                          - Restricted to telemetry sync & heartbeat
```

---

## 2. Remote Command Security & Idempotency

All remote commands (`POST /api/v1/commands/dispatch`) are signed with:
1. `commandId` (UUIDv4): Enforces single-execution idempotency.
2. `issuedBy` (Owner User ID): Cryptographically bound to the authenticated JWT.
3. `expiresAt` (RFC 3339 timestamp): Enforces an absolute validity window (default: 15 minutes). Devices reject expired commands even if received out-of-order.
4. `audit_logs` persistence: Every command dispatch is committed to an immutable append-only ledger.
