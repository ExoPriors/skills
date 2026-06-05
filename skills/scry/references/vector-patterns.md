# Scry Vector Patterns

Use this reference from the `/scry` skill when the user wants conceptual,
semantic, or hybrid retrieval. Start with live context and schema:

1. `GET /v1/scry/context?skill_generation=2026060501`
2. `GET /v1/scry/schema`
3. `POST /v1/scry/embed` when you need a new concept handle
4. `POST /v1/scry/query` with raw SQL and `Content-Type: text/plain`

## Before Relying On A Semantic Result

- confirm the embedding relation exists and check `vector_indexed`;
- verify the handle exists in the current key or anonymous-session namespace;
- keep `@handles` in vector-distance expressions or schema-advertised vector
  helpers; do not use them as text, entity ids, boolean predicates, or
  replacements for source/date/kind filters;
- use lexical or structured filters for recall when the user gave concrete
  terms, sources, authors, or dates;
- return distances and caveats rather than claiming exhaustive semantic truth;
- avoid raw vector output unless the user needs vectors specifically.

## Mental Model

Scry stores Voyage-4-lite vectors in a shared 2048-dimensional space. You store
concepts as named handles, then reference them in SQL:

```sql
embedding_voyage4 <=> @concept_handle
```

Smaller cosine distance means greater similarity. Use lexical search for recall
and vectors for conceptual ordering when the user asks for themes, analogies,
near misses, or "things like this".

Composition is an iterative query technique, not an automatic classifier. For
nontrivial mixes, axes, or debiasing, inspect nearest records and distances,
compare with a lexical or structured baseline, revise the handles or weights,
and only then summarize the pattern.

## Create A Concept Handle

```bash
curl -s "https://api.scry.io/v1/scry/embed" \
  -H "Authorization: Bearer $SCRY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "mech_interp",
    "text": "mechanistic interpretability, reverse-engineering learned circuits and features in neural networks",
    "model": "voyage-4-lite"
  }'
```

Handle names are SQL identifiers: letters, numbers, and underscores, starting
with a letter or underscore. Saving the same handle name overwrites it in the
current namespace. Personal keys have durable namespaces; anonymous bootstrap
keys have session-local namespaces.

## Canonical Surfaces

| Surface | Use |
| --- | --- |
| `scry.chunk_embeddings` | Passage and document-level semantic retrieval keyed by `entity_id` and `chunk_index` |
| `scry.entity_embeddings` | One entity-level vector row per entity (`chunk_index = 0`) |
| `scry.entities_with_embeddings` | Public entity rows pre-joined to entity-level vectors |
| `scry.embedding_coverage` | Source/kind coverage and readiness checks |
| `scry.*_embeddings` | Source-native embedding owner tables when schema advertises them |

Always call `/v1/scry/schema` before choosing a relation. Read
`vector_indexed`; prefer indexed surfaces for broad semantic ordering and
pre-filter first when the surface is not ANN-backed.

Vector result budgets follow the Scry guardrails: personal keys can request up
to 200 rows with raw vectors, and the absolute API ceiling for vector-bearing
responses is 500 rows. Prefer distances and ids over raw vector output unless
you actually need the vector values.

## Semantic Search

```sql
SELECT e.uri, e.title, e.original_author, e.source::text,
       emb.embedding_voyage4 <=> @mech_interp AS distance
FROM scry.chunk_embeddings emb
JOIN scry.entities e ON e.id = emb.entity_id
WHERE emb.chunk_index = 0
  AND e.kind = 'post'
  AND e.content_risk IS DISTINCT FROM 'dangerous'
ORDER BY distance
LIMIT 30;
```

Use `chunk_index = 0` for one result per entity. Drop that filter when passage
search is more useful than entity-level retrieval.

## Hybrid Search

Use lexical search to form a bounded candidate set, then order by semantic
distance:

```sql
WITH candidates AS (
  SELECT entity_id
  FROM scry.search_federated(
    'deceptive alignment mesa optimizer',
    NULL,
    ARRAY['post', 'paper'],
    200,
    20
  )
  WHERE entity_id IS NOT NULL
)
SELECT e.uri, e.title, e.original_author,
       emb.embedding_voyage4 <=> @deceptive_alignment AS distance
FROM candidates c
JOIN scry.entities e ON e.id = c.entity_id
JOIN scry.chunk_embeddings emb
  ON emb.entity_id = c.entity_id
 AND emb.chunk_index = 0
WHERE e.content_risk IS DISTINCT FROM 'dangerous'
ORDER BY distance
LIMIT 50;
```

This is the default pattern for practical agent work: lexical recall keeps the
scan bounded, semantic ordering handles the user's concept.

## Composition Cheatsheet

