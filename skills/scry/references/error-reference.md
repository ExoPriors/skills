# Scry Error Reference

All Scry API errors follow the standard envelope:

```json
{
  "error": {
    "code": "string_snake_case",
    "message": "human-readable description",
    "details": {}
  }
}
```

The `Retry-After` header (seconds) is present on 429 responses.

---

## Before deeper debugging

If local skill instructions still mention legacy ExoPriors hostnames or
legacy console routes, or if `/v1/scry/context` reports
`client_skill_generation: null` while you're using packaged Scry skills, stop
and run `npx skills update` first.

---

## Error Codes by HTTP Status

### 400 Bad Request

| Code | Message Pattern | Cause | Fix |
|------|----------------|-------|-----|
| `invalid_request` | "Empty query" | SQL body is empty | Provide SQL |
| `invalid_request` | "Only a single statement is supported" | Multiple SQL statements separated by `;` | Use a single SELECT (CTEs and UNIONs are fine) |
| `invalid_request` | "INSERT/UPDATE/DELETE/DROP/... is not allowed" | Write operation attempted | Use SELECT only |
| `invalid_request` | "EXPLAIN ANALYZE is not allowed" | EXPLAIN ANALYZE executes the query | Use plain EXPLAIN via `/v1/scry/estimate` |
| `invalid_request` | "Query must include a LIMIT clause" | Missing LIMIT | Add LIMIT (max 10,000) |
| `invalid_request` | "LIMIT exceeds maximum of 10000" | LIMIT too high | Reduce LIMIT |
| `invalid_request` | "Query length exceeds maximum" | SQL > 100KB | Shorten query |
| `invalid_request` | "Cartesian product detected" | Unjoined tables in FROM | Add JOIN conditions |
| `invalid_request` | "title is required" | Share/judgement missing required field | Provide the field |
| `invalid_request` | "exactly one target must be set" | Judgement has zero or multiple targets | Set exactly one of: `target_entity_id`, `target_actor_id`, `target_judgement_id`, `target_external_ref` |
| `invalid_request` | "public judgements must target an entity, actor, or judgement, not external_ref" | Public judgement attempted to use `target_external_ref` | Use `target_entity_id`, `target_actor_id`, or `target_judgement_id` for public scope, or keep `target_external_ref` at `self`/`group` privacy |
| `invalid_request` | "payload exceeds N bytes" | Share (1MB) or judgement (512KB) payload too large | Trim payload |
| `invalid_request` | "confidence must be between 0 and 1" | Confidence out of range | Use 0.0 to 1.0 |

### 401 Unauthorized

| Code | Message Pattern | Cause | Fix |
|------|----------------|-------|-----|
| `unauthorized` | "Missing or invalid API key" | No `Authorization: Bearer` header or key not recognized | Use your personal Scry API key from `scry.io/console` and ensure it has Scry access |
| `unauthorized` | "Invalid authorization format" | Authorization header malformed (extra quotes, whitespace, or newline in env var) | Strip CR/LF from key, ensure exact `Authorization: Bearer <key>` |
| `unauthorized` | "API key expired" | Key past 30-day expiry | Regenerate via `/api/console/scry/regenerate-key` or mint a fresh personal key |

### 402 Payment Required

| Code | Message Pattern | Cause | Fix |
|------|----------------|-------|-----|
| `insufficient_credits` | "Embedding token budget exhausted" | 1.5M token budget used up | Notify user; budget resets with a fresh personal key |
| `insufficient_credits` | "Insufficient credits for query" | Prepaid balance too low for the estimated query cost | Live funding rails are `x402`, Stripe saved-method funding, and crypto topup. Cards are a two-stage rail: save a card with `POST /v1/billing/setup-payment-method`, which returns `setup_url` for one operator browser visit, then use `POST /v1/billing/agent-topup`; that one-off stored-card path requires only a saved payment method. Inspect `GET /v1/scry/account` and read `funding.card_funding` to see whether the account still needs that setup handoff or is already API-ready. Recurring auto-topup is a separate opt-in that requires an active auto_topup mandate via `POST /v1/billing/payment-mandates` plus `PATCH /v1/billing/auto-topup`; inspect `GET /v1/billing/auto-topup/eligibility` when `funding.card_funding.state` reports `auto_topup_attention_required`. Non-wallet agents can receive a Scry-scoped key from a signed-in operator via `POST /v1/auth/api-keys`; agents with an EVM wallet can bootstrap directly via `POST /v1/auth/agent/signup`. `stripe_acp`, `ap2`, `visa_tap`, and `mastercard_agent_pay` are control-plane / future artifacts, not alternate live funding rails. |
| `estimate_exceeds_exposure` | "Estimated cost ... exceeds X-Scry-Max-Exposure" | The bid-adjusted estimate is already above the caller's authorized exposure | Run `/v1/scry/estimate`, narrow the query, or raise `X-Scry-Max-Exposure` |
| `query_exposure_exhausted` | "Query exhausted its authorized exposure" | Live runtime burn hit the authorized exposure for this query (with timeout fallback if needed) | Raise `X-Scry-Max-Exposure` or reduce scan scope / LIMIT |

