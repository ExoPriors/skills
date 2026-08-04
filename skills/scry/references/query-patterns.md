# Scry query patterns (ClickHouse SQL dialect)

Call `GET /v1/scry/schema`, choose an enabled registered relation, then send one
bounded SQL statement to `POST /v1/scry/query`.

> **Twitter corpus access:** `twitter.tweets` and `twitter.token_search` are
> not available to public keys — a query naming them is refused at admission.
> The patterns transfer unchanged to other text-indexed relations (e.g.
> `reddit.comments`, `forums.posts`).

## Shape probes: count first, retrieve second

Almost every empty result, timeout, and memory cap traces to querying blind —
unknown predicate selectivity, a guessed value that does not exist, or missing
vocabulary. Count-only probes make the shape visible before retrieval. On
token-indexed relations, they usually avoid row retrieval and `ORDER BY`.

**Selectivity probe.** Before any retrieval query, run its WHERE clause as a
count:

```sql
SELECT count() AS hits
FROM reddit.comments
WHERE created_utc >= '2026-05-01' AND created_utc < '2026-06-01'
  AND hasToken(search_text_lc, 'polysemanticity')
LIMIT 1
```

Zero → vocabulary or value problem; fix the terms before widening. Millions →
narrow the window or add a predicate before paying for ORDER BY over the
match set. A handful to thousands → retrieve directly.

**Empty-result bisection.** When a multi-predicate query returns nothing,
re-run the count dropping one predicate at a time. The predicate whose
removal makes the count jump is the killer — usually value shape, not
absence: wrong case (`subreddit = 'machinelearning'` vs `'MachineLearning'`),
an un-lowercased token against a `_lc` column, a prefixed vs bare ID.

**Value-space probe.** Never guess categorical values. One GROUP BY shows
the real value space with its spelling and skew (~2.5s on full-retention
Reddit for a one-month window):

```sql
SELECT subreddit, count() AS c
FROM reddit.comments
WHERE created_utc >= '2026-05-01'
GROUP BY subreddit
ORDER BY c DESC
LIMIT 30
```

**Fan out sequentially — or batch with `countIf` on narrow windows.** For
a day-or-few window, one single-pass `countIf` bundle beats N round-trips:

```sql
SELECT countIf(hasToken(search_text_lc, 'mechinterp')) AS c_mechinterp,
       countIf(hasToken(search_text_lc, 'interpretability')) AS c_interp,
       countIf(hasToken(search_text_lc, 'sae')) AS c_sae
FROM reddit.comments
WHERE created_utc >= '2026-05-20' AND created_utc < '2026-05-21'
LIMIT 1
```

Window-scoping law: `countIf` scans every row the WHERE admits once, so
it wins when the window is narrow; over wide windows (a month or more) a
single common token forces the full scan and sequential single-token
counts win, because each single probe lets the text index prune
independently (~0.7s each, measured). For combined retrieval after the
probes, use one `hasAnyTokens` array, not an OR chain (§Multi-token
search). `UNION` and other set operations are not served, so batching
across variants happens through `countIf` bundles, token arrays, or one
`t IN (...)` pass over `arrayJoin` (§Vocabulary expansion), never through
stitched statements.

**Token predicate laws.** A `hasToken` needle must be a single token:
a needle containing a separator (`mech-interp`, `mech interp`) is a hard
error, not an empty result — split it into per-token probes, or use the
phrase idiom in §Multi-token search when the phrase itself matters.
Counting note: `count()` over `arrayJoin(tokens(x))` counts occurrences;
wrap in `arrayDistinct` — `arrayJoin(arrayDistinct(tokens(x)))` — to
count documents. Aggregates with unbounded state (`topK`, `uniqExact`,
`groupArray`, `quantileExact` families) are not served; use plain
`GROUP BY … ORDER BY count() DESC LIMIT k` for top-K.

## Multi-token search on text-indexed columns

Schema `query_guidance.indexed_predicates` names each relation's indexed
text column. Three entry points engage the text index:

- `hasToken(col, 'token')` — one token.
- `hasAllTokens(col, ['t1','t2'])` — all tokens, intersected inside the
  index. Measured on one year of `reddit.comments`: 70ms and 4.3M rows
  read, where `hasToken(...) AND hasToken(...)` read 202M rows in 316ms
  for the same 1,636 matches.
- `hasAnyTokens(col, ['t1','t2'])` — any token, one index pass. Measured
  349ms where the equivalent five-way `hasToken` OR took 738ms.

The index stores tokens without positions, so a phrase has no direct index
path. For a phrase, intersect its tokens, then refine with `LIKE`:

