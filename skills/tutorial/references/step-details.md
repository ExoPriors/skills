# Tutorial Step Details

Detailed API calls, expected responses, error handling, and agent decision
logic for each tutorial step.

---

## Step 1: Verify API Key

### Request

```
GET /v1/scry/schema
Authorization: Bearer $EXOPRIORS_API_KEY
X-Scry-Client-Tag: tutorial
```

### Expected Response (200 OK)

```json
{
  "tables": [
    {
      "name": "entities",
      "schema": "scry",
      "type": "view",
      "estimated_rows": 229000000,
      "columns": [
        {"name": "id", "type": "uuid", "nullable": false},
        {"name": "uri", "type": "text", "nullable": true},
        {"name": "title", "type": "text", "nullable": true},
        ...
      ]
    },
    ...
  ]
}
```

### Tier Detection Logic

```
if key starts with "exopriors_public_" -> KEY_TIER = "public"
if key starts with "exopriors_" (no "public") -> KEY_TIER = "private"
```

### Error Cases

| HTTP Status | Meaning | Action |
|-------------|---------|--------|
| 401 | Invalid or expired key | Direct user to exopriors.com/scry |
| 429 | Rate limited | Wait and retry; explain rate limits |
| 503 | Scry pool unavailable | Inform user, suggest retry later |

### Smoke Test Alternative

If schema fails, try a minimal query as a backup check:

```
POST /v1/scry/query
Content-Type: text/plain
Authorization: Bearer $EXOPRIORS_API_KEY

SELECT 1 AS ok LIMIT 1
```

If this returns `{"columns":["ok"],"rows":[[1]]}`, the key works but the
schema endpoint may be temporarily unavailable.

---

## Step 2: Explore the Schema

### Parsing the Schema Response

The `tables` array contains views, materialized views, and functions.
Group them for the user:

**Core views** (always present):
- `scry.entities` -- the main entity table
- `scry.embeddings` -- chunk-level embedding vectors
- `scry.actors` -- author accounts
- `scry.people` -- cross-platform identity links
- `scry.person_aliases` -- identity merge records
- `scry.agent_judgements` -- structured agent observations
- `scry.agent_emitters` -- known emitter names

**Materialized views** (pre-computed, fast):
- `scry.mv_high_score_posts` -- high-signal posts with embeddings (best general start)
- `scry.mv_lesswrong_posts` -- LessWrong corpus
- `scry.mv_eaforum_posts` -- EA Forum corpus
- `scry.mv_hackernews_posts` -- Hacker News corpus
- `scry.mv_arxiv_papers` -- arXiv papers
- `scry.mv_twitter_threads` -- Twitter/X threads
- `scry.mv_substack_posts` -- Substack posts
- `scry.mv_blogosphere_posts` -- Independent blogs
- `scry.mv_forum_posts` -- Miscellaneous forums
- `scry.mv_high_karma_comments` -- High-quality comments with embeddings
- `scry.mv_author_stats` -- Per-author aggregate statistics

**Search functions** (BM25 lexical):
- `scry.search(query, kinds, limit_n)` -- returns rows with metadata
- `scry.search_ids(query, mode, kinds, limit_n)` -- returns IDs only (faster, max 2000)
- `scry.search_reddit_posts(query, subreddits, limit_n, window_key)`
- `scry.search_reddit_comments(query, subreddits, limit_n, window_key)`

**OpenAlex functions** (academic graph):
- `scry.openalex_find_authors(name, limit)`
- `scry.openalex_find_works(query, year, limit)`
- `scry.openalex_author_profile(author_id)`
- `scry.openalex_author_coauthors(author_id, year, limit)`

**Vector operations** (advanced):
- `contrast_axis(@pos, @neg)` -- direction vector
- `debias_vector(@axis, @topic)` -- remove overlap
- `debias_diagnostics(@axis, @topic)` -- sanity checks

### Topic Selection Guidance

If the user is unsure, suggest starting points:

- "AI alignment" -- rich corpus across LW, EA Forum, arXiv
- "climate policy" -- cross-source (news, academic, government)
- "open source maintainer burnout" -- GitHub + HN + blogs
- "prediction markets" -- Manifund, Kalshi, Polymarket data
- Whatever they are working on right now

---

## Step 3: First Lexical Search

### Keyword Extraction

From the user's natural language topic, extract 1-3 keyword phrases:

| User says | Keywords to use |
|-----------|----------------|
| "I'm interested in how LLMs handle long context" | `"long context" LLM` |
| "climate adaptation in developing countries" | `"climate adaptation" developing` |
| "Rust async runtime design" | `"async runtime" Rust` |

Prefer quoted phrases for precision. Avoid overly broad single words.

### Full Request