### 403 Forbidden

| Code | Message Pattern | Cause | Fix |
|------|----------------|-------|-----|
| `forbidden` | "Missing Scry scope" or feature-specific access denial | The key is missing required scope or is the wrong key type | Use a personal Scry API key with the needed scope |
| `forbidden` | "Postgres introspection blocked" | Query touched `pg_*` catalogs, `current_setting()`, `version()`, etc. | Use `GET /v1/scry/schema` instead |
| `forbidden` | "Only the share owner can update" | PATCH on share you don't own | Use the key that created the share |
| `delegated_authorization_required` | "X-Scry-Subject-Agent is not authorized..." | The caller supplied `X-Scry-Subject-Agent`, but the authenticated account has no matching active `query_access` mandate for that agent/resource | Inspect `GET /v1/billing/payment-mandates`, create/activate a `query_access` mandate with `max_query_exposure`, or retry without delegated subject mode |

### 404 Not Found

| Code | Message Pattern | Cause | Fix |
|------|----------------|-------|-----|
| `not_found` | "Share not found" | Invalid share slug | Check slug spelling |
| `not_found` | "Judgement not found" | Invalid judgement UUID or no access | Check UUID and auth |

### 409 Conflict

| Code | Message Pattern | Cause | Fix |
|------|----------------|-------|-----|
| `conflict` | "Handle already exists" | Concurrent write or namespace collision on an owned handle | Retry or choose a different handle name |

### 429 Too Many Requests

| Code | Message Pattern | Cause | Fix |
|------|----------------|-------|-----|
| `rate_limited` | "Rate limit exceeded" | Too many queries per minute | Wait `Retry-After` seconds |

**Default personal-key rate limits:**

| Tier | RPM | Max Concurrent |
|------|-----|----------------|
| Personal Scry key | 60 | 1 |

### 503 Service Unavailable

| Code | Message Pattern | Cause | Fix |
|------|----------------|-------|-----|
| `service_unavailable` | "Scry pool is required..." | Scry DB pool not configured | Server-side issue; retry later |
| `service_unavailable` | Timeout-related | Query exceeded adaptive timeout | Simplify query, use MVs, add filters |

---

## Quota and Limits Reference

### Row Limits

| Tier | Standard | With Vectors (`?include_vectors=1`) |
|------|----------|--------------------------------------|
| Personal Scry key | 2,000 | 200 |

### Bandwidth Limits (24h Rolling)

| Tier | Daily Cap |
|------|-----------|
| Personal Scry key | 1 GB |

### Embedding Token Budget

Private keys get 1.5M tokens per 30-day key lifecycle. Tokens are consumed by
`POST /v1/scry/embed` calls. The budget is not renewable within a key's lifetime.

### Query Timeout (Adaptive)

Timeouts are dynamic based on server load. The system reserves 12 cores for
non-Scry work and 10 cores for burst headroom.

| Condition | Personal Scry key | Higher-bid admission | Urgent admission |
|-----------|-------------------|----------------------|------------------|
| Idle | up to 30 min | up to 60 min | up to 2 hr |
| Normal | up to 10 min | up to 30 min | up to 60 min |
| Overloaded | up to 2 min | up to 10 min | up to 30 min |
| Absolute min | 20s | 60s | 5 min |

Paid queries can terminate earlier than the load-policy timeout when the
live-burn watchdog reaches the authorized exposure. `exposure_timeout_ms`
remains the fail-safe bound when the query is not producing rows yet or the
watchdog cannot stop it first. Estimate first if the user wants a tight
authorization.

### SQL Constraints

