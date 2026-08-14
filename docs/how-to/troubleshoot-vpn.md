# How-To: Troubleshoot Android VpnService DNS Filtering

This guide diagnoses and resolves issues with the Android local `VpnService` network filter.

---

## Symptom 1: Restricted Domains Are Still Loading

### Possible Causes:
1. **App Using Encrypted DNS (DoH/DoT)**: Browsers like Chrome or Firefox may have "Secure DNS" (DNS-over-HTTPS) enabled, bypassing local UDP port 53 DNS interception.
   - **Fix**: Disable "Use secure DNS" in browser settings or configure the FocusGuard VPN route to intercept TCP/UDP port 853 (DoT) and port 443 DoH fallback.
2. **Domain Cached Locally on Device**: Android's OS resolver may have cached the IP address before the policy limit was reached.
   - **Fix**: Toggle Airplane Mode on and off to flush the device DNS cache.
3. **Subdomain Not Covered**: The requested target is using an unexpected CDN hostname.
   - **Fix**: Check `backend/internal/policies/domain_matcher.go` to ensure parent domain rules are configured correctly.

---

## Symptom 2: "Always-On VPN" Interrupted

### Resolution:
1. Open Android **Settings > Network & internet > VPN**.
2. Tap the gear icon next to **FocusGuard**.
3. Toggle **Always-on VPN** to **ON**.
4. Enable **Block connections without VPN** for supervised/managed child profiles.

---

## Diagnostic Command

Inspect live DNS interception in Android logcat:
```bash
adb logcat -s FocusVpnService:D DnsPacketParser:D
```
Look for lines confirming:
```
[DnsPacketParser] Intercepted Query: m.youtube.com (Type: A) -> Policy MATCH -> Synthesizing NXDOMAIN (RCODE 3)
```
