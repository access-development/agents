# Testing and Troubleshooting

This guide covers test scenarios, curl commands, common issues, and a go-live validation checklist for the Access Loyalty Points API.

---

## Test Scenarios

### Prerequisites

- Access client certificate (`access-client.crt`) and private key (`access-client.key`) - what you present to your own server to simulate Access
- Access CA certificate (`access-ca.pem`) - the CA that signs Access's client certificate. This belongs in the **truststore of the hop that terminates the public hostname** so that hop can validate incoming client certs. You do not pass it to curl.
- Your server CA certificate (`your-server-ca.crt`) - for curl to validate your server, passed as `--cacert`
- Test `member_key` values provided by Access (e.g., `abc123`)
- Your base URL (e.g., `https://loyalty.yourdomain.com/api`)

### 1. Balance - Happy Path

```bash
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  "https://loyalty.yourdomain.com/api/v1/loyalty/balance?member_key=abc123" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z"
```

**Expected**: 200 with JSON body containing `member_key`, `available_points`, `loyalty_point_to_usd_exchange_rate`, `timestamp`. Response includes `X-Response-Timestamp` header.

### 2. Balance - Member Not Found

```bash
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  "https://loyalty.yourdomain.com/api/v1/loyalty/balance?member_key=nonexistent" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z"
```

**Expected**: 404 with `{"error_code": "MEMBER_NOT_FOUND", "message": "..."}`.

### 3. Create Hold - Happy Path

```bash
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  -X POST "https://loyalty.yourdomain.com/api/v1/loyalty/holds" \
  -H "Content-Type: application/json" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z" \
  -H "Idempotency-Key: test-hold-001" \
  -d '{
    "member_key": "abc123",
    "points_requested": 10000,
    "hold_duration_minutes": 5,
    "transaction_description": "Test hotel booking hold"
  }'
```

**Expected**: 201 with JSON body containing `hold_id`, `status: "ACTIVE"`, `expires_at`, `points_held: 10000`.

**Save the `hold_id`** for subsequent tests.

### 4. Create Hold - Insufficient Points

```bash
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  -X POST "https://loyalty.yourdomain.com/api/v1/loyalty/holds" \
  -H "Content-Type: application/json" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z" \
  -H "Idempotency-Key: test-hold-002" \
  -d '{
    "member_key": "abc123",
    "points_requested": 900000,
    "hold_duration_minutes": 5,
    "transaction_description": "Test insufficient points"
  }'
```

**Expected**: 409 with `{"error_code": "INSUFFICIENT_POINTS", "message": "..."}`.

Use a value that is **inside** the documented range (min 1, max 1,000,000) but above your test member's balance. A value above 1,000,000 tests range validation instead, and a correct server answers that with 400 `INVALID_REQUEST`. Adjust `900000` to suit your test member.

### 5. Idempotency - Duplicate Key

```bash
# First request
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  -X POST "https://loyalty.yourdomain.com/api/v1/loyalty/holds" \
  -H "Content-Type: application/json" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z" \
  -H "Idempotency-Key: test-hold-dup-001" \
  -d '{
    "member_key": "abc123",
    "points_requested": 5000,
    "hold_duration_minutes": 5,
    "transaction_description": "Idempotency test"
  }'

# Second request with SAME Idempotency-Key
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  -X POST "https://loyalty.yourdomain.com/api/v1/loyalty/holds" \
  -H "Content-Type: application/json" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z" \
  -H "Idempotency-Key: test-hold-dup-001" \
  -d '{
    "member_key": "abc123",
    "points_requested": 5000,
    "hold_duration_minutes": 5,
    "transaction_description": "Idempotency test"
  }'
```

**Expected**: Both responses return the same `hold_id` and response body. The second request does not create a new hold.

### 6. Redeem - Happy Path

```bash
# Replace HOLD_ID with the hold_id from test 3
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  -X POST "https://loyalty.yourdomain.com/api/v1/loyalty/redemptions" \
  -H "Content-Type: application/json" \
  -H "X-Request-Timestamp: 2024-01-15T12:01:00Z" \
  -H "Idempotency-Key: test-redeem-001" \
  -d '{
    "hold_id": "HOLD_ID",
    "member_key": "abc123",
    "points_to_redeem": 10000,
    "transaction_details": {
      "transaction_id": "test-txn-001",
      "type": "HOTEL_BOOKING",
      "description": "Test hotel booking",
      "supplier_confirmation": "CONF-TEST-001",
      "usd_value": "100.00"
    }
  }'
```

**Expected**: 200 with `status: "SUCCESS"`, `points_redeemed: 10000`, `transaction_id: "test-txn-001"`.

### 7. Cancel Hold - Happy Path

Create a new hold first, then cancel it:

