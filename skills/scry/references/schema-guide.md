# ClickHouse schema guide

`GET /v1/scry/schema` is the sole live authority. Call it before SQL and use
only enabled relations and helper functions it returns.

## Registered relations

| Relation | Purpose |
| --- | --- |
| `scry_hackernews.hackernews_items` | Hacker News items with source identity and timestamps |
| `scry_twitter_real.twitter_posts_current` | Deduplicated current Twitter/X observations |
| `scry_twitter_real.twitter_posts_raw` | Raw Twitter/X observation ledger |
| `scry_reddit_real.reddit_comments_raw` | Full-retention Reddit comments |
| `scry_mastodon.posts_current` | Deduplicated Mastodon posts |
| `scry_mastodon.profiles_current` | Deduplicated Mastodon profiles |
| `scry.scry_token_search` | Token-filtered Twitter/X rows |
| `scry.scry_author_timeline` | One-author Twitter/X timeline |
| `scry.scry_vector_topk` | Exact cosine top-k over the registered embedding sample |

The schema response decides enablement. Never infer a table from a source name; a relation it omits is unavailable.

## Starter

```sql
SELECT hn_id, title, original_author, original_timestamp, uri
FROM scry_hackernews.hackernews_items
WHERE title != ''
ORDER BY original_timestamp DESC
LIMIT 20
```

ClickHouse syntax applies. Prefer explicit columns, equality/range predicates,
and a small `LIMIT`. Inspect schema metadata for exact names and types before
joining or filtering a new surface.
