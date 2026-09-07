# FocusGuard Error Taxonomy & Standardized Error Handling

**Document ID**: `FG-ERR-006`  
**Version**: `1.0.0-PROD`  
**Date**: September 7, 2026  
**Status**: APPROVED SPECIFICATION  

---

## 1. Standard Error Envelope

Every error response returned by any FocusGuard HTTP endpoint or WebSocket error frame adheres strictly to the following JSON structure:

```json
{
  "error": {
    "code": "DEVICE_REVOKED",
    "message": "Device authorization has been permanently revoked by account owner",
    "requestId": "req_609a39ec8859",
    "timestamp": "2026-09-07T23:40:00.000Z",
    "retryable": false,
    "details": {}
  }
}
```

### 1.1 Field Definitions
- **`code`** *(string, required)*: Canonical machine-readable error identifier from the taxonomy below.
- **`message`** *(string, required)*: Concise, human-readable description of the error. Sensitive values (tokens, credentials, PII) are strictly masked.
- **`requestId`** *(string, required)*: Correlation identifier extracted from `X-Request-ID` header for end-to-end tracing.
- **`timestamp`** *(string, required)*: UTC ISO-8601 timestamp of when the error occurred.
- **`retryable`** *(boolean, required)*: Authoritative directive instructing the client whether it should retry the request.
- **`details`** *(object, optional)*: Additional structured context (e.g. field-level validation errors, retry-after seconds).

---

## 2. Comprehensive Error Code Catalog

| Error Code | HTTP Status | Description | Retryable | Client Action Required |
| :--- | :---: | :--- | :---: | :--- |
| **`AUTH_INVALID`** | `401 Unauthorized` | Missing, malformed, or signature-invalid JWT credentials. | ❌ No | Prompt user to log in or re-enroll. Do not retry. |
| **`AUTH_EXPIRED`** | `401 Unauthorized` | JWT access token expired. Refresh token available. | ⚠️ Conditional | Call `POST /api/v1/auth/refresh`. Retry with new token. |
| **`CROSS_TENANT_ACCESS`** | `403 Forbidden` | User or device attempted to query/mutate another tenant's resource. | ❌ No | Security anomaly. Abort operation immediately. |
| **`DEVICE_REVOKED`** | `403 Forbidden` | Device authorization permanently terminated by owner. | ❌ No | **Zero-Trust Wipe**: Destroy local tokens, lock UI, halt sync. |
| **`DEVICE_NOT_FOUND`** | `404 Not Found` | Device ID does not exist in registry. | ❌ No | Transition to `UNREGISTERED`; initiate fresh pairing. |
| **`PAIRING_CODE_INVALID`** | `404 Not Found` | 6-character human code `FG-XXXXXX` not recognized. | ❌ No | Prompt user to re-enter pairing code. |
| **`PAIRING_EXPIRED`** | `410 Gone` | Pairing session passed 5-minute time-to-live. | ❌ No | Generate a new pairing session on Dashboard. |
| **`PAIRING_CONSUMED`** | `410 Gone` | Pairing session already claimed by another device. | ❌ No | Pairing codes are strictly single-use. Re-pair required. |
| **`PAIRING_CONFLICT`** | `409 Conflict` | Approval or request attempted on cancelled/invalid state. | ❌ No | Re-read session state from server. |
| **`POLICY_INVALID`** | `400 Bad Request` | Policy schema invalid, negative limit, or missing targets. | ❌ No | Surface validation errors in policy editor. |
| **`POLICY_VERSION_CONFLICT`**| `409 Conflict` | Optimistic lock failure on policy mutation. | ⚠️ Conditional | Fetch latest policy version and re-apply edit. |
| **`CAPABILITY_UNSUPPORTED`** | `422 Unprocessable`| Target device lacks required enforcement primitive. | ❌ No | Informational alert; server filters target for device. |
| **`RATE_LIMITED`** | `429 Too Many Requests` | Request volume exceeded token-bucket limit. | ✅ Yes | Inspect `Retry-After` header; wait with backoff. |
| **`VALIDATION_ERROR`** | `400 Bad Request` | Malformed JSON payload or missing mandatory fields. | ❌ No | Fix client request structure. |
| **`NETWORK_UNAVAILABLE`** | `503 Service Unavailable`| Backend unreachable or local network down. | ✅ Yes | Queue request in local SQLite; engage exponential backoff. |
| **`COMMAND_EXPIRED`** | `410 Gone` | Remote command TTL exceeded before execution. | ❌ No | Drop command safely without executing. |
| **`INTERNAL_ERROR`** | `500 Server Error` | Unhandled backend exception or database failure. | ✅ Yes | Exponential backoff retry with jitter. |

---

## 3. Client Retry & Backoff Strategy

### 3.1 Non-Retryable Invariant
Clients **must NEVER retry** requests that fail with:
- `AUTH_INVALID` (401)
- `DEVICE_REVOKED` (403)
- `CROSS_TENANT_ACCESS` (403)
- `VALIDATION_ERROR` (400)
- `PAIRING_CONSUMED` / `PAIRING_EXPIRED` (410)

Immediate retry on authentication or revocation errors causes network storms and fills audit logs with noise.

### 3.2 Exponential Backoff with Jitter Formula
For retryable errors (`NETWORK_UNAVAILABLE`, `RATE_LIMITED`, `INTERNAL_ERROR`):

$$t_{\text{wait}} = \min\left(t_{\text{max}}, \; t_{\text{base}} \times 2^{\text{attempt}}\right) \times (1 \pm \text{jitter})$$

- **$t_{\text{base}}$**: 1.0 second
- **$t_{\text{max}}$**: 60.0 seconds
- **$\text{jitter}$**: Uniform random between $-0.25$ and $+0.25$ ($\pm 25\%$)
- **Maximum Retry Attempts**: 5 for realtime operations; unlimited with 60s clamp for offline durable event queue.
