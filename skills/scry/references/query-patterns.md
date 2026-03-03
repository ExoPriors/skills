# Scry Query Patterns

Comprehensive pattern library for common and advanced queries against the ExoPriors
Scry API. All patterns assume you have already called `GET /v1/scry/schema`.

---

## 1. Lexical Search Patterns

### Basic BM25 search
```sql
WITH c AS (
  SELECT id FROM scry.search('mechanistic interpretability',
    kinds=>ARRAY['post','paper'], limit_n=>100)
)
SELECT e.uri, e.title, e.original_author, e.original_timestamp, e.source::text
FROM c JOIN scry.entities e ON e.id = c.id
WHERE e.content_risk IS DISTINCT FROM 'dangerous'
ORDER BY e.original_timestamp DESC
LIMIT 50
```

### Scoped to a specific forum
```sql
WITH c AS (
  SELECT id FROM scry.search('corrigibility',
    mode=>'mv_lesswrong_posts', kinds=>ARRAY['post'], limit_n=>100)
)
SELECT e.uri, e.title, e.score, e.original_timestamp
FROM c JOIN scry.entities e ON e.id = c.id
WHERE e.content_risk IS DISTINCT FROM 'dangerous'
ORDER BY e.score DESC NULLS LAST
LIMIT 30
```

### IDs-only for large candidate sets
```sql
-- Get up to 2000 candidate IDs (no payload detoasting)
WITH ids AS (
  SELECT id FROM scry.search_ids('transformer scaling laws',
    kinds=>ARRAY['paper'], limit_n=>2000)
)
SELECT e.id, e.uri, e.title, e.source::text
FROM ids JOIN scry.entities e ON e.id = ids.id
WHERE e.original_timestamp >= '2024-01-01'
  AND e.content_risk IS DISTINCT FROM 'dangerous'
ORDER BY e.original_timestamp DESC
LIMIT 100
```

### Exhaustive search with pagination
```sql
SELECT id, uri, title, snippet, original_timestamp
FROM scry.search_exhaustive('alignment tax',
  kinds=>ARRAY['post'], limit_n=>200, offset_n=>0)
ORDER BY original_timestamp DESC
```

---

## 2. Reddit Patterns

### Fast subreddit discovery from lexical hits
```sql
WITH hits AS (
  SELECT subreddit
  FROM scry.search_reddit_posts(
    'twink OR twinks',
    limit_n=>500,
    window_key=>'2022_2023'
  )
)
SELECT subreddit, COUNT(*) AS hits
FROM hits
GROUP BY subreddit
ORDER BY hits DESC
LIMIT 30
```

Use this before expensive full-window `GROUP BY subreddit` scans.

### Search posts in specific subreddits
```sql
SELECT id, uri, subreddit, title, original_author, original_timestamp, score
FROM scry.search_reddit_posts(
  'GPU cluster training',
  subreddits=>ARRAY['MachineLearning','LocalLLaMA','singularity'],
  limit_n=>50,
  window_key=>'recent'
)
ORDER BY score DESC NULLS LAST
```

### Search comments
```sql
SELECT id, uri, subreddit, original_author, original_timestamp
FROM scry.search_reddit_comments(
  'loss spikes during training',
  subreddits=>ARRAY['MachineLearning'],
  limit_n=>50,
  window_key=>'2022_2023'
)
ORDER BY score DESC NULLS LAST
```

### Direct Reddit view query (no BM25)
```sql
SELECT id, uri, subreddit, title, upvotes, comment_count, original_timestamp
FROM scry.mv_reddit_posts_recent
WHERE subreddit = 'MachineLearning'
  AND upvotes > 100
ORDER BY original_timestamp DESC
LIMIT 50
```

### Safe iterative loop for expensive searches
```text
1) Clarify target intent (exact keyword vs conceptual theme).
2) Run /v1/scry/estimate for candidate SQL.
3) Run a narrow probe (single window, LIMIT 20-50).
4) Confirm relevance with the user.
5) Expand windows/subreddits/limit only after confirmation.
```

---

## 3. Academic Paper Patterns