```
POST /v1/scry/query
Content-Type: text/plain
Authorization: Bearer $EXOPRIORS_API_KEY
X-Scry-Client-Tag: tutorial
```

Body (raw SQL):

```sql
WITH c AS (
  SELECT id FROM scry.search_ids(
    '"long context" LLM',
    mode => 'mv_lesswrong_posts',
    kinds => ARRAY['post'],
    limit_n => 50
  )
  UNION
  SELECT id FROM scry.search_ids(
    '"long context" LLM',
    mode => 'mv_eaforum_posts',
    kinds => ARRAY['post'],
    limit_n => 50
  )
  UNION
  SELECT id FROM scry.search_ids(
    '"long context" LLM',
    mode => 'mv_hackernews_posts',
    kinds => ARRAY['post'],
    limit_n => 50
  )
)
SELECT
  e.id,
  e.uri,
  e.title,
  e.original_author,
  e.source,
  e.original_timestamp,
  e.score
FROM c
JOIN scry.entities e ON e.id = c.id
WHERE e.content_risk IS DISTINCT FROM 'dangerous'
ORDER BY e.original_timestamp DESC NULLS LAST
LIMIT 10;
```

### Expected Response

```json
{
  "columns": ["id", "uri", "title", "original_author", "source", "original_timestamp", "score"],
  "rows": [
    [
      "a1b2c3d4-...",
      "https://www.lesswrong.com/posts/...",
      "Long Context Windows Change Everything",
      "AuthorName",
      "lesswrong",
      "2025-11-15T12:00:00Z",
      42
    ],
    ...
  ]
}
```

### Presentation Format

Present as a numbered list:

```
1. "Long Context Windows Change Everything" by AuthorName
   Source: LessWrong | Nov 2025 | Score: 42
   https://www.lesswrong.com/posts/...

2. ...
```

### Error: No Results

If zero rows returned:
1. Try broader keywords (remove quotes, use single terms).
2. Try different materialized views (add `mv_arxiv_papers` or `mv_twitter_threads`).
3. Ask the user to rephrase.

### Error: Timeout

Public timeouts adapt to load (60-480s). If timeout occurs:
1. Reduce `limit_n` to 20 per source.
2. Search fewer materialized views.
3. Try a simpler query (single source).

---

## Step 4: Semantic Search (Private Keys)

### 4a. Embed the Topic

#### Request

```
POST /v1/scry/embed
Content-Type: application/json
Authorization: Bearer $EXOPRIORS_API_KEY
X-Scry-Client-Tag: tutorial
```

```json
{
  "name": "tutorial_topic",
  "model": "voyage-4-lite",
  "text": "How large language models handle very long input contexts, including techniques like sparse attention, retrieval augmentation, and context compression."
}
```

The `text` field should be a rich, descriptive expansion of the user's topic
(1-3 sentences). More descriptive text produces better embeddings.

#### Expected Response

```json
{
  "name": "tutorial_topic",
  "model": "voyage-4-lite",
  "dimensions": 2048,
  "tokens_used": 35,
  "tokens_remaining": 1499965,
  "status": "stored"
}
```

#### Public Key Handle Rules

Public keys must use the pattern `p_<8hex>_<name>`:

```json
{
  "name": "p_a1b2c3d4_tutorial_topic",
  "model": "voyage-4-lite",
  "text": "..."
}
```

Generate the 8-hex prefix randomly. Public handles are write-once (cannot
be overwritten). Store as `EMBED_HANDLE=@p_a1b2c3d4_tutorial_topic`.

### 4b. Semantic Search

#### Request

```
POST /v1/scry/query
Content-Type: text/plain
Authorization: Bearer $EXOPRIORS_API_KEY
X-Scry-Client-Tag: tutorial
```

```sql
SELECT
  entity_id AS id,
  uri,
  title,
  original_author,
  source,
  original_timestamp,
  score,
  embedding_voyage4 <=> @tutorial_topic AS distance
FROM scry.mv_high_score_posts
ORDER BY distance
LIMIT 10;
```

#### Expected Response

Same column structure as lexical, plus `distance` (float, lower is closer):

```json
{
  "columns": ["id", "uri", "title", "original_author", "source", "original_timestamp", "score", "distance"],
  "rows": [
    ["uuid...", "https://...", "Title", "Author", "lesswrong", "2025-...", 85, 0.312],
    ...
  ]
}
```

#### Presentation

Present as a numbered list. Highlight the distance score and call out
results that did NOT appear in the lexical search:

```
1. [NEW] "Retrieval-Augmented Generation at Scale" by ResearcherX
   Source: arXiv | Distance: 0.28 | Score: 120
   (Not found by keyword search -- different terminology, same concept)
```

