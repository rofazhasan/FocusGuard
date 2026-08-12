# FocusGuard Testing & Quality Assurance Plan

## 1. Testing Strategy Overview

FocusGuard enforces strict quality assurance across all three components (Go Backend, macOS Swift Native, Android Kotlin Native).

```
Level 3: End-to-End Cross-Device Integration Tests
Level 2: API Integration Tests & Component Tests
Level 1: Local Unit Tests (Go tests, Swift XCTest, Kotlin JUnit)
```

---

## 2. Test Execution Commands

### Backend (Go)
```bash
# Run all unit and package tests
cd backend
go test -v -cover ./...

# Run static analysis
go vet ./...
```

### macOS Native (Swift)
```bash
cd apps/macos
xcodebuild test -scheme FocusGuard -destination 'platform=macOS'
```

### Android Native (Kotlin)
```bash
cd apps/android
./gradlew testDebugUnitTest
```

---

## 3. Integration & E2E Verification Scenarios

1. **Cross-Device Shared Limit Test**:
   - Register Mac and Android devices for User A.
   - Set Policy: YouTube = 30 mins (1800s).
   - Log 15 mins on Mac, log 15 mins on Android.
   - Verify WebSocket emits `POLICY_LIMIT_REACHED`.
   - Verify both Mac and Android active shields trigger.

2. **Offline Reconnection Test**:
   - Turn off Wi-Fi on Android device.
   - Accrue 20 mins usage offline; verify local Room DB policy evaluator blocks app at limit.
   - Re-enable Wi-Fi.
   - Verify delta sync replays batch session upload idempotently without double counting.
