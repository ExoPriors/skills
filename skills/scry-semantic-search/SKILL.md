---
name: scry-semantic-search
description: >-
  Use when a question is about meaning rather than exact words: find the Hacker News, Reddit, forum, arXiv, OpenAlex, Wikipedia, mailing-list, open-web page or historical Twitter archive rows closest to a sentence you write; measure how much of a date window carries a vector; score rows along a contrast or debiased axis; pair two id lists by nearest vector; rerank lexical hits by a written intent. Covers the embeddings.* relations, /v1/scry/embed handles, scry_vector_topk_distance, the scry_* helpers, and the rerank, semantic_join and coverage_estimate tools.
---

# Semantic search and vector algebra

Nearest-vector ranking over the embedded chunk families, named vectors minted from text or from vector arithmetic, and the helpers that turn vectors into axes, centroids and audits. No embeddings.* row carries text: rank there, hydrate from the source relation.

## When to use

- The question names a meaning, not a phrase: "posts admitting a model invented citations" rather than the token `fabricated`.
- A lexical probe found the right rows plus noise and a written intent should order them.
- A date window must be measured: which items carry a vector, with the source relation as denominator.
- Two id lists should be paired by nearest meaning, or a concept scored along a direction built from two handles.
- Lexical still wins for a name, an exact phrase, an id, a date or a count: ranking returns a window, never a total.
- The core `scry` skill is assumed loaded and is not repeated here.

## Doors

Lag is the `schema?mode=index` line read on 2026-09-25. x_open and chunks are primary tier, the rest depth; none is reviewed-access.

| relation | one row is | key | time column | text (hydrate from) | notes |
|---|---|---|---|---|---|
| embeddings.hackernews_items | a chunk of one Hacker News item | hn_id, chunk_index | observed_on | hackernews.items by hn_id | lag 4 min; `hn_id` (=, BETWEEN) scopes before ranking |
| embeddings.forum_posts | a chunk of one forum post (LessWrong, EA Forum, ...) | post_key, ifNull(model_name, ''), chunk_index | observed_on | forums.posts by post_key | lag 21 min; chunks repeat per model_name |
| embeddings.reddit_comments | a chunk of one Reddit comment (t1_) or post (t3_) | full_id, chunk_index | original_timestamp (authored), observed_on | reddit.comments by id = substring(full_id, 4); reddit.posts for t3_ | lag 15 d; subreddit, kind, upvotes ride along |
| embeddings.arxiv_papers | a full-text chunk of one arXiv paper | arxiv_id, chunk_index | observed_on | title, published_year, cited_by_count ride along; academic.catalog by arxiv_id | lag 14 h; `arxiv_id` (=, IN) scopes before ranking |
| embeddings.openalex_works | a chunk of one OpenAlex work | work_id, chunk_index | observed_on | openalex.works by id = concat('https://openalex.org/', work_id) | lag 8 d |
| embeddings.wikipedia_articles | a chunk of one Wikipedia article | page_id, chunk_index | observed_on | wikipedia.articles by page_id | lag 132 d |
| embeddings.mailing_list_messages | a chunk of one public mailing-list message | message_key, chunk_index | observed_on | mailing_lists.messages by message_key | lag 5 min; `LIMIT 1 BY` overflows, rank plain |
| embeddings.crawl_pages | a chunk of one promoted crawl.pages row (open-web essays) | url, chunk_index | observed_on | crawl.pages by url | lag 4 min; `host =` scopes before ranking; `LIMIT 1 BY` overflows, rank plain |
| embeddings.tweets | a chunk of one historical Twitter archive post | canonical_uri, chunk_index | observed_on | twitter.tweets by tweet_id (often null): `GROUP BY tweet_id`, argMax(text, version) | lag 9 h; rows since 2026-08-24 are skeletons (embedding_dim 0) |
| embeddings.x_open | a chunk of one x_open.tweets post (a historical Twitter archive slice) | tweet_id (grain canonical_uri, chunk_index) | observed_on | x_open.tweets by tweet_id (integer literals) | no lag published; `tweet_id` (=, IN) indexed; `LIMIT 1 BY` overflows, rank plain |
| embeddings.chunks | a chunk of one row of a smaller family, readable `embedding` | source, target_key, chunk_index | observed_on | target_key is the source key | lag 7 h; the large corpora above are not rows here; `scry_cosine_similarity` and JOIN allowed |
| embeddings.coverage_cells | a chunk embedded on demand by a coverage request | source, entity_id, content_hash, chunk_index, chunker, model, dimensions, dtype, input_type | observed_on | external_id maps to the source's public relation | lag 7 h; readable `embedding`; filter request_id, or source plus model |
| embeddings.sources | a (source, family) registry row of the chunks family | source, family | last_write | none | lag 7 h; row_count covers embeddings.chunks only |

