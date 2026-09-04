# Testing and Troubleshooting

This guide covers test scenarios, curl commands, common issues, and a go-live validation checklist for the Access Loyalty Points API.

> **Fixture credentials in this document are for offline test runs only. Do not use the fixture secret for any real program.** The fixture secret is published in `references/hmac-signing-spec.md` § "Test vectors (VERIFIED)" so any verifier implementation can reproduce the algorithm offline.

---

## 0 - Reproduce Spec Test Vectors 1–3 (always do this first)

Before testing against your live endpoint, **write a unit test that reproduces the spec's three test vectors exactly** with the fixture secret. If your verifier cannot reproduce these, you have a canonical-string or HMAC algorithm bug. Test vector 1 below is the GET balance case; refer to `references/hmac-signing-spec.md` for vectors 2 and 3.

```
Fixture secret : test_loyalty_hmac_secret_do_not_use_in_prod
Fixture key_id : hmac_key_1
Vector 1 t     : 1787313600 (2026-08-21T12:00:00Z)
```

| Field | Value |
|---|---|
| METHOD | `GET` |
| path_and_query | `/api/v1/loyalty/balance?member_key=abc123` |
| body | empty (0 bytes) |
| body_sha256_hex | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| canonical | `1787313600.GET./api/v1/loyalty/balance?member_key=abc123.e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| v1 | `d910ff46fe7cddbc1c6580148a10dc0a170e221bcc3a6e77e8a0fcfc47e048bf` |

Pass criteria: your verifier computes `v1 = d910ff46fe7cddbc1c6580148a10dc0a170e221bcc3a6e77e8a0fcfc47e048bf` from this canonical string. If you get a different v1, your canonical string encoding or SHA-256/HMAC-SHA256 implementation is wrong. **Fix this before debugging anything else.**

Python one-liner (matches the spec's reproduction example):

```python
import hmac, hashlib
secret = b"test_loyalty_hmac_secret_do_not_use_in_prod"
canonical = b"1787313600.GET./api/v1/loyalty/balance?member_key=abc123.e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
print(hmac.new(secret, canonical, hashlib.sha256).hexdigest())
# d910ff46fe7cddbc1c6580148a10dc0a170e221bcc3a6e77e8a0fcfc47e048bf
```

---

## Test Scenarios

### Prerequisites

- Fixture secret (`test_loyalty_hmac_secret_do_not_use_in_prod`) and fixture key id (`hmac_key_1`) for offline vector reproduction only
- Per-program key id and secret issued by your Access Implementation Manager for sandbox testing
- Test `member_key` values provided by Access (e.g., `abc123`)
- Your base URL (e.g., `https://loyalty.yourdomain.com/api`)
- An HMAC-capable curl alternative or shell helper for signing requests. `openssl dgst -sha256 -hmac` works for one-off curl tests; for sustained testing, see "Computing v1" below.

### Important note on request signing

The curl examples below use placeholder `<v1>` values. **You must compute them per request.** Each request has a fresh `t` (Unix epoch second at the moment of the request) and a fresh body SHA-256, so the v1 is per-request. Use the algorithm in `references/hmac-signing-spec.md`; do not transcribe example values from documentation into live calls.

A minimal shell helper you can drop into your toolbox:

```bash
hmac_v1() {
  # args: secret, t, method, path_and_query, body_file_or_empty
  local secret="$1" t="$2" method="$3" path_and_query="$4" body="${5:-}"
  local body_sha
  if [ -z "$body" ] || [ "$body" = "-" ]; then
    body_sha=$(printf '' | openssl dgst -sha256 -binary | xxd -p -c 64)
  else
    body_sha=$(printf '%s' "$body" | openssl dgst -sha256 -binary | xxd -p -c 64)
  fi
  local canonical="${t}.${method}.${path_and_query}.${body_sha}"
  printf '%s' "$canonical" | openssl dgst -sha256 -hmac "$secret" -binary | xxd -p -c 64
}
```

