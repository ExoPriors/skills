---
name: scry-twitter-archive
description: >-
  Use when a question is about tweets, Twitter/X accounts, bios, follow
  edges, replies, quotes, or Community Notes: who said a phrase, when, first
  or most; how a term's share of a day's posts moved; what one account
  posted and how its bio and follower count changed; who replied to or
  quoted a post; whom an account follows and who follows it; which notes a
  post drew and their ratings. Covers the historical Twitter archive
  (twitter.*), its open sibling x_open.* (donated archives, curated AI
  discussion), community_notes.*, and the tweet embeddings.
---

# The historical Twitter archive

Posts, profiles, and edges as observed on x.com, at the observation grain: revisions are rows, profile states are rows, a follow edge carries its first and last sighting. `x_open.*` is the open sibling over a smaller donated-and-curated slice; `community_notes.*` is X's public export.

## When to use

- Who said a phrase, when, first or most, phrase-confirmed on `twitter.tweets`.
- How a term's share of one day's posts moved, by day, language, or author.
- What one handle posted, and how its bio and follower count changed.
- Who replied to or quoted a post; whom an account follows and who follows it; which accounts carry a word in their bio; which Community Notes a post drew and how they were rated.

The core `scry` skill (auth, query door, response fields, embed handles) is assumed loaded.

## Doors

Tier and lag from the `schema?mode=index` line, read 2026-09-25.

| relation | one row is | key | time | text | notes |
| --- | --- | --- | --- | --- | --- |
| `twitter.tweets` | one observed revision of a post | `tweet_id`, `version` | `bucket_date`; `original_timestamp` | `search_text_lc` tokens; `lower(text)` trigram | primary, lag 13m; fold `LIMIT 1 BY tweet_id` |
| `twitter.tweets_latest` | one post, newest revision | `tweet_id` | bound by `tweet_id` | as above | primary, lag 13m; the `tweet_id IN (...)` read |
| `twitter.users` | latest profile per `author_id`; unmerged rows recur | `author_id` | `observed_on` | `bio_lc` tokens; `bio` case-sensitive | depth, lag 4h; `argMax(col, observed_on)`; no handle index |
| `twitter.user_observations` | one profile observation per author-hour | `author_id`, `observed_hour` | `observed_on` | `bio_lc`, `bio` | depth, lag 7h; append-only |
| `twitter.bio_states` | one (author, bio) with first and last sighting | `author_id`, `bio` | `first_seen_on`, `last_seen_on` | `bio_lc`, `bio` | depth, lag 5h |
| `twitter.following` | one follow edge, follower-first | `follower_id`, `followee_id` | `first_observed_on`, `last_observed_on` | none | depth, lag 2h; filter `follower_id` or `follower_handle_lc` |
| `twitter.followers` | the same edges, followee-first | `followee_id`, `follower_id` | as above | none | depth, lag 2h; filter `followee_id` or `followee_handle_lc` |
| `twitter.replies` | one reply edge, keyed by target | `in_reply_to_tweet_id`, `tweet_id` | `bucket_date` | none | depth, lag 6h; no rows means unobserved |
| `twitter.quotes` | one quote edge, keyed by target | `quoted_tweet_id`, `tweet_id` | `bucket_date` | none | depth, lag 6h; retweets of a quoting post count |
| `twitter.author_timeline` | one post of one handle, newest first | args `handle`, `limit` (mandatory, max 10000) | `original_timestamp` | `text`, unindexed | depth, lag 13m; the per-author path |
| `twitter.token_search` | one revision matching one term | arg `term` | `bucket_date` | `text` | depth, lag 13m; several tokens go to `twitter.tweets` |
| `twitter.vector_search` | one neighbour of a query vector | args `vec = @handle`, `k` 1..100 | none | `canonical_uri` | depth, lag 8d; a curated followed-accounts sample |
| `twitter.recsys_follow_graph` | one anonymised follow edge | `user_index`, `author_index` | `time_chunk` | none | depth, frozen; structure only, never joins `twitter.users` |
| `x_open.tweets` | one open-slice post, converging per `tweet_id` | `tweet_id` | `bucket_date`; `original_timestamp` | as `twitter.tweets` | primary, lag 7h; `slice` in community_archive, long_ai_v1, thread_v1; the cheap sibling |
| `x_open.users` | latest profile of an open-slice author | `author_id` | `observed_hour`; `first_post`, `last_post` | `bio_lc` | depth, lag 39m; `slices`, `x_open_posts`, `follower_band` |
| `community_notes.notes` | one note of the 2025-02-22 export | `note_id` | `created_at` | `summary`, case-sensitive tokens | depth, frozen, lag 5d; `tweet_id` is the noted post |
| `community_notes.ratings` | one contributor rating of a note | `note_id`, `rater_participant_id` | `created_at` | none | depth, frozen; `helpfulness_level` in HELPFUL, SOMEWHAT_HELPFUL, NOT_HELPFUL |
| `community_notes.status_history` | one note's scoring-status timeline | `note_id` | `current_status_at` | none | depth, frozen; a note can lack a row |
| `embeddings.tweets` | one Voyage-4 chunk of an archive post | `canonical_uri`, `chunk_index` | `observed_on` | ANN only | depth, lag 8h; `tweet_id` is a String |
| `embeddings.x_open` | one Voyage-4 chunk of an open-slice post | `tweet_id`, `chunk_index` | `observed_on` | ANN only | primary; hydrate on `x_open.tweets` |