```bash
# Create hold
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  -X POST "https://loyalty.yourdomain.com/api/v1/loyalty/holds" \
  -H "Content-Type: application/json" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z" \
  -H "Idempotency-Key: test-hold-cancel-001" \
  -d '{
    "member_key": "abc123",
    "points_requested": 5000,
    "hold_duration_minutes": 5,
    "transaction_description": "Cancel test hold"
  }'

# Cancel it (replace HOLD_ID)
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  -X POST "https://loyalty.yourdomain.com/api/v1/loyalty/holds/HOLD_ID/cancel" \
  -H "Content-Type: application/json" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:30Z" \
  -H "Idempotency-Key: test-cancel-001" \
  -d '{"reason": "Test cancellation"}'
```

**Expected**: 200 with `status: "CANCELLED"`. Verify the member's balance is restored by calling the balance endpoint.

### 8. Refund - Happy Path

Refund the redemption from test 6:

```bash
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  -X POST "https://loyalty.yourdomain.com/api/v1/loyalty/refunds" \
  -H "Content-Type: application/json" \
  -H "X-Request-Timestamp: 2024-01-15T12:02:00Z" \
  -H "Idempotency-Key: test-refund-001" \
  -d '{
    "original_transaction_id": "test-txn-001",
    "refund_points": 10000,
    "reason": "Test refund"
  }'
```

**Expected**: 200 with `status: "REFUNDED"`, `points_refunded: 10000`. Verify balance is restored.

### 9. Hold Expiry

1. Create a hold with a short duration (e.g., `hold_duration_minutes: 1`).
2. Wait for the hold to expire (at least 1 minute + your expiration job interval).
3. Call balance to verify points are restored.
4. Attempt to redeem the expired hold.

```bash
# Attempt redemption of expired hold (replace HOLD_ID)
curl -v \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  -X POST "https://loyalty.yourdomain.com/api/v1/loyalty/redemptions" \
  -H "Content-Type: application/json" \
  -H "X-Request-Timestamp: 2024-01-15T12:05:00Z" \
  -H "Idempotency-Key: test-redeem-expired-001" \
  -d '{
    "hold_id": "HOLD_ID",
    "member_key": "abc123",
    "points_to_redeem": 5000,
    "transaction_details": {
      "transaction_id": "test-txn-002",
      "type": "HOTEL_BOOKING",
      "description": "Expired hold test",
      "usd_value": "50.00"
    }
  }'
```

**Expected**: `HOLD_NOT_FOUND` or `ALREADY_PROCESSED`. The status is 409 on the redemptions endpoint and 404 on the cancel endpoint, since redemptions declare no 404. See the per-operation table in `endpoint-contract-reference.md`.

### 10. mTLS - No Client Certificate

```bash
curl -v \
  --cacert your-server-ca.crt \
  "https://loyalty.yourdomain.com/api/v1/loyalty/balance?member_key=abc123" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z"
```

**Expected**: the request must not succeed. **What "rejected" looks like depends on your TLS version, and this trips people up.**

Under **TLS 1.3** (the version Access uses), the client certificate is requested *after* the handshake completes. curl will typically report a successful connection and then fail on the first read, with an error such as `OpenSSL SSL_read: error:0A00045C:SSL routines::tlsv13 alert certificate required`. This is a pass, not a handshake failure. Under TLS 1.2 the same condition surfaces as a handshake failure during connect.

Platform-specific results:
- **Nginx**: HTTP 496. This is an HTTP status returned over a completed TLS connection, which is expected and correct for nginx. It is not a contradiction.
- **HAProxy, AWS ALB, Spring Boot (app-level)**: connection terminated, usually surfacing as a TLS alert rather than an HTTP response.

**Pass criteria**: no `200` and no balance JSON. Any of the above outcomes counts as a pass. A `403` is also acceptable if you deliberately configured conditional mTLS with a custom error page.

> **Keep `--cacert your-server-ca.crt`.** Without it, curl aborts while validating *your server's* certificate before it ever gets to the client-certificate check. The test then "passes" without having exercised client-cert enforcement at all.

### 11. mTLS - Invalid Client Certificate

```bash
# Self-signed cert that is NOT signed by the Access CA
openssl req -x509 -newkey rsa:2048 -keyout fake-key.pem -out fake-cert.pem -days 1 -nodes -subj "/CN=fake"

curl -v \
  --cert fake-cert.pem \
  --key fake-key.pem \
  --cacert your-server-ca.crt \
  "https://loyalty.yourdomain.com/api/v1/loyalty/balance?member_key=abc123" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z"
```

**Expected**: the request must not succeed. The certificate is not signed by a trusted CA, so your server must reject it. As in test 10, under TLS 1.3 this usually appears as a post-handshake alert (`tlsv13 alert unknown ca` or similar) rather than a connect-time handshake failure.

