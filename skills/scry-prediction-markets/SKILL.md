---
name: scry-prediction-markets
description: >-
  Use when a question is about prediction markets or graded public forecasts:
  what a market on Kalshi, Polymarket, or Manifold asked and how it priced or
  resolved, how a Manifold price moved bet by bet, what traders said in market
  comments, and how pundits scored on Prediction Archive. Relations:
  markets.catalog, manifold.markets, manifold.bets, manifold.comments,
  predictionarchive.predictions, predictionarchive.predictors,
  predictionarchive.sources.
---

# Prediction markets and forecasts

Market questions, prices, bets, and comments from Kalshi, Polymarket, and Manifold, plus the Prediction Archive ledger of public predictions with their grades. One cross-venue catalog for "what markets exist", Manifold depth tables for "what happened inside a market", Prediction Archive for "who said what and were they right".

## When to use

- Which markets ask about X, on which venue, and at what price or resolution.
- How a Manifold market's price moved, who bet, and where the price sits on the latest bet.
- What traders argued in Manifold comments on a market or topic.
- A pundit's track record: predictions, grades, hit rate, cited sources.
- Base rates: how forecasts about a topic or year graded out.

The core `scry` skill (auth, query door, response fields) is assumed loaded.

## Doors

| relation | one row is | key | time column | text column(s) | notes |
|---|---|---|---|---|---|
| `markets.catalog` | one folded market across Kalshi, Polymarket, Manifold, latest fold wins | `market_key` = `source`/`market_native_id` | `close_time`, `open_time`; `observed_on` is the fold day | `title` (case-sensitive token index; `lower(title) LIKE` ngram index); `description`, `outcomes` arrive empty | primary tier; freshness frozen, state as of the latest fold; lag 3d on 2026-09-25; Kalshi dominates, filter `source` or `volume` before a broad scan |
| `manifold.markets` | one observation of one market's state | `market_id`, version `observed_at` | `created_at_source`; `close_time`, `resolution_time` | `title` + `text_description` (lowercase token index) | depth; indexed within minutes, lag 4m on 2026-09-25; `LIMIT 1 BY market_id` first |
| `manifold.bets` | one bet | `bet_id` | `created_at_source` | none (scan class) | depth; lag 1m on 2026-09-25; scope by `contract_id` or a time window; `username`, `contract_slug` arrive empty |
| `manifold.comments` | one comment | `comment_id` | `created_at_source` | `contract_question` + `raw_content` (lowercase token index) | depth; lag 1m on 2026-09-25; `uri` is the permalink |
| `predictionarchive.predictions` | one graded prediction | `prediction_id` | `predicted_on`; `evaluated_on` | `statement`, `title`, `context` (scan; `scry_lex` works) | depth; hourly, lag 28m on 2026-09-25; `outcome` is correct, incorrect, indeterminate, or pending |
| `predictionarchive.predictors` | one tracked predictor with the site's scorecard | `predictor_id` | `observed_on` (snapshot) | `name`, `about` | depth; hourly, lag 6m on 2026-09-25; cheaper than aggregating predictions when the headline scorecard suffices |
| `predictionarchive.sources` | one article, transcript, or post that yielded two or more predictions | `source_id` | `published_on` | `title`, `url`, `author` | depth; hourly, lag 4d on 2026-09-25; single-prediction sources exist only as `source_url` on the prediction row |

## Idioms

