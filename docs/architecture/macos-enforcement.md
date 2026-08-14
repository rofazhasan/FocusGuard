# macOS Native Enforcement Architecture

On macOS (Sonoma 14+ / Sequoia 15+), FocusGuard interfaces directly with Apple's Screen Time system frameworks: `FamilyControls`, `ManagedSettings`, and `DeviceActivity`.

---

## 1. Out-of-Process Shielding

Apple's Screen Time architecture executes enforcement outside the application's process boundary within `ManagedSettingsStore`:

```
┌─────────────────────────────────┐
│     FocusGuard Client App       │
│  - Evaluates local policy limits│
│  - Issues shield tokens         │
└────────────────┬────────────────┘
                 │
                 ▼ (Inter-process XPC)
┌─────────────────────────────────┐
│   macOS WindowServer / System   │
│  - ManagedSettings daemon       │
│  - Intercepts App Launches      │
│  - Intercepts WebKit Domains    │
└─────────────────────────────────┘
```

Because enforcement is handled by the macOS operating system itself:
- Force-quitting the FocusGuard GUI app does **not** lift active application shields.
- Browser windows cannot bypass the restriction by using Private Browsing or renaming binaries.

---

## 2. Background Activity Collector Daemon

The macOS background collector daemon runs a periodic sampling cycle (every 3 seconds):
1. **Frontmost Application Detection**: Queries `NSWorkspace.shared.frontmostApplication`.
2. **Browser Active Tab Domain Resolution**: Uses sandboxed Apple Events (`osascript`) to inspect active tab URLs in Safari and Google Chrome without reading page content or DOM.
3. **Usage Increment Ingestion**: Normalizes duration into 3-second ticks and reports them to the backend SQLite/PostgreSQL database and WebSocket hub.