| Goal | SQL expression |
| --- | --- |
| Search for one concept | `embedding_voyage4 <=> @concept` |
| Mix two concepts | `embedding_voyage4 <=> (scale_vector(@a, 0.6) + scale_vector(@b, 0.4))` |
| Remove one direction | `embedding_voyage4 <=> debias_vector(@concept, @unwanted)` |
| Build a contrast axis | `embedding_voyage4 <=> contrast_axis(@positive, @negative)` |
| Build a balanced contrast axis | `embedding_voyage4 <=> contrast_axis_balanced(@positive, @negative)` |
| Normalize a vector | `embedding_voyage4 <=> unit_vector(@concept)` |
| Compare handles | `SELECT cosine_similarity(@a, @b)` |
| Remove a direction with fallback | `embedding_voyage4 <=> debias_safe(@axis, @unwanted)` |
| Check debias overlap | `SELECT debias_removed_fraction(@axis, @topic)` |
| Diagnose debiasing | `SELECT * FROM debias_diagnostics(@axis, @topic)` |
| Compare time buckets | `AVG(embedding_voyage4::vector) FILTER (...) <=> AVG(embedding_voyage4::vector) FILTER (...)` |

## Vector Mixing

```sql
SELECT uri, title,
       embedding_voyage4 <=> (
         scale_vector(@mech_interp, 0.7) + scale_vector(@oversight, 0.3)
       ) AS distance
FROM scry.entities_with_embeddings
WHERE source IN ('lesswrong', 'eaforum', 'arxiv')
  AND content_risk IS DISTINCT FROM 'dangerous'
ORDER BY distance
LIMIT 20;
```

Cosine distance is scale-invariant. The weights change the direction of the
query vector, not its absolute size.

## Debiasing

```sql
SELECT debias_removed_fraction(@mech_interp, @hype) AS overlap;
```

If overlap is material, compare raw and debiased results before trusting the
residual:

```sql
SELECT uri, title,
       embedding_voyage4 <=> @mech_interp AS raw_distance,
       embedding_voyage4 <=> debias_vector(@mech_interp, @hype) AS debiased_distance
FROM scry.entities_with_embeddings
WHERE content_risk IS DISTINCT FROM 'dangerous'
ORDER BY debiased_distance
LIMIT 20;
```

Debiasing removes one direction. It is not a hard topic filter.

## Contrast Axes

Use matched pole descriptions:

```sql
SELECT uri, title,
       embedding_voyage4 <=> contrast_axis(@humble_tone, @authoritative_tone) AS distance
FROM scry.entities_with_embeddings
WHERE content_risk IS DISTINCT FROM 'dangerous'
ORDER BY distance
LIMIT 20;
```

Check `cosine_similarity(@positive, @negative)`. Very low similarity means the
poles do not share enough context; very high similarity means the axis may be
noise-dominated.

## Temporal Deltas

Temporal comparisons are SQL patterns over source timestamps and embedding
centroids. Build explicit time buckets, compare centroids, then inspect the
records nearest to each bucket or to the movement direction.

```sql
WITH bucketed AS (
  SELECT
    CASE
      WHEN original_timestamp >= '2022-01-01'
       AND original_timestamp < '2023-01-01' THEN '2022'
      WHEN original_timestamp >= '2025-01-01'
       AND original_timestamp < '2026-01-01' THEN '2025'
    END AS bucket,
    embedding_voyage4
  FROM scry.mv_lesswrong_posts
  WHERE original_timestamp >= '2022-01-01'
    AND original_timestamp < '2026-01-01'
    AND embedding_voyage4 IS NOT NULL
),
centroids AS (
  SELECT bucket, AVG(embedding_voyage4::vector) AS centroid
  FROM bucketed
  WHERE bucket IS NOT NULL
  GROUP BY bucket
)
SELECT recent.centroid <=> old.centroid AS centroid_distance
FROM centroids recent
JOIN centroids old ON recent.bucket = '2025' AND old.bucket = '2022'
LIMIT 1;
```

For topic-specific drift, create or reuse an `@handle`, prefilter with lexical
search or `embedding_voyage4 <=> @handle`, and only then aggregate. For
author-specific drift, filter by `original_author`, `author_person_id`, or a
source-native author/account field after checking `/v1/scry/schema`.
For passage-level or cross-source work, move from focused `scry.mv_*` helpers to
`scry.chunk_embeddings` only after checking schema and credential scope.

Temporal deltas are sensitive to uneven source coverage. Always report the row
counts per bucket and check source freshness before interpreting the distance.

## Common Mistakes

- Searching `scry.entities` directly for `embedding_voyage4`; use an embedding
  relation or `scry.entities_with_embeddings`.
- Expecting every source row to have an embedding; check `scry.embedding_coverage`
  and filter `embedding_voyage4 IS NOT NULL`.
- Running broad vector ordering before a cheap lexical/date/source probe.
- Requesting raw vector arrays; use distances and `@handle` references instead.
- Treating anonymous handles as durable; use a personal key for long-running work.
- Treating a compositional vector expression as a boolean filter, source filter,
  or entity identifier.
- Reporting a semantic result without checking embedding coverage or a lexical
  baseline when the claim matters.
- Assuming a built-in temporal-delta operator exists; use a
  `/v1/scry/schema`-confirmed helper or explicit time-bucket SQL.