- Token first, phrase second. Manifold: `hasToken(lower(concat(ifNull(title, ''), ' ', ifNull(text_description, ''))), 'agi')`; comments swap in `contract_question` and `raw_content`. Catalog: `hasAnyTokens(title, ['recession', 'Recession'])`, then `positionCaseInsensitive(title, 'us recession') > 0` to confirm a phrase.
- Latest state per market: wrap `manifold.markets` in `ORDER BY observed_at DESC LIMIT 1 BY market_id` before any filter on state, aggregate, or join. `observed_at` is the total order; `updated_at_source` is the source's own edit clock and ties.
- Time columns: `created_at_source` is when a market, bet, or comment was authored; `close_time` and `resolution_time` are the market's own events; `predicted_on` is when a prediction was made and `evaluated_on` when it was graded. `observed_on` is only the fold or observation day.
- Cheap sibling first: the predictors scorecard before aggregating predictions; `markets.catalog` with `source =` and `ORDER BY volume DESC` before any bets scan; bets and comments scoped by `contract_id = '<market_id>'` or a `created_at_source` window.
- Price from bets: `argMax(prob_after, created_at_source)` is the price on the latest bet; `prob_before != prob_after` keeps price-moving bets. `is_redemption` is null before 2024-07-04, so filter on the price change instead.
- Citation: `manifold.markets.uri` and `manifold.comments.uri` (`...#comment-<id>`) are permalinks; catalog `canonical_uri` points at `kalshi.com/markets/<ticker>` or `polymarket.com/event/<slug>`; Prediction Archive rows carry `uri`, and predictions also `source_url` for the cited article.
- Id lines: `market_key = 'manifold/<market_id>'`; `manifold.bets.contract_id` and `manifold.comments.contract_id` equal `manifold.markets.market_id`; `predictions.predictor_id` joins `predictors`; `predictions.source_id` joins `sources.source_id`, or `has(prediction_ids, prediction_id)` from the sources side. `LEFT ANTI JOIN predictionarchive.sources` counts predictions whose source page is absent.
- Semantic: mint a handle with `POST /v1/scry/embed`, then the top-level statement `SELECT target_key, scry_vector_topk_distance(embedding, @h) AS distance FROM embeddings.chunks WHERE source = 'manifold_markets' ORDER BY distance ASC LIMIT 10` returns market ids in well under a second. That form cannot sit inside a join; hydrate with `WHERE market_id IN (...)` or use row-level `scry_cosine_similarity` with `chunk_index = 0` in one slower statement. `scry_lex('recession', statement)` works on predictions.

## Worked queries

**Highest-volume Manifold markets mentioning AGI, latest state, deleted ones out**
```sql
SELECT market_id, title, probability, volume, unique_bettor_count, resolution, uri
FROM (
  SELECT market_id, title, probability, volume, unique_bettor_count, resolution, uri, is_deleted
  FROM manifold.markets
  WHERE hasToken(lower(concat(ifNull(title, ''), ' ', ifNull(text_description, ''))), 'agi')
  ORDER BY observed_at DESC
  LIMIT 1 BY market_id
)
WHERE is_deleted = 0
ORDER BY volume DESC
LIMIT 10
```
Ten markets with their permalinks; `probability` is null on non-binary markets. (verified 2026-09-25)

**Recession markets across venues by volume**
```sql
SELECT source, market_key, title, status, close_time, volume, canonical_uri
FROM markets.catalog
WHERE hasAnyTokens(title, ['recession', 'Recession'])
  AND positionCaseInsensitive(title, 'recession') > 0
ORDER BY volume DESC
LIMIT 10
```
Ten catalog rows, Polymarket at the top, each with its venue URL and fold-day status. (verified 2026-09-25)

**Prediction Archive hit rate by year, graded as the denominator**
```sql
SELECT toYear(predicted_on) AS year,
       count() AS predictions,
       countIf(outcome IN ('correct', 'incorrect')) AS graded,
       countIf(outcome = 'correct') AS correct,
       round(correct / graded, 3) AS hit_rate
FROM predictionarchive.predictions
WHERE predicted_on >= '2016-01-01' AND predicted_on < '2026-01-01'
GROUP BY year
ORDER BY year
LIMIT 20
```
One row per year; pending and indeterminate sit in `predictions` but not in `graded`. (verified 2026-09-25)