### Recent arXiv papers by category
```sql
SELECT entity_id, uri, title, original_author, original_timestamp
FROM scry.mv_arxiv_papers
WHERE original_timestamp >= '2025-01-01'
ORDER BY original_timestamp DESC
LIMIT 50
```

### arXiv papers filtered by primary category (via metadata)
```sql
SELECT id, uri, title, original_author, original_timestamp
FROM scry.entities
WHERE source = 'arxiv'
  AND metadata->>'primary_category' = 'cs.AI'
  AND original_timestamp >= '2024-06-01'
  AND content_risk IS DISTINCT FROM 'dangerous'
ORDER BY original_timestamp DESC
LIMIT 50
```

### Cross-source paper search
```sql
WITH hits AS (
  SELECT id FROM scry.search('RLHF reward hacking',
    kinds=>ARRAY['paper'], limit_n=>200)
)
SELECT e.uri, e.title, e.source::text, e.original_timestamp
FROM hits h JOIN scry.entities e ON e.id = h.id
WHERE e.content_risk IS DISTINCT FROM 'dangerous'
ORDER BY e.original_timestamp DESC
LIMIT 50
```

---

## 4. Author / People Patterns

### Author post counts by source
```sql
SELECT e.source::text, COUNT(*) AS docs, MAX(e.original_timestamp) AS latest
FROM scry.entities e
WHERE e.original_author ILIKE '%scott alexander%'
  AND e.content_risk IS DISTINCT FROM 'dangerous'
GROUP BY e.source::text
ORDER BY docs DESC
LIMIT 20
```

### Top authors on a source
```sql
SELECT a.handle, a.display_name, COUNT(*) AS post_count
FROM scry.entities e
JOIN scry.actors a ON a.id = e.author_actor_id
WHERE e.source = 'lesswrong'
  AND e.kind = 'post'
GROUP BY a.handle, a.display_name
ORDER BY post_count DESC
LIMIT 50
```

### Cross-platform identity lookup
```sql
SELECT p.display_name, pa.source::text, pa.author_name, pa.handle,
       pa.profile_url, pa.confidence
FROM scry.people p
JOIN scry.person_aliases pa ON pa.person_id = p.id
WHERE p.display_name ILIKE '%eliezer%'
ORDER BY pa.confidence DESC, pa.source
LIMIT 50
```

### All content by a person across platforms
```sql
SELECT e.title, e.uri, e.source::text, e.kind::text,
       e.original_timestamp, e.upvotes, a.handle
FROM scry.entities e
JOIN scry.actors a ON a.id = e.author_actor_id
JOIN scry.person_aliases pa ON pa.actor_id = a.id
WHERE pa.person_id = 'PERSON_UUID_HERE'
  AND e.content_risk IS DISTINCT FROM 'dangerous'
ORDER BY e.original_timestamp DESC
LIMIT 200
```

### Check if two accounts are the same person
```sql
SELECT pa1.person_id, p.display_name,
       pa1.source AS source_1, pa1.handle AS handle_1,
       pa2.source AS source_2, pa2.handle AS handle_2
FROM scry.person_aliases pa1
JOIN scry.person_aliases pa2 ON pa2.person_id = pa1.person_id
JOIN scry.people p ON p.id = pa1.person_id
WHERE pa1.source = 'twitter' AND pa1.handle ILIKE 'ESYudkowsky'
  AND pa2.source = 'lesswrong'
LIMIT 10
```

### GitHub maintainer discovery
```sql
SELECT github_login, display_name, max_repo_stars,
       unique_repo_count, repo_issue_comment_count
FROM scry.github_people
WHERE unique_repo_count >= 2
ORDER BY max_repo_stars DESC, unique_repo_count DESC
LIMIT 100
```

### Bridge GitHub identity to writing identity
```sql
WITH github_actor AS (
  SELECT actor_id FROM scry.github_people WHERE github_login = 'gwern' LIMIT 1
),
linked_person AS (
  SELECT pa.person_id FROM scry.person_aliases pa
  JOIN github_actor ga ON ga.actor_id = pa.actor_id LIMIT 1
)
SELECT pa.source::text, pa.author_name, pa.handle, pa.profile_url,
       ap.entity_count, ap.post_count
FROM linked_person lp
JOIN scry.person_aliases pa ON pa.person_id = lp.person_id
LEFT JOIN scry.mv_author_profiles ap
  ON ap.source = pa.source AND ap.author_norm = pa.author_norm
ORDER BY ap.entity_count DESC NULLS LAST
LIMIT 20
```

