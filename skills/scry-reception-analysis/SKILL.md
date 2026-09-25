---
name: scry-reception-analysis
description: >-
  Use when the question is how something was received: how a paper, model
  release, product, launch, acquisition, or person landed in the weeks after,
  which threads carried it, who the loudest voices were, which tone words the
  comments used, how scores settled, and where follow-on mentions went. Walks
  hackernews.items, hackernews.story_scores, reddit.posts, reddit.comments, the
  historical Twitter archive (twitter.tweets, x_open.tweets), forums.posts,
  openalex.cited_by, and markets.catalog.
---

# Reception analysis

Fix one subject and a window opening on its announcement, find the threads that carried it in each family, and read them with denominators: who spoke, in what tone, how scores settled, where mentions went, a source row behind each claim.

## When to use

- How was a paper, model, product, or launch received on Hacker News, Reddit, the historical Twitter archive, and forums in the weeks after?
- Which threads carried it, and how did their scores settle?
- Who were the loudest voices, by reach and by count?
- Which tone words did the discussion use, and what share of comments carried them?
- Did mentions decay, or return on a second event?
- Which markets priced the outcome, and which works cite the paper?

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Method

1. Subject as tokens plus a phrase, window closed from the announcement day: `hasAllTokens(search_text_lc, [...])` and `positionCaseInsensitive(search_text_lc, '<phrase>') > 0`; semantic search only for an idea without a stable name.
2. Threads: `hackernews.items`, `kind = 'post'`, key `hn_id`, window on `original_timestamp`, LEFT JOIN `hackernews.story_scores` (`argMax(upvotes, observed_hour)` by `hn_id`) with `count()` of observations and `min(observed_hour)` on the row. The curve for one `hn_id` is `story_scores` `ORDER BY observed_hour`; a story first observed weeks after posting shows its settled score, not its rise.
3. Voices and tone: `hackernews.items`, `kind = 'comment'`, `hn_id` bounded below by the story id, `story_hn_id IN (<ids>)` where filled, else `parent_hn_id IN (<ids>)` (top level only), `NOT is_deleted AND NOT dead`; `countIf(hasAnyTokens(search_text_lc, [...]))` per word family beside `count()`, `uniqExact(original_author)` for voices, `topK(3)(original_author)` for the most frequent.
4. Reddit: `reddit.posts`, key `id`, window on `created_utc`, grouped by `subreddit`, `uniqExact(id)` over readings, the phrase required in `title`; one post's comments from `reddit.comments`, `link_id = 't3_<id>'`, a closed `created_utc` window from the post day, `parent_id = link_id` for top level.
5. The historical Twitter archive forks: `x_open.tweets` (key `tweet_id`, window on `original_timestamp`) is the cheap sibling, the whole window per day in one statement, `uniqExact(tweet_id)` beside `uniqExact(author_id)`, absence there not absence from the archive; `twitter.tweets` is the wide relation, `bucket_date` bounded to about a week, `NOT startsWith(text, 'RT @')`, `uniqExact(tweet_id)` over revisions, voices by `max(author_followers)` for reach and `max(like_count)` for resonance.
6. Forums: `forums.posts`, key `post_key`, window on `original_timestamp`, `hasAllTokens(lower(payload), [...])`, grouped by `site_key`; denominators use `kind = 'post'`; `upvotes` only inside lesswrong, eaforum, devto.
7. Papers: `openalex.cited_by`, key `cited_work_id` (full `https://openalex.org/W...` id), `uniqExact(citing_work_id)` per month of `publication_date`; frozen, so the wave stops at its lag; the paper elsewhere is its arXiv id or DOI as a phrase.
8. Markets: `markets.catalog`, key `market_key`, `hasAnyTokens(title, ['Name', 'name'])` since the title index is case-sensitive, `close_time >= <announcement day>`; `probability`, `volume`, `status`, `resolution` read the outcome. The catalog is a fold with its own lag.
9. Denominators: numerator and denominator on one row (`countIf` beside `count()`, `uniqExactIf` beside `uniqExact`), grouped by the unit claimed (day, thread, subreddit, site); one family's count is never a share of another's; a family whose extent or lag misses the window is unreached, never zero.