For exact byte parity with the spec's test vectors and with the Access payment-api signer (`LoyaltyHmacInterceptor`), use this same canonical-string construction and the same hex encoding (lowercase). UTF-8 encoding must apply to the secret and the canonical string when HMAC computes.

### 1. Balance - Happy Path

```bash
T=$(date -u +%s)
SECRET="<your-real-sandbox-secret>"   # never commit a real secret
KEY_ID="hmac_key_1"
# path_and_query must match exactly what your server receives, including any URL prefix
PATH_Q="/api/v1/loyalty/balance?member_key=abc123"
V1=$(hmac_v1 "$SECRET" "$T" "GET" "$PATH_Q" "")

curl -v \
  "https://loyalty.yourdomain.com${PATH_Q}" \
  -H "X-Access-Key-Id: ${KEY_ID}" \
  -H "X-Access-Signature: t=${T},v1=${V1}" \
  -H "X-Request-Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

**Expected**: 200 with JSON body containing `member_key`, `available_points`, `loyalty_point_to_usd_exchange_rate`, `timestamp`. Response includes `X-Response-Timestamp` header.

### 2. Balance - Member Not Found

Same as test 1 but with a `member_key` known not to exist. Re-run the full request - `t` and `v1` are recomputed for the new path and query; reading this as "just change PATH_Q and run the same curl" will fail with 401 because the signature was over a different path.

```bash
T=$(date -u +%s)
SECRET="<your-real-sandbox-secret>"
KEY_ID="hmac_key_1"
PATH_Q="/api/v1/loyalty/balance?member_key=nonexistent"
V1=$(hmac_v1 "$SECRET" "$T" "GET" "$PATH_Q" "")

curl -v \
  "https://loyalty.yourdomain.com${PATH_Q}" \
  -H "X-Access-Key-Id: ${KEY_ID}" \
  -H "X-Access-Signature: t=${T},v1=${V1}" \
  -H "X-Request-Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

**Expected**: 404 with `{"error_code": "MEMBER_NOT_FOUND", "message": "..."}`. The HMAC signature must still be valid here - the verifier authenticates **before** the business logic sees the request.

### 3. Create Hold - Happy Path

```bash
T=$(date -u +%s)
BODY='{"member_key":"abc123","points_requested":10000,"hold_duration_minutes":5,"transaction_description":"Test hotel booking hold"}'
PATH_Q="/api/v1/loyalty/holds"
V1=$(hmac_v1 "$SECRET" "$T" "POST" "$PATH_Q" "$BODY")

curl -v \
  -X POST "https://loyalty.yourdomain.com${PATH_Q}" \
  -H "Content-Type: application/json" \
  -H "X-Access-Key-Id: ${KEY_ID}" \
  -H "X-Access-Signature: t=${T},v1=${V1}" \
  -H "X-Request-Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -H "Idempotency-Key: test-hold-001" \
  -d "$BODY"
```

**Expected**: 201 with JSON body containing `hold_id`, `status: "ACTIVE"`, `expires_at`, `points_held: 10000`.

**Save the `hold_id`** for subsequent tests.

### 4. Create Hold - Insufficient Points

Same as test 3 but with a `points_requested` above the test member's balance:

```bash
BODY='{"member_key":"abc123","points_requested":900000,"hold_duration_minutes":5,"transaction_description":"Test insufficient points"}'
```

**Expected**: 409 with `{"error_code": "INSUFFICIENT_POINTS", "message": "..."}`.

Use a value inside the documented range (min 1, max 1,000,000) but above your test member's balance. A value above 1,000,000 tests range validation instead, and a correct server answers that with 400 `INVALID_REQUEST`. Adjust `900000` to suit your test member.

### 5. Idempotency - Duplicate Key

Send the same `Idempotency-Key` twice with otherwise-identical bodies. The HMAC signature differs across the two calls because the body bytes are identical but `t` differs - that is fine; the contract is to verify, not to dedupe by signature.

