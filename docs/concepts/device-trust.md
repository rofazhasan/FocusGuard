# Concept: Device Trust & Consent Model

FocusGuard is built on **Consent-Based Device Management**. It provides parent-child and individual productivity governance without functioning as covert surveillance software.

---

## 1. Transparency Guarantee

Every managed device presents clear visual disclosures:
- In the Web Dashboard: **Managed Device View** (*"This device is protected by FocusGuard"*).
- In the Android App: A permanent foreground notification indicating active policy synchronization.
- In macOS System Settings: Listed under Authorized Screen Time Management.

---

## 2. Ephemeral Pairing Handshake

Devices cannot be claimed or commanded silently:
1. Pairing codes are random, 6-character strings (`FG-XXXXXX`).
2. Pairing codes expire in **5 minutes** (`300 seconds`).
3. An account owner must generate the code, and a user must physically enter it on the client device.
