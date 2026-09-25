---
name: scry-internet-archive
description: >-
  Use when a question is about the Internet Archive's item catalog or Scry's
  frozen archive of internet documents: what archive.org holds under an
  identifier, collection, creator, mediatype or language, which items match a
  title or subject, and which documents of the
  federated archive (forum posts and comments, newsletters, mailing-list and
  Usenet messages, tweets, repository documents, market comments) say a
  phrase, who wrote them, how they trend by month, plus semantic search over
  their embedded chunks. Covers internet_archive.items, internet.documents
  and embeddings.internet_documents.
---

# Internet Archive and archived documents

The Internet Archive's item catalog, one metadata record per item and no item
files, beside a frozen federated archive of internet documents and the
embedded chunks of those documents.

## When to use

- What does archive.org hold for an identifier, a title, a creator, a subject, or a collection, and under which mediatype and language?
- How many items does a collection hold, when were they added, and which are the most downloaded?
- Which archived forum posts, newsletters, mailing-list messages or tweets contain a phrase, and who wrote them?
- Month by month, what share of one source's documents mention a term?
- Which archived documents read like a passage you can describe but cannot name?

The core `scry` skill (authentication, the query door, response fields) is assumed loaded.

## Doors

Lag is the index line on 2026-09-25; `GET /v1/scry/schema?mode=index` is the authority.

| relation | one row is | key | time column | text | notes |
| --- | --- | --- | --- | --- | --- |
| `internet_archive.items` | one observation of an item's raw catalog JSON, per `(source_key, identifier)` | `source_key` (one collection catalog each), `source_record_id` (the archive.org identifier); `payload_hash` | `observed_on` refresh day; the item's own `date`, `publicdate`, `addeddate` are strings inside `payload` | `payload`, unindexed | primary, `periodic` 27h; catalog metadata only, no item files; `source_record_id` and `payload_hash` equalities use bloom filters |
| `internet.documents` | one document of the frozen federated archive, by `source` | `id` UUID; filter `source` first; `uri` equality has its own bloom filter | `original_timestamp` authored (null for a share of rows), `observed_on` refreshed | `search_text_lc` tokens; `lower(ifNull(content_text, ''))` trigrams | depth, `frozen` 65d; `is_deleted = 0`; a source's current rows live in its own relation |
| `embeddings.internet_documents` | one Voyage-4 chunk vector of an `internet.documents` row | `target_type` (`entity`), `target_id` = `internet.documents.id`, `chunk_index` | `observed_on` | vectors only | depth, `frozen` 44d; ANN; `embedding_dim = 0` rows are chunk skeletons |

## Idioms

- Scope the catalog by `source_key` first. The value space is four collection catalogs: `internet_archive_full_catalog` (the public catalog), `internet_archive_wikiteam_catalog`, `internet_archive_usenet_catalog`, `internet_archive_computermagazines_catalog`; the three named collections are small enough to scan, group and rank freely.
- Read the catalog record with JSON functions: `JSONExtractString(payload, 'title')`, `'mediatype'`, `'date'`, `'publicdate'`, `'language'`; `JSONExtractUInt(payload, 'downloads')`, `'item_size'`; `JSONExtract(payload, 'collection', 'Array(String)')` (an array on each row); `parseDateTimeBestEffortOrNull(JSONExtractString(payload, 'publicdate'))` for a date. `creator` and `subject` are a string on some rows and an array on others: `if(JSONType(payload, 'creator') = 'Array', JSONExtract(payload, 'creator', 'Array(String)'), [JSONExtractString(payload, 'creator')])`.
- Text in the catalog has no index: `positionCaseInsensitive(payload, '<phrase>') > 0` scans in physical order and stops when a plain `LIMIT` fills, so pair it with `SELECT DISTINCT` on the columns you keep (re-observations fold) and never with `ORDER BY`, which forces the whole read. A known identifier is a bloom lookup: `WHERE source_record_id = '<identifier>' ORDER BY observed_on DESC LIMIT 1 BY source_key` gives its latest record per catalog.
- Count catalog items as `count(DISTINCT source_record_id)`: an identifier is re-observed on later refresh days and can sit under several `source_key`s.
- On documents, `source` first, then `hasToken(search_text_lc, '<lowercase token>')` or `hasAllTokens(search_text_lc, [...])` with one rare token, then `positionCaseInsensitive(search_text_lc, '<phrase>') > 0` to confirm the phrase; a substring with no clean token goes through the trigram door spelled exactly `lower(ifNull(content_text, '')) LIKE '%<needle>%'`. `original_timestamp` windows refine results, not the read.
- The same post can carry two `id`s at one `uri`: post-level counts use `LIMIT 1 BY uri`, and a hydrate by `id IN (...)` orders `observed_on DESC LIMIT 1 BY id`.
- Cite a catalog row as `https://archive.org/details/<source_record_id>`; cite a document by its `uri`, or, where `uri` is null (mailing-list rows), by `list_name` and `message_id` from `metadata`.
- Semantic: mint `@handle` with `POST /v1/scry/embed {text, name}` from an answer-shaped paragraph, rank with `scry_vector_topk_distance(embedding_voyage4, @handle) AS distance` on `embeddings.internet_documents` alone, then hydrate `internet.documents` by the distinct `target_id`s; `WHERE target_id IN (<subquery on internet.documents>)` prunes a non-ANN read of the chunk relation to those documents.

## Worked queries

**Which archive items mention "Feynman lectures" in their catalog record?**

```sql
SELECT DISTINCT source_record_id AS identifier,
       JSONExtractString(payload, 'title') AS title,
       JSONExtractString(payload, 'mediatype') AS mediatype,
       JSONExtractString(payload, 'date') AS date
FROM internet_archive.items
WHERE source_key = 'internet_archive_full_catalog'
  AND positionCaseInsensitive(payload, 'feynman lectures') > 0
LIMIT 10
```