- Max query length: 100 KB
- Max LIMIT: 10,000 rows
- Single statement only (no `;` multi-statement)
- SELECT only (no INSERT, UPDATE, DELETE, DDL)
- No EXPLAIN ANALYZE (use `/v1/scry/estimate`)
- No FOR UPDATE / FOR SHARE
- No SELECT INTO
- No writes inside CTEs
- No Cartesian products (unjoined tables)
- The public Scry SQL surface blocks `pg_*` catalog access, `current_setting()`, `version()`,
  `current_user`, `session_user`, etc.

### Share Limits

- Title: max 180 chars
- Summary: max 800 chars
- Payload: max 1 MB (JSON)
- Payloads are automatically scanned for API key patterns and redacted

### Judgement Limits

- Emitter: max 120 chars
- judgement_kind: max 120 chars
- Summary: max 4,000 chars
- Payload: max 512 KB (JSON)
- Tags: max 32, each max 64 chars
- Confidence: 0.0 to 1.0
- target_external_ref: max 400 chars
- Public judgements cannot use `target_external_ref`

---

## Fallback Strategies

### Query Timeout Fallback

1. Replace `scry.entities` with a specific materialized view
2. Add `WHERE source = '...'` to narrow scope
3. Add date range filters (`original_timestamp >= '...'`)
4. Reduce LIMIT
5. Use `scry.search_ids()` instead of `scry.search()` for cheaper candidate fetch
6. Run `/v1/scry/estimate` to check plan cost, suggested reserve, and `exposure_timeout_ms` before retrying
7. If the error is `query_exposure_exhausted`, raise `X-Scry-Max-Exposure` only after confirming the broader query is actually worth paying for

If curl prints HTTP `000`, that is usually a client timeout before the server
responded (for example `--max-time` shorter than server timeout). Increase
client timeout and/or estimate first.

### Rate Limit Fallback

1. Read `Retry-After` header and wait that many seconds
2. If sustained, batch queries (combine multiple filters into one CTE-based query)
3. Cache results client-side for repeat lookups

### Bandwidth Limit Fallback

1. Reduce LIMIT on queries returning payload text
2. Select only needed columns (omit `payload`, `metadata` when not needed)
3. Use `LEFT(payload, N)` to truncate payload in SELECT
4. Avoid `?include_vectors=1` unless vectors are needed

### Token Budget Exhaustion

1. Tell the user their embedding budget is exhausted
2. Suggest using pre-existing @handles or materialized view embeddings
3. For semantic search without new handles, use `scry.mv_*` views that have
   `embedding_voyage4` pre-joined

### Dangerous Content Warning

When query results include dangerous content, the API returns a header warning.
Always filter with `content_risk IS DISTINCT FROM 'dangerous'` on canonical
entity surfaces that expose the field directly, such as `scry.entities`. If a
source-native surface does not expose `content_risk`, join it to `scry.entities`
on `entity_id` and filter there. Never display payload text from dangerous
entities in LLM-visible contexts.

---

## Common Mistakes

| Mistake | Error | Fix |
|---------|-------|-----|
| JSON-wrapping the SQL body | Parse error | Use `Content-Type: text/plain` with raw SQL |
| Missing LIMIT | "Query must include a LIMIT clause" | Add LIMIT |
| API key from `.env` fails intermittently | 401 "Invalid authorization format" | Clean key with `KEY_CLEAN=\"$(printf '%s' \"$SCRY_API_KEY\" | tr -d '\\r\\n')\"` |
| Using `kind = 'post'` without cast | Type mismatch | Use `kind = 'post'` (enum literal) or `kind::text = 'post'` |
| Querying `pg_catalog` on the Scry SQL surface | Forbidden | Use `GET /v1/scry/schema` |
| Assuming all entities have embeddings | Empty results | Add `WHERE embedding_voyage4 IS NOT NULL` |
| Using `id IN (SELECT ...)` | Slow O(n^2) | Use `EXISTS` or `JOIN` instead |
| Scanning scry.entities without WHERE | Timeout | Use a materialized view or add filters |
| Forgetting dangerous content filter | Potential prompt injection | Add `content_risk IS DISTINCT FROM 'dangerous'` on a canonical entity surface, or join through `scry.entities` and filter there |
| Using `score` for sorting large tables | Slow (COALESCE expression) | Use `upvotes` or source-specific fields |
| Multiple statements with `;` | "Only a single statement is supported" | Remove trailing `;` or combine into one query |
