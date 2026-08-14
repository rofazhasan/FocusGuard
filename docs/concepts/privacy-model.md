# Concept: Data Minimization & Privacy Model

FocusGuard is designed under the philosophy of **Radical Data Minimization**: the system cannot leak data it never collects.

---

## 1. What FocusGuard NEVER Collects

- ❌ **Keystrokes**: Zero keylogger code exists anywhere in the codebase.
- ❌ **Screen Pixels / Screenshots**: No screen recording or OCR analysis.
- ❌ **Personal Messages / Audio**: Zero microphone or notification body snooping.
- ❌ **Full Browser History / Search Queries**: Only the high-level hostname (`youtube.com`) is matched. The full URL path (e.g. video titles or search terms) is immediately discarded locally.
- ❌ **Packet Payloads**: The Android `VpnService` inspects DNS query headers only and never reads or decrypts TLS payloads.

---

## 2. What FocusGuard Collects

- ✅ **Target Label**: High-level application or domain name (e.g. `youtube.com`).
- ✅ **Duration**: Elapsed seconds in the active/foreground state.
- ✅ **Timestamp**: Calendar date for daily budget aggregation.
