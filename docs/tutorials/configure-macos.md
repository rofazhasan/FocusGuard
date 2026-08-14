# Tutorial: Configuring macOS Screen Time Enforcement

This tutorial explains how FocusGuard interfaces with Apple's native Screen Time frameworks (`FamilyControls`, `ManagedSettings`, and `DeviceActivity`) on macOS Sonoma (14+) and Sequoia (15+).

---

## Learning Objectives
- Understanding Apple's Screen Time framework security model.
- Authorizing `AuthorizationCenter.shared.requestAuthorization(for: .individual)`.
- Configuring `ManagedSettingsStore.shield.applications` and `webDomains`.
- Setting up the background activity monitoring collector.

---

## 1. Requesting Screen Time Authorization

On macOS, managing application restrictions out-of-process requires explicit user authorization via Apple's `FamilyControls`:

```swift
import FamilyControls

public class ScreenTimeAuthorizer {
    public static func requestAccess() async throws {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            print("[FocusGuard macOS] ScreenTime Authorization Granted.")
        } catch {
            print("[FocusGuard macOS] Authorization Denied: \(error.localizedDescription)")
            throw error
        }
    }
}
```

When this runs, macOS presents a native system confirmation prompt requiring Touch ID or the administrator password.

---

## 2. Activating Application & Domain Shields

When an attention policy is violated or a focus session begins, FocusGuard invokes `ManagedSettingsStore` to shield target applications and browser domains:

```swift
import ManagedSettings

public class MacOSEnforcementEngine {
    private let store = ManagedSettingsStore(named: .init("FocusGuardShield"))

    public func applyShield(appTokens: Set<ApplicationToken>, domainTokens: Set<WebDomainToken>) {
        store.shield.applications = appTokens
        store.shield.webDomains = domainTokens
    }

    public func removeShield() {
        store.shield.applications = nil
        store.shield.webDomains = nil
    }
}
```

When a shielded application is launched by the user, macOS intercepts execution at the WindowServer compositor level and renders Apple's native Screen Time restriction shield.

---

## 3. Background Activity Monitoring Collector

To continuously assess active time without draining CPU cycles, FocusGuard runs a lightweight collector daemon querying frontmost applications and active browser tabs:

```swift
import AppKit

func getFrontmostApp() -> (name: String, bundleId: String)? {
    if let app = NSWorkspace.shared.frontmostApplication {
        return (app.localizedName ?? "Unknown", app.bundleIdentifier ?? "")
    }
    return nil
}
```

The collector normalizes usage into discrete 3-second slices and aggregates them against active policy limits.
