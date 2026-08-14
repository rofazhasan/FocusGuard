# Security: Authorization & Role-Based Access Control

FocusGuard enforces Role-Based Access Control (RBAC) across three principal identities:

---

## Authorization Matrix

| Identity | Read Fleet Status | Create/Delete Policies | Dispatch Remote Focus | Claim Pairing Code |
|---|---|---|---|---|
| **Account Owner** | ✅ | ✅ | ✅ | ❌ (Generates only) |
| **Managed Device** | ✅ (Scoped only) | ❌ | ❌ | ✅ (Claims only) |
| **Personal Node** | ✅ | ❌ | ❌ | ✅ |