**Pass criteria**: no `200` and no balance JSON.

> This test is the one that catches a truststore containing the wrong CA, or `ssl_verify_client optional` left in place without a result check. If it returns `200`, your mTLS is not enforcing anything, regardless of what test 1 showed.

### 12. TLS 1.3 Negotiation

Access negotiates TLS 1.3 only. Verify the hop that terminates the public hostname supports it. Run tests 10–12 against that hostname, not against the app behind it:

```bash
curl -v --tlsv1.3 --tls-max 1.3 \
  --cert access-client.crt \
  --key access-client.key \
  --cacert your-server-ca.crt \
  "https://loyalty.yourdomain.com/api/v1/loyalty/balance?member_key=abc123" \
  -H "X-Request-Timestamp: 2024-01-15T12:00:00Z"
```

**Expected**: 200 with a balance payload, and `SSL connection using TLSv1.3` in the verbose output.

If this fails while test 1 passes, the public hostname is capping at TLS 1.2. **Access will not be able to reach you**, even though every other test in this document passes. Fix the TLS policy on the validating hop before go-live. See the TLS 1.3 callout in `mtls-configuration-guide.md`.

---

## Common Issues

### "Connection reset" or "handshake failure" when testing with curl

**Cause**: Most likely an incomplete CA chain in your trust store, or the client certificate is not being sent correctly.

**Fix**:
1. Verify your client cert and key match: `openssl x509 -in access-client.crt -noout -subject -issuer`
2. Check the CA chain is complete: `openssl verify -CAfile access-ca.pem access-client.crt`
3. Use `-v` flag with curl to see the TLS handshake details
4. Test with OpenSSL directly for more detail:
   ```bash
   openssl s_client -connect loyalty.yourdomain.com:443 \
     -cert access-client.crt -key access-client.key \
     -CAfile your-server-ca.crt -showcerts
   ```

### "Unable to get issuer certificate" or "unable to verify the first certificate"

**Cause**: Your trust store is missing an intermediate CA certificate. The Access CA chain has an intermediate that you did not include.

**Fix**: Concatenate the intermediate and root CA into a single PEM file:
```bash
cat access-intermediate.pem access-root.pem > access-ca.pem
```

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
1. Check your scheduled job is running (add logging)
2. Verify the query: `SELECT * FROM holds WHERE status = 'ACTIVE' AND expires_at < NOW()`
3. Ensure the expiration job restores points atomically (use a transaction)
4. Test with a short hold duration (1 minute) to verify quickly

### Idempotency not working (duplicate holds created)

**Cause**: Your idempotency check is not working, or you are checking after processing instead of before.

**Fix**:
1. Check for the `Idempotency-Key` BEFORE processing the request
2. Use a unique constraint on the idempotency key column in your database
3. Handle concurrent requests with a lock or database transaction
4. Verify your idempotency store is persistent (survives restarts)

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

### mTLS

- [ ] mTLS is enforced at the hop that terminates the public hostname (cloud LB, reverse proxy, or the app if it is that hop)
- [ ] Trust store on that hop contains the complete Access CA chain (intermediate + root)
- [ ] mTLS handshake succeeds with Access client cert against the public hostname
- [ ] **TLS 1.3 negotiates successfully** (test 12, against the public hostname). Access will not fall back to TLS 1.2.
- [ ] Requests without client cert are rejected (test 10, run with `--cacert`)
- [ ] Requests with invalid client cert are rejected (test 11, run with `--cacert`)
- [ ] The app does not invent or require an Access-defined trust header
- [ ] Certificate expiration date is monitored
- [ ] Trust store update process on the validating hop is documented and tested

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
- [ ] Redemptions succeed when the request body carries only `hold_id` (resolve the rest from the stored hold)

### Data Format

- [ ] JSON field names use snake_case
- [ ] Points are integers (no decimals)
- [ ] USD values are strings with 2 decimal places (e.g., `"100.00"`)
- [ ] Timestamps are ISO 8601 in UTC

### Business Logic

- [ ] Idempotency key persistence works (duplicate keys return original response)
- [ ] Idempotency records are retained for at least 48 hours
- [ ] Hold auto-expiration implemented and tested
- [ ] Cancel restores held points
- [ ] Refund credits points back for redeemed transactions
- [ ] Cannot redeem an expired or cancelled hold
- [ ] Cannot cancel an already redeemed hold
- [ ] Concurrent hold requests on the same member do not cause double-spending

### Integration

- [ ] Sandbox testing completed with Access
- [ ] Access Implementation Manager has validated the mTLS handshake
- [ ] Domains added to Access CSP allowlist
- [ ] Server does **not** require `program-key` and accepts requests that omit it (Access does not currently send it)
