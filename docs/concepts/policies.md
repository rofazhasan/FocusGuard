# Concept: Policy & Rule Fundamentals

In FocusGuard, an **Attention Policy** is a declarative specification of time constraints applied to digital stimuli.

---

## 1. Declarative Rule vs. Imperative Block

Unlike traditional website blockers that rely on hardcoded static blocklists, FocusGuard separates:
1. **The Policy Intent**: *"Allow 45 minutes of total social media usage across all devices per day."*
2. **The Target Bindings**: Mapping the intent to domain rules (`instagram.com`, `reddit.com`) and bundle identifiers (`com.burbn.instagram`).
3. **The State Machine**: Evaluating real-time cumulative usage and engaging shields only when the budget condition is breached.

---

## 2. Policy Versioning

Policies maintain a strictly increasing `version` integer. When a policy is updated:
- The server bumps `version = version + 1`.
- Enrolled devices compare their cached `policyVersion` against incoming broadcasts.
- Outdated local policies are discarded and replaced atomically.
