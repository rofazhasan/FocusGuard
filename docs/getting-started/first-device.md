# Enrolling Your First Device

FocusGuard uses a **consent-based enrollment protocol** ensuring that no device can be managed without physical access and explicit authorization.

---

## The 4-Step Enrollment Workflow

```
[ OWNER DASHBOARD ]                     [ MANAGED DEVICE (Android) ]
        │                                             │
        ├──── 1. POST /enrollment/create ────────────►│ (Generates Pairing Code "FG-XXXXXX", 5m TTL)
        │                                             │
        │                                             ├──── 2. Enter code on device
        │                                             │
        │◄─── 3. POST /enrollment/claim ──────────────┤ (Device claims code & submits hardware ID)
        │                                             │
        ├──── 4. Broadcast DEVICE_ENROLLED (WS) ─────►│ (Device receives JWT & stores in Room DB)
```

---

## Procedure

### 1. Generate a Pairing Code in the Dashboard
1. On the Owner Dashboard (`http://localhost:3001`), click **📱 + Pair New Device**.
2. Enter a descriptive device name (e.g. `Student Pixel Tablet` or `Work MacBook`).
3. Select the role:
   - **Managed Device (Child / Student / Sub-node)**: Strictly enforced remote policies.
   - **Personal Secondary Device**: Personal cross-device shared budget node.
4. Click **Generate New Code**.
5. A 6-character code (e.g. `FG-8492`) will appear with an active 5-minute countdown timer.

### 2. Enter the Pairing Code on the Target Device
1. Open the FocusGuard app on the Android or secondary macOS device.
2. Select **Join Existing Account**.
3. Type the 6-character code or scan the displayed QR code.
4. Tap **Confirm & Enroll**.

### 3. Grant Required Platform Permissions
- **Android**:
  - Grant **Usage Access** (`Settings > Apps > Special app access > Usage access`) so FocusGuard can track foreground application time.
  - Approve the **VPN Connection Request** to enable the local RFC 1035 DNS sinkhole.
- **macOS**:
  - Approve the **Screen Time & Family Controls** authorization prompt.

### 4. Verification
The device will immediately appear in the **Enrolled Fleet Devices** panel with status `PROTECTED` and role badge `Managed Node`.
