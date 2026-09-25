---
name: scry-reddit
description: >-
  Use when a question is about Reddit: what a subreddit or its commenters said
  about a topic, which subreddits or authors carried a term, a post's comment
  tree, a term's monthly share inside a community, subreddit rules, wiki pages
  and directory facts, earlier readings of posts and comments later deleted or
  removed (reviewed access), and semantic search over comment embeddings.
  Covers reddit.posts, reddit.comments, reddit.comments_popular,
  reddit.subreddits, reddit.subreddit_rules, reddit.subreddit_wikis, both
  withdrawn relations and embeddings.reddit_comments.
---

# Reddit

Reddit as readings: submissions and comments keyed by subreddit and time, the
subreddit directory with its rules and wiki pages, earlier readings of rows
Reddit later showed withdrawn, and chunk embeddings over comments and posts.

## When to use

- What a community said about a term, quoted with a permalink, in a time window.
- How a term's share of a subreddit's posts or comments moved month by month.
- Who carries a topic in a subreddit, and where a term is discussed across subreddits.
- A post's comment tree, a comment's direct replies, the audience of a set of posts.
- A subreddit's rules, wiki pages, subscriber count and type.
- Passages near a described idea when the vocabulary is unknown (embeddings).

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Doors

| relation | one row is | key | time column | text column(s) | notes (lag per the schema index, 2026-09-25) |
| --- | --- | --- | --- | --- | --- |
| `reddit.posts` | one reading of a submission: title, selftext, score, num_comments, domain, url | `id`; access key `subreddit, created_utc, id` | `created_utc`; `state_observed_at` orders readings | `search_text_lc` = lowercased title and selftext; trigram door `lower(concat(title, ' ', selftext))` | primary, lag 63m; selftext empty on link posts |
| `reddit.comments` | one reading of a comment; `link_id` = `t3_` + post id, `parent_id` = `link_id` marks top level | `id`; access key `subreddit, created_utc, id` | `created_utc`; `state_observed_at, retrieved_on` order readings | `search_text_lc` = lowercased body; trigram door `lower(body)` | depth, lag 62m; wide: prefer `comments_popular` for cross-subreddit scans |
| `reddit.comments_popular` | one row per comment with score >= 100, same columns | `id` | `created_utc` | `search_text_lc`; `lower(body)` | depth, lag 8h; rows join daily, so the newest days read `reddit.comments WHERE score >= 100` |
| `reddit.subreddits` | one directory reading of a subreddit: title, descriptions, subscribers, type, flags, lang | `subreddit` (display-cased) | `created_utc` is the subreddit's creation; `retrieved_on` the reading | descriptions and `submit_text`, unindexed | depth, lag 1d; `argMax(col, retrieved_on)` for the last reading |
| `reddit.subreddit_rules` | one rule: short name, description, `kind` (all, link, comment), violation reason | `subreddit, priority` | `created_utc`; `retrieved_on` | `short_name`, `description`, unindexed | depth, lag 5h; `ORDER BY priority` |
| `reddit.subreddit_wikis` | one wiki page's newest revision: markdown, revision date, author, reason | `subreddit, page` | `revision_date`; `retrieved_on` | `content`, unindexed | depth, lag 1d |
| `reddit.posts_withdrawn` | an earlier reading of a post Reddit later showed deleted or removed, columns as `reddit.posts` | `id`; access key `subreddit, created_utc, id` | `created_utc` | `search_text_lc` | depth, lag 6h; reviewed access; no author, id, url or domain index, so bound subreddit and time |
| `reddit.comments_withdrawn` | the same for a comment, columns as `reddit.comments` | `id`; access key `subreddit, created_utc, id` | `created_utc` | `search_text_lc` | depth, lag 6h; reviewed access; no author or id index |
| `embeddings.reddit_comments` | one chunk vector: `kind` comment (`full_id` `t1_…`) or post (`t3_…`); no text, often no timestamp | `full_id, chunk_index` | `original_timestamp`; `observed_on` | none: hydrate the base relation | depth, lag 15d; serves ANN; `id = substring(full_id, 4)` |

Access to the withdrawn relations is reviewed and requested by writing to hi@scry.io.

## Idioms

