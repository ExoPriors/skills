# OpenAlex Helper Functions Reference

Complete parameter and return-type documentation for every `scry.openalex_*` function. All functions are `SECURITY DEFINER`, `STABLE`, and clamp limits to `[1, 5000]`.

---

## scry.openalex_find_authors

Fuzzy author lookup by name or exact lookup by author ID. Uses trigram similarity for queries >= 3 characters, prefix matching for shorter queries, and direct ID lookup for inputs matching `^A[0-9]+$`.

### Signature

```sql
scry.openalex_find_authors(
    p_query   text,          -- search string (name or author ID)
    p_limit_n int DEFAULT 50 -- max rows returned
)
```

### Returns

| Column           | Type    | Description |
|------------------|---------|-------------|
| `author_id`      | text    | OpenAlex author ID (e.g., `A5000005023`) |
| `display_name`   | text    | Author's display name |
| `orcid`          | text    | ORCID identifier (nullable) |
| `name_score`     | real    | Match quality: 1.0 = exact match, 0.92-0.93 = prefix match, trigram similarity otherwise |
| `work_count`     | bigint  | Number of works in the graph |
| `total_citations` | bigint | Sum of `cited_by_count` across all works |
| `latest_year`    | int     | Most recent publication year |

### Behavior

- Empty or null query returns no rows.
- If `p_query` matches `^A[0-9]+$`, performs prefix match on `author_id`.
- For queries < 3 chars, uses `ILIKE prefix%` only.
- For queries >= 3 chars, combines prefix hits and contains hits with trigram scoring, then deduplicates.
- Results ordered by `name_score DESC`, `total_citations DESC`, `work_count DESC`.

### Example

```sql
SELECT * FROM scry.openalex_find_authors('geoffrey hinton', 10);
SELECT * FROM scry.openalex_find_authors('A5000005023', 1);
```

---

## scry.openalex_find_works

Paper search by title keyword, DOI, or work ID. Returns full payload text when available.

### Signature

```sql
scry.openalex_find_works(
    p_query     text,              -- search string (title, DOI, or work ID)
    p_year_from int DEFAULT NULL,  -- filter: publication_year >= this (NULL = no filter)
    p_limit_n   int DEFAULT 200    -- max rows returned
)
```

### Returns

| Column             | Type    | Description |
|--------------------|---------|-------------|
| `work_id`          | text    | OpenAlex work ID (e.g., `W2741809807`) |
| `entity_id`        | uuid    | ExoPriors entity ID if promoted to shared corpus (nullable) |
| `title`            | text    | `COALESCE(display_name, title)` |
| `publication_year`  | int    | Year of publication |
| `cited_by_count`   | bigint  | Citation count |
| `doi`              | text    | DOI (nullable) |
| `uri`              | text    | Best available URL: `source_uri` > entity URI > OpenAlex URL |
| `payload`          | text    | Abstract/fulltext, truncated to 50K chars (nullable) |
| `title_score`      | real    | Match quality: 1.0 = exact, 0.93-0.98 = partial match, trigram otherwise |

### Behavior

- Detects DOIs (`^10\.[0-9]{4,9}/`) and work IDs (`^W[0-9]+$`) for direct lookup.
- For title searches >= 4 chars: if prefix matches fill the limit, uses prefix-only; otherwise combines prefix + contains with trigram scoring.
- Payload sourced from `openalex_work_payloads` first, falls back to `public_entities.payload`.
- Results ordered by `title_score DESC`, `cited_by_count DESC`.

### Example

```sql
SELECT work_id, title, publication_year, cited_by_count, doi, uri
FROM scry.openalex_find_works('attention is all you need', 2017, 10);

SELECT work_id, title, uri
FROM scry.openalex_find_works('10.1038/nature14539', NULL, 5);
```

---

## scry.openalex_find_works_fast

Metadata-only variant of `openalex_find_works`. Same search logic but skips payload and `openalex_work_payloads` joins entirely. Use when you need titles, citations, and DOIs without text content.

### Signature

```sql
scry.openalex_find_works_fast(
    p_query     text,              -- search string (title, DOI, or work ID)
    p_year_from int DEFAULT NULL,  -- filter: publication_year >= this (NULL = no filter)
    p_limit_n   int DEFAULT 200    -- max rows returned
)
```

### Returns

| Column             | Type    | Description |
|--------------------|---------|-------------|
| `work_id`          | text    | OpenAlex work ID |
| `entity_id`        | uuid    | ExoPriors entity ID if promoted (nullable) |
| `title`            | text    | `COALESCE(display_name, title)` |
| `publication_year`  | int    | Year of publication |
| `cited_by_count`   | bigint  | Citation count |
| `doi`              | text    | DOI (nullable) |
| `uri`              | text    | Always `https://openalex.org/{work_id}` |
| `title_score`      | real    | Match quality score |

