---
name: scry-trend-tracking
description: >-
  Use when the question is how a term's share of the conversation moved over
  time: month-by-month share against a family's own volume, eras named from
  the series, growth as a ratio to the previous month or era, the peak month
  taken back to cited rows, or one term across families side by side.
  Covers hackernews.items, reddit.comments_popular and reddit.comments, the
  historical Twitter archive (x_open.tweets, twitter.tweets), forums.posts,
  stackexchange.posts, academic.catalog and mailing_lists.messages. Method,
  not corpus.
---

# Trend tracking

How a term's share of what a family said moved month by month: each rate over that family's own volume in the same window, eras named from the series, growth as a ratio.

## When to use

- A term's share of a family's posts by month, silent months as zero rather than missing.
- Eras named from the series, each era's share as a ratio to the era before.
- One term across families in one statement, each against its own denominator.
- The peak month, taken back to the rows that made it.
- Whether a family's extent reaches the window before a share is reported there.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Method

1. Fix the window and grain: a half-open range on the family's authored clock (the time column under Families); month grain, year on the catalog.
2. Lexical is the instrument: `hasToken(search_text_lc, 'x')` where the column exists, `hasToken(lower(payload), 'x')` on forums and mailing lists, `hasAnyTokens(title, ['X', 'x'])` on the catalog's case-sensitive title index; confirm a phrase with `positionCaseInsensitive`. Semantic (an embed handle over the family's `embeddings.*` sibling) chooses tokens once and is never the numerator: a ranked list has no denominator.
3. Probe selectivity across candidate families in one UNION ALL, each branch with its own LIMIT, before any series: it shows who carries the term and whose extent misses the window.
4. Cheap sibling or wide relation: `reddit.comments_popular` and `x_open.tweets` return a monthly series in seconds; `reddit.comments` wants a `subreddit` scope beside `created_utc`; `twitter.tweets` is one `bucket_date` day per statement and its `count()` counts revisions. A sibling's share is the share of that subset; say so.
5. Denominator in the same SELECT: `countIf(<token>)` over `count()`, or `uniqExactIf(key, <token>)` over `uniqExact(key)` where rows are observations; `WITH FILL FROM ... TO ... STEP INTERVAL 1 MONTH` makes silent months zero; `lagInFrame(per_mille, 1) OVER (ORDER BY month)` is the ratio to the previous month.
6. Name eras from the series, not before it: breakpoints where the ratio changes regime, encoded with `multiIf`, each era's share and its ratio to the era before, per family, in one statement.
7. Cite the peak month with the family's id, url, timestamp and author columns. Each share names its numerator, denominator, family and window.

## Worked walk

Question: how did "agentic" move across families from 2025-01 through 2026-08, as a share of each family's own monthly volume?

**Step 1: selectivity across families in one statement**
```sql
SELECT family, hits FROM (
  (SELECT 'hackernews.items' AS family, count() AS hits FROM hackernews.items
   WHERE original_timestamp >= '2025-01-01' AND original_timestamp < '2026-09-01' AND hasToken(search_text_lc, 'agentic') LIMIT 1)
  UNION ALL
  (SELECT 'reddit.comments_popular', uniqExact(id) FROM reddit.comments_popular
   WHERE created_utc >= '2025-01-01' AND created_utc < '2026-09-01' AND hasToken(search_text_lc, 'agentic') LIMIT 1)
  UNION ALL
  (SELECT 'x_open.tweets', uniqExact(tweet_id) FROM x_open.tweets
   WHERE bucket_date >= '2025-01-01' AND bucket_date < '2026-09-01' AND hasToken(search_text_lc, 'agentic') LIMIT 1)
  UNION ALL
  (SELECT 'forums.posts', count() FROM forums.posts
   WHERE original_timestamp >= '2025-01-01' AND original_timestamp < '2026-09-01' AND hasToken(lower(payload), 'agentic') LIMIT 1)
  UNION ALL
  (SELECT 'stackexchange.posts', count() FROM stackexchange.posts
   WHERE original_timestamp >= '2025-01-01' AND original_timestamp < '2026-09-01' AND hasToken(search_text_lc, 'agentic') LIMIT 1)
  UNION ALL
  (SELECT 'mailing_lists.messages', count() FROM mailing_lists.messages
   WHERE original_timestamp >= '2025-01-01' AND original_timestamp < '2026-09-01' AND hasToken(lower(payload), 'agentic') LIMIT 1)
)
ORDER BY hits DESC
LIMIT 10
```
One row per family: Stack Exchange is zero because its extent ends before the window, the Reddit sibling is thin; the walk continues on Hacker News, the open slices and mailing lists. (verified 2026-09-25)

