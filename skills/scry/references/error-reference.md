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
| `invalid_request` | "payload exceeds N bytes" | Share (1MB) or judgement (512KB) payload too large | Trim payload |
| `invalid_request` | "confidence must be between 0 and 1" | Confidence out of range | Use 0.0 to 1.0 |

### 401 Unauthorized

| Code | Message Pattern | Cause | Fix |
|------|----------------|-------|-----|
| `unauthorized` | "Missing or invalid API key" | No `Authorization: Bearer` header or key not recognized | Use your personal Scry API key from `scry.io/console` and ensure it has Scry access |
| `unauthorized` | "Invalid authorization format" | Authorization header malformed (extra quotes, whitespace, or newline in env var) | Strip CR/LF from key, ensure exact `Authorization: Bearer <key>` |
| `unauthorized` | "API key expired" | Key past 30-day expiry | Regenerate via `/api/console/scry/regenerate-key` or get new pass |

### 402 Payment Required

| Code | Message Pattern | Cause | Fix |
|------|----------------|-------|-----|
| `insufficient_credits` | "Embedding token budget exhausted" | 1.5M token budget used up | Notify user; budget resets with new pass |
| `subscription_required` | "Active Scry pass required" | Feature requires paid pass | Purchase day/week/month pass at scry.io |

### 403 Forbidden

| Code | Message Pattern | Cause | Fix |
|------|----------------|-------|-----|
| `forbidden` | "Active Scry pass required" | Feature requires a paid Scry pass (for example rerank or premium queue access) | Upgrade in `scry.io/console` and retry with the same personal Scry API key |
| `forbidden` | "Postgres introspection blocked" | Query touched `pg_*` catalogs, `current_setting()`, `version()`, etc. | Use `GET /v1/scry/schema` instead |
| `forbidden` | "Only the share owner can update" | PATCH on share you don't own | Use the key that created the share |

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

**Rate limits by tier:**

| Tier | RPM | Max Concurrent |
|------|-----|----------------|
| Base account | 60 | 1 |
| Day pass | 120 | 1 |
| Week pass | 240 | 2 |
| Month pass | 600 | 3 |

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
| Base account | 2,000 | 200 |
| Pass | higher than base account | higher than base account |

### Bandwidth Limits (24h Rolling)

| Tier | Daily Cap |
|------|-----------|
| Base account | 1 GB |
| Pass / priority add-on | plan-dependent |
| Week pass | 2 GB |
| Month pass | 5 GB |

### Embedding Token Budget

Private keys get 1.5M tokens per 30-day key lifecycle. Tokens are consumed by
`POST /v1/scry/embed` calls. The budget is not renewable within a key's lifetime.

### Query Timeout (Adaptive)

Timeouts are dynamic based on server load. The system reserves 12 cores for
non-Scry work and 10 cores for burst headroom.

| Condition | Base account | Pass | Priority |
|-----------|--------------|------|----------|
| Idle | up to 30 min | up to 60 min | up to 2 hr |
| Normal | up to 10 min | up to 30 min | up to 60 min |
| Overloaded | up to 2 min | up to 10 min | up to 30 min |
| Absolute min | 20s | 60s | 5 min |

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

---

## Fallback Strategies

### Query Timeout Fallback

1. Replace `scry.entities` with a specific materialized view
2. Add `WHERE source = '...'` to narrow scope
3. Add date range filters (`original_timestamp >= '...'`)
4. Reduce LIMIT
5. Use `scry.search_ids()` instead of `scry.search()` for cheaper candidate fetch
6. Run `/v1/scry/estimate` to check plan cost before retrying

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
Always filter with `content_risk IS DISTINCT FROM 'dangerous'` unless the user
explicitly requests unfiltered results. Never display payload text from dangerous
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
| Forgetting dangerous content filter | Potential prompt injection | Add `content_risk IS DISTINCT FROM 'dangerous'` |
| Using `score` for sorting large tables | Slow (COALESCE expression) | Use `upvotes` or source-specific fields |
| Multiple statements with `;` | "Only a single statement is supported" | Remove trailing `;` or combine into one query |
