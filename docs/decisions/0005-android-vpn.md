# ADR 0005: Local RFC 1035 DNS Sinkhole for Android Network Filtering

- **Status**: Accepted
- **Date**: 2026-08-14
- **Author**: FocusGuard Systems Architecture Team

---

## Context
Android does not provide a native `ManagedSettingsStore` equivalent for systemwide web domain filtering without Mobile Device Management (MDM) enrollment or device rooting.

---

## Decision
We engineered a local RFC 1035 UDP DNS sinkhole running over Android's native `VpnService`:
1. All IP traffic is routed into a local virtual TUN interface (`10.0.0.2`).
2. Only UDP port 53 DNS query packets are parsed and filtered.
3. Blocked domains receive a synthesized `NXDOMAIN` (RCODE 3) packet.
4. Allowed traffic passes to upstream DNS (`8.8.8.8`) without entering any remote proxy.

---

## Consequences
- **Positive**: Zero external proxy servers; zero root requirements; sub-millisecond local DNS evaluation.
- **Negative**: Occupies Android's single active VPN slot; cannot run simultaneously with third-party commercial VPN apps.
