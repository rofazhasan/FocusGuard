# ADR 0004: 6-Tier Deterministic Policy Precedence Engine

- **Status**: Accepted
- **Date**: 2026-08-14
- **Author**: FocusGuard Systems Architecture Team

---

## Context
When multiple overlapping policies, category restrictions, emergency focus sessions, and allowlists are active simultaneously, undefined rule resolution leads to unpredictable system states.

---

## Decision
We implemented a strict 6-tier deterministic precedence engine in `backend/internal/policies/domain_matcher.go`:
1. System Safety (Always `ALLOW`)
2. Explicit Allowlist (`ALLOW`)
3. Emergency Policy / Active Focus Lockout (`BLOCK`)
4. Explicit Domain Policy Limits (`BLOCK` on budget exhaustion)
5. Category Policy Limits (`BLOCK` on budget exhaustion)
6. Default (`ALLOW`)

---

## Consequences
- **Positive**: 100% deterministic decision-making with explainable reason strings; explicit whitelists always take precedence over broad category bans.
- **Negative**: Rule order is fixed in code and cannot be rearranged arbitrarily by users without explicit priority flags.