```bash
# First request
curl -v \
  -X POST "https://loyalty.yourdomain.com/api/v1/loyalty/holds" \
  -H "Content-Type: application/json" \
  -H "X-Access-Key-Id: ${KEY_ID}" \
  -H "X-Access-Signature: t=${T1},v1=${V1_A}" \
  -H "X-Request-Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -H "Idempotency-Key: test-hold-dup-001" \
  -d "$BODY"

# Second request with SAME Idempotency-Key, fresh t
curl -v \
  -X POST "https://loyalty.yourdomain.com/api/v1/loyalty/holds" \
  -H "Content-Type: application/json" \
  -H "X-Access-Key-Id: ${KEY_ID}" \
  -H "X-Access-Signature: t=${T2},v1=${V1_B}" \
  -H "X-Request-Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -H "Idempotency-Key: test-hold-dup-001" \
  -d "$BODY"
```

**Expected**: Both responses return the same `hold_id` and response body. The second request does not create a new hold.

### 6. Redeem - Happy Path

Replace `HOLD_ID` with the `hold_id` from test 3:

```bash
T=$(date -u +%s)
BODY='{"hold_id":"HOLD_ID","member_key":"abc123","points_to_redeem":10000,"transaction_details":{"transaction_id":"test-txn-001","type":"HOTEL_BOOKING","description":"Test hotel booking","supplier_confirmation":"CONF-TEST-001","usd_value":"100.00"}}'
PATH_Q="/api/v1/loyalty/redemptions"
V1=$(hmac_v1 "$SECRET" "$T" "POST" "$PATH_Q" "$BODY")

curl -v \
  -X POST "https://loyalty.yourdomain.com${PATH_Q}" \
  -H "Content-Type: application/json" \
  -H "X-Access-Key-Id: ${KEY_ID}" \
  -H "X-Access-Signature: t=${T},v1=${V1}" \
  -H "X-Request-Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -H "Idempotency-Key: test-redeem-001" \
  -d "$BODY"
```

**Expected**: 200 with `status: "SUCCESS"`, `points_redeemed: 10000`, `transaction_id: "test-txn-001"`.

### 7. Cancel Hold - Happy Path

```bash
# (Create hold first - see test 3)

T=$(date -u +%s)
BODY='{"reason":"Test cancellation"}'
PATH_Q="/api/v1/loyalty/holds/HOLD_ID/cancel"
V1=$(hmac_v1 "$SECRET" "$T" "POST" "$PATH_Q" "$BODY")

curl -v \
  -X POST "https://loyalty.yourdomain.com${PATH_Q}" \
  -H "Content-Type: application/json" \
  -H "X-Access-Key-Id: ${KEY_ID}" \
  -H "X-Access-Signature: t=${T},v1=${V1}" \
  -H "X-Request-Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -H "Idempotency-Key: test-cancel-001" \
  -d "$BODY"
```

**Expected**: 200 with `status: "CANCELLED"`. Verify the member's balance is restored.

### 8. Refund - Happy Path

Refund the redemption from test 6:

```bash
T=$(date -u +%s)
BODY='{"original_transaction_id":"test-txn-001","refund_points":10000,"reason":"Test refund"}'
PATH_Q="/api/v1/loyalty/refunds"
V1=$(hmac_v1 "$SECRET" "$T" "POST" "$PATH_Q" "$BODY")

curl -v \
  -X POST "https://loyalty.yourdomain.com${PATH_Q}" \
  -H "Content-Type: application/json" \
  -H "X-Access-Key-Id: ${KEY_ID}" \
  -H "X-Access-Signature: t=${T},v1=${V1}" \
  -H "X-Request-Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -H "Idempotency-Key: test-refund-001" \
  -d "$BODY"
```

**Expected**: 200 with `status: "REFUNDED"`, `points_refunded: 10000`. Verify balance is restored.

### 9. Hold Expiry

