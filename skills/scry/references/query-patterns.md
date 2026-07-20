# ClickHouse query patterns

Call `GET /v1/scry/schema`, choose an enabled registered relation, then send one
bounded ClickHouse statement to `POST /v1/scry/query`.

## Recent Hacker News items

```sql
SELECT hn_id, title, original_author, original_timestamp, uri
FROM scry_hackernews.hackernews_items
WHERE title != ''
ORDER BY original_timestamp DESC
LIMIT 20
```

## Hacker News aggregation

```sql
SELECT original_author, count() AS item_count
FROM scry_hackernews.hackernews_items
WHERE original_author IS NOT NULL
GROUP BY original_author
ORDER BY item_count DESC
LIMIT 20
```

## Recent Twitter/X observations

```sql
SELECT tweet_id, author_handle, text, original_timestamp, observed_at
FROM scry_twitter_real.twitter_posts_current
WHERE author_handle = 'example'
ORDER BY observed_at DESC
LIMIT 20
```

## Reddit comments

```sql
SELECT id, subreddit, author, body, created_utc
FROM scry_reddit_real.reddit_comments_raw
WHERE subreddit = 'MachineLearning'
ORDER BY created_utc DESC
LIMIT 20
```

Use only columns returned by the live schema. For lexical discovery, prefer
`POST /v1/scry/search`; do not substitute undocumented SQL compatibility
functions. Treat row counts, freshness, provenance, and corpus coverage as
separate claims.

## Registered vector helpers

Vector SQL uses ClickHouse helpers advertised by `GET /v1/scry/schema`:

- base algebra: `scry_vec_dot`, `scry_cosine_similarity`, `scry_vector_norm`,
  `scry_unit_vector`, `scry_scale_vector`, `scry_project_onto`,
  `scry_debias_vector`, `scry_debias_removed_fraction`, `scry_debias_safe`,
  `scry_contrast_axis`, and `scry_contrast_axis_balanced`
- diagnostics: `scry_axis_diagnostics`, `scry_debias_audit`,
  `scry_handle_matrix`, and `scry_seed_centroid`

Unquoted `@handles` are owner-scoped. ClickHouse binds their 2,048 Float32
values out of band and accepts placeholders only in registered vector argument
positions; quoted `@handle` text remains literal.
The PostgreSQL lane substitutes handles only and uses native functions for algebra; the ClickHouse lane also expands `scry_*` helpers, so helper SQL routed to the wrong home is rejected by design.

No ClickHouse retrieval relation is currently enabled. The physically present
`scry.scry_vector_search` and `scry.scry_vector_topk` views do not enforce the
corpus `content_risk IS DISTINCT FROM 'dangerous'` law, so the registry keeps
them unavailable. Use the PostgreSQL-homed `scry.semantic_search` or
`scry.semantic_rerank` surface for retrieval; do not query those physical
ClickHouse views directly.

Confirm the live signature and columns before use. Do not use
database-specific vector operators or assume that an unregistered embedding
table is queryable.

Vectors are ranking hypotheses. Check nearest rows against lexical evidence,
provenance, source coverage, and the intended concept before reporting a
semantic conclusion.

## Failure recovery

| Status | First move |
| --- | --- |
| `400` | Re-read `/v1/scry/schema`; fix ClickHouse syntax, relation, columns, or missing `LIMIT`. |
| `401` | Reload `SCRY_API_KEY` and remove whitespace. |
| `402` | Inspect account, pricing, estimate, and funding state. |
| `403` | Use a key with Scry scope; do not probe engine catalogs. |
| `429` | Respect `Retry-After`. |
| `503` | Tighten the query or retry later. |

If a relation or helper is absent from `/v1/scry/schema`, it is unavailable.
Choose another registered surface or report the coverage gap. Never route the
query to a fallback database.

For slow queries: reduce selected columns, add a selective predicate, lower the
limit, and inspect a recent time window when the schema exposes one. Use
`POST /v1/scry/estimate` before a broader retry.

### Field notes (verified 2026-07-14, twitter corpus)

- `request_timeout` (lane timeout, HTTP 408): scans finishing under ~80s pass;
  multi-minute scans get cut. Shard by `bucket_date` window (one quarter of
  `twitter_posts` with a sampled-author predicate runs in 10–80s) instead of
  retrying the full scan.
- `query_resource_limit_exceeded` (memory cap) is partly environmental: an
  identical query can pass, then fail minutes later. The structural fix beats
  retries: collapse GROUP BY cardinality by pre-selecting a small author set —
  `author_id IN (<inline subquery>) OR intHash64(author_id) % N = 0`.
- The SQL validator does not resolve CTE names — `WITH x AS (...) ... IN
  (SELECT ... FROM x)` fails as `mixed_executor_homes`, claiming `x` is an
  unregistered relation. Inline the subquery instead.
- `query_exposure_exhausted`: raise the per-query ceiling with an
  `x-scry-budget: <nanodollars>` header (e.g. `1000000000` = $1).
- `POST /v1/scry/estimate` may return `planner_unavailable` on builds without
  the EXPLAIN seam; budget from observed `spend_nanodollars` instead.
- A relation can appear in the schema `surfaces` list yet be denied as
  unregistered at query time; trust the relation list inside the denial error.
- Result rows arrive as `$untrusted.exact_b64u` (urlsafe base64 JSON) and the
  body can carry control characters — strip `[\x00-\x1f]` before parsing and
  pad the base64. An occasional edge `502` with body `error code: 502` is
  transient; retry once.
