# FocusGuard — Automated Jira Workflow & Smart Commits Guide

This guide explains how to set up **100% Automated Jira Tracking** connected directly to your GitHub repository (`rofazhasan/FocusGuard`). 

When enabled, Jira will automatically:
1. Detect commit messages and pull requests referencing issue keys (e.g. `FG-101`, `FG-304`).
2. Transition tickets automatically: `TO DO` ➔ `IN PROGRESS` ➔ `CODE REVIEW` ➔ `DONE`.
3. Add verification comments and commit links to Jira issues automatically.

---

## 1. Native Jira Smart Commits (Built-in GitHub Syntax)

When writing Git commit messages, include the **Jira Issue Key** along with Smart Commit commands:

### Syntax Format:
`<ISSUE_KEY> #<COMMAND> <COMMENT_TEXT>`

### Examples:

#### A. Transitioning Issue to `IN PROGRESS`:
```bash
git commit -m "FG-201 #in-progress feat: develop JWT authentication endpoints and Argon2id password hashing"
```

#### B. Transitioning Issue to `DONE` with Verification Comment:
```bash
git commit -m "FG-102 #done feat: PostgreSQL schema DDL migration script 000001_init_schema.up.sql #comment Verified table constraints and indexes cleanly created."
```

#### C. Transitioning Issue to `CODE REVIEW` on PR creation:
```bash
git commit -m "FG-304 #code-review feat: implement ManagedSettingsStore custom ShieldConfigurationExtension UI"
```

---

## 2. Setting Up GitHub <-> Jira Integration (5 Minutes Setup)

To enable automatic commit and branch tracking in Jira Cloud:

1. Log into **Jira Cloud** (`https://your-domain.atlassian.net`).
2. Go to **Apps** (top menu) ➔ **Find new apps** ➔ Search for **GitHub for Jira** (Official Atlassian App).
3. Click **Get app** ➔ **Get it now**.
4. Click **Connect Organization** and select your GitHub user/organization (`rofazhasan`).
5. Select the `FocusGuard` repository (`rofazhasan/FocusGuard`).
6. Click **Save & Connect**.

---

## 3. Configuring Jira No-Code Automation Rules

In Jira Cloud, you can create automatic trigger rules so you never have to manually drag cards across columns:

### Rule 1: Auto-Move to `IN PROGRESS` when Branch/Commit is Created
- **Trigger**: `Development event` ➔ `Branch created` OR `Commit created`
- **Condition**: Issue status equals `TO DO` or `BACKLOG`
- **Action**: Transition issue to `IN PROGRESS`

### Rule 2: Auto-Move to `CODE REVIEW` when Pull Request is Opened
- **Trigger**: `Development event` ➔ `Pull request created`
- **Action**: Transition issue to `CODE REVIEW`
- **Action**: Add comment: *"Pull request opened on GitHub. Pending peer code review."*

### Rule 3: Auto-Move to `DONE` when Pull Request is Merged
- **Trigger**: `Development event` ➔ `Pull request merged`
- **Condition**: Issue status is NOT `DONE`
- **Action**: Transition issue to `DONE`
- **Action**: Add comment: *"Pull Request successfully merged into main/develop. Automated CI tests passed. Issue marked DONE."*

---

## 4. GitHub Actions CI/CD Auto-Transition Workflow

You can also trigger Jira status updates directly inside `.github/workflows/` using the official `atlassian/gajira` GitHub Action:

```yaml
name: Jira Auto-Update on CI Pass

on:
  push:
    branches: [ main, develop ]

jobs:
  test_and_transition:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run Backend Tests
        run: cd backend && go test ./...

      - name: Login to Jira
        uses: atlassian/gajira-login@v3
        env:
          JIRA_BASE_URL: ${{ secrets.JIRA_BASE_URL }}
          JIRA_USER_EMAIL: ${{ secrets.JIRA_USER_EMAIL }}
          JIRA_API_TOKEN: ${{ secrets.JIRA_API_TOKEN }}

      - name: Find Jira Issue Key from Commit
        id: find_issue
        uses: atlassian/gajira-find-issue-key@v3
        with:
          string: ${{ github.event.head_commit.message }}

      - name: Transition Issue to DONE
        if: steps.find_issue.outputs.issue != ''
        uses: atlassian/gajira-transition@v3
        with:
          issue: ${{ steps.find_issue.outputs.issue }}
          transition: "DONE"
```

---

## 5. Summary of Automated Developer Workflow

```text
Create Branch (feature/FG-101-...)  ──> Jira auto-moves ticket to IN PROGRESS
              │
Commit Code with FG-101             ──> Jira attaches commit diff & logs to ticket
              │
Open Pull Request                   ──> Jira auto-moves ticket to CODE REVIEW
              │
CI Tests Pass & PR Merged           ──> Jira auto-moves ticket to DONE & posts summary!
```