## Worked walk

Question: how was Nvidia's agreement to acquire Hugging Face, announced 2026-08-27, received in the four weeks after?

**Hacker News threads, settled scores, observation counts.**
```sql
SELECT i.hn_id, i.title, i.original_author, i.original_timestamp, s.score, s.comments, s.observations, s.first_seen
FROM hackernews.items AS i
LEFT JOIN (
  SELECT hn_id, argMax(upvotes, observed_hour) AS score, argMax(comment_count, observed_hour) AS comments,
         count() AS observations, min(observed_hour) AS first_seen
  FROM hackernews.story_scores WHERE original_timestamp >= '2026-08-26' GROUP BY hn_id
) AS s ON s.hn_id = i.hn_id
WHERE i.kind = 'post' AND i.original_timestamp >= '2026-08-26' AND i.original_timestamp < '2026-09-25'
  AND hasAllTokens(i.search_text_lc, ['nvidia', 'hugging'])
  AND positionCaseInsensitive(i.search_text_lc, 'hugging face') > 0
ORDER BY s.score DESC
LIMIT 12
```
The announcement thread (hn_id 49458161, score 1988) leads, a second wave arrives on 2026-09-03 and 2026-09-04 when the deal closed, and each thread's first observation is 2026-09-12: settled scores, not curves. (verified 2026-09-25)

**Voices and tone under the four largest threads.**
```sql
SELECT story_hn_id AS thread, count() AS comments, uniqExact(original_author) AS voices,
       countIf(hasAnyTokens(search_text_lc, ['antitrust', 'monopoly'])) AS antitrust,
       countIf(hasAnyTokens(search_text_lc, ['worried', 'concerned'])) AS worried,
       countIf(hasAnyTokens(search_text_lc, ['great', 'congrats'])) AS cheer,
       topK(3)(original_author) AS most_frequent
FROM hackernews.items
WHERE kind = 'comment' AND hn_id >= 49458161 AND hn_id < 49800000
  AND story_hn_id IN (49458161, 49548952, 49567357, 49558584)
  AND NOT is_deleted AND NOT dead
GROUP BY thread
ORDER BY comments DESC
LIMIT 12
```
`story_hn_id` is filled here, so the tree count matches the thread's comment count; each tone family is a small share of its thread, cheer ahead of antitrust and worry, and three names lead by count. (verified 2026-09-25)

**Reddit threads by subreddit, phrase in the title.**
```sql
SELECT subreddit, uniqExact(id) AS posts, max(score) AS top_score, argMax(title, score) AS top_title, argMax(id, score) AS top_id
FROM reddit.posts
WHERE created_utc >= '2026-08-26' AND created_utc < '2026-09-25'
  AND hasAllTokens(search_text_lc, ['nvidia', 'hugging'])
  AND positionCaseInsensitive(title, 'hugging face') > 0
GROUP BY subreddit
ORDER BY top_score DESC
LIMIT 12
```
General subreddits hold the highest-scored posts, model-hosting communities the most posts. (verified 2026-09-25)

**Mention curve in the historical Twitter archive, cheap sibling first.**
```sql
SELECT toDate(original_timestamp) AS day, uniqExact(tweet_id) AS mentions, uniqExact(author_id) AS authors
FROM x_open.tweets
WHERE original_timestamp >= '2026-08-26' AND original_timestamp < '2026-09-10'
  AND hasAllTokens(search_text_lc, ['nvidia', 'hugging'])
  AND positionCaseInsensitive(search_text_lc, 'hugging face') > 0
GROUP BY day
ORDER BY day
LIMIT 20
```
Two waves, the announcement day and the closing days 2026-09-03 and 2026-09-04, authors close to mentions each day, so no single account drives the curve. (verified 2026-09-25)

**Loudest voices by reach, one week of the wide relation.**
```sql
SELECT author_handle, max(author_followers) AS followers, uniqExact(tweet_id) AS posts, argMax(tweet_id, like_count) AS top_tweet, max(like_count) AS top_likes
FROM twitter.tweets
WHERE bucket_date >= '2026-08-26' AND bucket_date < '2026-09-03'
  AND hasAllTokens(search_text_lc, ['nvidia', 'hugging'])
  AND positionCaseInsensitive(search_text_lc, 'hugging face') > 0
  AND NOT startsWith(text, 'RT @')
GROUP BY author_handle
ORDER BY followers DESC
LIMIT 12
```
News desks lead by followers, a reply bot by post count, and the most-liked post came from a smaller account: followers for reach, likes for resonance. (verified 2026-09-25)