---

## 5. Hybrid Search (Lexical + Semantic)

### BM25 candidates, semantic rerank via embedding
```sql
WITH c AS (
  SELECT id FROM scry.search('deceptive alignment mesa-optimizer',
    kinds=>ARRAY['post'], limit_n=>200)
)
SELECT e.uri, e.title, e.original_author,
       emb.embedding_voyage4 <=> @p_deadbeef_deceptive_alignment AS distance
FROM c
JOIN scry.entities e ON e.id = c.id
JOIN scry.embeddings emb ON emb.entity_id = c.id AND emb.chunk_index = 0
WHERE e.content_risk IS DISTINCT FROM 'dangerous'
ORDER BY distance
LIMIT 50
```

### Using the built-in hybrid_search function
```sql
SELECT id, uri, title, original_author, original_timestamp, distance
FROM scry.hybrid_search(
  'reward modeling',
  @p_deadbeef_reward_modeling,
  kinds=>ARRAY['post','paper'],
  limit_n=>100,
  rerank_n=>50
)
LIMIT 30
```

---

## 6. Semantic-Only Search (via MV)

### Nearest neighbors on a materialized view
```sql
SELECT entity_id, uri, title, original_author, score,
       embedding_voyage4 <=> @p_deadbeef_topic AS distance
FROM scry.mv_lesswrong_posts
WHERE embedding_voyage4 IS NOT NULL
ORDER BY distance
LIMIT 20
```

### Cross-source semantic search
```sql
SELECT entity_id, uri, title, original_author, source,
       embedding_voyage4 <=> @p_deadbeef_topic AS distance
FROM scry.mv_posts
WHERE source IN ('lesswrong', 'eaforum', 'hackernews')
  AND embedding_voyage4 IS NOT NULL
ORDER BY distance
LIMIT 20
```

### High-signal posts only
```sql
SELECT entity_id, uri, title, original_author, source,
       embedding_voyage4 <=> @p_deadbeef_topic AS distance
FROM scry.mv_high_score_posts
WHERE embedding_voyage4 IS NOT NULL
ORDER BY distance
LIMIT 20
```

---

## 7. Thread / Conversation Patterns

### Find all replies in a thread
```sql
SELECT id, uri, original_author, original_timestamp,
       LEFT(payload, 200) AS preview
FROM scry.entities
WHERE anchor_entity_id = 'ROOT_ENTITY_UUID_HERE'
  AND content_risk IS DISTINCT FROM 'dangerous'
ORDER BY original_timestamp
LIMIT 100
```

### Find direct replies to a specific entity
```sql
SELECT id, uri, original_author, original_timestamp,
       LEFT(payload, 200) AS preview
FROM scry.entities
WHERE parent_entity_id = 'PARENT_ENTITY_UUID_HERE'
  AND content_risk IS DISTINCT FROM 'dangerous'
ORDER BY original_timestamp
LIMIT 50
```

---

## 8. Aggregation / Analytics Patterns

### Entity kind distribution for a source
```sql
SELECT kind::text, COUNT(*)
FROM scry.entities
WHERE source = 'hackernews'
GROUP BY kind::text
ORDER BY 2 DESC
LIMIT 20
```

### Posts per month for a source
```sql
SELECT date_trunc('month', original_timestamp) AS month, COUNT(*)
FROM scry.entities
WHERE source = 'lesswrong' AND kind = 'post'
  AND original_timestamp >= '2020-01-01'
  AND content_risk IS DISTINCT FROM 'dangerous'
GROUP BY month
ORDER BY month
LIMIT 100
```

### Top-scoring posts across sources (recent)
```sql
SELECT uri, title, source::text, score, original_timestamp
FROM scry.entities
WHERE kind = 'post'
  AND original_timestamp >= NOW() - INTERVAL '30 days'
  AND score IS NOT NULL
  AND content_risk IS DISTINCT FROM 'dangerous'
ORDER BY score DESC
LIMIT 50
```

