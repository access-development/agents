---
name: loyalty-points-integration
description: |
  Implement the Access Development Loyalty Points API on your server. This skill guides you
  through building the five REST endpoints Access calls to manage loyalty point balances,
  holds, redemptions, refunds, and cancellations. Covers the OpenAPI 3.0 contract, mTLS
  security configuration across all major hosting platforms (AWS, Azure, GCP, on-premises),
  idempotency requirements, hold lifecycle rules, and testing. Use when integrating loyalty
  points redemption ("burn") into the Access Travel Platform.
trigger: |
  Use when the developer wants to implement loyalty points endpoints for the Access Travel
  Platform, configure mTLS for Access client certificate authentication, scaffold a loyalty
  points server from the OpenAPI spec, troubleshoot an mTLS handshake failure, or understand
  the hold/redeem/refund lifecycle for loyalty point transactions.
---

# Access Development - Loyalty Points Integration Skill

You are an expert integration engineer helping a developer implement the **Access Loyalty Points API** on their server. Access calls these endpoints during the travel shopping flow to manage loyalty point balances, holds, redemptions, refunds, and cancellations. Your job is to guide them through the contract, security configuration, and testing in whatever language, framework, and hosting environment they use.

## How to use this skill

When a developer asks for help implementing loyalty points integration, follow the progressive disclosure pattern below. Start with the **Quick-Start Journey** that matches their need, then drill into the relevant reference sections as questions arise.

---

## 1 - Architecture Overview

```
┌─────────────────────┐         ┌──────────────────────────────┐
│  Access Payment API │ ── mTLS ─▶│  Your Loyalty Points API    │
│  (the caller)       │ ◀────────│  (the server you implement)  │
└─────────────────────┘           └──────────────────────────────┘
        │                                    │
        │ OkHttp + PKCS12 keystore           │ 5 REST endpoints under /v1/loyalty/
        │ TLS 1.3 only (no 1.2 fallback)     │ Your ingress validates client cert
        │ 5s timeout, 3 attempts, breaker    │ Your app handles business logic
```

**Key principle**: Access is the caller. You are the server. You implement five REST endpoints that Access calls over mutual TLS. Access presents a client certificate signed by a trusted CA. Your ingress (load balancer, API gateway, or reverse proxy) validates that certificate before requests reach your application.

### What you implement

| Endpoint | Method | Purpose |
|---|---|---|
| `/v1/loyalty/balance` | GET | Return available points balance and point-to-USD valuation |
| `/v1/loyalty/holds` | POST | Reserve (hold) points for a pending transaction |
| `/v1/loyalty/holds/{hold_id}/cancel` | POST | Release a previously created hold |
| `/v1/loyalty/redemptions` | POST | Deduct points for a confirmed booking |
| `/v1/loyalty/refunds` | POST | Credit points back for a refunded transaction |

All paths are relative to your base URL (e.g., `https://your-api.example.com/api/v1/loyalty/`).

### Prerequisites

1. **Access Travel SDK integrated** - The SDK handles member onboarding and produces the `member_key` used in all loyalty requests. See the [Access Travel Integration skill](../access-travel-integration/) for setup.
2. **API credentials from Access** - Access provisions mTLS certificate details (trusted CA, expected subject/SAN), test endpoint URLs, and program-specific configuration during onboarding.
3. **Domain allowlisting** - Your domains must be added to Access's CSP allowlist before deployment.

---

## 2 - Quick-Start Journeys

### Journey A - "I need to implement the loyalty endpoints"

1. **Review the OpenAPI spec** (see `references/openapi.yaml`) - it is the source of truth for request/response schemas, headers, and error codes.
2. **Choose your mTLS approach** (see section 3 below) based on your hosting platform.
3. **Implement the five endpoints** (see `references/endpoint-contract-reference.md` for detailed schemas and examples).
4. **Handle idempotency and hold lifecycle** (see `references/hold-lifecycle-and-idempotency.md`).
5. **Test with curl** (see `references/testing-and-troubleshooting.md`).
6. **Coordinate go-live** with your Access Implementation Manager.