## Idioms

- Token first, phrase second: `hasAllTokens(search_text_lc, ['a', 'b']) AND positionCaseInsensitive(search_text_lc, 'a b') > 0`; tokens are lowercase. `lower(text) LIKE '%needle%'` is the trigram door for substrings.
- Bound `bucket_date` first on `twitter.tweets`; `ORDER BY tweet_id DESC` is newest-first on the key and stops at LIMIT, while `ORDER BY original_timestamp` sorts the whole match set. `twitter.tweets_latest` folds before the index prunes, so bound it by the key: `tweet_id >= (toUnixTimestamp(toDateTime('<start>', 'UTC')) * 1000 - 1288834974657) * 4194304`.
- Fold revisions after the filter: `ORDER BY version DESC LIMIT 1 BY tweet_id`; a post count is `uniqExact(tweet_id)`, never `count()`; hydrate known ids with `argMax(col, version) GROUP BY tweet_id`.
- Per-author reads go through `twitter.author_timeline(handle = 'x', limit = n)`, `x-scry-max-seconds: 30` for a prolific handle; bare `author_handle = 'x'` on `twitter.tweets` is refused. An older date slice starts from the author spine `twitter.tweets_by_author` (`author_handle_lc`) and hydrates literal ids.
- The cheap sibling `x_open.tweets` (`slice = 'long_ai_v1'` for AI discussion) answers year-wide aggregates cheaply; absence there is not absence from the archive.
- Edges read on their keyed side (`in_reply_to_tweet_id`, `quoted_tweet_id`, `follower_id`, `followee_handle_lc`). Hydrate edge ids on `twitter.tweets_latest WHERE tweet_id IN (<literal ids>)`; an `IN (SELECT ...)` there scans.
- Profiles: resolve a handle to `author_id` (`twitter.author_timeline(handle = 'x', limit = 1)` carries it), then `twitter.users WHERE author_id = <id>` with `argMax(col, observed_on)`; `max(followers)` is the peak, not the latest.
- Citation: `https://x.com/i/status/<tweet_id>` needs no handle. Ids are 64-bit and arrive as JSON strings: re-enter them as integer literals, never through a float.
- Semantic: `scry_vector_topk_distance(embedding_voyage4, @handle)` on `embeddings.x_open` ranks the open slice, `embeddings.tweets` the archive; the latter's `tweet_id` is a String, so hydrate on `twitter.tweets` with integer literals and `argMax(col, version)`.

## Worked queries

**Who used the phrase "context engineering" in the last 30 days, newest first**

```sql
SELECT tweet_id, author_handle, original_timestamp, reply_count, like_count, text
FROM twitter.tweets
WHERE bucket_date >= today() - 30
  AND hasAllTokens(search_text_lc, ['context', 'engineering'])
  AND positionCaseInsensitive(search_text_lc, 'context engineering') > 0
  AND NOT startsWith(text, 'RT @')
ORDER BY tweet_id DESC, version DESC
LIMIT 1 BY tweet_id
LIMIT 10
```

One row per post, newest first, retweets excluded. (verified 2026-09-25)

**What share of one day's posts mention "anthropic"**

