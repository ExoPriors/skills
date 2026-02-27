# Research Workflow Templates

Detailed step-by-step instructions for each workflow template. These expand on
the summaries in `SKILL.md` with concrete SQL, curl commands, and decision
points.

All templates assume `EXOPRIORS_API_KEY` and `EXOPRIORS_API_BASE` are set.
All SQL is executed via `POST /v1/scry/query` with `Content-Type: text/plain`.
Always check `GET /v1/scry/schema` before writing queries.
Always filter dangerous sources: `(metadata->>'content_risk') IS DISTINCT FROM 'dangerous'`.

---

## 1. Literature Review

**Use when:** You want to survey what the corpus contains about a topic, ranked
by quality, and produce a shareable summary.

**Expected output:** A share artifact with the top 20 items and a judgement
summarizing findings. Typical runtime: 2-5 minutes.

### Step 1A: Scoping Query

Ask the user (or infer from context):
- Topic keywords and phrases
- Time range (all time, last 2 years, etc.)
- Source preference (all, or specific like lesswrong/arxiv/hackernews)
- Quality bar (high-signal only, or broad recall)

### Step 1B: Lexical Candidate Search (200+ items)

Search across multiple sources for broad recall. Union across `mode` targets.

```sql
WITH c AS (
  SELECT id FROM scry.search_ids(
    '"your topic phrase"',
    mode => 'mv_lesswrong_posts', kinds => ARRAY['post'], limit_n => 100
  )
  UNION
  SELECT id FROM scry.search_ids(
    '"your topic phrase"',
    mode => 'mv_eaforum_posts', kinds => ARRAY['post'], limit_n => 100
  )
  UNION
  SELECT id FROM scry.search_ids(
    '"your topic phrase"',
    mode => 'mv_hackernews_posts', kinds => ARRAY['post'], limit_n => 100
  )
)
SELECT e.id, e.uri, e.title, e.original_author, e.source,
       e.original_timestamp, e.score
FROM c
JOIN scry.entities e ON e.id = c.id
WHERE (e.metadata->>'content_risk') IS DISTINCT FROM 'dangerous'
ORDER BY e.original_timestamp DESC NULLS LAST
LIMIT 200;
```

Record the count of results and save the entity IDs for later steps.

### Step 1C: Embed the Core Concept

Distill the research question into a concept vector.

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/embed" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "lit_review_concept",
    "model": "voyage-4-lite",
    "text": "A 2-3 sentence description of the exact concept you are reviewing. Be specific about what makes this topic distinctive."
  }'
```

### Step 1D: Hybrid Rank (lexical candidates by semantic distance)

Take the lexical candidates from 1B and rank them by distance to the concept.

```sql
WITH c AS (
  -- repeat the UNION from 1B, or use a list of known IDs
  SELECT id FROM scry.search_ids('"your topic"',
    mode => 'mv_lesswrong_posts', kinds => ARRAY['post'], limit_n => 200)
)
SELECT e.id, e.uri, e.title, e.original_author, e.source,
       emb.embedding_voyage4 <=> @lit_review_concept AS distance
FROM c
JOIN scry.entities e ON e.id = c.id
JOIN scry.embeddings emb ON emb.entity_id = c.id AND emb.chunk_index = 0
WHERE (e.metadata->>'content_risk') IS DISTINCT FROM 'dangerous'
ORDER BY distance
LIMIT 50;
```

The top 50 by semantic distance are your rerank candidates.

### Step 1E: Rerank Top 50 by Clarity + Insight

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/rerank" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "sql": "SELECT id, payload FROM scry.entities WHERE id = ANY(ARRAY[<top 50 IDs from 1D>]::uuid[]) AND (metadata->>'\''content_risk'\'') IS DISTINCT FROM '\''dangerous'\'' LIMIT 50",
    "attributes": [
      {"id": "clarity", "weight": 1.0},
      {"id": "technical_depth", "weight": 0.8},
      {"id": "insight", "weight": 1.2}
    ],
    "topk": {"k": 20},
    "comparison_budget": 400,
    "text_max_chars": 3000
  }'
```

If you do not have a private key, skip this step and use the semantic-ranked
list from 1D as your final ordering.

### Step 1F: Create Share

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/shares" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "query",
    "title": "Literature review: <topic>",
    "summary": "Searched <N> candidates across <sources>. Top 20 ranked by clarity, depth, and insight.",
    "payload": {
      "methodology": "lexical search -> semantic rank -> LLM rerank",
      "candidate_count": 200,
      "sources_searched": ["lesswrong", "eaforum", "hackernews"],
      "concept_handle": "@lit_review_concept",
      "rerank_attributes": ["clarity", "technical_depth", "insight"],
      "top_results": [
        {"uri": "...", "title": "...", "author": "...", "score": 0.94},
        ...
      ]
    }
  }'