```sql
SELECT subreddit, score, body
FROM reddit.comments
WHERE hasAllTokens(search_text_lc, ['lid', 'off'])
  AND search_text_lc LIKE '%lid off%'
ORDER BY score DESC
LIMIT 20
```

Do not send bare `LIKE '%...%'` predicates without a token prefilter: the
engine then reads every row body in the scanned range, which is the common
path to the memory cap.

## Vocabulary expansion from the corpus

The corpus itself is the best thesaurus: rows matching a seed term carry the
community's own jargon, spellings, and adjacent handles. Use one bounded
probe:

```sql
SELECT t AS token, count() AS c
FROM (
  SELECT arrayJoin(tokens(search_text_lc)) AS t
  FROM reddit.comments
  WHERE created_utc >= '2026-05-01' AND created_utc < '2026-06-01'
    AND hasToken(search_text_lc, 'mechinterp')
)
WHERE length(t) > 3
GROUP BY t
ORDER BY c DESC
LIMIT 40
```

Skim past stopwords — the raw counts are co-occurrence, not salience. The
yield is the mid-list tokens you did not know to search for: project names,
insider shorthand, author handles. Feed each candidate back through a
selectivity probe and keep the ones with real signal. This turns lexical
fanout from guessing variants into reading them off the data.

### Prefix lexicon: spelling and morphology variants with counts

The same `arrayJoin` shape with a prefix filter reads the corpus's own
lexicon — case variants, compounds, misspellings, other-language forms —
each with its frequency. Start with a day window and widen only when one
day is too sparse:

```sql
SELECT t AS token, count() AS docs
FROM (
  SELECT arrayJoin(arrayDistinct(tokens(search_text_lc))) AS t
  FROM reddit.comments
  WHERE created_utc >= '2026-05-15' AND created_utc < '2026-05-16'
)
WHERE t LIKE 'attent%'
GROUP BY t
ORDER BY docs DESC
LIMIT 100
```

### Background frequencies and salience

To rank co-occurrence candidates by salience instead of raw count, fetch
their corpus-wide document frequencies in one bounded pass and compare
against their frequency inside the matched set — a candidate is jargon
when its share inside the match set far exceeds its share outside:

```sql
SELECT t AS token, count() AS docs
FROM (
  SELECT arrayJoin(arrayDistinct(tokens(search_text_lc))) AS t
  FROM reddit.comments
  WHERE created_utc >= '2026-05-15' AND created_utc < '2026-05-16'
)
WHERE t IN ('neurons', 'preprint', 'icml', 'saes', 'probes')
GROUP BY t
LIMIT 100
```

### Term trend lines

Per-month counts for one term use one bounded query:

```sql
SELECT toStartOfMonth(original_timestamp) AS m, count() AS hits
FROM hackernews.items
WHERE original_timestamp >= '2026-01-01'
  AND hasToken(search_text_lc, 'mechinterp')
GROUP BY m
ORDER BY m ASC
LIMIT 24
```

Beware the open month: the current month is a partial aggregate and will
read as a collapse next to closed months. Compare closed months only, or
normalize by the month's total row count.

## Recent Hacker News items

```sql
SELECT hn_id, title, original_author, original_timestamp, uri
FROM hackernews.items
WHERE title != ''
ORDER BY original_timestamp DESC
LIMIT 20
```

## Hacker News aggregation

```sql
SELECT original_author, count() AS item_count
FROM hackernews.items
WHERE original_author IS NOT NULL
GROUP BY original_author
ORDER BY item_count DESC
LIMIT 20
```

## Twitter corpus (offline for public keys)

`twitter.tweets`, `twitter.token_search`, and `twitter.vector_search` are
offline for public keys. Treat a refusal as unavailability and use another
registered text-indexed relation.

## Reddit comments

```sql
SELECT id, subreddit, author, body, created_utc
FROM reddit.comments
WHERE subreddit = 'MachineLearning'
ORDER BY created_utc DESC
LIMIT 20
```

Use only columns returned by the live schema. For lexical discovery, prefer
`POST /v1/scry/search`; do not substitute undocumented SQL compatibility
functions. Treat row counts, freshness, provenance, and corpus coverage as
separate claims.

## Semantic search from text

Load `SCRY_API_KEY`. Mint one named query vector:

```bash
curl -s https://api.scry.io/v1/scry/embed \
  -H "Authorization: Bearer $SCRY_API_KEY" \
  -H "Content-Type: application/json" \
  --data '{"text":"How do communities govern powerful AI systems?","name":"my_query"}'
```