### Journey B - "I need to configure mTLS security"

1. **Identify your hosting platform** (AWS, Azure, GCP, on-premises, or application-level).
2. **Read the matching section** in `references/mtls-configuration-guide.md`.
3. **Obtain the Access client CA certificate** from your Access Implementation Manager.
4. **Configure your ingress** to require and validate client certificates signed by that CA.
5. **Test the mTLS handshake** using the curl commands in the troubleshooting reference.
6. **Set up certificate expiration monitoring** - Access will provide a new client cert before the old one expires. You need a process to update your trust store.

### Journey C - "I'm troubleshooting an mTLS handshake failure"

1. **Check the troubleshooting section** in `references/testing-and-troubleshooting.md`.
2. **Verify your CA chain is complete** - the most common cause of mTLS failures is an incomplete certificate chain (missing intermediate CA).
3. **Test directly against your application** first (bypassing any load balancer) to isolate where the handshake fails.
4. **Check platform-specific pitfalls** in `references/mtls-configuration-guide.md` for your hosting platform.

### Journey D - "I need to understand the hold/redeem/refund lifecycle"

1. **Read `references/hold-lifecycle-and-idempotency.md`** for the full lifecycle.
2. Key concepts: holds reserve points (5 min default), redemption converts a hold to a permanent deduction, refunds credit points back after a redemption, cancel releases a hold without deducting points.
3. **Idempotency is mandatory** - all POST endpoints receive an `Idempotency-Key` header. You must persist it and return the original response on duplicate requests.

---

## 3 - mTLS Security Configuration

mTLS is the sole authentication mechanism defined by the OpenAPI spec. Access presents a client certificate signed by a trusted CA. Your server validates that certificate at the ingress layer (load balancer, API gateway, or reverse proxy) before requests reach your application.

### Your ingress must support TLS 1.3

**The Access caller negotiates TLS 1.3 only. It will not fall back to TLS 1.2.** If your ingress is configured with a TLS 1.2 maximum, or sits on a platform or security policy that caps at 1.2, Access cannot connect at all.

This is the most common cause of a failed go-live, and it is easy to miss: your own `curl` tests will happily negotiate TLS 1.2 and pass, so every test in `references/testing-and-troubleshooting.md` can succeed against a server Access cannot reach. Verify explicitly:

```bash
# Must succeed. If this fails, Access cannot reach you.
curl -v --tlsv1.3 --tls-max 1.3 \
  --cert access-client.crt --key access-client.key \
  --cacert your-server-ca.crt \
  "https://your-api.example.com/api/v1/loyalty/balance?member_key=abc123" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z"
```

Note that the OpenAPI spec's security scheme says "TLS 1.2+". That is the floor for cipher and protocol hygiene, not a statement that 1.2 is sufficient for interoperability. Enable 1.3.

### Decision Tree

```
Where is your loyalty API hosted?
│
├── AWS
│   ├── Application Load Balancer (ALB) ────── See references/mtls-configuration-guide.md §AWS ALB
│   ├── Network Load Balancer (NLB) ────────── See references/mtls-configuration-guide.md §AWS NLB
│   ├── API Gateway ─────────────────────────── See references/mtls-configuration-guide.md §AWS API Gateway
│   └── No LB (direct EC2) ──────────────────── See references/mtls-configuration-guide.md §Application-Level
│
├── Azure
│   └── Application Gateway v2 ──────────────── See references/mtls-configuration-guide.md §Azure
│
├── Google Cloud Platform
│   └── Cloud Load Balancer ─────────────────── See references/mtls-configuration-guide.md §GCP
│
├── On-premises / Data Center
│   ├── Nginx ───────────────────────────────── See references/mtls-configuration-guide.md §Nginx
│   └── HAProxy ─────────────────────────────── See references/mtls-configuration-guide.md §HAProxy
│
└── Application-level (any platform)
    └── Spring Boot / Node.js / Python ──────── See references/mtls-configuration-guide.md §Application-Level
```

