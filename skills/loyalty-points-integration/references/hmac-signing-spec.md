# Access Loyalty Points API - HMAC-SHA256 Request Signing

**Status:** V1 contract (replaces mTLS as the required authentication method)  
**Date:** 2026-08-21  
**Audience:** Client implementers, Access `payment-api` (signer), loyalty-points-integration skill  
**Style:** Stripe webhook signatures (timestamp + `v1` HMAC in a header, dual-secret rotation, 5-minute replay window). Canonical string is **not** Stripe-identical: GET balance has an empty body, so method, path, and query are part of the signed payload.

---

## Public algorithm, secret keys

The algorithm, canonicalization rules, headers, error codes, and test vectors in this document are **public**. They belong in:

- the official OpenAPI in the `loyalty-points-integration` skill (`references/openapi.yaml` in `access-development/agents`)
- the client-facing Znai site (`~/dev/client-documentation/loyalty-points/`, published at https://developers.accessdevelopment.com/loyalty-points/). The PDF is retired.
- the `loyalty-points-integration` skill HMAC reference (`references/hmac-signing-spec.md`, when PD-8059 lands)

Security depends only on the **per-program HMAC secret** issued at onboarding. That secret is a credential. It is never committed, never placed in the skill, never placed in OpenAPI examples except the labeled test-vector fixture below, and never logged.

Hiding the algorithm would not improve security. It would prevent client engineers and coding assistants from implementing verification correctly. Every language standard library can compute HMAC-SHA256. The hard part is agreeing on the exact bytes that are signed. Those bytes are specified here, with test vectors.

---

## Roles

| Party | Role |
|---|---|
| Access `payment-api` | Caller. Signs every request. Holds current and previous secrets in Secrets Manager. |
| Client loyalty API | Callee. Verifies the signature in application code **before** business logic. Holds the same current and previous secrets in their vault. |
| TLS | Required (1.2 or 1.3). Provides confidentiality in transit. Does **not** authenticate Access. There is no client certificate. |

Access is the only signer. Clients never sign requests back to Access on this contract.

---

## Credentials (the actual secret)

During onboarding Access issues, per program (PCID):

| Item | Public? | Notes |
|---|---|---|
| `key_id` | Yes (sent on every request) | Opaque id, e.g. `hmac_key_1`. Used to select which secret to verify with during rotation. |
| HMAC secret | **No** | High-entropy random string, at least 32 bytes before encoding. Treat as a password. Store in a secrets manager. |
| Previous `key_id` + secret | **No** (secret) | Optional. Present only during a rotation overlap window. |

Sandbox and production secrets are different. A sandbox secret must never work in production.

---

## Headers Access sends

Existing headers are unchanged (`X-Request-Timestamp`, `X-Request-ID`, `Idempotency-Key` on POST). Two new headers:

| Header | Required | Example |
|---|---|---|
| `X-Access-Key-Id` | Yes | `hmac_key_1` |
| `X-Access-Signature` | Yes | `t=1787313600,v1=d910ff46fe7cddbc1c6580148a10dc0a170e221bcc3a6e77e8a0fcfc47e048bf` |

`X-Request-Timestamp` stays ISO 8601 UTC for logging and latency. It is **not** the security timestamp. The security timestamp is the integer `t` inside `X-Access-Signature`. Do not parse the ISO header and feed it into HMAC. Format differences (`Z` vs `+00:00`, millis) would break verification across languages.

---

## Canonical string

UTF-8, no trailing newline:

```
{t}.{METHOD}.{path_and_query}.{body_sha256_hex}
```

Four fields, separated by `.` (ASCII 0x2E).

### `t`

Unix epoch **seconds** (integer, no millis), taken from the `t=` element of `X-Access-Signature`. UTC.

### `METHOD`

Uppercase HTTP method as sent: `GET` or `POST`.

### `path_and_query`

The origin-form request target: path starting with `/`, plus `?` and query string when present. No scheme, no host, no fragment.

Examples, if Access calls `https://loyalty.example.com/api/v1/loyalty/...`:

| Request | `path_and_query` |
|---|---|
| GET balance | `/api/v1/loyalty/balance?member_key=abc123` |
| POST hold | `/api/v1/loyalty/holds` |
| POST cancel | `/api/v1/loyalty/holds/hold-12345/cancel` |

The client's URL prefix **is** part of the signed string. If their base URL is `https://loyalty.example.com/api`, the signed path starts with `/api/...`. If their base URL is `https://loyalty.example.com/` and the app is mounted at `/v1`, the signed path starts with `/v1/...`. Access signs the URL it actually requests (`loyalty_api_base_url` + path). The verifier must hash the path and query of the request it received, not a hardcoded `/v1/loyalty/...`.

Query encoding: Access encodes query values as **RFC 3986** (UTF-8, space as `%20`, unreserved `A-Z a-z 0-9 - . _ ~` left unencoded). Do not use `application/x-www-form-urlencoded` (`+` for space). Do not reorder query parameters. Access sends `member_key` as the only query parameter on GET `/balance`.

### `body_sha256_hex`

Lowercase hex SHA-256 of the **raw HTTP body bytes** as transmitted.

- GET: body is empty. SHA-256 of zero bytes is always `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
- POST: hash the bytes on the wire. Do **not** parse JSON and re-serialize before hashing. Whitespace, key order, and Unicode escaping all change the hash.

Access sends compact JSON (no pretty-print, UTF-8, snake_case field names). Clients should hash `request.rawBody`, not `JSON.stringify(parsed)`.

---

## Signature

```
v1 = lowercase_hex( HMAC-SHA256( key=utf8(secret), msg=utf8(canonical_string) ) )
```

`X-Access-Signature` format (no spaces):

```
t=<seconds>,v1=<64 hex chars>
```

Unknown elements in that header may be ignored (forward compatible). `t` and `v1` are required. Access sends exactly one `v1` per request.

---

## Verifier algorithm (client)

Run this **before** idempotency lookup and before any hold, redeem, cancel, or refund mutation.

1. If the request is not HTTPS, reject.
2. Read `X-Access-Key-Id` and `X-Access-Signature`. If either is missing or `X-Access-Signature` does not contain `t` and `v1`, return **401** `AUTHENTICATION_FAILED`.
3. Parse `t` as an integer. If `|now_utc_seconds - t| > 300`, return **401** `AUTHENTICATION_FAILED` (replay / clock skew). 300 seconds matches the 5-minute hold window.
4. Look up the secret for `X-Access-Key-Id`. During rotation the client holds two secrets. If the key id is unknown, return **401**.
5. Build `path_and_query` from the received request (path + query as on the wire).
6. SHA-256 the raw body (empty for GET).
7. Build the canonical string. Compute `expected_v1`.
8. Compare `expected_v1` to the provided `v1` in **constant time** (`MessageDigest.isEqual`, `crypto.timingSafeEqual`, `hmac.compare_digest`, `CryptographicOperations.FixedTimeEquals`). If they differ, return **401** `AUTHENTICATION_FAILED`. Do not say "wrong secret" vs "wrong canonical string" in the body.
9. Only then run business logic. On POST, then apply `Idempotency-Key` rules.

Do **not** persist an `Idempotency-Key` for a 401. A later correctly signed retry with the same key must execute, not replay a cached auth failure.

Suggested error body (same `ErrorResponse` shape as the rest of the contract):

```json
{
  "error_code": "AUTHENTICATION_FAILED",
  "message": "Invalid or missing request signature"
}
```

HTTP status **401**. Access does not retry 4xx, so a wrong verifier will fail the booking path immediately. That is intentional. Fix the verifier; do not return 500 to force a retry of a bad signature.

---

## Rotation

Overlap, not a hard cut.

1. Access generates `hmac_key_2` and a new secret. Issues the new secret to the client through the Implementation Manager (or a secrets channel, never email in the clear).
2. Client installs `hmac_key_2` **alongside** `hmac_key_1`. Both verify.
3. Access switches the signer to `hmac_key_2` (sends that `X-Access-Key-Id`).
4. After a confirmed overlap (recommended: 7 days, or until no `hmac_key_1` traffic), client retires `hmac_key_1`.
5. Access retires the previous secret from Secrets Manager.

If verification fails during overlap, try only the secret named by `X-Access-Key-Id`. Do not HMAC-compare against every secret you hold; that turns a stolen old key into a valid signer even after Access has moved on, and it hides key-id bugs.

---

## What is not signed (and why)

| Item | Signed? | Why |
|---|---|---|
| Host / scheme | No | TLS server certificate binds the host. |
| `X-Request-ID` | No | Changes per retry by design. |
| `Idempotency-Key` | No | Already a business-level duplicate guard; it is in the POST headers but not the canonical string. Path + body bind the operation. |
| `X-Request-Timestamp` (ISO) | No | `t=` is the security clock. |
| Response | No | This contract authenticates Access to the client, not the reverse. |

---

## TLS

HTTPS is required. TLS 1.2 minimum. TLS 1.3 preferred. Access will negotiate either. There is **no** client certificate and **no** requirement to configure mTLS on the load balancer, API gateway, or application.

IP allowlisting is optional defense in depth. It is not a substitute for signature verification.

---

## Test vectors (VERIFIED)

These were computed with Python 3 `hmac` / `hashlib` on 2026-08-21. A client implementation **must** reproduce the `v1` values exactly. If it does not, the canonical string is wrong.

**Fixture secret (not a real credential):**

```
test_loyalty_hmac_secret_do_not_use_in_prod
```

**`t`:** `1787313600` (2026-08-21T12:00:00Z)

**`key_id`:** `hmac_key_1`

### Vector 1 - GET balance

| Field | Value |
|---|---|
| METHOD | `GET` |
| path_and_query | `/api/v1/loyalty/balance?member_key=abc123` |
| body | empty (0 bytes) |
| body_sha256_hex | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| canonical | `1787313600.GET./api/v1/loyalty/balance?member_key=abc123.e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| v1 | `d910ff46fe7cddbc1c6580148a10dc0a170e221bcc3a6e77e8a0fcfc47e048bf` |

```
X-Access-Key-Id: hmac_key_1
X-Access-Signature: t=1787313600,v1=d910ff46fe7cddbc1c6580148a10dc0a170e221bcc3a6e77e8a0fcfc47e048bf
```

### Vector 2 - POST create hold

Body is this exact 121-byte UTF-8 string (no newline, no extra spaces):

```
{"member_key":"abc123","points_requested":10000,"hold_duration_minutes":5,"transaction_description":"Hotel booking hold"}
```

| Field | Value |
|---|---|
| METHOD | `POST` |
| path_and_query | `/api/v1/loyalty/holds` |
| body_sha256_hex | `a7a65c42b645692bacf88811dc126c475a567db6f4a5638a97b0ab4e704a43b5` |
| canonical | `1787313600.POST./api/v1/loyalty/holds.a7a65c42b645692bacf88811dc126c475a567db6f4a5638a97b0ab4e704a43b5` |
| v1 | `cb557158186e3d5d6d35fa06f418ac69bdaa965d78a97889c5424b0438c8ae0f` |

```
X-Access-Key-Id: hmac_key_1
X-Access-Signature: t=1787313600,v1=cb557158186e3d5d6d35fa06f418ac69bdaa965d78a97889c5424b0438c8ae0f
Idempotency-Key: hold-001
```

### Vector 3 - GET with RFC 3986-encoded member_key

`member_key` on the wire is `abc%2F123` (value `abc/123`).

| Field | Value |
|---|---|
| path_and_query | `/api/v1/loyalty/balance?member_key=abc%2F123` |
| canonical | `1787313600.GET./api/v1/loyalty/balance?member_key=abc%2F123.e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| v1 | `d281480bf01084eb32d9bb9c0d990d9f6efe97d967ef139484389b753ac6e9e5` |

### Negative checks

| Case | Expect |
|---|---|
| Same vector 2 canonical, secret `wrong` | v1 `75ca8ec249f9240df8e33d035c18692e252f147f525b17c27f57f3c1f8eadbdf` (must **not** match vector 2) |
| `t` older than 300 seconds | 401, do not compute a "close enough" match |
| Pretty-printed JSON body (spaces after colons) | different body hash, 401 |
| Path `/v1/loyalty/holds` when Access called `/api/v1/loyalty/holds` | 401 |
| Re-serialized JSON with keys reordered | 401 |

Reproduce vector 2:

```python
import hmac, hashlib
secret = b"test_loyalty_hmac_secret_do_not_use_in_prod"
canonical = b"1787313600.POST./api/v1/loyalty/holds.a7a65c42b645692bacf88811dc126c475a567db6f4a5638a97b0ab4e704a43b5"
print(hmac.new(secret, canonical, hashlib.sha256).hexdigest())
# cb557158186e3d5d6d35fa06f418ac69bdaa965d78a97889c5424b0438c8ae0f
```

---

## Reference snippets (verify only)

### Java 21

```java
static String hmacSha256Hex(String secret, String canonical) throws Exception {
  Mac mac = Mac.getInstance("HmacSHA256");
  mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
  byte[] raw = mac.doFinal(canonical.getBytes(StandardCharsets.UTF_8));
  return HexFormat.of().formatHex(raw);
}

static boolean signaturesEqual(String a, String b) {
  return MessageDigest.isEqual(
      a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8));
}
```

Hash the body with `MessageDigest.getInstance("SHA-256")` over the raw request bytes. For GET, pass a zero-length array.

### Node.js

```js
import crypto from "node:crypto";