The normal metered provider call uses `voyage-4-lite`. It stores a
2,048-dimension vector under `my_query`. If the response reports a different
model, trust the response model field. List stored vectors:

```bash
curl -s https://api.scry.io/v1/scry/vectors \
  -H "Authorization: Bearer $SCRY_API_KEY"
```

Use the stored name as the unquoted handle `@my_query` in SQL.

### Embedding corpus catalog

The live schema is the authority for which embedding relations exist, their
row counts, freshness, and which currently serve ANN (`serves_ann: true`).
Hydration joins for the registered families:

| relation | scope column users filter on | hydration join |
| --- | --- | --- |
| `embeddings.academic_paper_chunks` | `source_bucket` or exact `paper_key` | `academic.papers.paper_key = paper_key` |
| `embeddings.forum_posts` | `post_key` prefix, such as `lesswrong%` | `forums.posts.post_key = post_key` |
| `embeddings.reddit_comments` | `subreddit`, then `kind` | `reddit.comments.id = substring(full_id, 4)` for comments |
| `embeddings.hackernews_items` | exact or ranged `hn_id` | `hackernews.items.hn_id = hn_id` |
| `embeddings.stackexchange_posts` | `site`, then `stackexchange_id` | `(stackexchange.posts.id, stackexchange.posts.site) = (stackexchange_id, site)` |
| `embeddings.mailing_list_messages` | `message_key` prefix, such as `xorg-devel::` | `mailing_lists.messages.message_key = message_key` |

Unscoped ANN and `count()` over `embeddings.academic_paper_chunks` are
expensive (tens of seconds and large burden). Scope with `paper_key` or
`source_bucket`.

### Search LessWrong

Rank LessWrong chunks. Keep the model filter:

```sql
SELECT post_key, chunk_index, token_count, model_name,
       scry_vector_topk_distance(embedding_voyage4, @my_query) AS distance
FROM embeddings.forum_posts
WHERE model_name = 'voyage-4-lite'
  AND post_key LIKE 'lesswrong%'
ORDER BY distance ASC
LIMIT 20
```

The table stores each chunk under both `voyage-4-lite` and
`voyage-4-large`. Without `WHERE model_name = 'voyage-4-lite'`, near-duplicate
chunks occupy the result list.

Hydrate text in a second query. Copy the returned keys into `IN`:

```sql
SELECT post_key, title, original_author, original_timestamp, payload
FROM forums.posts
WHERE post_key IN (
  '<post_key from the ANN result>'
)
LIMIT 20
```

The hydration key is
`forums.posts.post_key = embeddings.forum_posts.post_key`.

### Search Reddit

Scope ANN ranking to one subreddit:

```sql
SELECT full_id, kind, subreddit, original_timestamp, upvotes,
       chunk_index, token_count, model_name,
       scry_vector_topk_distance(embedding_voyage4, @my_query) AS distance
FROM embeddings.reddit_comments
WHERE subreddit = 'CryptoCurrency'
  AND kind = 'comment'
ORDER BY distance ASC
LIMIT 20
```

Replace the subreddit equality with
`subreddit IN ('CryptoCurrency', 'MachineLearning')` to search a small set.
Keep `kind = 'comment'`.

The embedding relation has no text column. Hydrate comment bodies in a second
query. Copy the returned `full_id` values into `substring`:

```sql
SELECT id, subreddit, author, body, created_utc, score
FROM reddit.comments
WHERE subreddit = 'CryptoCurrency'
  AND id IN (
    substring('<full_id from the ANN result>', 4)
  )
LIMIT 20
```

Reddit embedding keys include the thing prefix, such as `t1_112n`. Raw comment
IDs omit it, such as `112n`. The verified hydration key is
`reddit.comments.id = substring(embeddings.reddit_comments.full_id, 4)`.
Keep the subreddit predicate. Add a `created_utc` window from the returned
`original_timestamp` values when hydrating a large result list.

The Reddit embedding corpus is predominantly `voyage-4-nano` with a small
`voyage-4-lite` share. Voyage-4 models share a ranking space — a same-chunk
`voyage-4-lite` versus `voyage-4-large` check averaged
`cosineDistance = 0.092` over 262 rows — so use the minted Lite query vector
against Nano corpus rows. Check the live schema freshness metadata before
use.

### Recall audit: semantic sweep over the lexical net

A lexical net cannot measure its own recall. When a question must be
answered exhaustively, close the loop:

1. Run the lexical fanout and keep the matched row IDs.
2. Mint one query vector from the question text (§Semantic search from
   text) and rank the same scope with `scry_vector_topk_distance`.
