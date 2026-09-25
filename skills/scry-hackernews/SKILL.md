---
name: scry-hackernews
description: >-
  Use when a question is about Hacker News: who said what and when on HN, the
  first item to mention a term, how much of HN discussed a topic per month,
  which stories or Show HN posts scored highest and how a score moved, who
  replied under which stories, what tone earns Show HN upvotes, or semantic
  search over HN items. Covers hackernews.items (stories, comments, jobs,
  polls since 2006), hackernews.story_scores (upvote and comment-count
  observations since 2025-12), hackernews.show_hn_traits and
  show_hn_trait_effects (scored Show HN register), and
  embeddings.hackernews_items (ANN vectors).
---

# Hacker News

Source-native Hacker News: stories, comments, jobs and polls as one item
relation keyed by `hn_id`, a score record beside it, a scored Show HN
register, and a vector index over item text.

## When to use

- Earliest attestation or who-said-it on HN: a term, a phrase, a handle, a URL.
- Volume over time: items or stories matching a token per month, against the window's own denominator.
- Rankings: top stories or Show HN posts in a window by latest score; one story's score trajectory; the most active commenters; the most linked hosts.
- Thread structure: replies under one story or a set of stories, by author.
- Show HN register: which traits (certainty, hype, technical depth, feedback invite) go with upvotes, with example stories.
- Topical search without the vocabulary: vector ranking over HN items, then hydration by id.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Doors

| relation | one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `hackernews.items` | one HN item: story, comment, job, poll or pollopt (`kind` is post/comment; `hn_type` names the HN type) | `hn_id` | `original_timestamp` (authored); `observed_on` (observed) | `search_text_lc` (token index over title + body); `lower(payload)` (substring lane) | primary; hourly, lag 4m on 2026-09-25. `upvotes`/`comment_count` follow HN from 2026-09-12 through a rolling changed-ids window; rank recent stories through `story_scores`. |
| `hackernews.story_scores` | one observation of a story's (upvotes, comment_count, tags), kept when the record changed | `hn_id, observed_hour` | `original_timestamp` (story); `observed_on`, `observed_hour` (observation) | `title` (no index) | depth; hourly, lag 7m on 2026-09-25. Stories created since 2025-12-01, the trailing 30 days re-observed continuously. The cheaper door for any score question. |
| `hackernews.show_hn_traits` | one Show HN story with its latest score and ten standardized trait scores | `hn_id` | `posted_at` | `title` (no index) | depth; frozen, built 2026-09-12; model-derived, experimental. Show HN stories since 2025-12-01 with a body of 200+ bytes and a score record. |
| `hackernews.show_hn_trait_effects` | one trait's correlation with log upvotes: raw, length-controlled, fit period, holdout, quintile shares | `trait` | `observed_on` | none | depth; frozen, built 2026-09-12. Read it whole; it is the first read for "what does HN reward". |
| `embeddings.hackernews_items` | one Voyage-4 chunk of one item | `hn_id, chunk_index` | `observed_on` | none (vectors live in the index) | depth; live, lag 5m on 2026-09-25; `serves_ann: true`. Only `hn_id` scopes the search before ranking. |

## Idioms

- Tokens are lowercase whole words on `search_text_lc`: `hasToken` for one, `hasAllTokens` for co-occurrence, `hasAnyTokens` for spellings; confirm a phrase after the token prefilter with `positionCaseInsensitive(search_text_lc, 'a b') > 0`. A substring of three or more characters rides the n-gram lane as `lower(payload) LIKE '%needle%'`; bare LIKE on `search_text_lc` is refused.
- Bound `original_timestamp`: the relation is kept by month of it, so the window is the read, and an unbounded token predicate reads the whole relation (a few seconds for a count; an aggregate over the matched text may not fit, so declare `x-scry-max-seconds`). `hn_id` rises with time, so a date window is an id window:

```sql
SELECT min(hn_id) AS lo, max(hn_id) AS hi FROM hackernews.items WHERE original_timestamp >= '2026-08-01'
```