```sql
SELECT bucket_date,
       uniqExact(tweet_id) AS tweets,
       uniqExactIf(tweet_id, hasToken(search_text_lc, 'anthropic')) AS mentions,
       round(100.0 * mentions / tweets, 3) AS pct
FROM twitter.tweets
WHERE bucket_date = '2026-09-23'
GROUP BY bucket_date
LIMIT 1
```

Posts, not revisions, on both sides of the ratio; one day per statement, a week exceeds a 20 s deadline. (verified 2026-09-25)

**Community Notes on ivermectin rated helpful**

```sql
SELECT n.note_id, n.tweet_id, n.created_at, s.current_status, n.summary
FROM community_notes.notes AS n
INNER JOIN community_notes.status_history AS s ON s.note_id = n.note_id
WHERE hasAnyTokens(n.summary, ['Ivermectin', 'ivermectin'])
  AND s.current_status = 'CURRENTLY_RATED_HELPFUL'
ORDER BY n.created_at DESC
LIMIT 10
```

Note text with its status; the inner join drops notes without a status row. (verified 2026-09-25)

**Who has "interpretability" in their bio, by followers**

```sql
SELECT author_id,
       argMax(handle, observed_on) AS h,
       argMax(followers, observed_on) AS fl,
       argMax(bio, observed_on) AS latest_bio
FROM twitter.users
WHERE hasToken(bio_lc, 'interpretability')
GROUP BY author_id
ORDER BY fl DESC
LIMIT 15
```

One row per account, latest handle, followers, and bio; `argMax` makes unmerged observations safe. (verified 2026-09-25)

**Who replied to a post, and what they said**

```sql
SELECT tweet_id
FROM twitter.replies
WHERE in_reply_to_tweet_id = 2056753169888334312
ORDER BY tweet_id DESC
LIMIT 20
```

```sql
SELECT tweet_id, author_handle, original_timestamp, like_count, text
FROM twitter.tweets_latest
WHERE tweet_id IN (2102138953415668052, 2095791241715929484, 2092929892375777417, 2092197022724133219, 2088473524893860142)
ORDER BY like_count DESC
LIMIT 5
```

Reply ids from the edge read, re-entered as integer literals; observed replies are a lower bound on `reply_count`. (verified 2026-09-25)

**Posts nearest a paragraph about alignment being capabilities in disguise**

```sql
SELECT tweet_id, canonical_uri, chunk_index,
       scry_vector_topk_distance(embedding_voyage4, @twarch_probe) AS distance
FROM embeddings.x_open
ORDER BY distance ASC
LIMIT 10
```

`@twarch_probe` is a handle minted with `POST /v1/scry/embed`; a post can repeat across chunks, so hydrate the ids on `x_open.tweets` with `LIMIT 1 BY tweet_id`. (verified 2026-09-25)

## Traps

- `count()` on `twitter.tweets` counts revisions (a post deleted at the source keeps its observed ones); `author_handle` is blank and `observed_on` NULL on some rows (`author_id` is always set).
- `summary` and `bio` token indexes are case-sensitive: spell both cases in `hasAnyTokens`. `text` can carry U+FFFD over invalid bytes; `hex(text)` reads them raw.
- ANN on `embeddings.x_open` accepts only `LIMIT 1 BY canonical_uri` as a collapse, which can exceed the statement byte ceiling; collapse at hydration.
- A missing edge is not a non-edge: a follow edge's absence is evidence only for a seed with high `coverage_ratio` in `twitter.follow_coverage`; `follower_handle` is blank on most edges, so filter ids and join `twitter.users` for names.
- A note without a `status_history` row has no status, not NEEDS_MORE_RATINGS; `tweet_id` is Int64 there and UInt64 on tweets; an unobserved noted post has no tweet row.
- `twitter.author_timeline` takes `limit` before any outer WHERE, so an older date slice returns nothing; a prolific handle can pass 15 s, so declare the deadline.

## Cross-family joins

- `community_notes.notes.tweet_id` to `twitter.tweets_latest.tweet_id` as integer literals, for the noted post.
- `x_open.*` shares `tweet_id` and `author_id` with `twitter.*`; the profile and edge relations key on the same `author_id`.
- `embeddings.tweets.tweet_id` (String) to `twitter.tweets.tweet_id` via `toUInt64`; `canonical_uri` is `https://x.com/i/status/<tweet_id>` in both.
- `persons.links` groups a Twitter account with its other public accounts under `person_id`; access is reviewed and requested by writing to hi@scry.io.
