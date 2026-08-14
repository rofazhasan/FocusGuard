# Security Policy

FocusGuard is designed around privacy, device autonomy, and explicit user consent. We take security vulnerabilities seriously and appreciate responsible disclosure.

---

## Supported Versions

Only the latest active minor release receives active security patches.

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

---

## Reporting a Vulnerability

If you discover a security vulnerability or potential privilege escalation flaw in FocusGuard (e.g. bypassing native OS shields, spoofing cryptographic tokens, DNS leakage, or unauthorized device enrollment), please report it to our engineering team.

### How to Report
- **Email**: Send an encrypted or plain report to `security@focusguard.local` (or file a GitHub Private Vulnerability Advisory).
- **Include**:
  1. Description of the vulnerability.
  2. Steps to reproduce or proof-of-concept script.
  3. Affected platform (`macOS`, `Android`, or `Backend`).
  4. Impact assessment.

### Disclosure Policy
- We acknowledge reports within **48 hours**.
- We provide an initial mitigation plan within **7 business days**.
- We request a **90-day embargo period** before public disclosure to allow patches to be deployed to all supported client platforms.

---

## Security Architecture Principles

1. **Least Privilege Enforcement**: FocusGuard never requires root (`sudo`) on macOS or OS-level rooting on Android. All enforcement operates within documented Apple (`FamilyControls`, `ManagedSettings`) and Google (`VpnService`, `UsageStatsManager`) sandbox boundaries.
2. **Consent-Based Enrollment**: Devices cannot be claimed or commanded silently. Enrollment requires physical access to view the 6-character pairing code or scan the QR code.
3. **Data Minimization**: Raw URLs, full packet contents, search queries, screen pixels, and keystrokes are never logged, analyzed, or transmitted.
4. **Idempotent Remote Commands**: Remote commands include cryptographic UUIDs and strict time-to-live (`expiresAt`) boundaries to prevent replay attacks.
