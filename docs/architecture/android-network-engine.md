# Android Network Engine Architecture

FocusGuard achieves systemwide, rootless domain filtering on Android via a **Local RFC 1035 UDP DNS Sinkhole** implemented over Android's native `VpnService`.

---

## 1. Zero External Tunneling Guarantee

Traditional VPN apps tunnel all user traffic through an external remote proxy server. FocusGuard runs **100% locally on-device**:
- All IP traffic (`0.0.0.0/0`) is routed into a local virtual TUN interface (`10.0.0.2`).
- FocusGuard inspects **only UDP port 53 DNS query packets**.
- Non-DNS TCP/UDP packets pass through unmodified.
- No network data ever leaves the device.

---

## 2. RFC 1035 DNS Parser & Response Synthesizer

```
[ DNS Query: "youtube.com" (UDP Port 53) ]
                   │
                   ▼
       [ RFC 1035 Packet Parser ]
                   │
       [ Is Domain on Blocklist? ]
          /                 \
       (YES)                (NO)
        /                     \
[ Synthesize RFC 1035     [ Forward query to
  NXDOMAIN (RCODE 3) ]      upstream DNS 8.8.8.8 ]
        │                     │
        ▼                     ▼
[ Write to TUN Buffer ]   [ Return Real IP ]
```

### DNS Header Flags & Synthesized NXDOMAIN
When a blocked domain query is detected, the engine generates an RFC 1035 response packet:
- `QR = 1` (Response)
- `RA = 1` (Recursion Available)
- `RCODE = 3` (`NXDOMAIN` — Non-Existent Domain)
- `ANCOUNT = 0` (Zero Answers)

This causes the Android OS resolver and all browsers to immediately drop the connection without hanging.