### Two fundamental patterns

**Pattern 1: Ingress terminates mTLS (ALB, API Gateway, Azure App Gateway, GCP LB, Nginx, HAProxy)**

The load balancer/proxy validates the client certificate during the TLS handshake, terminates TLS, and forwards the request as plain HTTP to your application. Your app never sees the certificate. Some platforms can inject cert details as headers for application-level authorization.

```
Access ──[mTLS cert]──▶ Ingress (validates cert) ──[plain HTTP + optional headers]──▶ Your App
```

**Pattern 2: TCP passthrough (NLB, or no LB)**

The load balancer forwards raw TCP. Your application handles the full TLS handshake, including client certificate validation. The app reads the certificate directly from the TLS layer.

```
Access ──[mTLS cert]──▶ NLB (TCP forward, no inspection) ──[encrypted TLS]──▶ Your App (validates cert)
```

### What Access provides

During onboarding, your Access Implementation Manager will provide:
- The **trusted CA certificate** (PEM format) that signs Access's client certificate
- The **expected subject name (CN)** and **Subject Alternative Name (SAN)** for validation
- **Test endpoint URLs** for sandbox validation
- Certificate renewal timeline and process

You configure your ingress to trust this CA and reject any connection that does not present a valid client certificate signed by it.

### Critical: certificate rotation

Access client certificates expire. Access will provide a replacement certificate before expiration. You must:
1. Monitor certificate expiration dates
2. Have a process to update your trust store before the old certificate expires
3. Test the new certificate in your sandbox before production cutover
4. Consider overlapping trust (temporarily trust both old and new CA) during transitions

See `references/mtls-configuration-guide.md` for platform-specific instructions on updating trust stores.

---

## 4 - Endpoint Contract Summary

All endpoints are under `/v1/loyalty/`. Full schemas, examples, and error codes are in `references/endpoint-contract-reference.md` and `references/openapi.yaml`.

### Headers

| Header | Required | Method | Description |
|--------|----------|--------|-------------|
| `X-Request-Timestamp` | Yes | All | ISO 8601 UTC timestamp from Access |
| `X-Request-ID` | No | All | Optional correlation/audit ID, regenerated per attempt |
| `Idempotency-Key` | Yes | POST only | Stable across retries; persist for dedup |
| `program-key` | Not yet sent | GET balance, POST holds | Planned; see below. Do not require it. |
| `X-Response-Timestamp` | Yes | All responses | ISO 8601 UTC timestamp generated by your server |

### The program-key header

**Access does not currently send `program-key`.** It is documented here because it is planned for clients that run multiple loyalty programs on one API server, so that those clients can design for it now. Until it ships:

- **Do not require it.** Rejecting a request that omits `program-key` will break every call Access makes today.
- **Read it if present, otherwise fall back** to your single configured program.

It would become relevant when a single implementation serves multiple program instances with Access, which typically happens when:

- A client has multiple subscription tiers with different product access (e.g., one program for hotels-only, another for hotels + theme parks)
- A client operates multiple brands or divisions that are billed independently by Access
- A single API server handles loyalty points for multiple Access programs

If you think you need multi-program support, raise it with your Access Implementation Manager rather than building against this header.

### Error responses

All errors use a standard JSON body:

```json
{
  "error_code": "INSUFFICIENT_POINTS",
  "message": "Member has 500 points; requested 10000",
  "details": {}
}
```

The HTTP status depends on the operation, because each operation defines its own set of responses. Use this table, not a single global mapping:

| `error_code` | HTTP Status | Operations | When to use |
|---|---|---|---|
| `INVALID_REQUEST` | 400 | All | Validation failure (bad fields, missing required) |
| `INSUFFICIENT_POINTS` | 409 | Holds | Not enough available points for the hold |
| `HOLD_NOT_FOUND` | 404 | Cancel | Hold ID does not exist |
| `HOLD_NOT_FOUND` | 409 | Redemptions | Hold does not exist or has expired. Redemptions define no 404. |
| `MEMBER_NOT_FOUND` | 404 | Balance | `member_key` does not match any member |
| `ALREADY_PROCESSED` | 409 | Redemptions, refunds, cancel | Hold already redeemed or cancelled; refund already processed |
| `ERROR` | 500 | All | Internal server error |

Note that `POST /v1/loyalty/holds` defines only 400, 409, and 500. If `member_key` is unknown at hold time, return 400 `INVALID_REQUEST` rather than a 404 the contract does not define.

---

## 5 - Idempotency and Hold Lifecycle

### Idempotency (critical)

All POST endpoints receive an `Idempotency-Key` header from Access. This key is stable across retries of the same logical operation. Your implementation **must**:

1. Persist the `Idempotency-Key` with the response for every processed request
2. On receiving a duplicate key, return the original response without re-executing the operation
3. Use whatever backing store fits your stack (Redis, database table, etc.)