- Stories are `kind = 'post'` (`hn_type` story, job, poll, pollopt); comments are `kind = 'comment'`, carry NULL `upvotes` and an empty `title`. Items collapses re-loaded versions itself; no `LIMIT 1 BY hn_id` is needed there.
- Scores come from `story_scores`, an append-only observation log: latest per story is `argMax(upvotes, observed_hour) ... GROUP BY hn_id`, or `ORDER BY observed_hour DESC LIMIT 1 BY hn_id` when the whole latest row (tags included) is wanted; a trajectory is one `hn_id` ordered by `observed_hour`. `tags` carries `show_hn`, `ask_hn`, `front_page`, `story` and `author_<handle>`: filter with `has(tags, 'show_hn')`.
- Threads descend from the story through `parent_hn_id IN (<ids>)` (indexed), with `hn_id` bounded to the window on the reply side; a top-level comment's `parent_hn_id` is its story. `story_hn_id` is NULL on most archive comments (see `known_holes`), so never rebuild a thread from it alone.
- Citation: `uri` is the item's permalink (`https://news.ycombinator.com/item?id=<hn_id>`); `outbound_url` is the linked page of a link story, and `domain(outbound_url)` groups by host.
- Semantic: mint a handle (`POST /v1/scry/embed {text, name}`), rank `embeddings.hackernews_items` under a `hn_id` prefilter with `LIMIT 1 BY hn_id`, then hydrate the ids from `hackernews.items`:

```sql
SELECT hn_id, kind, original_author, original_timestamp, title, left(payload, 120) AS excerpt, uri
FROM hackernews.items
WHERE hn_id IN (49677081, 49664777, 49846501, 49198101, 49546983, 49570473, 49835124, 49379884, 49193041, 49739836)
ORDER BY hn_id DESC
LIMIT 10
```

## Worked queries

**Where and when did "vibe coding" first appear on HN?**

```sql
SELECT hn_id, kind, original_author, original_timestamp, uri
FROM hackernews.items
WHERE hasAllTokens(search_text_lc, ['vibe', 'coding'])
  AND positionCaseInsensitive(search_text_lc, 'vibe coding') > 0
ORDER BY original_timestamp ASC
LIMIT 10
```

Earliest attestations first, a story on 2025-02-03 at the head; unbounded on purpose, so it reads the whole relation in a few seconds. (verified 2026-09-25)

**What share of stories mentioned LLMs, month by month?**

```sql
SELECT toStartOfMonth(original_timestamp) AS month,
       countIf(hasToken(search_text_lc, 'llm')) AS llm_stories,
       count() AS stories,
       round(100 * llm_stories / stories, 2) AS pct
FROM hackernews.items
WHERE kind = 'post'
  AND original_timestamp >= '2025-09-01' AND original_timestamp < '2026-09-01'
GROUP BY month
ORDER BY month ASC
LIMIT 12
```

One row per closed month with hits, the denominator and the share; the open month is a partial aggregate, so close the window. (verified 2026-09-25)

**Which Show HN posts of the past week scored highest?**

```sql
SELECT hn_id,
       argMax(upvotes, observed_hour) AS score,
       argMax(comment_count, observed_hour) AS comments,
       any(title) AS title,
       any(original_author) AS author,
       count() AS observations
FROM hackernews.story_scores
WHERE original_timestamp >= today() - 7
  AND has(tags, 'show_hn')
GROUP BY hn_id
ORDER BY score DESC
LIMIT 10
```

One row per story at its latest observation; `observations` is how many times the record changed, a proxy for how long it stayed in motion. (verified 2026-09-25)

**Who replied most under stories about SQLite since August?**