```

### Step 1G: Record Judgement

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/judgements" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "emitter": "research-workflow",
    "judgement_kind": "literature_review",
    "target_external_ref": "topic:<your_topic_slug>",
    "summary": "Brief summary of what the review found.",
    "payload": {
      "candidate_count": 200,
      "top_20_entity_ids": ["..."],
      "share_slug": "<slug from 1F>",
      "key_themes": ["theme1", "theme2"]
    },
    "confidence": 0.75,
    "tags": ["literature_review", "<topic>"],
    "privacy_level": "public"
  }'
```

### Decision Points

- If lexical search returns fewer than 20 results, broaden the query or add
  more `mode` targets (try `mv_arxiv_papers`, `mv_twitter_threads`).
- If no embeddings exist for candidates (join to `scry.embeddings` returns
  empty), fall back to pure lexical ordering by `score DESC`.
- If rerank is unavailable (public key), the semantic-ranked list is still
  valuable; note this limitation in the share summary.

---

## 2. Person Dossier

**Use when:** You want to understand a specific person's work, expertise, and
presence across the corpus.

**Expected output:** A share with the person's profile, best works ranked by
insight, and a judgement on their expertise areas.

### Step 2A: Find the Person Across Platforms

Start with a name or handle. Use the people graph primitives.

```sql
SELECT p.id AS person_id, p.display_name,
       a.source, a.author_name, a.author_key
FROM scry.people p
JOIN scry.person_aliases a ON a.person_id = p.id
WHERE p.display_name ILIKE '%Person Name%'
LIMIT 20;
```

If the person is not in `scry.people`, fall back to direct entity search:

```sql
SELECT DISTINCT source, original_author,
       COUNT(*) AS doc_count,
       MAX(original_timestamp) AS most_recent
FROM scry.entities
WHERE original_author ILIKE '%Person Name%'
  AND (metadata->>'content_risk') IS DISTINCT FROM 'dangerous'
GROUP BY source, original_author
ORDER BY doc_count DESC
LIMIT 20;
```

For academic authors, use OpenAlex:
```sql
SELECT * FROM scry.openalex_find_authors('person name', 10);
```

### Step 2B: Retrieve Their Content

Once you have an author key, get their posts/papers:

```sql
SELECT id, uri, title, source, kind, original_timestamp, score
FROM scry.entities
WHERE original_author = 'exact_author_name'
  AND source = 'lesswrong'
  AND (metadata->>'content_risk') IS DISTINCT FROM 'dangerous'
ORDER BY original_timestamp DESC NULLS LAST
LIMIT 100;
```

For cross-platform, union across sources found in 2A.

### Step 2C: Rerank by Insight

Take the person's top content and rerank to find their best work.

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/rerank" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "sql": "SELECT id, payload FROM scry.entities WHERE original_author = '\''exact_author'\'' AND source = '\''lesswrong'\'' AND (metadata->>'\''content_risk'\'') IS DISTINCT FROM '\''dangerous'\'' ORDER BY original_timestamp DESC NULLS LAST LIMIT 50",
    "attributes": [
      {"id": "insight", "weight": 1.5},
      {"id": "clarity", "weight": 1.0},
      {"id": "technical_depth", "weight": 1.0}
    ],
    "topk": {"k": 10},
    "comparison_budget": 200,
    "text_max_chars": 3000
  }'
```

### Step 2D: Create Share

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/shares" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "insight",
    "title": "Person dossier: <Name>",
    "summary": "Profile of <Name> across <N> platforms with <M> documents. Top works ranked by insight.",
    "payload": {
      "person_name": "...",
      "platforms": {"lesswrong": 45, "twitter": 120, "hackernews": 8},
      "total_documents": 173,
      "active_since": "2019-03",
      "most_recent": "2026-01",
      "top_works": [...],
      "expertise_areas": ["area1", "area2"]
    }
  }'
```

### Step 2E: Record Judgement

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/judgements" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "emitter": "research-workflow",
    "judgement_kind": "person_expertise_assessment",
    "target_external_ref": "person:<name_slug>",
    "summary": "Brief assessment of expertise areas and output quality.",
    "payload": {
      "platforms": ["lesswrong", "twitter"],
      "document_count": 173,
      "top_work_ids": ["..."],
      "share_slug": "...",
      "expertise_areas": ["area1", "area2"],
      "output_quality_summary": "Consistently high clarity; strongest on X topic"
    },
    "confidence": 0.7,
    "tags": ["person_dossier", "<name>"],
    "privacy_level": "public"
  }'
