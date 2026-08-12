# FocusGuard — Antigravity Engineering Lifecycle Specification

This document details the end-to-end automated Agile development lifecycle for FocusGuard, mapping Jira issue selection down to verified code delivery.

---

## 🔄 End-to-End Development Flow

```
                 JIRA
                   │
                   ▼
              Select Issue
                   │
                   ▼
              Antigravity
              reads issue
                   │
                   ▼
             Plan change
                   │
                   ▼
             Developer A/B
                   │
                   ▼
               Code
                   │
                   ▼
              Build/Test
                   │
             ┌─────┴─────┐
             │           │
           FAIL         PASS
             │           │
             ▼           ▼
            Fix       Code Review
                         │
                         ▼
                    Integration
                         │
                         ▼
                    Verification
                         │
                         ▼
                    Jira → DONE
```

---

## 📌 Phase Definitions & Rule Standards

1. **Jira Issue Selection**:
   - Issue selected from backlog (`FG-101` through `FG-803`).
   - Developer A or Developer B assigned according to domain ownership matrix (Developer A: macOS/UI; Developer B: Android/Backend).

2. **Antigravity Issue Analysis**:
   - Reads summary, acceptance criteria, linked dependencies, and platform security boundaries.

3. **Implementation Planning**:
   - Generates/updates implementation plan artifact (`implementation_plan.md`).
   - Solicits user review and explicit approval prior to mutating code.

4. **Code Execution**:
   - Writes minimal, clean, non-contiguous edits.
   - Preserves API contracts and comments.

5. **Build & Test Verification Loop**:
   - Runs `go test ./...` for backend services.
   - Runs `swiftc -parse` for macOS native modules.
   - Runs `JUnit` tests for Android platform logic.
   - **FAIL Branch**: Immediately inspects full un-truncated error logs, diagnoses root cause, applies fix, and re-runs test suite.
   - **PASS Branch**: Proceeds to peer code review.

6. **Peer Code Review & Integration**:
   - Cross-developer review of feature branch PRs.
   - Merges into `develop` on bi-weekly Integration Days.

7. **Final Verification & Jira DONE Transition**:
   - Empirical runtime verification confirmed.
   - Ticket transitioned to `DONE` accompanied by structured Jira completion comment.
