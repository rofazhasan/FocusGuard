# FocusGuard Developer Onboarding & Workflow

## 1. Development Principles & Incremental Process

For every feature or modification, developers must adhere to the 10-step incremental rule:

1. Explain architecture and design.
2. Create/modify files.
3. Implement core logic.
4. Add automated unit/integration tests.
5. Run static checks (`go vet`, `swiftlint`, `ktlint`).
6. Run unit test suite.
7. Run integration tests.
8. Report changed files.
9. Report remaining items / issues.
10. Update documentation.

---

## 2. Git Workflow & Commit Guidelines

### Main Branches:
- `main`: Production-ready release code.
- `develop`: Primary integration branch.

### Feature Branches:
- `feature/macos-usage`
- `feature/macos-enforcement`
- `feature/android-usage`
- `feature/android-vpn`
- `feature/backend-auth`
- `feature/policy-engine`
- `feature/device-sync`
- `feature/dashboard`
- `feature/focus-session`

### Commit Message Syntax:
- `feat:` New feature implementation
- `fix:` Bug fix
- `test:` Unit or integration test addition/modification
- `refactor:` Code restructuring without behavior changes
- `docs:` Documentation updates
- `chore:` Dependency or build system changes
- `ui:` Visual interface changes