function hmacSha256Hex(secret, canonical) {
  return crypto.createHmac("sha256", secret).update(canonical, "utf8").digest("hex");
}

function signaturesEqual(a, b) {
  const left = Buffer.from(a, "utf8");
  const right = Buffer.from(b, "utf8");
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}
```

### Python 3

```python
import hashlib, hmac

def hmac_sha256_hex(secret: str, canonical: str) -> str:
    return hmac.new(secret.encode("utf-8"), canonical.encode("utf-8"), hashlib.sha256).hexdigest()

def signatures_equal(a: str, b: str) -> bool:
    return hmac.compare_digest(a, b)
```

### C#

```csharp
using System.Security.Cryptography;
using System.Text;

static string HmacSha256Hex(string secret, string canonical) {
    using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
    var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(canonical));
    return Convert.ToHexString(hash).ToLowerInvariant();
}

static bool SignaturesEqual(string a, string b) =>
    CryptographicOperations.FixedTimeEquals(
        Encoding.UTF8.GetBytes(a), Encoding.UTF8.GetBytes(b));
```

---

## Access signer notes (`payment-api`)

Not required for clients. Listed so the caller and the verifier stay aligned.

- Sign in an OkHttp interceptor on `LoyaltyApiClient` so every GET and POST is covered (balance, hold, redeem, cancel, refund).
- Set `t` to `Instant.now().getEpochSecond()` and also set `X-Request-Timestamp` to the same instant in ISO-8601. Do not feed the ISO string into HMAC.
- Canonical `path_and_query` must be taken from the request URL OkHttp will send (path + encoded query), not from a reconstructed string that disagrees with `URLEncoder`. **Do not use `URLEncoder.encode` for query values** (it emits `+` for space). Use RFC 3986 encoding.
- Body hash is SHA-256 of the `RequestBody` bytes that are actually written. If Jackson writes the JSON, hash those bytes, not a second `writeValueAsString`.
- Store current and previous secrets in AWS Secrets Manager. `ClientProgram` should hold `hmac_key_id` and secret **names**, not secret values. Dual-column or versioned secrets for overlap.
- `LoyaltyApiClientProvider` currently caches `OkHttpClient` forever in `ConcurrentHashMap`. Secret or key-id rotation must bust that cache (or the interceptor must read secrets on each request / via a TTL). Today's mTLS cache would have the same bug.
- Drop the TLS 1.3-only pin in `LoyaltyApiHttpClientFactory` (PD-7976). TLS 1.2+ is enough once mTLS is gone.
- `mtls_keystore_path` / `mtls_truststore_path` become unused. Prefer new HMAC columns and leave the old columns nullable for a cleanup migration; do not require PKCS12 files for a program to be active.
- Keystore password stub (`resolveKeystorePassword` returns the secret name) is obsolete for this path. Wire Secrets Manager for HMAC secrets as the PA-06 work.
- Perks Ascend `LoyaltyIngressAuthenticationFilter` (trust `X-Client-Verified`) is not an HMAC verifier. It must be replaced in the same cut or Ascend will accept unsigned calls that set a header.

---

## OpenAPI changes (for the skill / spec PR)

Edit the **skill** OpenAPI (`access-development/agents` `skills/loyalty-points-integration/references/openapi.yaml`). Do not revive `archive/client-facing/openapi.yaml`.

Client-facing prose lives in Znai (`~/dev/client-documentation/loyalty-points/`), not a PDF. Update `operations/security.md`, `getting-started/prerequisites.md`, and testing pages there in the same cut as the skill.

- Replace `components.securitySchemes.mtls` with an `apiKey` scheme on `X-Access-Signature` (and document `X-Access-Key-Id` as a required header parameter).
- Add `401` + `AUTHENTICATION_FAILED` to every operation.
- Require TLS 1.2 or 1.3. Remove "client certificate required" and "Access will not fall back to TLS 1.2".
- Keep `X-Request-Timestamp` required for logging.

---

## Checklist for a client go-live

- [ ] Verifier reproduces vectors 1-3
- [ ] Negative cases return 401 (wrong secret, stale `t`, pretty-printed body)
- [ ] Constant-time compare
- [ ] Raw body hashed, not re-serialized JSON
- [ ] `path_and_query` matches the received URL prefix
- [ ] Secrets in a vault, not in source
- [ ] Current + previous key ids accepted during a rotation drill
- [ ] 401 is not stored as an idempotent response
- [ ] No mTLS / client-cert requirement left on the public hostname
