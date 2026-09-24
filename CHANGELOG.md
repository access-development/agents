# Changelog

Notable changes to the Access Development agent skills.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`npx skills add access-development/agents` installs current `master`.
To pin a released version, see [Versions](README.md#versions) in the README.

## [Unreleased]

## [2.0.0] - 2026-09-10

Breaking change in `loyalty-points-integration`.

### loyalty-points-integration

#### Changed

- **Breaking:** HMAC-SHA256 request signing is V1 authentication. Access does not present a client certificate. The application that receives the request must verify the signature before any business logic. Canonical spec: `references/hmac-signing-spec.md`. OpenAPI `securitySchemes` now describes HMAC headers, not `mutualTLS`.

#### Removed

- mTLS as an accepted V1 authentication path. The previous mTLS configuration guide is retired. If a network team is still being asked for a client certificate, that instruction is out of date.

### Repository

#### Added

- This changelog, GitHub Releases, and install-time version pinning (`npx skills add access-development/agents#vX.Y.Z`).

## [1.2.1] - 2026-08-14

### Repository

#### Changed

- Corrected the README install documentation for the `skills` CLI, including the Grok Build skills path.

## [1.2.0] - 2026-08-13

### loyalty-points-integration

#### Changed

- Redeem is documented as the full `RedeemRequest`, not `hold_id` only. Omitted confirmatory fields are resolved from the stored hold rather than rejected as 400.
- Idempotent retries (same `Idempotency-Key`) must return the cached 200/201. Do not turn that retry into `409 ALREADY_PROCESSED`. That code is only for a different operation against a hold that is already terminal.
- 404 means the resource this URL asked for does not exist. Collection POSTs do not return 404. Access does not retry any 4xx.
- Retry backoff matches the shipped caller: 500ms, then 1000ms, then 2000ms.

## [1.1.0] - 2026-08-12

### loyalty-points-integration

#### Added

- New skill for implementing the five Loyalty Points API endpoints Access calls during travel shopping: balance, holds, cancel, redemptions, and refunds. Includes the OpenAPI 3.0 contract, hold lifecycle, idempotency, and testing guidance. V1 authentication in this version is mTLS.

## [1.0.0] - 2026-03-09

### access-travel-integration

#### Added

- Initial skill for integrating the Access Development Travel Platform: server-side session tokens, JavaScript SDK embedding, deep linking (hotels, cars, theme parks, activities, flights), and event handling.

### Repository

#### Added

- Public repo layout and `npx skills add access-development/agents` install path.

[Unreleased]: https://github.com/access-development/agents/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/access-development/agents/compare/v1.2.1...v2.0.0
[1.2.1]: https://github.com/access-development/agents/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/access-development/agents/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/access-development/agents/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/access-development/agents/releases/tag/v1.0.0
