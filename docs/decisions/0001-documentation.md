# ADR 0001: Adoption of Diátaxis Documentation Framework

- **Status**: Accepted
- **Date**: 2026-08-14
- **Author**: FocusGuard Systems Architecture Team

---

## Context
FocusGuard is a complex cross-platform distributed system spanning Go backend services, macOS Screen Time frameworks, Android network kernels, and web dashboards. Traditional unstructured documentation creates confusion by mixing step-by-step beginner guides with deep architectural theory and API reference material.

---

## Decision
We adopt the **Diátaxis documentation framework**, structuring all documentation into four distinct quadrants:
1. **Tutorials**: Learning-oriented guides for newcomers.
2. **How-To Guides**: Problem-oriented recipes for specific tasks.
3. **Reference**: Information-oriented specifications (APIs, schemas, configurations).
4. **Concepts / Explanation**: Understanding-oriented theoretical discussions.

---

## Consequences
- **Positive**: Clear information hierarchy; developers and evaluators can find relevant content without cognitive overhead.
- **Negative**: Requires maintaining separation across multiple modular markdown documents.