### Per-author topic mapping
```sql
SELECT *
FROM scry.author_topics(
  '%eliezer%',
  ARRAY['alignment', 'rationality', 'AI risk', 'decision theory']
)
```

---

## 9. OffshoreLeaks / Graph Patterns

### Find edges for a node
```sql
SELECT e.edge_type, e.metadata
FROM scry.entity_edges e
JOIN scry.entities n ON n.id = e.from_entity_id
WHERE n.source = 'offshoreleaks'
  AND n.metadata->>'node_id' = '10002580'
LIMIT 50
```

### Search OffshoreLeaks nodes by name
```sql
SELECT node_id, node_type, name, jurisdiction, countries
FROM scry.offshoreleaks_nodes
WHERE name ILIKE '%acme%'
LIMIT 50
```

---

## 10. Prediction Market Patterns

### Active Manifold markets
```sql
SELECT entity_id, uri, title, original_timestamp
FROM scry.mv_manifold_markets
WHERE original_timestamp >= '2025-01-01'
ORDER BY original_timestamp DESC
LIMIT 50
```

### Metaculus questions
```sql
SELECT entity_id, uri, title, original_timestamp
FROM scry.mv_metaculus_questions
ORDER BY original_timestamp DESC
LIMIT 50
```

---

## 11. Podcast / Media Patterns

### Podcast episodes
```sql
SELECT id, title, uri, original_author, original_timestamp
FROM scry.sporc_episodes
ORDER BY original_timestamp DESC
LIMIT 30
```

---

## 12. OpenAlex Patterns

### Find an author
```sql
SELECT * FROM scry.openalex_find_authors('hinton', 20)
```

### Find works by title or DOI
```sql
SELECT work_id, title, publication_year, cited_by_count, uri
FROM scry.openalex_find_works('attention is all you need', 2017, 10)
```

```sql
SELECT work_id, title, uri
FROM scry.openalex_find_works('10.1038/nature14539', NULL, 5)
```

Metadata-only (no payload, lower latency):
```sql
SELECT * FROM scry.openalex_find_works_fast('deep reinforcement learning', 2020, 50)
```

### Author deep-dive workflow
```sql
SELECT * FROM scry.openalex_author_profile('A5000005023');
SELECT work_id, title, publication_year, cited_by_count
FROM scry.openalex_author_works('A5000005023', 2020, 30);
SELECT * FROM scry.openalex_author_coauthors('A5000005023', 2020, 20);
SELECT * FROM scry.openalex_author_citation_neighbors('A5000005023', 2018, 25);
```

### Institution researchers
```sql
SELECT * FROM scry.openalex_institution_authors('I13416579', 2022, 30)
```

### Concept cluster authors
```sql
SELECT * FROM scry.openalex_concept_authors('C199360897', 2020, 30)
```

### Direct SQL: works citing a paper
```sql
SELECT w.work_id, w.title, w.publication_year, w.cited_by_count
FROM scry.openalex_work_references r
JOIN scry.openalex_works w ON w.work_id = r.work_id
WHERE r.referenced_work_id = 'W2741809807'
ORDER BY w.cited_by_count DESC NULLS LAST
LIMIT 50
```

### Semantic search over promoted papers
```sql
SELECT entity_id, title, original_author, openalex_id, doi,
       embedding_voyage4 <=> @target AS distance
FROM scry.mv_openalex_papers
WHERE embedding_voyage4 IS NOT NULL
ORDER BY distance
LIMIT 50
```

---

## 13. Shares Patterns

### Create a query share
```bash
curl -s -X POST https://api.exopriors.com/v1/scry/shares \
  -H "Authorization: Bearer $EXOPRIORS_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "query",
    "title": "Top alignment posts this month",
    "summary": "Highest-scored LessWrong alignment posts in the last 30 days.",
    "payload": {
      "sql": "SELECT ...",
      "result": {"columns": [...], "rows": [...]}
    }
  }'
```