## Idioms

- Mint once, reference unquoted: `POST /v1/scry/embed` with `{"text": "...", "name": "my_query", "model": "voyage-4-nano"}` or `{"expression": "scry_contrast_axis_balanced(@pos, @neg)", "name": "my_axis"}`, then `@my_query` in SQL; `/v1/scry/vectors` lists and deletes.
- One shape: a single `scry_vector_topk_distance(embedding_voyage4, @h) AS distance` projection, one relation, no JOIN, `ORDER BY distance ASC`, `LIMIT` 1 to 100. `LIMIT 1 BY <leading key>` collapses chunks to items on hackernews_items, arxiv_papers, reddit_comments, wikipedia_articles, openalex_works and tweets; on x_open, mailing_list_messages and crawl_pages it overflowed the 131072-byte compile ceiling, so rank plain.
- Scope before ranking only where registered (`hn_id`, `host`, `arxiv_id`, `tweet_id` on their relations above). Any other WHERE post-filters a window of about 400 candidates, so an empty keyed result is not absence; count the key's chunks instead: `SELECT count() FROM embeddings.hackernews_items WHERE hn_id = 49528718`.
- Lexical first on the source relation: `hasToken` / `hasAllTokens` on `search_text_lc` plus `positionCaseInsensitive` for the phrase; add `x-scry-rerank: <intent>` and `x-scry-rerank-column: <column>` when a written intent, not time, should order the hits.
- Time: `observed_on` is the embed date, not the authoring date (reddit_comments also carries authored `original_timestamp`). Turn a date window into an id window on the source (`min(hn_id)`, `max(hn_id)`) and use it as both prefilter and denominator.
- Hydrate in a second statement with the ids from the first (`hn_id IN (...)`, `url IN (...)`, `id IN (concat('https://openalex.org/', work_id))`, `id = substring(full_id, 4)`); the citation is the source relation's permalink.
- Row-level algebra lives on embeddings.chunks: `scry_cosine_similarity(c.embedding, @h)` with a JOIN to the source and `LIMIT 1 BY c.target_key`, scoped by `source` and a `target_key LIKE` prefix.
- Audit an axis before ranking by it: `scry_axis_diagnostics(@pos, @neg)` (element 3 pole_similarity, element 6 recommendation) before `scry_contrast_axis_balanced`; `scry_debias_audit(@axis, @nuisance)` (element 4 removed_fraction, element 6 safe_norm) before `scry_debias_safe`. One helper projection per statement; mint the composition as a handle and score rows by cosine against it. An axis is a direction, never a top-k operand.
- MCP by curl (`mcp-name`): `coverage_estimate` (`selector: {source, since, until}`, `model`) reports `selected.covered` and `native_lane.searchable`; `semantic_join` pairs `left` and `right` id lists on crawl_pages (url), openalex_works (work_id) or tweets (canonical_uri) with `k`; `market_status` reports `lanes_down` and `retry_window_s`.

## Worked queries

**Which Hacker News items say "fabricated citations", newest first?**
```sql
SELECT hn_id, original_timestamp, original_author, left(payload, 160) AS snippet
FROM hackernews.items
WHERE hasAllTokens(search_text_lc, ['fabricated', 'citations'])
  AND positionCaseInsensitive(search_text_lc, 'fabricated citations') > 0
ORDER BY original_timestamp DESC
LIMIT 10
```
Ten items with author and snippet; with `x-scry-rerank` and `x-scry-rerank-column: snippet` the rows return ordered by the intent. (verified 2026-09-25)