**Most-traded binary Manifold markets this month with the price on the latest bet**
```sql
SELECT b.contract_id AS market_id, m.title,
       count() AS bets, uniqExact(b.user_id) AS bettors,
       argMax(b.prob_after, b.created_at_source) AS last_price
FROM manifold.bets AS b
INNER JOIN (
  SELECT market_id, title, outcome_type
  FROM manifold.markets
  ORDER BY observed_at DESC
  LIMIT 1 BY market_id
) AS m ON m.market_id = b.contract_id
WHERE b.created_at_source >= '2026-09-01' AND b.created_at_source < '2026-09-25'
  AND b.prob_before != b.prob_after
  AND m.outcome_type = 'BINARY'
GROUP BY b.contract_id, m.title
ORDER BY bets DESC
LIMIT 10
```
Ten markets with bet and bettor counts and the last traded price; group by the base column, not the alias. (verified 2026-09-25)

**Most accurate predictors with a real sample**
```sql
SELECT name, accuracy_pct, graded, correct, incorrect, indeterminate, pending, total_predictions, uri
FROM predictionarchive.predictors
WHERE graded >= 30
ORDER BY accuracy_pct DESC, graded DESC
LIMIT 10
```
Predictor rows with the site's scorecard; `accuracy_pct` is correct over graded, indeterminate excluded. (verified 2026-09-25)

**Markets semantically closest to a question, hydrated with title and price**
```sql
SELECT e.target_key AS market_id, m.title, m.probability, m.volume, round(e.sim, 3) AS sim
FROM (
  SELECT target_key, scry_cosine_similarity(embedding, @pm_agi_by_2030) AS sim
  FROM embeddings.chunks
  WHERE source = 'manifold_markets' AND chunk_index = 0
  ORDER BY sim DESC
  LIMIT 10
) AS e
INNER JOIN (
  SELECT market_id, title, probability, volume
  FROM manifold.markets
  ORDER BY observed_at DESC
  LIMIT 1 BY market_id
) AS m ON m.market_id = e.target_key
ORDER BY sim DESC
LIMIT 10
```
Ten markets ranked by cosine similarity to a handle minted from a paragraph describing an AGI-by-2030 market; about ten seconds, so send `x-scry-max-seconds: 20`. (verified 2026-09-25)

## Traps

- Wrong clock: `observed_on` and `observed_at` say when a state was read, not when anything happened; on the catalog `observed_on` is the fold day and `status`, `volume`, `probability` are as of that fold.
- Unscoped scans: bets have no text index, and contract, user, and time predicates scan the table; bound with a `created_at_source` window or `contract_id`, send `x-scry-max-seconds`, and treat `deadline_partial: true` as a wrong probe.
- Alias columns: after a `LIMIT 1 BY` subquery, group and filter on base columns (`b.contract_id`), not on the aliased projection, or the engine refuses with NOT_AN_AGGREGATE.
- Deleted and stale rows: `manifold.markets.is_deleted` and `manifold.comments.is_deleted` mark removed items, filter after dedup; on Polymarket catalog rows `status = 'active'` outlives the close, so open means `status IN ('active', 'open') AND close_time >= now()`.
- Duplicates: `manifold.markets` is observation-append, so a bare `count()` counts observations, and a join without `LIMIT 1 BY market_id` fans out.
- Nulls: `probability` is null on non-binary markets; catalog `description`, `outcomes`, `resolve_time`, `liquidity` arrive empty; `evaluated_on` and `evaluation_reasoning` are null while a prediction is pending; a `source_id` can name a page absent from `predictionarchive.sources`.
- Case and encoding: the catalog title token index is case-sensitive (use `hasAnyTokens` over both spellings or `lower(title) LIKE '%...%'`); Manifold and comment token indexes are lowercase; predictions keep the source's curly apostrophes (`Apple’s`), so match with `positionCaseInsensitive` or `ILIKE` rather than a straight-quote token; `predictor_name` is a scan column, `predictor_id` is the key.

## Cross-family joins

- `predictionarchive.predictions.source_url = hackernews.items.outbound_url` finds the Hacker News threads on an article a prediction cites (rows returned 2026-09-25).
- `embeddings.chunks` with `source = 'manifold_markets'` carries `target_key = manifold.markets.market_id`; `markets.catalog.market_key = 'manifold/<market_id>'` ties the catalog row to the same market.
- `predictionarchive.predictions.source_domain` and `source_url` line up with `crawl.pages.host` and `crawl.pages.url` for the cited page's text.
