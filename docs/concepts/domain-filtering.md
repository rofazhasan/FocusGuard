# Concept: Subdomain Matching & Filtering Theory

This document explains the algorithmic principles of domain matching and safety guardrails.

---

## 1. Domain Normalization Pipeline

Raw domain strings pass through a multi-stage normalization pipeline:
1. **Lowercase & Trim**: `  YOUTUBE.COM  ` $\rightarrow$ `youtube.com`
2. **Protocol Strip**: `https://youtube.com` $\rightarrow$ `youtube.com`
3. **Path/Query Strip**: `youtube.com/watch?v=123` $\rightarrow$ `youtube.com`
4. **Port Strip**: `youtube.com:443` $\rightarrow$ `youtube.com`
5. **Trailing Dot Strip**: `youtube.com.` $\rightarrow$ `youtube.com`
6. **WWW Standardize**: `www.youtube.com` $\rightarrow$ `youtube.com`

---

## 2. Preventing False-Positive Collisions

A common flaw in naive website blockers is using `strings.Contains(candidate, target)`. This causes catastrophic false positives:
- Matching `youtube.com` against `notyoutube.com` (Blocked mistakenly!)
- Matching `steam.com` against `steampowered.com`

FocusGuard enforces hierarchical subdomain boundary matching:
$$\text{Match}(C, T) \iff (C = T) \lor (\exists S : C = S + "." + T)$$
This guarantees that `m.youtube.com` matches `youtube.com`, but `notyoutube.com` is safely permitted.
