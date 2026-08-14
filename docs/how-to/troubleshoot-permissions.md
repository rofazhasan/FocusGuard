# How-To: Troubleshoot Platform Permissions

This guide addresses permission authorization failures on macOS and Android.

---

## 1. macOS Screen Time & Accessibility Permissions

### Issue: `AuthorizationCenter.shared.requestAuthorization` fails with error code 1
- **Cause**: The application is not signed with a valid provisioning profile containing the `com.apple.developer.family-controls` entitlement.
- **Resolution**:
  1. Open `apps/macos/FocusGuard.xcodeproj` in Xcode.
  2. Under **Signing & Capabilities**, verify your Apple Developer Team is selected.
  3. Ensure `Family Controls (Development)` is listed under Capabilities.

### Issue: Accessibility / AppleScript Permission Revoked
- **Resolution**:
  1. Open **System Settings > Privacy & Security > Accessibility**.
  2. Ensure **FocusGuard** is toggled **ON**.
  3. Under **Automation**, ensure FocusGuard has permission to query frontmost browser windows (Safari, Chrome).

---

## 2. Android Usage Access & Background Battery Optimization

### Issue: Usage tracking stops when the screen is locked
- **Cause**: Android OEM battery management (e.g. Samsung, Xiaomi) killing background services.
- **Resolution**:
  1. Go to **Settings > Apps > FocusGuard > Battery**.
  2. Change battery optimization from *Optimized* to **Unrestricted**.
  3. Under **Special app access > Alarms & reminders**, enable **Allow setting alarms**.