### Progressive share (stub then update)
```bash
# Step 1: Create stub
curl -s -X POST https://api.exopriors.com/v1/scry/shares \
  -H "Authorization: Bearer $EXOPRIORS_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "rerank",
    "title": "Rerank in progress...",
    "summary": "Computing; will update with results."
  }'
# Returns: {"slug": "abc123", ...}

# Step 2: Update with results
curl -s -X PATCH https://api.exopriors.com/v1/scry/shares/abc123 \
  -H "Authorization: Bearer $EXOPRIORS_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Top clarity posts (reranked)",
    "payload": {"request": {...}, "response": {...}}
  }'
```

### Create an insight share
```bash
curl -s -X POST https://api.exopriors.com/v1/scry/shares \
  -H "Authorization: Bearer $EXOPRIORS_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "insight",
    "title": "arXiv alignment papers doubled in 2024",
    "summary": "Year-over-year analysis shows 2.1x growth in alignment-tagged papers.",
    "payload": {
      "metric": "paper_count_yoy",
      "2023": 1420,
      "2024": 2983,
      "methodology": "COUNT WHERE primary_category LIKE cs.AI AND payload ILIKE alignment"
    }
  }'
```

### Create a markdown transcript share
```bash
curl -s -X POST https://api.exopriors.com/v1/scry/shares \
  -H "Authorization: Bearer $EXOPRIORS_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "markdown",
    "title": "Agent transcript: speculative decoding",
    "summary": "Conversation summary with citations.",
    "payload": {
      "markdown": "# Agent transcript\n\n## User\nHow does speculative decoding work?\n\n## Assistant\n...",
      "format": "markdown"
    }
  }'
```

---

## 14. Judgement Patterns

### Emit a classification judgement
```bash
curl -s -X POST https://api.exopriors.com/v1/scry/judgements \
  -H "Authorization: Bearer $EXOPRIORS_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "emitter": "classifier-agent-v2",
    "judgement_kind": "topic_classification",
    "target_external_ref": "arxiv:2401.12345",
    "summary": "Primarily about reward hacking in RLHF systems.",
    "payload": {
      "primary_topic": "reward_hacking",
      "secondary_topics": ["rlhf", "alignment"],
      "method": "title+abstract keyword match + embedding similarity"
    },
    "confidence": 0.91,
    "tags": ["arxiv", "reward_hacking", "rlhf"],
    "privacy_level": "public"
  }'
```

### Judgement on a judgement (meta-judgement)
```bash
curl -s -X POST https://api.exopriors.com/v1/scry/judgements \
  -H "Authorization: Bearer $EXOPRIORS_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "emitter": "reviewer-agent",
    "judgement_kind": "agreement",
    "target_judgement_id": "JUDGEMENT_UUID_HERE",
    "payload": {"agreement": true, "reason": "independently verified via citation graph"},
    "score": 0.95,
    "confidence": 0.8,
    "privacy_level": "public"
  }'
```

### Query existing judgements
```sql
SELECT j.id, j.emitter, j.judgement_kind, j.summary,
       j.confidence, j.created_at
FROM scry.agent_judgements j
WHERE j.judgement_kind = 'topic_classification'
ORDER BY j.created_at DESC
LIMIT 50
```

---

## Performance Tips

1. **Use MVs over scry.entities** for any source-specific query. MVs are
   pre-filtered and often have indexes that scry.entities does not.

2. **Avoid `payload ILIKE '%...'`** on scry.entities. This detoasts every row.
   Use `scry.search()` for text search instead.

3. **Avoid `COUNT(*)` on large tables.** Use `/v1/scry/schema` row estimates or
   `pg_class.reltuples` (authenticated keys only).

4. **Use `scry.search_ids()` over `scry.search()`** when you only need IDs
   for further filtering. It avoids detoasting payload/snippet.

5. **Filter `embedding_voyage4 IS NOT NULL`** when joining scry.embeddings.
   Not all entities have embeddings.

6. **Use `chunk_index = 0`** for document-level semantic search. Omit it only
   for chunk-level granularity.

7. **Run `/v1/scry/estimate` first** for complex queries. The EXPLAIN output
   reveals sequential scans and estimated costs before you burn quota.

8. **Cast enum columns** (`kind::text`, `source::text`) in GROUP BY and WHERE
   to avoid type mismatch errors.