**Step 2: monthly share on Hacker News, gap fill, ratio to the previous month**
```sql
SELECT toStartOfMonth(original_timestamp) AS month,
       countIf(hasToken(search_text_lc, 'agentic')) AS hits,
       count() AS items,
       round(1000.0 * hits / items, 2) AS per_mille,
       round(per_mille / nullIf(lagInFrame(per_mille, 1) OVER (ORDER BY month ASC), 0), 2) AS ratio_to_prev
FROM hackernews.items
WHERE original_timestamp >= '2025-01-01' AND original_timestamp < '2026-09-01'
GROUP BY month
ORDER BY month ASC WITH FILL FROM toDate('2025-01-01') TO toDate('2026-09-01') STEP INTERVAL 1 MONTH
LIMIT 20
```
One row per month, no gap; the share climbed through 2025, peaked in early 2026 and eased; the first ratio is null by construction. (verified 2026-09-25)

**Step 3: mailing lists, where rows are observations, denominator as its own subquery**
```sql
SELECT d.month, h.hits, d.messages, round(1000.0 * h.hits / d.messages, 3) AS per_mille
FROM (
  SELECT toStartOfMonth(original_timestamp) AS month, uniqExact(message_key) AS messages
  FROM mailing_lists.messages
  WHERE original_timestamp >= '2025-01-01' AND original_timestamp < '2026-09-01'
  GROUP BY month
) AS d
LEFT JOIN (
  SELECT toStartOfMonth(original_timestamp) AS month, uniqExact(message_key) AS hits
  FROM mailing_lists.messages
  WHERE original_timestamp >= '2025-01-01' AND original_timestamp < '2026-09-01'
    AND hasToken(lower(payload), 'agentic')
  GROUP BY month
) AS h ON h.month = d.month
ORDER BY d.month ASC
LIMIT 20
```
Messages, not observations, on both sides; the share rose across the window and only the token branch touches text. (verified 2026-09-25)

**Step 4: eras across families, share and ratio to the era before**
```sql
SELECT family, era, hits, total, per_mille,
       round(per_mille / nullIf(lagInFrame(per_mille, 1) OVER (PARTITION BY family ORDER BY era_start ASC), 0), 2) AS ratio_to_prev_era
FROM (
  (SELECT 'hackernews.items' AS family,
          multiIf(original_timestamp < '2025-05-01', 'a: early', original_timestamp < '2026-02-01', 'b: climb', 'c: plateau') AS era,
          min(toStartOfMonth(original_timestamp)) AS era_start,
          countIf(hasToken(search_text_lc, 'agentic')) AS hits, count() AS total,
          round(1000.0 * hits / total, 3) AS per_mille
   FROM hackernews.items
   WHERE original_timestamp >= '2025-01-01' AND original_timestamp < '2026-08-01'
   GROUP BY era LIMIT 3)
  UNION ALL
  (SELECT 'x_open.tweets' AS family,
          multiIf(bucket_date < '2025-05-01', 'a: early', bucket_date < '2026-02-01', 'b: climb', 'c: plateau') AS era,
          min(toStartOfMonth(bucket_date)) AS era_start,
          uniqExactIf(tweet_id, hasToken(search_text_lc, 'agentic')) AS hits, uniqExact(tweet_id) AS total,
          round(1000.0 * hits / total, 3) AS per_mille
   FROM x_open.tweets
   WHERE bucket_date >= '2025-01-01' AND bucket_date < '2026-08-01'
   GROUP BY era LIMIT 3)
)
ORDER BY family ASC, era_start ASC
LIMIT 20
```
Three eras per family at the breakpoints step 2 showed; each climb is a ratio to the family's own earlier share, so families compare by ratio, never by raw share. (verified 2026-09-25)