```sql
SELECT c.original_author AS commenter, count() AS replies, uniqExact(s.hn_id) AS stories
FROM hackernews.items AS c
INNER JOIN (SELECT hn_id FROM hackernews.items WHERE kind = 'post' AND original_timestamp >= '2026-08-01' AND hasToken(search_text_lc, 'sqlite')) AS s
  ON c.parent_hn_id = s.hn_id
WHERE c.hn_id >= 49129847 AND NOT c.is_deleted AND NOT c.dead
GROUP BY commenter
ORDER BY replies DESC
LIMIT 10
```

Top-level repliers with reply and story counts; the `c.hn_id` floor (from the id-window idiom) keeps the reply side inside the window. (verified 2026-09-25)

**Which tone earns Show HN upvotes, and did it replicate?**

```sql
SELECT trait, round(corr_upvotes_length_controlled, 3) AS r_len_ctl,
       round(corr_fit_period, 3) AS r_fit, round(corr_holdout, 3) AS r_holdout,
       round(top_quintile_share_10plus, 3) AS top5_10plus, round(bottom_quintile_share_10plus, 3) AS bottom5_10plus
FROM hackernews.show_hn_trait_effects
ORDER BY r_len_ctl DESC
LIMIT 11
```

The whole table, one row per trait plus `body_length` as the control; quote `r_len_ctl`, trust a trait only when `r_holdout` keeps the sign of `r_fit`, and read the effect as the two quintile shares. (verified 2026-09-25)

**Which recent items sound like a build-system rewrite story, without naming it?**

```sql
SELECT hn_id, chunk_index,
       scry_vector_topk_distance(embedding_voyage4, @hn_probe) AS distance
FROM embeddings.hackernews_items
WHERE hn_id >= 49129847
ORDER BY distance ASC
LIMIT 1 BY hn_id
LIMIT 10
```

Ten items, nearest chunk each, after minting `@hn_probe` from an answer-shaped passage; hydrate the ids with the statement in Idioms. (verified 2026-09-25)

## Traps

- Wrong clock: `original_timestamp` is when the item was written; `observed_on` and `first_observed_on` are ingest days; `story_scores.observed_hour` orders observations; `show_hn_traits` keeps `posted_at`.
- `story_scores` is an observation log: `count()` counts observations, not stories; deduplicate with `GROUP BY hn_id` or `LIMIT 1 BY hn_id` before ranking.
- `upvotes` on `items` is a snapshot for stories outside the rolling changed-ids window and a load-time value for rows before 2025-12; for scores read `story_scores`.
- Aliasing an aggregate `upvotes` while ordering by it errors NOT_AN_AGGREGATE; alias it `score`.
- `is_deleted` and `dead` items stay as rows; exclude both for author or reply counts.
- `story_hn_id` is NULL on most archive comments; a merged duplicate's comments keep the duplicate's id even in the tail. The `parent_hn_id` chain is the tree.
- An unbounded `GROUP BY` or `arrayJoin` over text matches can outrun the deadline where the bare count fits; bound the months or declare `x-scry-max-seconds`.
- `hasToken` is case-sensitive; `search_text_lc` is already lowercase; `original_author = 'dang'` is exact-case.
- `payload` is plain text with HN's markup already resolved; quoted lines open with `>`; comments have no `title`, so title-only probes miss them.
- ANN: a keyed prefilter probes a bounded share of the index, so an empty keyed result is not absence; any WHERE other than `hn_id` post-filters a small candidate window and can only shrink the result.
- Show HN traits: quote medians and shares, not means (most stories sit at 1-3 points), and `corr_upvotes_length_controlled`, not `corr_upvotes`.

## Cross-family joins

- `original_author` is an HN handle: match it to `reddit.posts.author` or `forums.posts.author_handle` as a lead, never as an identity.
- `outbound_url` meets `crawl.pages.url` for the linked page's text, and `domain(outbound_url)` meets `crawl.pages.host`.
- `hn_id` drives the Datalog edges `hackernews.children`, `parent`, `story_items`, `by` and `items_of`, and keys the embeddings relation.
- A cross-venue series mirrors an HN month series on `reddit.posts.created_utc` under UNION ALL (examples slug `hn-versus-reddit-volume`).