3. Hydrate the ANN top rows and diff them against the lexical hits.

ANN rows that the lexical net missed are the measured leak. Read them for
the vocabulary you did not search — community phrasings rarely match the
question's words — then add those tokens and probe again. Report recall as
the result of this audit, never as an assertion.

## Academic metadata joins

`openalex.works` carries title, year, authorships, topics, citations,
and `doi_norm` (lowercase bare DOI, bloom-indexed). Full text lives in
`academic.papers`, keyed by percent-encoded DOI. The bridge:

```sql
SELECT w.title, w.publication_year, w.cited_by_count, p.text
FROM openalex.works AS w
INNER JOIN academic.papers AS p
  ON w.doi_norm = decodeURLComponent(p.paper_key)
WHERE w.doi_norm = '10.1093/nq/s11-x.256.418b'
LIMIT 1
```

Semantic result hydration composes the same bridge: chunk search returns
`paper_key`; `decodeURLComponent(paper_key)` equals `works.doi_norm`. For
the full estate map and the reviewer-discovery loop, follow
`references/academic-reviewers.md`.

## Registered vector helpers

Vector SQL uses registered helpers advertised by `GET /v1/scry/schema`:

- base algebra: `scry_vec_dot`, `scry_cosine_similarity`, `scry_vector_norm`,
  `scry_unit_vector`, `scry_scale_vector`, `scry_project_onto`,
  `scry_debias_vector`, `scry_debias_removed_fraction`, `scry_debias_safe`,
  `scry_contrast_axis`, and `scry_contrast_axis_balanced`
- ranking: `scry_vector_topk_distance`
- diagnostics: `scry_axis_diagnostics`, `scry_debias_audit`,
  `scry_handle_matrix`, and `scry_seed_centroid`

Unquoted `@handles` are owner-scoped. The query runtime binds their 2,048 Float32
values out of band and accepts placeholders only in registered vector argument
positions; quoted `@handle` text remains literal.
The query runtime expands registered `scry_*` helpers only after deterministic
validation; helper SQL outside those admitted shapes is rejected by design.

Registered embedding relations support exactly one
`scry_vector_topk_distance(embedding, @handle) AS distance` projection from
one ANN relation, optional `WHERE` predicates, `ORDER BY distance ASC`, and
`LIMIT 1` through `100`. The helper is ranking-only. Other vector helpers
retain their algebra semantics.

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
| `402` | Inspect account, pricing, and funding state. |
| `403` | Use a key with Scry scope; do not probe engine catalogs. |
| `429` | Respect `Retry-After`. |
| `503` | Tighten the query or retry later. |

If a relation or helper is absent from `/v1/scry/schema`, it is unavailable.
Choose another registered surface or report the coverage gap. Never route the
query to a fallback database.

For slow queries: reduce selected columns, add a selective predicate, lower the
limit, and inspect a recent time window when the schema exposes one. Broaden
only after the bounded retry succeeds.

### Known failure modes

- `request_timeout` (query execution timeout, HTTP 408): shard by an indexed
  time window instead of retrying the full scan.
- The parser accepts the standard `WITH <name> AS (SELECT ...)` CTE form.
  ClickHouse scalar `WITH <expr> AS <name>` fails as a parse error. Inline the
  expression or use the standard CTE form.
- `query_exposure_exhausted`: raise the per-query ceiling with an
  `x-scry-budget: <nanodollars>` header (e.g. `1000000000` = $1).
- A relation can appear in the schema `surfaces` list yet be denied as
  unregistered at query time; trust the relation list inside the denial error.
- Parallel queries on one key can return `429` above the per-account
  concurrency gate (24 as of 2026-07-29; was 2 before, which caused 429s
  at 3 concurrent). Obey `Retry-After` on retry.
- `hasToken` retrieval cost lives in row reads + ORDER BY, not in matching:
  a common token over a broad window can run for minutes under any `ORDER BY`,
  while the same predicate is suitable for a count-only shape probe. Count
  first; read a retrieval timeout as "match set too wide", then narrow the
  window or predicates before retrying.
- An `OR` between `doi_norm` and `hasToken` predicates on
  `openalex.works` defeats index pruning and times out. Run the exact
  `doi_norm` query first, then the token query as a separate fallback.
- Result rows arrive as `$untrusted.exact_b64u` (urlsafe base64 JSON) and the
  body can carry control characters — strip `[\x00-\x1f]` before parsing and
  pad the base64. An occasional edge `502` with body `error code: 502` is
  transient; retry once.