**What share of one week's Hacker News items carries a vector?**
```sql
SELECT min(hn_id) AS lo, max(hn_id) AS hi, count() AS items
FROM hackernews.items
WHERE original_timestamp >= '2026-09-01' AND original_timestamp < '2026-09-08';

SELECT uniqExact(hn_id) AS embedded_items,
       (SELECT uniqExact(hn_id) FROM hackernews.items
        WHERE hn_id BETWEEN 49516301 AND 49604280) AS corpus_items,
       round(embedded_items / corpus_items, 3) AS embedded_share
FROM embeddings.hackernews_items
WHERE hn_id BETWEEN 49516301 AND 49604280
LIMIT 1
```
The first gives the id window; the second returns embedded count, corpus count and their ratio in one row. (verified 2026-09-25)

**Which items in that week are closest to "an author admits a model invented citations"?**
```sql
SELECT hn_id, chunk_index, token_count,
       scry_vector_topk_distance(embedding_voyage4, @my_query) AS distance
FROM embeddings.hackernews_items
WHERE hn_id BETWEEN 49516301 AND 49604280
ORDER BY distance ASC
LIMIT 1 BY hn_id
LIMIT 10
```
Ten items, one chunk each, nearest first; hydrate from hackernews.items by hn_id. (verified 2026-09-25)

**Which EA Forum posts sit closest to the query, titles in the same statement?**
```sql
SELECT c.target_key, p.title, p.original_timestamp,
       scry_cosine_similarity(c.embedding, @my_query) AS sim
FROM embeddings.chunks AS c
INNER JOIN forums.posts AS p ON p.post_key = c.target_key
WHERE c.source = 'forum_posts' AND c.target_key LIKE 'eaforum%'
ORDER BY sim DESC
LIMIT 1 BY c.target_key
LIMIT 10
```
Ten posts with title and similarity; the readable embedding column allows the JOIN. (verified 2026-09-25)

**Which subreddits carry the embedded comments authored in January 2025?**
```sql
SELECT subreddit, count() AS chunks, uniqExact(full_id) AS items
FROM embeddings.reddit_comments
WHERE original_timestamp >= '2025-01-01' AND original_timestamp < '2025-02-01'
GROUP BY subreddit
ORDER BY chunks DESC
LIMIT 20
```
Twenty subreddits with chunk and item counts for the window; a ranking with no vector in it. (verified 2026-09-25)

**Is "careful measured reply" versus "dismissive sneer" a usable axis?**
```sql
SELECT tupleElement(scry_axis_diagnostics(@pos, @neg), 3) AS pole_similarity,
       tupleElement(scry_axis_diagnostics(@pos, @neg), 6) AS recommendation
LIMIT 1
```
One row: the pole similarity and a recommendation word (`contrast_axis` here), read before minting the axis. (verified 2026-09-25)

## Traps

- A WHERE on a ranking statement post-filters the candidate window except the registered prefilters; an empty filtered result is a wrong probe before it is an absence.
- "did not answer within the deadline": the lane was busy, retry as is, a longer `x-scry-max-seconds` only waits. "marked down, retry after Ns": wait that long; `market_status` names the lane and window.
- "Compiled statement: N bytes" is the 131072-byte ceiling: helper calls expand into arithmetic and `LIMIT 1 BY` expands on wide keys; two helper projections overflowed where one passed.
- `model_name` only shrinks a result; the Voyage 4 models share one space, never filter on it.
- `embedding_voyage4` on the per-corpus relations is a ranking operand, not a readable vector; embeddings.tweets skeleton rows are refused by `semantic_join`.
- embeddings.sources counts the chunks family only; `coverage_estimate` reports a sampled native lane, not a corpus census.
- `CROSS JOIN` and `ON 1 = 1` are refused: put a denominator in a scalar subquery or a `UNION ALL`. A JOIN inside a top-k statement is refused; join only on embeddings.chunks.

## Cross-family joins

- Ids are the source keys: a ranked list hydrates against its own relation and joins there on shared columns (hn_id to hackernews.items, url to crawl.pages, arxiv_id to academic.catalog and on to academic.papers by paper_key).
- Meaning across families: `semantic_join` pairs id lists on crawl_pages, openalex_works or tweets; otherwise mint one handle, rank each family in its own statement, and merge by distance yourself (distances are comparable across the Voyage 4 models).
- embeddings.chunks joins any source in SQL because its embedding is readable: `source` plus `target_key` lines up with the source key, as forums.posts.post_key above.