### Handling Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `handle not found` | @handle was not stored | Re-run the embed call |
| `token budget exceeded` | 1.5M token budget hit | Use existing handles |
| `cannot overwrite handle` | Public handle already exists | Generate new hex prefix |

---

## Step 5: Rerank (Private Keys)

### Building the Candidate Set

Use entity IDs from `CANDIDATES` (merged from Steps 3+4). Cap at 25 for the
tutorial (keeps cost low, response fast).

### Request

```
POST /v1/scry/rerank
Content-Type: application/json
Authorization: Bearer $EXOPRIORS_API_KEY
X-Scry-Client-Tag: tutorial
```

```json
{
  "sql": "SELECT id, payload FROM scry.entities WHERE id = ANY(ARRAY['uuid1','uuid2','uuid3']::uuid[]) AND content_risk IS DISTINCT FROM 'dangerous' LIMIT 25",
  "attributes": [
    {
      "id": "clarity",
      "prompt": "clarity of reasoning",
      "weight": 1.0
    }
  ],
  "topk": {"k": 5},
  "comparison_budget": 50,
  "model_tier": "balanced",
  "text_max_chars": 2000
}
```

### Expected Response

```json
{
  "entities": [
    {
      "id": "uuid...",
      "scores": {"clarity": 0.87},
      "rank": 1,
      "title": "...",
      "uri": "..."
    },
    ...
  ],
  "meta": {
    "comparisons_made": 48,
    "model_tier": "balanced",
    "attributes": ["clarity"],
    "credits_charged": 0.15
  }
}
```

### Attribute Options

For the tutorial, use `clarity` (universally interesting, easy to understand).
For advanced users, mention alternatives:

| Attribute ID | Prompt | Good for |
|-------------|--------|----------|
| `clarity` | clarity of reasoning | General quality filter |
| `technical_depth` | technical depth and rigor | Research papers |
| `insight` | non-obvious insight | Finding hidden gems |
| Custom | any natural language prompt | Domain-specific needs |

Multiple attributes can be combined:
```json
"attributes": [
  {"id": "clarity", "prompt": "clarity of reasoning", "weight": 1.2},
  {"id": "insight", "prompt": "non-obvious insight", "weight": 1.0}
]
```

### Cost Awareness

Rerank consumes credits. For the tutorial:
- 25 candidates x 1 attribute x 50 comparisons = minimal cost
- Mention: "This used ~50 LLM comparisons, costing roughly $0.10-0.20"

### Error: "requires an authenticated user API key"

Public keys cannot rerank. Skip to Step 6.

---

## Step 6: Create a Share

### Request

```
POST /v1/scry/shares
Content-Type: application/json
Authorization: Bearer $EXOPRIORS_API_KEY
```

```json
{
  "kind": "query",
  "title": "Tutorial: Long Context LLMs (first search)",
  "summary": "Results from a guided Scry tutorial exploring how LLMs handle long context windows.",
  "payload": {
    "tutorial_version": "v1",
    "topic": "How LLMs handle long context",
    "key_tier": "private",
    "steps_completed": ["schema", "lexical", "semantic", "rerank", "share"],
    "lexical_results": [
      {"id": "uuid1", "title": "...", "uri": "...", "source": "lesswrong", "score": 42}
    ],
    "semantic_results": [
      {"id": "uuid2", "title": "...", "uri": "...", "distance": 0.28}
    ],
    "rerank_results": [
      {"id": "uuid3", "title": "...", "uri": "...", "clarity_score": 0.87}
    ]
  }
}
```

### Expected Response

```json
{
  "slug": "tut-long-context-llms-a1b2c3",
  "kind": "query",
  "title": "Tutorial: Long Context LLMs (first search)",
  "summary": "Results from a guided Scry tutorial...",
  "created_at": "2026-02-27T15:30:00Z",
  "url": "https://exopriors.com/scry/share/tut-long-context-llms-a1b2c3"
}
```

### Payload Constraints

- Max payload: 1MB (1,000,000 bytes).
- Max title: 180 characters.
- Max summary: 800 characters.
- API keys are automatically redacted from payloads.

### Progressive Updates

After creating the share, results from later steps can be patched in:

```
PATCH /v1/scry/shares/{slug}
Content-Type: application/json
Authorization: Bearer $EXOPRIORS_API_KEY
```

```json
{
  "payload": {
    "...previous fields...",
    "judgement_id": "uuid-of-judgement"
  }
}
```

---

## Step 7: Record a Judgement

### Request

```
POST /v1/scry/judgements
Content-Type: application/json
Authorization: Bearer $EXOPRIORS_API_KEY
```

