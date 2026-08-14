# ADR 0006: Consent-Based Device Enrollment via 6-Character Cryptographic TTL Tokens

- **Status**: Accepted
- **Date**: 2026-08-14
- **Author**: FocusGuard Systems Architecture Team

---

## Context
Traditional remote device management tools require installing invasive root certificates or permanent MDM profiles, creating privacy and security concerns for students and family members.

---

## Decision
We implemented an ephemeral 6-character pairing code protocol:
1. Codes are formatted as `FG-XXXXXX` generated via `crypto/rand`.
2. Codes carry a strict 5-minute Time-to-Live (`expiresAt`).
3. Single-claim validation in an atomic transaction marks `is_claimed = 1`.
4. The claiming device is issued a scoped JWT bound specifically to its unique hardware ID.

---

## Consequences
- **Positive**: High security; zero possibility of silent remote enrollment; simple, user-friendly onboarding UX.
- **Negative**: Requires the user to be physically present at both devices during the 5-minute pairing window.