1. Create a hold with a short duration (e.g., `hold_duration_minutes: 1`).
2. Wait for the hold to expire.
3. Call balance to verify points are restored.
4. Attempt to redeem the expired hold (expect `HOLD_NOT_FOUND` or `ALREADY_PROCESSED`).

The status is 409 on the redemptions endpoint and 404 on the cancel endpoint. See the per-operation error table in `endpoint-contract-reference.md`.

### 10. HMAC - Missing `X-Access-Key-Id` or `X-Access-Signature`

Send a request with no signing headers:

```bash
curl -v \
  "https://loyalty.yourdomain.com/api/v1/loyalty/balance?member_key=abc123" \
  -H "X-Request-Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

**Expected**: 401 with `error_code: "AUTHENTICATION_FAILED"`. The body must not distinguish the cause from other 401 cases.

### 11. HMAC - Stale Timestamp (more than 300 seconds old)

Sign a request with `t` set to a value 400 seconds in the past:

```bash
T=$(($(date -u +%s) - 400))
# … sign a vector-1 GET as in test 1, using $T …
```

**Expected**: 401 with `error_code: "AUTHENTICATION_FAILED"`. The verifier must **not** accept the request based on signature match alone - clock-skew protection runs first.

### 12. HMAC - Wrong Secret

Use the spec's fixture secret to sign a request that the verifier expects to validate against a different (correct) secret.

**Expected**: 401 with `error_code: "AUTHENTICATION_FAILED"`. This test catches:
- A verifier that compares against every secret it holds (forbidden during rotation per spec - defeats key retirement).
- A verifier that mistakenly uses the wrong key for the given `key_id`.

### 13. HMAC - Pretty-printed Body

Sign a request body that re-serializes the same logical JSON with extra whitespace:

```bash
# Compact (the body Access actually sends)
COMPACT='{"member_key":"abc123","points_requested":10000,"hold_duration_minutes":5,"transaction_description":"Test"}'
# Pretty:
PRETTY=$'{\n  "member_key": "abc123",\n  "points_requested": 10000,\n  "hold_duration_minutes": 5,\n  "transaction_description": "Test"\n}'
```

Sign the compact body. Re-hash the pretty body in the verifier to confirm it differs:

```bash
echo -n "$COMPACT" | openssl dgst -sha256
echo -n "$PRETTY" | openssl dgst -sha256
```

The hex digests differ. Your verifier must compute the body SHA-256 over the exact bytes on the wire, not a re-serialized form. **Expected**: signing with the compact body's v1 against a server that received the pretty body returns 401. Sending the compact body that matches what Access actually transmits succeeds.

### 14. HMAC - Path Prefix Mismatch

Access signs `/api/v1/loyalty/holds`. If your platform routes everything at `/v1/loyalty/holds` directly (no `/api` prefix), the path the verifier hashes must match what was received. Sending a request signed for `/api/v1/loyalty/holds` against a server that received `/v1/loyalty/holds` will fail verification - your verifier must hash the received path, not a hardcoded one.

**Expected**: 401 with `error_code: "AUTHENTICATION_FAILED"`. This test catches signers that hardcode the path portion or that strip `/api` before hashing.

### 15. HMAC - Reordered JSON Keys

The body Access sends has keys in a stable order. Sign that exact byte sequence. If your verifier parses JSON and re-serializes to canonicalize keys before hashing, you will accept any permutation. **Always hash the wire bytes.**

```bash
# Correct order Access sends
ORDER_A='{"member_key":"abc123","points_requested":10000,"hold_duration_minutes":5,"transaction_description":"Test"}'
# Re-ordered
ORDER_B='{"hold_duration_minutes":5,"transaction_description":"Test","member_key":"abc123","points_requested":10000}'

