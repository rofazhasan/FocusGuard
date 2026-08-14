# Concept: Distributed Attention Budgets

An **Attention Budget** represents a finite daily quota of allowed engagement with designated distracting platforms.

---

## 1. Cross-Device Quota Aggregation

Traditional device-specific limiters fail because users switch devices when a limit expires (e.g. reaching 30 minutes on a laptop and continuing on a phone).

FocusGuard unifies device quotas:

$$\text{Total Usage} = \sum_{i=1}^{N} \text{Usage}(\text{Device}_i)$$

When $\text{Total Usage} \ge \text{Policy Limit}$, the backend triggers simultaneous multi-device enforcement across the entire fleet.

---

## 2. Midnight Partitioning & Reset

Attention budgets operate on strict 24-hour cycles:
- All usage records are partitioned by date string (`YYYY-MM-DD`).
- Aggregates reset automatically at `00:00:00` in the user's configured timezone.