```

If the person has an `actor_id` in the system, use `target_actor_id` instead
of `target_external_ref`.

---

## 3. Emerging Field Scout

**Use when:** You want to track what is new in a field, compare recent vs
historical output, and identify trending themes.

**Expected output:** A share with time-windowed comparisons and a trend
judgement.

### Step 3A: Embed the Field Concept

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/embed" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "field_concept",
    "model": "voyage-4-lite",
    "text": "Description of the field you want to track."
  }'
```

### Step 3B: Time-Windowed Semantic Search

Run the same semantic query over two time windows: recent (last 6 months)
and historical (before that).

**Recent window:**
```sql
SELECT entity_id, uri, title, original_author, source,
       original_timestamp, score,
       embedding_voyage4 <=> @field_concept AS distance
FROM scry.mv_high_score_posts
WHERE original_timestamp >= NOW() - INTERVAL '6 months'
ORDER BY distance
LIMIT 200;
```

**Historical window:**
```sql
SELECT entity_id, uri, title, original_author, source,
       original_timestamp, score,
       embedding_voyage4 <=> @field_concept AS distance
FROM scry.mv_high_score_posts
WHERE original_timestamp < NOW() - INTERVAL '6 months'
  AND original_timestamp >= NOW() - INTERVAL '3 years'
ORDER BY distance
LIMIT 200;
```

### Step 3C: Compare Windows

Compute summary statistics for each window:
- Mean distance (closer = more on-topic)
- Count of items within distance threshold
- Source distribution

```sql
WITH recent AS (
  SELECT embedding_voyage4 <=> @field_concept AS distance,
         source
  FROM scry.mv_high_score_posts
  WHERE original_timestamp >= NOW() - INTERVAL '6 months'
  ORDER BY distance
  LIMIT 500
),
historical AS (
  SELECT embedding_voyage4 <=> @field_concept AS distance,
         source
  FROM scry.mv_high_score_posts
  WHERE original_timestamp < NOW() - INTERVAL '6 months'
    AND original_timestamp >= NOW() - INTERVAL '3 years'
  ORDER BY distance
  LIMIT 500
)
SELECT
  'recent' AS window,
  COUNT(*) AS total,
  AVG(distance) AS avg_distance,
  COUNT(*) FILTER (WHERE distance < 0.3) AS close_matches
FROM recent
UNION ALL
SELECT
  'historical',
  COUNT(*),
  AVG(distance),
  COUNT(*) FILTER (WHERE distance < 0.3)
FROM historical;
```

If recent has more close matches relative to total, the field is growing.

### Step 3D: Rerank Recent by Insight

Take the top 50 from the recent window and rerank.

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/rerank" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "sql": "SELECT id, payload FROM scry.entities WHERE id = ANY(ARRAY[<recent top 50 IDs>]::uuid[]) AND (metadata->>'\''content_risk'\'') IS DISTINCT FROM '\''dangerous'\'' LIMIT 50",
    "attributes": [
      {"id": "insight", "weight": 1.5},
      {"id": "technical_depth", "weight": 1.0}
    ],
    "topk": {"k": 15},
    "comparison_budget": 250
  }'
```

### Step 3E: Share + Judge

Create the share with the comparison data and the reranked recent items.
Record a trend judgement with the growth signal.

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/judgements" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "emitter": "research-workflow",
    "judgement_kind": "field_trend_assessment",
    "target_external_ref": "field:<field_slug>",
    "summary": "Brief trend assessment.",
    "payload": {
      "recent_close_matches": 45,
      "historical_close_matches": 28,
      "growth_signal": "increasing",
      "top_recent_ids": ["..."],
      "share_slug": "..."
    },
    "confidence": 0.65,
    "tags": ["field_scout", "<field>"],
    "privacy_level": "public"
  }'
```

---

## 4. Reading List Builder

**Use when:** You have seed papers/posts and want to expand them into a curated
reading list via citations and semantic neighbors.

**Expected output:** A share with 15-25 curated items ordered for reading,
plus a judgement.

### Step 4A: Start from Seeds

The user provides 3-10 seed items (URLs, titles, or entity IDs). Look them up:

```sql
SELECT id, uri, title, original_author, source, original_timestamp
FROM scry.entities
WHERE uri IN ('https://...', 'https://...')
  AND (metadata->>'content_risk') IS DISTINCT FROM 'dangerous'
LIMIT 20;
```

Or by title search:
```sql
WITH c AS (
  SELECT id FROM scry.search_ids('"exact title phrase"',
    mode => 'mv_lesswrong_posts', kinds => ARRAY['post'], limit_n => 10)
)
SELECT e.id, e.uri, e.title, e.original_author
FROM c
JOIN scry.entities e ON e.id = c.id
LIMIT 5;
```

