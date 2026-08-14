# Testing: Network & DNS Packet Parsing

Tests specifically targeted at RFC 1035 packet decoding, header serialization, and DNS query parsing.

---

## Verified Test Cases
1. **Standard A Record Query**: Validates parsing of standard 12-byte DNS headers and QNAME length-prefixed label parsing (`\x07youtube\x03com\x00`).
2. **Subdomain A Record Query**: Validates multi-label QNAME (`\x01m\x07youtube\x03com\x00`).
3. **NXDOMAIN Response Synthesis**: Verifies setting bit flags `0x8183` (QR=1, RD=1, RA=1, RCODE=3).
4. **Malicious / Truncated Packet Rejection**: Confirms parser does not panic on buffer underflow or invalid label lengths.