Distinct identifiers in physical order, not ranked; the read stops when the page fills, so a rarer phrase reads more and can cut at the deadline: scope a collection catalog or raise `x-scry-max-seconds`. (verified 2026-09-25)

**Which collections hold the computer-magazine catalog's text items?**

```sql
SELECT arrayJoin(JSONExtract(payload, 'collection', 'Array(String)')) AS collection,
       count(DISTINCT source_record_id) AS items
FROM internet_archive.items
WHERE source_key = 'internet_archive_computermagazines_catalog'
  AND JSONExtractString(payload, 'mediatype') = 'texts'
GROUP BY collection
ORDER BY items DESC
LIMIT 15
```

One row per collection, items counted once each; an item lists several collections, so the column does not sum to the catalog. (verified 2026-09-25)

**Month by month in 2023, what share of LessWrong documents mention RLHF?**

```sql
SELECT toStartOfMonth(original_timestamp) AS month,
       count() AS docs,
       countIf(hasToken(search_text_lc, 'rlhf')) AS mentioning,
       round(mentioning / docs, 4) AS share
FROM internet.documents
WHERE source = 'lesswrong' AND is_deleted = 0
  AND original_timestamp >= '2023-01-01' AND original_timestamp < '2024-01-01'
GROUP BY month
ORDER BY month
LIMIT 12
```

`docs` is the denominator, posts and comments authored that month; read `share` against it. (verified 2026-09-25)

**Who wrote most about "shard theory" on LessWrong, and when did each start?**

```sql
SELECT original_author, count() AS n, min(original_timestamp) AS first_at
FROM internet.documents
WHERE source = 'lesswrong' AND is_deleted = 0
  AND hasAllTokens(search_text_lc, ['shard', 'theory'])
  AND positionCaseInsensitive(search_text_lc, 'shard theory') > 0
GROUP BY original_author
ORDER BY n DESC
LIMIT 10
```

One row per author name as written, posts and comments together; the phrase test drops rows where the two tokens sit apart. (verified 2026-09-25)

**How many embedded chunks does each "shard theory" post carry?**

```sql
SELECT target_id AS id, count() AS chunks, sum(token_count) AS tokens,
       max(observed_on) AS embedded_on
FROM embeddings.internet_documents
WHERE target_type = 'entity'
  AND target_id IN (SELECT id FROM internet.documents
                    WHERE source = 'lesswrong' AND kind = 'post' AND is_deleted = 0
                      AND hasAllTokens(search_text_lc, ['shard', 'theory'])
                      AND positionCaseInsensitive(search_text_lc, 'shard theory') > 0)
GROUP BY target_id
ORDER BY chunks DESC
LIMIT 10
```

One row per embedded post, longest first; the `IN` subquery keys the chunk read, where a `JOIN` reads the whole chunk relation. (verified 2026-09-25)

**Which archived documents read like a personal calibration write-up?**

```sql
SELECT target_id, chunk_index,
       scry_vector_topk_distance(embedding_voyage4, @my_query) AS distance
FROM embeddings.internet_documents
ORDER BY distance ASC
LIMIT 10
```

Nearest chunks first, a document can repeat; `@my_query` is minted from the paragraph you hope to find, and the distinct `target_id`s hydrate from `internet.documents` by `id IN (...)`. (verified 2026-09-25)

## Traps

- `ORDER BY observed_on DESC LIMIT 1 BY source_record_id` over the whole catalog reads it end to end; only a `source_record_id` equality or a small `source_key` affords it.
- `JSONExtractString` returns an empty string where the field is an array (`creator`, `subject` on some rows); `language` is unnormalized (`English`, `en`, `Unknown`, empty); `date` is empty on some rows.
- `snapshot_id` is an opaque catalog cursor, not a version; the version is `observed_on`.
- A `LIKE` over bare `content_text` scans the relation and a `LIKE` over `search_text_lc` is refused; the trigram door is the exact spelling above, and `hasToken` wants lowercase tokens.
- `ORDER BY observed_on DESC LIMIT 1 BY source` across several sources reads in physical order and cuts at the deadline; sample one `source` per statement with a plain `LIMIT`.
- `original_timestamp` is null on a share of rows: a time window silently drops them; `title` is null on comments and messages.
- `is_deleted = 0` excludes withdrawn rows; a removed forum comment can also survive with a `status` inside `metadata` and an empty body.
- Under ANN ranking, the engine's `ann_chunks_not_collapsed` warning asks for `LIMIT 1 BY target_type, target_id`, but with a 2048-dimension handle that form exceeds the statement byte ceiling: use the plain form and fold on hydrate. A `model_name` predicate only shrinks the window; a keyed prefilter miss is not absence.
- `positionCaseInsensitive` folds ASCII case only; catalog titles in other scripts want `positionCaseInsensitiveUTF8`.

## Cross-family joins

- `internet.documents.id = forums.posts.entity_id` and `uri = forums.posts.uri` for the forum sources (lesswrong, eaforum and the rest); `id = embeddings.internet_documents.target_id`.
- Mailing-list rows: `JSONExtractString(metadata, 'message_id') = mailing_lists.messages.message_id`; Twitter rows: `toUInt64(JSONExtractString(metadata, 'tweetId')) = twitter.tweets.tweet_id` in the historical Twitter archive.
- `crawled_url` rows carry the page URL in `uri`, the column `crawl.pages.url` keys (with its `host`).
- A catalog identifier resolves at `https://archive.org/details/<source_record_id>`; the Usenet catalog's items are mbox bundles of the newsgroups `mailing_lists.messages` serves by `list_key`, matched by name.