- Scope, then search. `subreddit` and `created_utc` lead the access key: a token on `search_text_lc` with both bounds reads one partition; the same token over the whole relation can die at the deadline. Subreddits are display-cased (`'MachineLearning'`), tokens lowercased.
- Phrase: prune with `hasAllTokens(search_text_lc, ['t1', 't2'])`, confirm with `positionCaseInsensitive(search_text_lc, 't1 t2') > 0`. A token is a whole word: `autoencoder` misses `autoencoders`. Substrings and hyphenated compounds take the trigram door, `lower(body) LIKE '%needle%'`; bare `ILIKE` or `positionCaseInsensitive` alone reads the relation.
- Cheaper sibling: `reddit.comments_popular` answers "where and who" across subreddits at a fraction of the read; it is the score >= 100 subset, not Reddit, and its newest days sit in `reddit.comments`.
- Readings, not entities: an id can recur. Count with `uniqExact(id)`, keep the newest reading with `ORDER BY state_observed_at DESC, retrieved_on DESC LIMIT 1 BY id` (posts: `state_observed_at`), and wrap that in a subquery before ranking by score.
- Threads: `link_id = 't3_<post id>'` with a closed `created_utc` window (post day to post day plus 30 days) reads a post's tree in one statement; a lower bound alone reads later partitions. Direct replies: `link_id` beside `parent_id = 't1_<comment id>'`; `parent_id` alone is unindexed.
- Point lookups: `id = '<exact>'` or an `IN` list of about 8 ids (keep the subreddit predicate: 0.3 s against 18.7 s without); `author = '<exact>'`; on posts `url = '<exact>'` and `domain = '<exact>'`, pairing a heavy domain with a subreddit or a window.
- Scores compare only between rows of like age: rank by score inside archive months, never across the thin tail past the newest archive month (values read minutes after posting) nor across 2023-07-11 to 2023-10-31; `dateDiff('hour', created_utc, state_observed_at)` bounds reading age.
- Citation: a post is `concat('https://www.reddit.com/r/', subreddit, '/comments/', id, '/')`; a comment is `concat('https://www.reddit.com/r/', subreddit, '/comments/', substring(link_id, 4), '/_/', id, '/')`.
- Semantic: mint `@handle` with the core skill's embed call, rank `embeddings.reddit_comments` unscoped (a `WHERE` post-filters a ~400-candidate window; put the community's diction in the text), collapse chunks with `LIMIT 1 BY full_id`, hydrate `reddit.comments` by `substring(full_id, 4)` with the subreddit predicate kept.

## Worked queries

**What r/MachineLearning commenters said about sparse autoencoders in 2024**

```sql
SELECT id, score, created_utc, left(body, 160) AS snippet
FROM reddit.comments
WHERE subreddit = 'MachineLearning'
  AND created_utc >= '2024-01-01' AND created_utc < '2025-01-01'
  AND hasAllTokens(search_text_lc, ['sparse', 'autoencoders'])
  AND positionCaseInsensitive(search_text_lc, 'sparse autoencoders') > 0
ORDER BY score DESC LIMIT 10
```

Seven comments in 0.2 s, best first; an archive year, so score ranks. (verified 2026-09-25)

**Share of r/LocalLLaMA posts mentioning quantization, by month**

```sql
SELECT toStartOfMonth(created_utc) AS month, uniqExact(id) AS posts,
       uniqExactIf(id, hasToken(search_text_lc, 'quantization')) AS quantization_posts,
       round(quantization_posts / posts, 4) AS share
FROM reddit.posts
WHERE subreddit = 'LocalLLaMA'
  AND created_utc >= '2025-01-01' AND created_utc < '2025-07-01'
GROUP BY month ORDER BY month LIMIT 6
```

Six rows, denominator beside numerator, ids not readings; compare the share, the counts fall with archive volume. (verified 2026-09-25)

**Audience of a month's DeepSeek posts: comments under them**

```sql
SELECT uniqExact(id) AS comments, uniqExact(author) AS commenters, uniqExact(link_id) AS threads
FROM reddit.comments
WHERE subreddit = 'MachineLearning'
  AND created_utc >= '2025-01-01' AND created_utc < '2025-03-01'
  AND link_id IN (
    SELECT concat('t3_', id) FROM reddit.posts
    WHERE subreddit = 'MachineLearning'
      AND created_utc >= '2025-01-01' AND created_utc < '2025-02-01'
      AND hasToken(search_text_lc, 'deepseek'))
LIMIT 1
```