### Step 4B: Expand via Citation Neighbors (Academic Seeds)

For academic papers, use OpenAlex citation traversal:

```sql
SELECT * FROM scry.openalex_author_citation_neighbors('A_AUTHOR_ID', 2020, 25);
```

Or find related works:
```sql
SELECT work_id, title, publication_year, cited_by_count, uri
FROM scry.openalex_find_works('topic from seed titles', 2020, 50);
```

### Step 4C: Expand via Semantic Neighbors (Non-Academic Seeds)

Embed the "essence" of the seed set:

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/embed" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "reading_list_core",
    "model": "voyage-4-lite",
    "text": "Synthesize a 2-3 sentence description of what the seed items have in common. What is the core thread?"
  }'
```

Then find semantic neighbors:
```sql
SELECT entity_id, uri, title, original_author, source,
       embedding_voyage4 <=> @reading_list_core AS distance
FROM scry.mv_high_score_posts
ORDER BY distance
LIMIT 200;
```

Exclude the seeds themselves from the expansion results.

### Step 4D: Rerank Expanded Set

Combine seeds + expansion candidates. Rerank by relevance to the core concept.

If you have more than 200 items after expansion, pre-filter by semantic distance
first (take the closest 100 from the expansion, plus all seeds).

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/rerank" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "sql": "SELECT id, payload FROM scry.entities WHERE id = ANY(ARRAY[<seed + expansion IDs>]::uuid[]) AND (metadata->>'\''content_risk'\'') IS DISTINCT FROM '\''dangerous'\'' LIMIT 100",
    "attributes": [
      {"id": "clarity", "weight": 1.2},
      {"id": "insight", "weight": 1.0}
    ],
    "topk": {"k": 25},
    "comparison_budget": 300,
    "text_max_chars": 3000
  }'
```

### Step 4E: Order for Reading

The rerank gives quality scores, but reading order matters. Suggest an order:
1. Seeds first (the user already knows these; they anchor understanding)
2. Foundational items (older, high clarity, establishes concepts)
3. Core contributions (high insight, the main value of the list)
4. Recent extensions (newest items that build on the core)

This ordering is a judgement call. State your reasoning in the share.

### Step 4F: Share as Curated List

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/shares" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "query",
    "title": "Reading list: <topic>",
    "summary": "Curated from <N> seeds, expanded to <M> candidates, ranked by clarity and insight. <K> items in suggested reading order.",
    "payload": {
      "seeds": [{"uri": "...", "title": "..."}],
      "methodology": "seed expansion via semantic neighbors + LLM rerank",
      "reading_order": [
        {"position": 1, "uri": "...", "title": "...", "author": "...", "why": "Foundational; defines key terms"},
        {"position": 2, "uri": "...", "title": "...", "author": "...", "why": "Core contribution; novel framework"},
        ...
      ],
      "expansion_stats": {
        "candidates_found": 200,
        "after_rerank": 25
      }
    }
  }'
```

### Step 4G: Record Judgement

```bash
curl -s "${EXOPRIORS_API_BASE:-https://api.exopriors.com}/v1/scry/judgements" \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "emitter": "research-workflow",
    "judgement_kind": "curated_reading_list",
    "target_external_ref": "topic:<topic_slug>",
    "summary": "25-item reading list on <topic>, seeded from <N> items.",
    "payload": {
      "seed_count": 5,
      "expansion_count": 200,
      "final_count": 25,
      "share_slug": "...",
      "top_entity_ids": ["..."]
    },
    "confidence": 0.7,
    "tags": ["reading_list", "<topic>"],
    "privacy_level": "public"
  }'
```

---

## Composing Custom Workflows

The four templates above cover common patterns, but you can compose the
six-step pipeline in any order. Some variations:

**Comparative review:** Run two literature reviews with different @handles,
then compare the top-20 lists. Which items appear in both? Which are unique?

**Author network mapping:** Start from a person dossier, find their most-cited
coauthors via OpenAlex, then run person dossiers on each. Create a share
with the network graph.

**Contrarian search:** Embed both the mainstream position and a contrarian
position. Use `contrast_axis(@mainstream, @contrarian)` to find items that
specifically argue against the mainstream. Rerank by insight to find the
strongest contrarian arguments.

**Cross-domain bridge:** Embed a concept from domain A and search in domain B's
corpus. Items with moderate semantic distance (deciles 4-7) are often the
most interesting cross-domain connections.

For all custom workflows, follow the output contract from SKILL.md:
produce a share_slug, candidate_count, top_results, judgements_written,
and next_actions.