### Behavior

Identical search logic to `openalex_find_works`. URI is always the OpenAlex canonical URL (no payload join means no `source_uri` fallback). Significantly lower latency for large result sets.

### Example

```sql
SELECT * FROM scry.openalex_find_works_fast('deep reinforcement learning', 2020, 50);
```

---

## scry.openalex_author_profile

Single-author career profile with aggregated statistics, top concepts, and top institutions. Designed for quick people triage.

### Signature

```sql
scry.openalex_author_profile(
    p_author_id text  -- OpenAlex author ID (e.g., 'A5000005023')
)
```

### Returns

Single row:

| Column              | Type    | Description |
|---------------------|---------|-------------|
| `author_id`         | text    | OpenAlex author ID |
| `display_name`      | text    | Author's display name |
| `orcid`             | text    | ORCID identifier (nullable) |
| `work_count`        | bigint  | Total works in graph |
| `total_citations`   | bigint  | Sum of cited_by_count across all works |
| `first_year`        | int     | Earliest publication year |
| `last_year`         | int     | Most recent publication year |
| `coauthor_count`    | bigint  | Distinct coauthors |
| `institution_count` | bigint  | Distinct institutions affiliated with |
| `top_concepts`      | jsonb   | Array of up to 10 objects: `{concept_id, display_name, work_count, mean_score}` |
| `top_institutions`  | jsonb   | Array of up to 10 objects: `{institution_id, display_name, country_code, work_count}` |

### Behavior

Uses lateral joins to compute all stats in a single query. Returns zero rows if the author ID is not found. `top_concepts` ordered by `work_count DESC, mean_score DESC`. `top_institutions` ordered by `work_count DESC`.

### Example

```sql
SELECT * FROM scry.openalex_author_profile('A5000005023');

-- Extract top concepts as rows
SELECT
  p.author_id, p.display_name,
  c->>'concept_id' AS concept_id,
  c->>'display_name' AS concept_name,
  (c->>'work_count')::int AS concept_works
FROM scry.openalex_author_profile('A5000005023') p,
     jsonb_array_elements(p.top_concepts) c;
```

---

## scry.openalex_author_works

List all works by a specific author, with payload text when available.

### Signature

```sql
scry.openalex_author_works(
    p_author_id text,              -- OpenAlex author ID
    p_year_from int DEFAULT NULL,  -- filter: publication_year >= this (NULL = no filter)
    p_limit_n   int DEFAULT 200    -- max rows returned
)
```

### Returns

| Column             | Type    | Description |
|--------------------|---------|-------------|
| `work_id`          | text    | OpenAlex work ID |
| `entity_id`        | uuid    | ExoPriors entity ID if promoted (nullable) |
| `title`            | text    | `COALESCE(display_name, title)` |
| `publication_year`  | int    | Year of publication |
| `cited_by_count`   | bigint  | Citation count |
| `doi`              | text    | DOI (nullable) |
| `uri`              | text    | Best available URL |
| `payload`          | text    | Abstract/fulltext, truncated to 50K chars (nullable) |

### Behavior

Joins `openalex_work_authorships` -> `openalex_works` -> `openalex_work_payloads` (optional) -> `public_entities` (optional). Ordered by `publication_year DESC`, `cited_by_count DESC`.

### Example

```sql
SELECT work_id, title, publication_year, cited_by_count
FROM scry.openalex_author_works('A5000005023', 2020, 30);
```

---

## scry.openalex_author_coauthors

Discover who an author collaborates with, ranked by frequency of shared works.

### Signature

```sql
scry.openalex_author_coauthors(
    p_author_id text,              -- OpenAlex author ID
    p_year_from int DEFAULT NULL,  -- filter: shared works from this year onward
    p_limit_n   int DEFAULT 200    -- max rows returned
)
```

### Returns

| Column                  | Type    | Description |
|-------------------------|---------|-------------|
| `coauthor_id`           | text    | Coauthor's OpenAlex author ID |
| `coauthor_display_name` | text    | Coauthor's display name |
| `shared_work_count`     | bigint  | Number of works they co-authored |
| `shared_work_citations` | bigint  | Total citations on shared works |
| `first_shared_year`     | int     | Year of earliest shared work |
| `last_shared_year`      | int     | Year of most recent shared work |

### Behavior

Finds all works by the target author (optionally filtered by year), then aggregates other authors on those works. Excludes the target author from results. Ordered by `shared_work_count DESC`, `shared_work_citations DESC`.

### Example

```sql
-- Recent collaborators of Geoffrey Hinton
SELECT * FROM scry.openalex_author_coauthors('A5000005023', 2020, 20);
```

---

## scry.openalex_author_citation_neighbors