**Step 5: the peak month back to rows**
```sql
SELECT hn_id, original_author, original_timestamp, upvotes, title, uri
FROM hackernews.items
WHERE original_timestamp >= '2026-02-01' AND original_timestamp < '2026-03-01'
  AND hasToken(search_text_lc, 'agentic')
  AND kind = 'post' AND NOT is_deleted AND NOT dead
ORDER BY upvotes DESC
LIMIT 10
```
Peak-month stories ranked by score, each with author, timestamp and a citable uri. (verified 2026-09-25)

## Reading the answer

- A share is numerator over denominator on one family, one window, one clock; a ratio is share over an earlier share; both operands are stated. Another family's or clock's denominator is not a trend.
- Citation columns: `hn_id`, `original_author`, `original_timestamp`, `uri` on Hacker News; `id`, `author`, `created_utc`, `subreddit`, `link_id` on Reddit; `tweet_id`, `author_handle`, `original_timestamp` and `https://x.com/i/status/<tweet_id>` on the historical Twitter archive; `uri`, `original_author`, `original_timestamp` on forums, Stack Exchange and mailing lists (`message_key` is the stable id); `doi`, `arxiv_id` or `pmid` with `published_year` on the catalog.
- Coverage: the response's `coverage` block carries, per relation, `extent` (its clock column and bounds), `freshness_lag_seconds`, `known_holes` and `empty_result_means`. A zero month past `extent.max` or inside a hole is absence of rows, not of talk. `deadline_partial` true means the series is cut and its shares are wrong, not small.
- Empty means, in order: the token does not fit the family's index, the clock column is wrong, the window lies outside the extent, the sibling is too thin; only then absence.

## Traps

- Alias collisions: one alias for two clocks in a join, or unnamed UNION ALL branches, resolve silently; carry the family literal per branch and qualify join sides (`d.month`, `h.month`).
- Time columns differ per family: `bucket_date` on the historical Twitter archive is the storage day; the catalog's `extent` column is `observed_on`, the fold day, and says nothing about paper years; `observed_on` anywhere dates the observation, never the post.
- Duplicates across observations: `twitter.tweets` rows are revisions and `count()` counts them; `mailing_lists.messages` versions a `message_key` by `observed_on` and a cross-post is one row per list; `reddit.comments` holds readings of a comment. Count the key with `uniqExact` on both sides, or fold with `LIMIT 1 BY <key>`.
- A token meaning two things: "agentic" is a psychology term before it is a software term, so the catalog's earlier years carry the other sense; confirm with `hasAllTokens` or a phrase and name the sense counted.
- Extent short of the window: `stackexchange.posts` ends per site in 2024 (declared in `known_holes`) and returns zero for a 2025 window; drop the family rather than report a zero share. The Reddit sibling's trailing month is thin because rows join daily; the catalog's trailing year is partial.
- Denominator composition shifts: `forums.posts` volume jumps when a site's history enters the relation, so a relation-wide share falls while the term's count rises; scope by `site_key`.

## Families

- `hackernews.items`: key `hn_id`; time `original_timestamp`; text `search_text_lc`; `count()`.
- `reddit.comments_popular`: key `id`; time `created_utc`; text `search_text_lc`; the score-threshold subset; `uniqExact(id)`.
- `reddit.comments`: key `id` (scope `subreddit, created_utc`); time `created_utc`; text `search_text_lc`; `uniqExact(id)`.
- `twitter.tweets`: key `tweet_id`, `version`; time `bucket_date`, `original_timestamp`; text `search_text_lc`; one day per statement; `uniqExact(tweet_id)`. The historical Twitter archive.
- `x_open.tweets`: key `tweet_id`; time `bucket_date`, `original_timestamp`; text `search_text_lc`; `slice` scopes; `uniqExact(tweet_id)`.
- `forums.posts`: key `post_key`; time `original_timestamp`; text `lower(payload)`; `site_key` scopes; `kind = 'post'` for post rates.
- `stackexchange.posts`: key `site`, `id`; time `original_timestamp`; text `search_text_lc`; extent ends in 2024.
- `academic.catalog`: key `paper_key` (`arxiv_id`, `pmid`, `doi`); time `published_year`, `published_at`; text `title` (case-sensitive, `hasAnyTokens`); year grain.
- `mailing_lists.messages`: key `message_key`; time `original_timestamp` (nullable); text `lower(payload)`; `list_key` scopes; `uniqExact(message_key)`.