echo -n "$ORDER_A" | openssl dgst -sha256
echo -n "$ORDER_B" | openssl dgst -sha256
```

The hex digests differ. Send signed ORDER_A → accept. Send signed ORDER_A to a verifier that re-serialized as ORDER_B internally would still hash the bytes it received and reject; that is correct.

### 16. TLS 1.3 Negotiation (optional but recommended)

`X-Access-Signature` works over either TLS 1.2 or 1.3. To confirm your ingress supports 1.3:

```bash
openssl s_client -connect loyalty.yourdomain.com:443 -tls1_3
```

If your TLS policy caps at 1.2, returns a downgrade error, or otherwise fails here, fix the TLS policy on the validating hop before go-live. Access will negotiate either, so this is a regression check, not a hard requirement.

---

## Common Issues

### "401 AUTHENTICATION_FAILED" with no obvious cause

**Cause**: Most often a canonical-string construction mismatch. Re-run the spec vectors in your verifier unit tests - if those pass, walk through the live request byte by byte.

**Fix**:
1. Confirm `t` in the request matches the `t` you signed.
2. Confirm `path_and_query` matches exactly - same query order, same encoding.
3. Confirm `body_sha256` matches the bytes transmitted (compact JSON, no re-serialization).
4. Confirm secret matches (key id → secret mapping correct).
5. Confirm the comparison is constant-time (`MessageDigest.isEqual`, `crypto.timingSafeEqual`, `hmac.compare_digest`, or `CryptographicOperations.FixedTimeEquals`).

### Spec vectors pass, live requests still 401

**Cause**: Likely a query-encoding mismatch between your curl helper and your server's parser. `URLEncoder.encode` emits `+` for space; the spec requires RFC 3986 (`%20`).

**Fix**: Use the `hmac_v1()` shell helper above (which writes the path-and-query verbatim), or compute v1 inside your test client using the same UTF-8 + RFC 3986 path string your server actually received (echoed from a `request.getPath()` if your framework exposes it).

### 401 on a request that was just fine a minute ago

**Cause**: Replay window exceeded. `t` must be within ±300 seconds of your verifier's UTC clock. Skewed clocks, NTP drift, or sending at the boundary can drop requests.

**Fix**: Confirm NTP sync, ensure both sides compute `t` from system time (not request start time), and instrument logs to print both client and server `t` together for skew debugging.

### Idempotency keys stuck returning cached 401s

**Cause**: Your idempotency layer is caching 401 responses. Per spec, do not persist `Idempotency-Key` for 401s.

**Fix**: In your idempotency check, persist only after successful HMAC verification. A later retry with a valid signature must execute even if the same `Idempotency-Key` produced 401 previously.

### Balance works but holds return 409 INSUFFICIENT_POINTS

**Cause**: Your hold implementation is not reserving points atomically, or the available balance check is not accounting for existing active holds.

**Fix**: When checking available points for a new hold, subtract all ACTIVE holds for that member:

```sql
SELECT available_points - COALESCE(SUM(h.points_held), 0) as effective_available
FROM members m
LEFT JOIN holds h ON h.member_key = m.member_key AND h.status = 'ACTIVE'
WHERE m.member_key = ?
GROUP BY m.available_points
```

Or better: deduct points from `available_points` at hold time and restore on cancel/expire.

### Hold auto-expiry not working

**Cause**: Your expiration job is not running frequently enough, or it is not correctly identifying expired holds.

**Fix**:
1. Check your scheduled job is running (add logging).
2. Verify the query: `SELECT * FROM holds WHERE status = 'ACTIVE' AND expires_at < NOW()`.
3. Ensure the expiration job restores points atomically (use a transaction).
4. Test with a short hold duration (1 minute) to verify quickly.

### Idempotency not working (duplicate holds created)

**Cause**: Your idempotency check is not working, or you are checking after processing instead of before.

**Fix**:
1. Check for the `Idempotency-Key` BEFORE processing the request (after HMAC verification).
2. Use a unique constraint on the idempotency key column in your database.
3. Handle concurrent requests with a lock or database transaction.
4. Verify your idempotency store is persistent (survives restarts).

### JSON field names are camelCase instead of snake_case

**Cause**: Your JSON serializer is using camelCase by default (common in Java/Jackson, Node.js).

**Fix**:
- **Java/Jackson**: `@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)` or global config `spring.jackson.property-naming-strategy=SNAKE_CASE`
- **Node.js**: Use a snake_case conversion library or manually map field names
- **Python/FastAPI**: Keep Pydantic field names in snake_case and do not set `alias_generator`. `to_camel` would emit camelCase JSON, which is the bug this section is about. Python field names already match the contract.

### USD values returned as numbers instead of strings

**Cause**: Your JSON serializer is converting string values like `"100.00"` to numbers.

**Fix**: Ensure USD value fields are typed as strings in your DTOs/models. Do not use `float` or `double` for monetary amounts. In Java, use `BigDecimal` and serialize as string with `@JsonSerialize(using = ToStringSerializer.class)` or configure Jackson to serialize BigDecimal as string.

---

## Go-Live Validation Checklist

### HMAC

- [ ] Verifier reproduces spec vectors 1–3 exactly (see Section 0)
- [ ] Verifier uses constant-time comparison
- [ ] Verifier hashes raw body bytes (no JSON parse-then-reserialize)
- [ ] Verifier uses the **received** path-and-query, encoding-aware (RFC 3986)
- [ ] Verifier rejects `|now - t| > 300` with 401, regardless of signature match
- [ ] Verifier returns 401 `AUTHENTICATION_FAILED` for missing/malformed headers, unknown `key_id`, or signature mismatch. Body does not distinguish cause
- [ ] Verifier does not persist `Idempotency-Key` entries for 401
- [ ] Verifier holds current and previous secrets during rotation; tries only the secret named by `X-Access-Key-Id` (never all-secrets HMAC-compare)
- [ ] Secrets stored only in a vault, never in source, never logged
- [ ] TLS 1.2 or 1.3 verified on the public hostname
- [ ] No client-certificate requirement anywhere on the public hostname

### Endpoints

- [ ] `GET /v1/loyalty/balance` returns correct balance and exchange rate
- [ ] `POST /v1/loyalty/holds` creates holds and reserves points atomically
- [ ] `POST /v1/loyalty/redemptions` redeems active holds
- [ ] `POST /v1/loyalty/refunds` credits points back for redeemed transactions
- [ ] `POST /v1/loyalty/holds/{id}/cancel` releases holds and restores points
- [ ] All error responses use the correct `error_code` enum values, with the **per-operation** HTTP status from `endpoint-contract-reference.md` (note `HOLD_NOT_FOUND` is 409 on redemptions and 404 on cancel)
- [ ] All responses include `X-Response-Timestamp` header
- [ ] **p99 response time is under 5 seconds** on all five endpoints. Access times out at 5s per attempt.
- [ ] Transient internal failures return 5xx, not 4xx. Access never retries a 4xx.
- [ ] Redemptions accept the full RedeemRequest body. If a confirmatory field is omitted, resolve it from the stored hold rather than returning 400

### Data Format

- [ ] JSON field names use snake_case
- [ ] Points are integers (no decimals)
- [ ] USD values are strings with 2 decimal places (e.g., `"100.00"`)
- [ ] Timestamps are ISO 8601 in UTC

### Business Logic

- [ ] Idempotency key persistence works **after HMAC verification**, not before (duplicate keys return the original 200/201, not `409 ALREADY_PROCESSED`)
- [ ] Idempotency records are retained for at least 48 hours
- [ ] 401 responses are not persisted as idempotent
- [ ] Hold auto-expiration implemented and tested
- [ ] Cancel restores held points
- [ ] Refund credits points back for redeemed transactions
- [ ] Cannot redeem an expired or cancelled hold
- [ ] Cannot cancel an already redeemed hold
- [ ] Concurrent hold requests on the same member do not cause double-spending

### Integration

- [ ] Sandbox testing completed with Access
- [ ] Access Implementation Manager has validated that signed requests from stage are accepted
- [ ] Domains added to Access CSP allowlist
- [ ] Server does **not** require `program-key` and accepts requests that omit it (Access does not currently send it)