One row: comments, distinct commenters, threads; the comment window runs a month past the post window so late replies count. (verified 2026-09-25)

**One post's comment tree, newest reading per comment, ranked**

```sql
SELECT id, author, score, top_level, permalink, snippet FROM (
  SELECT id, author, score, parent_id = link_id AS top_level, left(body, 120) AS snippet,
         concat('https://www.reddit.com/r/', subreddit, '/comments/', substring(link_id, 4), '/_/', id, '/') AS permalink
  FROM reddit.comments
  WHERE link_id = 't3_1ib2vtx'
    AND created_utc >= '2025-01-27' AND created_utc < '2025-02-26'
  ORDER BY state_observed_at DESC, retrieved_on DESC
  LIMIT 1 BY id)
ORDER BY score DESC LIMIT 20
```

Twenty comments in 2 s with a citable permalink each; `top_level` 1 marks replies to the post itself. (verified 2026-09-25)

**Who carries r/MachineLearning's comment volume in a quarter**

```sql
SELECT author, uniqExact(id) AS comments, uniqExact(link_id) AS threads, max(score) AS best
FROM reddit.comments
WHERE subreddit = 'MachineLearning'
  AND created_utc >= '2025-01-01' AND created_utc < '2025-04-01'
  AND author NOT IN ('[deleted]', 'AutoModerator')
GROUP BY author ORDER BY comments DESC LIMIT 10
```

Ten authors with comment, thread and best-score columns; read `threads` against `comments` to tell breadth from bulk. (verified 2026-09-25)

**Comments nearest a described experience, then their text**

```sql
SELECT full_id, kind, subreddit, original_timestamp, upvotes,
       scry_vector_topk_distance(embedding_voyage4, @reddit_skill_probe) AS distance
FROM embeddings.reddit_comments
ORDER BY distance ASC LIMIT 1 BY full_id LIMIT 20
```

Twenty ids by distance, mixed `kind`, `original_timestamp` often null; hydrate the `t1_` ids in a second call with the subreddit the rows name:

```sql
SELECT id, author, created_utc, score, left(body, 160) AS snippet
FROM reddit.comments
WHERE subreddit = 'LocalLLaMA' AND id IN ('o4jsb7e', 'p3471uy', 'jzwd8mk', 'odf8nwh', 'o6j6avh', 'l0pu681')
ORDER BY state_observed_at DESC, retrieved_on DESC LIMIT 1 BY id LIMIT 20
```

Six comments in 0.3 s with their real timestamps and scores. (verified 2026-09-25)

## Traps

- `observed_on` and `state_observed_at` are reading times, not authoring times; window on `created_utc`.
- A token over `reddit.comments` with neither subreddit nor window is the classic deadline kill; scope it or use `comments_popular`.
- `count()` counts readings; `uniqExact(id)` counts comments or posts. Repeated ids sit in the tail months and in 2017-09.
- Case: `subreddit = 'machinelearning'` is a silent zero; `hasToken` on `body` is case-sensitive, so search `search_text_lc`. A needle with a space or hyphen is a hard error in `hasToken`.
- An aggregate aliased to a base column name (`argMax(subscribers, retrieved_on) AS subscribers`) fails as not-an-aggregate in `ORDER BY`; alias distinctly.
- Deleted or removed rows read as Reddit shows them, author `[deleted]`, body `[removed]`; the earlier reading is served in the withdrawn relations only, joined by id.
- Scores in the tail and in 2023-07-11 to 2023-10-31 read near zero; `comments_popular` joins daily and its newest days are missing.
- `body` is markdown as served (quote markers, escaped `_`, entities); confirm phrases on `search_text_lc`, quote from `body`.

## Cross-family joins

- `reddit.posts.url` and `domain` meet `hackernews.items.uri` and `crawl.pages.url` / `host` as the link as posted; scheme, `www` and trailing-slash variants are distinct values.
- `author` meets `hackernews.items.original_author` by exact string through `IN (subquery)`; a handle is not a person.
- `subreddit` joins `reddit.subreddits`, `reddit.subreddit_rules` and `reddit.subreddit_wikis` display-cased.
- `embeddings.reddit_comments.full_id` joins `reddit.comments.id` or `reddit.posts.id` by `kind` through `substring(full_id, 4)`.
