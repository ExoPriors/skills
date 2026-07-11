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