```json
{
  "emitter": "tutorial-agent",
  "judgement_kind": "topic_exploration",
  "target_external_ref": "tutorial:long-context-llms",
  "summary": "LessWrong and arXiv dominate discourse on long-context LLMs. The clearest writing comes from practitioners, not theorists.",
  "payload": {
    "topic": "How LLMs handle long context",
    "share_slug": "tut-long-context-llms-a1b2c3",
    "candidate_count": 25,
    "search_methods_used": ["lexical", "semantic", "rerank"],
    "key_tier": "private",
    "top_sources": ["lesswrong", "arxiv"],
    "observation": "Practitioner posts scored higher on clarity than academic papers."
  },
  "confidence": 0.7,
  "tags": ["tutorial", "exploration", "llm", "long-context"],
  "privacy_level": "public"
}
```

### Expected Response

```json
{
  "id": "d4e5f6a7-...",
  "emitter": "tutorial-agent",
  "judgement_kind": "topic_exploration",
  "target_external_ref": "tutorial:long-context-llms",
  "summary": "LessWrong and arXiv dominate...",
  "confidence": 0.7,
  "created_at": "2026-02-27T15:35:00Z"
}
```

### Field Constraints

| Field | Max Length | Required |
|-------|-----------|----------|
| `emitter` | 120 chars | yes |
| `judgement_kind` | 120 chars | yes |
| `summary` | 4,000 chars | no |
| `payload` | 512 KB | yes (can be `{}`) |
| `tags` | 32 tags, 64 chars each | no |
| `target_external_ref` | 400 chars | exactly one target required |
| `confidence` | 0.0 - 1.0 | no |

### Target Types

Exactly one target must be set:

| Field | When to use |
|-------|------------|
| `target_entity_id` | Judging a specific entity (UUID) |
| `target_actor_id` | Judging a specific author (UUID) |
| `target_judgement_id` | Judging another judgement (layered) |
| `target_external_ref` | External reference string (tutorial uses this) |

### Querying Judgements Later

```sql
SELECT
  j.id,
  j.emitter,
  j.judgement_kind,
  j.summary,
  j.confidence,
  j.payload,
  j.created_at
FROM scry.agent_judgements j
WHERE j.judgement_kind = 'topic_exploration'
ORDER BY j.created_at DESC
LIMIT 20;
```

---

## Agent Decision Tree

Use this to determine which steps to run:

```
Start
  |
  v
Step 1: Verify key
  |
  +--> Key invalid? -> Help user get a key -> STOP
  |
  v
Step 2: Show schema, get topic
  |
  v
Step 3: Lexical search (always)
  |
  +--> KEY_TIER = private?
  |      |
  |      +--> YES: Step 4 (embed + semantic)
  |      |         |
  |      |         v
  |      |    Step 5 (rerank)
  |      |
  |      +--> NO: Explain semantic/rerank, skip to Step 6
  |
  v
Step 6: Create share (always)
  |
  v
Step 7: Record judgement (always)
  |
  v
Wrap-up: Summarize + suggest next steps
```

---

## Adapting for Different Contexts

### CLI Agent (Claude Code, Codex, etc.)

Execute curl commands directly via shell. Write SQL to temp files to avoid
quoting issues. Parse JSON responses with `jq`:

```bash
curl -s ... | jq '.rows[:5][] | {title: .[2], author: .[3], source: .[4]}'
```

### Browser Agent (OpenClaw, etc.)

Use the `exec` tool for curl commands. For the Scry UI at
`https://exopriors.com/scry`, the agent can also use the browser tool to
demonstrate the interactive SQL editor.

### Notebook Agent (Jupyter, etc.)

Use `requests` library:

```python
import requests, os

BASE = os.getenv("EXOPRIORS_API_BASE", "https://api.exopriors.com")
KEY = os.environ["EXOPRIORS_API_KEY"]
HEADERS = {"Authorization": f"Bearer {KEY}", "X-Scry-Client-Tag": "tutorial"}

# Schema
schema = requests.get(f"{BASE}/v1/scry/schema", headers=HEADERS).json()

# Query
resp = requests.post(
    f"{BASE}/v1/scry/query",
    headers={**HEADERS, "Content-Type": "text/plain"},
    data="SELECT id, title FROM scry.entities LIMIT 5"
)
rows = resp.json()["rows"]
```

---

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Missing `Content-Type: text/plain` on query | 415 or parse error | Set header explicitly |
| No `LIMIT` clause | Error: LIMIT required | Always include LIMIT |
| Public key tries rerank | 403 Forbidden | Skip Step 5 |
| @handle not found in SQL | Query error | Verify embed step succeeded |
| Payload too large for share | 400 error | Trim results to top-N |
| Quoting in shell curl | Malformed JSON | Write SQL to temp file |
| Single quotes in SQL over JSON | Parse error | Use `''` escaping or temp file |
