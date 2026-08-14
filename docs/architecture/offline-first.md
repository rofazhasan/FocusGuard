# Offline-First Architecture

FocusGuard is designed so that devices remain strictly protected even during complete internet disconnection.

---

## 1. Local Policy Authority Caching

Enrolled clients cache their active policy bundle in local persistent storage:
- **Android**: Room SQLite database with tables `local_policies`, `local_targets`, and `pending_deltas`.
- **macOS**: CoreData SQLite store in the sandboxed Application Support directory.

```
[ Incoming Network Request / App Launch ]
                   │
                   ▼
       [ Is Device Online? ]
          /            \
       (YES)           (NO)
        /                \
[ Evaluate Cloud   [ Evaluate Local Room/
  Policy State ]     CoreData Cache ]
        \                /
         ▼              ▼
     [ Execute Enforcement Action ]
```

---

## 2. Monotonic Clock Anti-Tampering

To prevent users from rolling back the device system clock to bypass daily limits:
- **macOS**: Queries `mach_continuous_time()` and `clock_gettime(CLOCK_MONOTONIC_RAW)`.
- **Android**: Uses `SystemClock.elapsedRealtime()`.
- If wall-clock time jumps backwards while the monotonic timer increases, FocusGuard flags clock tampering and maintains active shields until verification.