**Markets that priced the outcome.**
```sql
SELECT source, market_key, title, status, probability, volume, close_time, canonical_uri
FROM markets.catalog
WHERE close_time >= '2026-08-26'
  AND hasAnyTokens(title, ['Hugging', 'hugging', 'HuggingFace'])
ORDER BY volume DESC
LIMIT 12
```
One Manifold market, "What will happen to Hugging Face?", resolved on 2026-09-03, the closing day the curve showed; the rest are incident markets about the same company, so a title match is read before it is counted. (verified 2026-09-25)

## Reading the answer

- Citation per family: Hacker News `hn_id`, `uri`, `original_author`, `original_timestamp`; Reddit `id` as `https://www.reddit.com/r/<subreddit>/comments/<id>/`, `author`, `created_utc`; the archive `tweet_id` as `https://x.com/i/status/<tweet_id>`, `author_handle`, `original_timestamp`; forums `uri`, `original_author`, `original_timestamp`; OpenAlex `citing_work_id`, `publication_date`; markets `canonical_uri`, `close_time`.
- Coverage from the response: `coverage.extent`, `coverage.freshness_lag_seconds`, `coverage.known_holes` per relation, next to each count; `coverage.grain` names key and version column, so a count over observations is `uniqExact(key)` and a score is the latest observation.
- An empty result is a wrong probe before it is an absence: read `zero_rows.establishes` and `empty_result_note`, then retry with a rarer token, the phrase alone, the cheap sibling, or a wider window; `deadline_partial: true` is a cut scan, not a result.

## Traps

- Alias collisions: `id` is a Reddit post id and an OpenAlex URL; `score` is a Reddit reading and an alias set on Hacker News; `title` sits on items, story_scores, markets. Prefix joined columns.
- Time columns differ: `original_timestamp` (Hacker News, the archive, forums), `created_utc` (Reddit), `bucket_date` for storage (twitter.tweets), `publication_date` of the citing work (OpenAlex), `close_time` (markets); one window pasted across families is wrong somewhere.
- Duplicates across observations: twitter.tweets revisions, reddit.posts and reddit.comments readings, story_scores hourly rows; `count()` counts observations, `uniqExact(key)` counts things.
- A token means two things: a name is also a common word, and a roundup mentions a subject without being about it; confirm the phrase, key threads on the title.
- Extent and lag: story_scores begins in late 2025, so an earlier launch has no curve, and a story first observed after it settled is a flat line; OpenAlex is frozen months behind; the catalog folds on a few days, so a market closed before the fold may be absent; Reddit tail scores sit near zero, so rank by score only inside archive months.
- `story_hn_id` is NULL on most older Hacker News comments; there `parent_hn_id IN` gives top-level replies, and a share over them is of top-level replies, not the thread.

## Families

- hackernews.items: key `hn_id`, time `original_timestamp`, text `search_text_lc`.
- hackernews.story_scores: key `hn_id`, version `observed_hour`, time `observed_hour` (story `original_timestamp`), text `title`.
- reddit.posts: key `id` (readings), time `created_utc`, text `search_text_lc`.
- reddit.comments: key `id` (readings), time `created_utc`, text `search_text_lc`.
- twitter.tweets: key `tweet_id` (revisions), time `original_timestamp`, `bucket_date` for storage, text `search_text_lc`.
- x_open.tweets: key `tweet_id` (`slice`), time `original_timestamp`, text `search_text_lc`.
- forums.posts: key `post_key` (scope `site_key`), time `original_timestamp`, text `lower(payload)`.
- openalex.cited_by: key `cited_work_id`, time `publication_date` of the citing work, text none.
- markets.catalog: key `market_key`, time `close_time`, `open_time`, `observed_on` the fold day, text `title` (case-sensitive tokens).
