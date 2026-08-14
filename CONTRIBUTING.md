# Contributing to FocusGuard

Thank you for your interest in contributing to FocusGuard! We welcome contributions from engineers, designers, and researchers committed to advancing ethical digital attention enforcement.

---

## Code of Conduct

All contributors are expected to adhere to our [Code of Conduct](CODE_OF_CONDUCT.md).

---

## Development Workflow

### 1. Fork & Clone
```bash
git clone https://github.com/<your-username>/FocusGuard.git
cd FocusGuard
```

### 2. Workspace Setup
- **Backend**: Requires Go 1.22+
  ```bash
  cd backend
  go test ./...
  ```
- **macOS Client**: Requires Xcode 15+ & Swift 6.0+
  Open `apps/macos/FocusGuard.xcodeproj` in Xcode.
- **Android Client**: Requires Android Studio Iguana+ with JDK 17+
  Open `apps/android` in Android Studio.
- **Web Dashboard**: Requires Node.js 18+
  ```bash
  cd apps/web
  npm install
  ```

### 3. Branching & Commit Guidelines
- Use feature branches off `main`: `feature/scoped-policy-rules` or `fix/rfc1035-dns-padding`.
- Write structured Conventional Commits:
  - `feat(backend): add idempotent remote command dispatcher`
  - `fix(macos): prevent monotonic clock drift in activity monitor`
  - `docs(architecture): document offline-first state reconciliation`
  - `test(android): add unit tests for midnight usage split`

### 4. Running the Test Suite
Before opening a pull request, ensure all tests pass:
```bash
# Backend unit & integration tests
cd backend && go test -v ./...

# macOS Swift verification
cd apps/macos/FocusGuard && swiftc -parse-as-library ProofA/ProofAMacOSEnforcement.swift

# Android verification tests
cd apps/android && go run proof/proof_b_android_enforcement.go
```

### 5. Pull Request Process
1. Ensure your PR addresses a single focused concern.
2. Update relevant Diátaxis documentation in `docs/` if API contracts or user-facing behaviors change.
3. Link relevant GitHub issues in the PR description.
4. Maintain zero mock data: all platform integrations must operate against real OS APIs.