Discover which authors are most cited by a given author's works. This is an outbound citation traversal: it follows the reference lists of the target author's papers, then aggregates the authors of the cited works.

### Signature

```sql
scry.openalex_author_citation_neighbors(
    p_author_id text,              -- OpenAlex author ID
    p_year_from int DEFAULT NULL,  -- filter: only consider citing works from this year onward
    p_limit_n   int DEFAULT 200    -- max rows returned
)
```

### Returns

| Column                  | Type    | Description |
|-------------------------|---------|-------------|
| `neighbor_author_id`    | text    | Cited author's OpenAlex ID |
| `neighbor_display_name` | text    | Cited author's display name |
| `referenced_work_count` | bigint  | Distinct works by this neighbor that were cited |
| `reference_events`      | bigint  | Total citation events (one author's paper citing another's; can exceed work count if multiple papers cite the same work) |
| `referenced_citations`  | bigint  | Total citation count of the referenced works |

### Behavior

Path: target author's works -> their references -> authorships on referenced works -> aggregate by neighbor author. Excludes the target author. Ordered by `reference_events DESC`, `referenced_work_count DESC`.

High `reference_events` relative to `referenced_work_count` means the target author repeatedly cites distinct papers by this neighbor -- a strong signal of intellectual influence.

### Example

```sql
SELECT * FROM scry.openalex_author_citation_neighbors('A5000005023', 2018, 25);
```

---

## scry.openalex_institution_authors

Find researchers who publish from a given institution.

### Signature

```sql
scry.openalex_institution_authors(
    p_institution_id text,         -- OpenAlex institution ID (e.g., 'I13416579')
    p_year_from      int DEFAULT NULL, -- filter: works from this year onward
    p_limit_n        int DEFAULT 200   -- max rows returned
)
```

### Returns

| Column           | Type    | Description |
|------------------|---------|-------------|
| `author_id`      | text    | Author's OpenAlex ID |
| `display_name`   | text    | Author's display name |
| `work_count`     | bigint  | Works at this institution (within year filter) |
| `total_citations` | bigint | Total citations on those works |
| `latest_year`    | int     | Most recent publication year |

### Behavior

Joins `openalex_work_institutions` -> `openalex_work_authorships` -> authors. Counts distinct works per author. Ordered by `work_count DESC`, `total_citations DESC`.

Note: an author appears here if any of their works list this institution -- they may have since moved.

### Example

```sql
-- Active ML researchers at MIT since 2022
SELECT * FROM scry.openalex_institution_authors('I13416579', 2022, 30);
```

---

## scry.openalex_concept_authors

Find researchers whose works are tagged with a given OpenAlex concept.

### Signature

```sql
scry.openalex_concept_authors(
    p_concept_id text,             -- OpenAlex concept ID (e.g., 'C199360897')
    p_year_from  int DEFAULT NULL, -- filter: works from this year onward
    p_limit_n    int DEFAULT 200   -- max rows returned
)
```

### Returns

| Column              | Type    | Description |
|---------------------|---------|-------------|
| `author_id`         | text    | Author's OpenAlex ID |
| `display_name`      | text    | Author's display name |
| `work_count`        | bigint  | Works tagged with this concept |
| `total_citations`   | bigint  | Total citations on those works |
| `mean_concept_score`| real    | Average concept relevance score (0-1) across their works |
| `latest_year`       | int     | Most recent publication year |

### Behavior

Joins `openalex_work_concepts` -> `openalex_work_authorships` -> authors. Concept scores are OpenAlex's relevance scores (0-1) for how strongly a work relates to the concept. Ordered by `work_count DESC`, `total_citations DESC`, `mean_concept_score DESC`.

### Example

```sql
-- Top researchers in Reinforcement Learning since 2020
SELECT * FROM scry.openalex_concept_authors('C79586636', 2020, 30);
```

---

## Raw Scry views

These views expose the underlying OpenAlex tables directly through the Scry read-only interface. Use them for queries the helper functions do not cover.

### scry.openalex_works

All OpenAlex works with optional payload and entity linkage.

| Column                     | Type         | Description |
|----------------------------|--------------|-------------|
| `work_id`                  | text         | Primary key |
| `entity_id`                | uuid         | Linked ExoPriors entity (nullable) |
| `doi`                      | text         | DOI (nullable) |
| `title`                    | text         | `COALESCE(display_name, title)` |
| `publication_year`         | int          | Year |
| `publication_date`         | date         | Full date (nullable) |
| `work_type`                | text         | Article, book-chapter, etc. |
| `cited_by_count`           | bigint       | Citation count |
| `is_oa`                    | boolean      | Open access flag |
| `oa_status`                | text         | gold, green, hybrid, bronze, closed |
| `oa_url`                   | text         | OA URL (nullable) |
| `host_venue_display_name`  | text         | Journal/venue name |
| `host_venue_issn_l`        | text         | Linking ISSN |
| `host_venue_publisher`     | text         | Publisher name |
| `updated_date`             | date         | Last OpenAlex update |
| `uri`                      | text         | Best URL |
| `payload`                  | text         | Abstract/fulltext, 50K char limit |
| `original_author`          | text         | From linked entity (nullable) |
| `original_timestamp`       | timestamptz  | From linked entity (nullable) |
| `metadata`                 | jsonb        | Extra OpenAlex metadata |
| `created_at`               | timestamptz  | Row creation time |
| `updated_at`               | timestamptz  | Row update time |