This follows the [Stripe idempotency convention](https://docs.stripe.com/api/idempotent_requests). See `references/hold-lifecycle-and-idempotency.md` for implementation patterns.

### Hold lifecycle

```
    ┌─────────┐     POST /holds      ┌─────────┐
    │ (none)  │ ──────────────────▶ │ ACTIVE  │
    └─────────┘                     └────┬────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
              POST /redemptions   POST /holds/{id}/cancel   (auto-expire
                    │                    │                  after duration)
                    ▼                    ▼                    │
              ┌─────────┐          ┌──────────┐              ▼
              │ REDEEMED│          │CANCELLED │         ┌─────────┐
              └────┬────┘          └──────────┘         │ EXPIRED │
                   │                                     └─────────┘
              POST /refunds
                   │
                   ▼
              ┌──────────┐
              │ REFUNDED │  (points credited back)
              └──────────┘
```

Key rules:
- **Hold duration**: Access standard is 5 minutes. Your system must auto-release unredeemed holds after expiry.
- **Redemption requires an active hold**: You cannot redeem without a prior hold.
- **Cancel vs refund**: Cancel releases a hold (points were never deducted). Refund credits back already-deducted points after a redemption.
- **Atomicity**: Use database transactions for hold and redemption operations to prevent double-spending under concurrent requests.

See `references/hold-lifecycle-and-idempotency.md` for detailed implementation guidance.

---

## 6 - Response Time Budget and Retry Behavior

Access enforces a strict timeout on every call. Your endpoints must answer well inside it, or the integration will fail in ways that are hard to diagnose from your side.

| Property | Value |
|---|---|
| Connect / read / write timeout | **5 seconds each** |
| Attempts per logical operation | **3** (1 initial + 2 retries) |
| Backoff between attempts | 500ms, then 1000ms |
| Retried | 5xx responses and connection/IO failures |
| **Not** retried | **All 4xx responses** |
| Circuit breaker | Opens after 5 consecutive failed calls, stays open 30 seconds |

What this means for your implementation:

- **Answer within 5 seconds.** A hold that takes 8 seconds will never succeed, no matter how correct it is. Access sees a read timeout, retries twice, and gives up. Budget for your slowest dependency, not your median.
- **Return 4xx for real client errors only.** A 4xx stops Access immediately with no retry. Returning 400 for a transient internal problem turns a recoverable blip into a lost booking. Use 5xx for anything you want retried.
- **This is why idempotency matters.** All three attempts carry the same `Idempotency-Key`. If your server processed attempt 1 but the response was lost, attempts 2 and 3 must return the stored response rather than creating a second hold or deducting points twice. See section 5.
- **Sustained failures trip a breaker.** After 5 consecutive failures Access stops calling your endpoints for 30 seconds. During that window every transaction that would use points fails. Recovery is automatic, but a flapping endpoint produces disproportionate customer impact.
- **`X-Request-ID` changes per attempt; `Idempotency-Key` does not.** Correlate retries by `Idempotency-Key`, not by `X-Request-ID`.

---

## 7 - Data Precision Rules

- **Points are integers** - no fractions. A member has 250000 points, not 250000.5.
- **USD values are strings** - always use string representation (e.g., `"0.01"`, `"100.00"`) to avoid floating-point precision issues. This follows best practices for financial APIs.
- **Exchange rate is a string** - `loyalty_point_to_usd_exchange_rate` is a string like `"0.01"` (1 point = $0.01). The pattern is `^\d+\.\d{2}$`.
- **All monetary values are in USD** today. Additional currencies are planned.

---

## 8 - Testing

### Quick test with curl

```bash
# Test balance endpoint (with mTLS client cert)
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  "https://your-api.example.com/api/v1/loyalty/balance?member_key=abc123" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z"

# Test hold creation
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  -X POST "https://your-api.example.com/api/v1/loyalty/holds" \
  -H "Content-Type: application/json" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z" \
  -H "Idempotency-Key: hold-001" \
  -d '{
    "member_key": "abc123",
    "points_requested": 10000,
    "hold_duration_minutes": 5,
    "transaction_description": "Hotel booking hold"
  }'
```

See `references/testing-and-troubleshooting.md` for:
- Full test scenarios (happy path, insufficient points, hold expiry, duplicate idempotency)
- Platform-specific debug commands
- Common error diagnosis
- Go-live validation checklist

---

## 9 - Go-Live Checklist

Before production launch, confirm:

- [ ] All five endpoints implemented and tested against the OpenAPI spec
- [ ] mTLS configured at your ingress - Access client certificate validated before requests reach your app
- [ ] **TLS 1.3 verified end to end** with `curl --tlsv1.3 --tls-max 1.3` (Access will not fall back to 1.2)
- [ ] **p99 response time under 5 seconds** on all five endpoints, measured under production-like load
- [ ] Transient/internal failures return 5xx, not 4xx (Access never retries a 4xx)
- [ ] Server does not require `program-key` and accepts requests that omit it
- [ ] Trust store contains the Access CA certificate (complete chain including intermediates)
- [ ] Idempotency key persistence working (duplicate keys return original response)
- [ ] Hold auto-expiration implemented (unredeemed holds released after duration)
- [ ] Error responses match the spec's `ErrorResponse` schema with correct `error_code` values
- [ ] `X-Response-Timestamp` header included on all responses
- [ ] All USD values serialized as strings (not numbers)
- [ ] All points values are integers
- [ ] JSON field names use snake_case (e.g., `member_key`, `points_requested`)
- [ ] Certificate expiration monitoring configured
- [ ] Sandbox testing completed with Access
- [ ] Domains added to Access CSP allowlist
- [ ] Access Implementation Manager has validated the mTLS handshake

---

## Reference Files

| File | Description |
|------|-------------|
| `references/openapi.yaml` | OpenAPI 3.0 specification (source of truth for endpoint contract) |
| `references/mtls-configuration-guide.md` | Platform-by-platform mTLS setup (AWS, Azure, GCP, Nginx, HAProxy, application-level) |
| `references/endpoint-contract-reference.md` | Detailed endpoint schemas, request/response examples, error codes |
| `references/hold-lifecycle-and-idempotency.md` | Hold states, redemption flow, refund handling, idempotency patterns |
| `references/testing-and-troubleshooting.md` | Test scenarios, curl commands, common issues, debug guide |

---

*For questions or support, contact your Access Implementation Manager.*
