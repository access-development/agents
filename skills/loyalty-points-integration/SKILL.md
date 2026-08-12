---
name: loyalty-points-integration
description: |
  Implement the Access Development Loyalty Points API on your server. This skill guides you
  through building the five REST endpoints Access calls to manage loyalty point balances,
  holds, redemptions, refunds, and cancellations. Covers the OpenAPI 3.0 contract, mTLS
  intake (who validates the client cert: the app, a cloud load balancer, or a reverse
  proxy), platform recipes, idempotency, hold lifecycle, and testing. Use when integrating
  loyalty points redemption ("burn") into the Access Travel Platform.
trigger: |
  Use when the developer wants to implement loyalty points endpoints for the Access Travel
  Platform, configure mTLS for Access client certificate authentication, scaffold a loyalty
  points server from the OpenAPI spec, troubleshoot an mTLS handshake failure, or understand
  the hold/redeem/refund lifecycle for loyalty point transactions.
---

# Access Development - Loyalty Points Integration Skill

You are an expert integration engineer helping a developer implement the **Access Loyalty Points API** on their server. Access calls these endpoints during the travel shopping flow to manage loyalty point balances, holds, redemptions, refunds, and cancellations. Your job is to guide them through the contract, security configuration, and testing in whatever language, framework, and hosting environment they use.

## How to use this skill

When a developer asks for help implementing loyalty points integration, follow the progressive disclosure pattern below. Start with the **Quick-Start Journey** that matches their need, then drill into the relevant reference sections as questions arise. For anything involving mTLS, run the section 3 intake before generating security code. The five endpoints do not wait on that answer.

---

## 1 - Architecture Overview

```
┌─────────────────────┐         ┌──────────────────────────────────────────┐
│  Access Payment API │ ── mTLS ─▶│  Public hostname of your loyalty API     │
│  (the caller)       │           │  TLS 1.3 · Access client cert required   │
└─────────────────────┘           └──────────────────┬───────────────────────┘
        │                                            │
        │ OkHttp + PKCS12                            │
        │ TLS 1.3 only (no 1.2 fallback)             │
        │ 5s timeout, 3 attempts, breaker            │
                                                     │
              ┌──────────────────────────────────────┼──────────────────────────────────────┐
              │                                      │                                      │
       Cloud LB validates                  Reverse proxy validates                 App validates
       (ALB / App Gateway /                (nginx / HAProxy / F5)                  (or TCP passthrough)
        Cloud LB / API GW)
              │                                      │                                      │
              └──────────────────┬───────────────────┘                                      │
                                 │                                                          │
                      App sees HTTP                                              App terminates TLS
                      Optional internal                                          Keystore + truststore
                      trust signal; the name                                     client-auth = need
                      is yours, not Access's
```

**Key principle**: Access is the caller. The client implements five REST endpoints. Access presents a client certificate signed by a CA they provide. **The hop that terminates the public hostname must validate that certificate.** That hop is often a cloud load balancer or reverse proxy, not the application. Access is satisfied at that hop. What happens behind it is the client's network policy.

### What you implement

| Endpoint | Method | Purpose |
|---|---|---|
| `/v1/loyalty/balance` | GET | Return available points balance and point-to-USD valuation |
| `/v1/loyalty/holds` | POST | Reserve (hold) points for a pending transaction |
| `/v1/loyalty/holds/{hold_id}/cancel` | POST | Release a previously created hold |
| `/v1/loyalty/redemptions` | POST | Deduct points for a confirmed booking |
| `/v1/loyalty/refunds` | POST | Credit points back for a refunded transaction |

All paths are relative to your base URL (e.g., `https://your-api.example.com/api`).

### Prerequisites

1. **Access Travel SDK integrated** - The SDK handles member onboarding and produces the `member_key` used in all loyalty requests. See the [Access Travel Integration skill](../access-travel-integration/) for setup.
2. **API credentials from Access** - Access provisions mTLS certificate details (trusted CA, expected subject/SAN), test endpoint URLs, and program-specific configuration during onboarding.
3. **Domain allowlisting** - Your domains must be added to Access's CSP allowlist before deployment.

---

## 2 - Quick-Start Journeys

### Journey A - "I need to implement the loyalty endpoints"

1. **Review the OpenAPI spec** (see `references/openapi.yaml`) - it is the source of truth for request/response schemas, headers, and error codes.
2. **Run the mTLS intake** (section 3). Implement the five endpoints without waiting on Q1. Do not generate a keystore, ingress config, or trust-header check until Q1 is answered.
3. **Implement the five endpoints** (see `references/endpoint-contract-reference.md` for detailed schemas and examples).
4. **Handle idempotency and hold lifecycle** (see `references/hold-lifecycle-and-idempotency.md`).
5. **Test with curl** (see `references/testing-and-troubleshooting.md`).
6. **Coordinate go-live** with your Access Implementation Manager.