### scry.openalex_authors

| Column         | Type        | Description |
|----------------|-------------|-------------|
| `author_id`    | text        | Primary key (`^A[0-9]+$`) |
| `display_name` | text        | Author name |
| `orcid`        | text        | ORCID (nullable) |
| `metadata`     | jsonb       | Extra fields |
| `created_at`   | timestamptz | Row creation |
| `updated_at`   | timestamptz | Row update |

### scry.openalex_institutions

| Column             | Type        | Description |
|--------------------|-------------|-------------|
| `institution_id`   | text        | Primary key (`^I[0-9]+$`) |
| `display_name`     | text        | Institution name |
| `country_code`     | text        | ISO 3166-1 alpha-2 (nullable) |
| `institution_type` | text        | education, company, government, etc. |
| `ror`              | text        | ROR identifier (nullable) |
| `metadata`         | jsonb       | Extra fields |
| `created_at`       | timestamptz | Row creation |
| `updated_at`       | timestamptz | Row update |

### scry.openalex_concepts

| Column         | Type        | Description |
|----------------|-------------|-------------|
| `concept_id`   | text        | Primary key (`^C[0-9]+$`) |
| `display_name` | text        | Concept name |
| `level`        | int         | Hierarchy level (0 = broadest, 5 = most specific) |
| `metadata`     | jsonb       | Extra fields |
| `created_at`   | timestamptz | Row creation |
| `updated_at`   | timestamptz | Row update |

### scry.openalex_work_authorships

| Column                  | Type        | Description |
|-------------------------|-------------|-------------|
| `work_id`               | text        | FK to works |
| `author_id`             | text        | FK to authors |
| `author_sequence`       | smallint    | Position (1-indexed) |
| `author_position`       | text        | first, middle, last |
| `is_corresponding`      | boolean     | Corresponding author flag |
| `raw_author_name`       | text        | Name as it appeared on the paper |
| `raw_affiliation_string`| text        | Affiliation as it appeared |
| `created_at`            | timestamptz | Row creation |
| `updated_at`            | timestamptz | Row update |

### scry.openalex_work_institutions

| Column           | Type        | Description |
|------------------|-------------|-------------|
| `work_id`        | text        | FK to works |
| `institution_id` | text        | FK to institutions |
| `author_count`   | int         | Authors from this institution on this work |
| `created_at`     | timestamptz | Row creation |
| `updated_at`     | timestamptz | Row update |

### scry.openalex_work_references

| Column               | Type        | Description |
|----------------------|-------------|-------------|
| `work_id`            | text        | The citing work |
| `referenced_work_id` | text        | The cited work |
| `created_at`         | timestamptz | Row creation |

### scry.openalex_work_concepts

| Column       | Type        | Description |
|--------------|-------------|-------------|
| `work_id`    | text        | FK to works |
| `concept_id` | text        | FK to concepts |
| `score`      | real        | Relevance score (0.0-1.0) |
| `level`      | int         | Concept hierarchy level |
| `created_at` | timestamptz | Row creation |
| `updated_at` | timestamptz | Row update |

### scry.mv_openalex_papers

Materialized view of OpenAlex papers promoted into the shared corpus. Includes voyage-4-lite embeddings for semantic search.

| Column              | Type        | Description |
|---------------------|-------------|-------------|
| `entity_id`         | uuid        | ExoPriors entity ID |
| `uri`               | text        | Entity URL |
| `source`            | text        | Always `openalex` |
| `kind`              | text        | Always `paper` |
| `original_author`   | text        | Author name |
| `original_timestamp`| timestamptz | Publication timestamp |
| `title`             | text        | Paper title |
| `openalex_id`       | text        | OpenAlex work ID |
| `doi`               | text        | DOI (nullable) |
| `cited_by_count`    | int         | Citation count |
| `primary_category`  | text        | Primary category (nullable) |
| `work_type`         | text        | Work type (nullable) |
| `word_count`        | int         | Payload word count |
| `preview`           | text        | First 500 chars of payload |
| `embedding_voyage4` | halfvec     | Voyage-4-lite embedding (nullable; cosine distance via `<=>`) |
