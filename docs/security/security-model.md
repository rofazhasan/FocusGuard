# Security Model

FocusGuard enforces a strict least-privilege security model across network and operating system boundaries.

---

## 1. Zero Root Privilege Requirement
- **macOS**: FocusGuard runs as a standard unprivileged user space application. It requires zero `sudo` root privileges and loads zero custom kernel extensions (`kexts`).
- **Android**: FocusGuard requires zero root / Magisk exploits. It operates entirely within standard Android SDK boundaries.

---

## 2. Cryptographic Storage & Secrets
- User passwords are saved using `bcrypt` (cost factor 10).
- Authentication tokens are HMAC-SHA256 signed JWTs with expiration bounds.
- Pairing codes use cryptographically secure random number generators (`crypto/rand`).