### Journey B - "I need to configure mTLS security"

1. **Run the mTLS intake** (section 3). Ask Q1 as a numbered list. If the answer is "I don't know," emit the [Network-team brief](references/mtls-configuration-guide.md#network-team-brief) and pause mTLS work.
2. **Load only the matching section** of `references/mtls-configuration-guide.md` after Q1 is answered.
3. **Obtain the Access client CA certificate** from the Access Implementation Manager.
4. **Configure the hop that terminates the public hostname** — or produce the network-team brief if the developer does not own that hop.
5. **Test the mTLS handshake** against the public hostname using the curl commands in the troubleshooting reference.
6. **Set up certificate expiration monitoring** - Access will provide a new client cert before the old one expires. The trust store on the validating hop needs a documented update process.

### Journey C - "I'm troubleshooting an mTLS handshake failure"

1. **Check the troubleshooting section** in `references/testing-and-troubleshooting.md`.
2. **Verify the CA chain is complete** on the hop that actually validates the cert - the most common cause of mTLS failures is an incomplete certificate chain (missing intermediate CA).
3. **Test against the public hostname first.** Then, only if that hop is not the app, test the app directly to isolate where the handshake fails.
4. **Check platform-specific pitfalls** in `references/mtls-configuration-guide.md` for the validating hop, not for the app by default.

### Journey D - "I need to understand the hold/redeem/refund lifecycle"

1. **Read `references/hold-lifecycle-and-idempotency.md`** for the full lifecycle.
2. Key concepts: holds reserve points (5 min default), redemption converts a hold to a permanent deduction, refunds credit points back after a redemption, cancel releases a hold without deducting points.
3. **Idempotency is mandatory** - all POST endpoints receive an `Idempotency-Key` header. You must persist it and return the original response on duplicate requests.

---

## 3 - mTLS Security Configuration

mTLS is the sole authentication mechanism in the OpenAPI spec. Access presents a client certificate signed by a CA they provide. **The hop that terminates the public hostname must validate that certificate.** That hop is often not the application.

Access does not send an API key or bearer token. Access does not define any HTTP header as part of this contract. An internal trust header, if the client's network already injects one, is their policy.

### Access invariants

These apply to whichever hop terminates the public hostname:

- **TLS 1.3.** Access will not fall back to TLS 1.2.
- **Client cert required**, signed by the Access-provided CA (full chain, including intermediates).
- **Missing or untrusted cert rejected** before business logic.
- **CN / SAN checks** where the platform supports them, using the values the Implementation Manager sends. Do not invent those values.

The OpenAPI security scheme requires TLS 1.3. Access will not fall back to TLS 1.2.

```bash
# Must succeed against the public hostname. If this fails, Access cannot reach you.
curl -v --tlsv1.3 --tls-max 1.3 \
  --cert access-client.crt --key access-client.key \
  --cacert your-server-ca.crt \
  "https://your-api.example.com/api/v1/loyalty/balance?member_key=abc123" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z"
```

`curl` without `--tls-max 1.3` will happily negotiate TLS 1.2 and pass against a server Access cannot reach.

### Intake (required before any mTLS code)

Ask these as **ordinary conversation**, one question per turn. Present discrete choices as a numbered list. Accept a number or a short phrase. Do **not** call a structured-option tool (`AskUserQuestion` or equivalent): this skill is used in Claude Code, Cursor, Copilot, and other agents that have no common question widget.

Before asking language, cloud, or framework, inspect the repo. Do not ask what is already obvious.

**Q1 — Who validates the Access client certificate?** Ask this before generating a keystore, ingress config, or trust-header check.

```
1. The application — TLS (and the client cert) reaches our process. We need a keystore / truststore.
2. A cloud load balancer — AWS / Azure / GCP validates at the edge, then forwards to the app.
3. An edge reverse proxy — nginx, HAProxy, F5, or similar validates, then forwards to the app.
4. I don't know. Give me something I can send to our network / DevOps team.
```

Scenario 1 is the uncommon case (no LB, or TCP passthrough such as AWS NLB). Default to assuming the edge terminates TLS until Q1 says otherwise.

If they pick 4, or hesitate, **pause mTLS work** and emit the [Network-team brief](references/mtls-configuration-guide.md#network-team-brief) verbatim (fill in only the hostname). Keep implementing the five endpoints.

**Q2 — one follow-up, only after Q1.**

| Q1 | Ask next | Then |
|---|---|---|
| 1 Application | Language / runtime if not obvious. Anything in front (NLB, mesh sidecar) that might still terminate TLS? | Load `references/mtls-configuration-guide.md` §Application-Level. Add §AWS NLB only if they are on AWS TCP passthrough. Generate keystore / `client-auth=need` (or equivalent). |
| 2 Cloud LB | Which product, if they know it: ALB, NLB, API Gateway, Azure App Gateway v2, GCP Application LB. NLB is scenario 1 (passthrough). Do they own the LB config? | Do **not** put TLS in the app. Load only the matching cloud section. Generate LB config only if they own that layer; otherwise emit the [network-team brief](references/mtls-configuration-guide.md#network-team-brief). |
| 3 Reverse proxy | nginx, HAProxy, F5, or other? Do they own that config? Dedicated vhost vs shared? | Same split: generate proxy config only if they own it. Prefer a dedicated vhost over path-based optional verify. |
| 4 Unsure | Stop asking. Hand over the brief. Offer to keep going on the five endpoints. | Do not load a platform section. Do not invent a fourth recipe. |

**Q3 — only if they volunteer that the app should re-check a trust signal.** Ask for the header (or equivalent) **their network team already uses**, and how the app is isolated so that signal cannot be spoofed. If they do not name one, the app checks nothing. Never invent a header name (`X-SSL-Client-Verify`, `x-amzn-mtls-clientcert`, or any other).

### Other topologies (CDN, F5, Apigee, mesh)

Do not add a fourth recipe. Walk the hop chain with two questions until one hop answers yes to (1):

1. Does this hop terminate TLS and validate the Access client cert against the Access CA?
2. What does the next hop receive: still encrypted TLS, or HTTP plus an internal signal?

That hop is the Access security boundary. The three scenarios above are enough color for a network team to configure it.

### Two implementation patterns

Interview in **scenarios** (how network teams talk). Implement in **patterns** (what the code does).

- **Pattern A — edge terminates** (scenarios 2 and 3). The app sees HTTP. Do not generate a keystore. An internal trust signal is optional and named by the client, not by Access. It is only trustworthy if the edge is in verify / reject-invalid mode **and** the app is not reachable except through that hop.
- **Pattern B — app terminates** (scenario 1, including NLB TCP passthrough). The app needs a server keystore, a truststore containing the Access CA, and `client-auth=need` (or equivalent).

Platform recipes, header examples, and cert rotation live in `references/mtls-configuration-guide.md`. Load a section only after Q1. During onboarding the Implementation Manager provides the CA PEM, expected CN/SAN, sandbox URLs, and the rotation timeline.

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

**Access does not currently send `program-key`.** Shipping it is tracked by PD-7890 and PD-7891. It is documented here so multi-program clients can design for it. Until those tickets are in production:

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
- [ ] mTLS enforced at the hop that terminates the public hostname — Access client cert validated there
- [ ] **TLS 1.3 verified against the public hostname** with `curl --tlsv1.3 --tls-max 1.3` (Access will not fall back to 1.2)
- [ ] **p99 response time under 5 seconds** on all five endpoints, measured under production-like load
- [ ] Transient/internal failures return 5xx, not 4xx (Access never retries a 4xx)
- [ ] Server does not require `program-key` and accepts requests that omit it
- [ ] Trust store on the validating hop contains the Access CA certificate (complete chain including intermediates)
- [ ] App does not invent or require an Access-defined trust header
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

## Instruction to the LLM

1. If the travel SDK is not already working, point at the [Access Travel Integration skill](../access-travel-integration/) first. `member_key` comes from it.
2. Follow section 3 for all mTLS work: one numbered question per turn, no structured-option tool, no keystore unless Q1 is scenario 1, no invented trust header.
3. Implement the five endpoints without waiting on Q1. If Q1 is unanswered, emit the Network-team brief from the mTLS guide and continue with business logic.
4. Load only the matching section of `references/mtls-configuration-guide.md` after Q1.
5. Do not require `program-key`. Redemptions may arrive with only `hold_id`; resolve the rest from the stored hold.

---

## Reference Files

| File | Description |
|------|-------------|
| `references/openapi.yaml` | OpenAPI 3.0 specification (source of truth for endpoint contract) |
| `references/mtls-configuration-guide.md` | Intake follow-through, network-team brief, and platform recipes (AWS, Azure, GCP, Nginx, HAProxy, application-level) |
| `references/endpoint-contract-reference.md` | Detailed endpoint schemas, request/response examples, error codes |
| `references/hold-lifecycle-and-idempotency.md` | Hold states, redemption flow, refund handling, idempotency patterns |
| `references/testing-and-troubleshooting.md` | Test scenarios, curl commands, common issues, debug guide |

---

*For questions or support, contact your Access Implementation Manager.*
