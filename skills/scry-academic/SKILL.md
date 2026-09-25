---
name: scry-academic
description: >-
  Use when a question is about papers, preprints, authors, citations, or
  clinical trials: find a paper by DOI, arXiv id, PMID or title; list an
  author's works from a name or ORCID; count who cites a work and where;
  measure a field's output by year; read full text; rank papers or registry
  studies by meaning; join trials to the papers they reference. Covers the
  merged academic catalog (arXiv, PubMed, PMC, Europe PMC, INSPIRE-HEP,
  journal full text), OpenAlex works, authors and citation edges,
  ClinicalTrials.gov studies, paper assessments, and the paper and trial
  embedding lanes.
---

# Papers and citations

The merged paper catalog with full text behind it, OpenAlex works, authors and citation edges, ClinicalTrials.gov studies, and chunk embeddings over each.

## When to use

- Resolve a paper from a DOI, arXiv id, PMID, PMCID, or title words and read its full text.
- List an author's works from a name or ORCID and hydrate them.
- Trace citations: what a work references, who cites it, in which venues, by year.
- Count a field's papers per year and the share cited, open access, or retracted.
- Rank papers or registry studies semantically from an embedded passage, then hydrate.
- Join trials to the papers they reference, or filter trials by condition, phase, sponsor.

The core `scry` skill (authentication, the query door, response fields) is assumed loaded.

## Doors

| relation | what one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `academic.catalog` | one merged row per paper across arXiv, PMC, PubMed, Europe PMC, INSPIRE-HEP, HuggingFace and a DOI-keyed journal corpus | `paper_key`; `arxiv_id`, `pmid`, `pmcid` | `published_year`, `published_at`; `observed_on` = fold day | `title` (case-sensitive word index; `lower(title)` trigram) | primary, frozen, lag 14d; `has_fulltext = 1` marks text in `academic.papers` |
| `academic.papers` | one full-text revision per source paper | `paper_key` (`bucket`) | `observed_on` | `text` (case-sensitive word index; `lower(text)` trigram) | depth, frozen, lag 8m; `quality_label = 'good'` is the faithful core |
| `academic.extractions` | one extraction attempt, failures included | `paper_key` + `observed_on` (`status`) | `observed_on` | `text`; `lower(text)` word index | depth, lag 11m; prefer `academic.papers` |
| `academic.assessments` | one 16-dimension model assessment per (`rubric_version`, `model`, `paper_key`) | `paper_key`; `source_id` (arXiv id) | `assessed_at` | none | depth, frozen, lag 42d; scores 1-10 per `primary_category` |
| `openalex.works` | one row per work version | `id` (full URL); `doi_norm` (lowercase bare DOI) | `publication_date`, `publication_year` | `search_text_lc` = `lower(title)` | primary, frozen, lag 91d; count with `uniq(id)` |
| `openalex.authors` | one author profile (names, ORCID, h-index, institutions) | `id`; `orcid_norm` (uppercase bare) | `updated_date` | `search_text_lc` (names) | depth, frozen, lag 91d |
| `openalex.author_works` | one (author, work) edge | `author_id`; `work_id` filterable | `publication_year` | none | depth, static between snapshot loads |
| `openalex.cited_by` | one (cited, citing) edge | `cited_work_id` | `publication_date` of the citing work | none | depth, frozen, lag 91d; `citing_work_id` alone is unkeyed |
| `trials.studies` | one current row per ClinicalTrials.gov study | `nct_id` | `observed_on` (sync day); `start_date` is a source string | `lower(concat(brief_title, ' ', official_title, ' ', brief_summary))` word index, trigram | depth, daily, lag 20h |
| `embeddings.arxiv_papers` | one arXiv paper chunk with catalog `title`, `published_year`, `cited_by_count` | `arxiv_id` + `chunk_index` | `observed_on` | vector only | depth, lag 14h, ANN; `=`/`IN` on `arxiv_id` scopes before ranking |
| `embeddings.openalex_works` | one chunk per work | `work_id` (bare `W...`) | `observed_on` | vector only | depth, frozen, lag 7d, ANN |
| `embeddings.pubmed_papers` | one chunk per PubMed record | `pmid` + `chunk_index` | `observed_on` | vector only | depth, frozen, lag 71d, ANN |
| `embeddings.academic_paper_chunks` | one chunk of `academic.papers` text | `paper_key` + `source_text_sha256` | `observed_on` | readable vector, no ANN | depth, lag 2h; exact cosine under a `paper_key` scope only |
| `embeddings.trials` | one chunk per study | `nct_id` + `chunk_index` | `observed_on` | vector only | depth, daily, lag 20h, ANN |

## Idioms

- Find by key. Catalog: `paper_key`, `arxiv_id`, `pmid`, `pmcid = 'PMC...'`. Works: `doi_norm` (lowercase bare DOI) or `id` (full URL). Build `paper_key` as the lowercase DOI with slashes after the first as `%2f`.
- Titles: on works, `hasAllTokens(search_text_lc, ['sparse', 'autoencoders'])` then `positionCaseInsensitive(search_text_lc, 'sparse autoencoders') > 0` for the phrase; `search_text_lc` is the title alone. Catalog `title` is mixed case: `hasAnyTokens(title, ['Sparse', 'sparse'])`. Tokens are whole words.
- Full text: `hasToken(text, '<Token>')` on `academic.papers` with `quality_label = 'good'` and `LIMIT 1 BY paper_key`. Bridge to works on `doi_norm = decodeURLComponent(paper_key)` with a literal `doi_norm`.
- Authors: resolve the id on `openalex.authors` (`hasAllTokens(search_text_lc, ['yoshua', 'bengio'])` or `orcid_norm`), list `openalex.author_works WHERE author_id = '<id>'`, hydrate `openalex.works WHERE id IN (...)`.
- Citations: references are the work's own `referenced_works`; citers are `openalex.cited_by WHERE cited_work_id = '<id>'`, counted with `uniqExact(citing_work_id)`, hydrated via `openalex.works WHERE id IN (SELECT citing_work_id ...)`, never a JOIN.
- Dedup: works `LIMIT 1 BY id` or `uniq(id)`; papers `LIMIT 1 BY paper_key` or `uniqExact(paper_key)`; assessments pinned to one `rubric_version` and `model`; embedding lanes `LIMIT 1 BY <key>`; trials need none.
- Time: count by `published_year` (catalog) or `publication_year` (works); `published_at` and `publication_date` are often January 1 at year precision, `published_at` NULL for PubMed-only rows; an arXiv id's prefix is its posting month.
- Semantic: mint a handle with `POST /v1/scry/embed`; on ANN lanes `scry_vector_topk_distance(embedding_voyage4, @h) AS distance ... ORDER BY distance ASC LIMIT 1 BY <key> LIMIT n`; hydrate by catalog `arxiv_id` or `pmid`, works `id = concat('https://openalex.org/', work_id)`, trials `nct_id`. `embeddings.academic_paper_chunks`: `scry_cosine_similarity(embedding, @h) AS sim` under `WHERE paper_key = '<key>'`, `ORDER BY sim DESC`.
- Source URL: catalog `doi` under `https://doi.org/`, `arxiv_id` under `https://arxiv.org/abs/`, `pmid` under `https://pubmed.ncbi.nlm.nih.gov/`; works `id` is already a URL; trials `https://clinicaltrials.gov/study/<nct_id>`.
- Trials: `has(conditions, 'Obesity')`, `has(phases, 'PHASE3')`, `has_results = true`, `arrayJoin(interventions)`; `payload` only for `JSONExtract`.

## Worked queries

**Which works titled with sparse autoencoders are most cited since 2023?**

```sql
SELECT id, doi_norm, publication_year, cited_by_count, title
FROM openalex.works
WHERE hasAllTokens(search_text_lc, ['sparse', 'autoencoders'])
  AND positionCaseInsensitive(search_text_lc, 'sparse autoencoders') > 0
  AND publication_year >= 2023
ORDER BY cited_by_count DESC
LIMIT 1 BY id
LIMIT 10
```

One row per work with its bare DOI; the phrase test drops split titles. (verified 2026-09-25)

**How many cs.CL papers per year, and what share reached ten citations?**

```sql
SELECT published_year, count() AS papers, countIf(cited_by_count >= 10) AS cited_10plus,
       round(cited_10plus / papers, 3) AS share
FROM academic.catalog
WHERE has(categories, 'cs.CL') AND published_year BETWEEN 2018 AND 2025
GROUP BY published_year
ORDER BY published_year
LIMIT 20
```

One row per year with its denominator; the share falls toward the present as citations accrue with age. (verified 2026-09-25)

**What are an author's most cited works, one row per work?**

```sql
SELECT id, publication_year, cited_by_count, title
FROM openalex.works
WHERE id IN (SELECT work_id FROM openalex.author_works WHERE author_id = 'https://openalex.org/A5086198262')
ORDER BY cited_by_count DESC
LIMIT 1 BY id
LIMIT 10
```

The author id came from `openalex.authors` by name tokens; `LIMIT 1 BY id` folds snapshot duplicates. (verified 2026-09-25)

**Who cites a paper most often?**

```sql
SELECT tupleElement(tupleElement(a, 'author'), 'display_name') AS author, uniqExact(id) AS citing_works
FROM (
  SELECT id, arrayJoin(authorships) AS a
  FROM openalex.works
  WHERE id IN (SELECT citing_work_id FROM openalex.cited_by WHERE cited_work_id = 'https://openalex.org/W4316135772')
)
GROUP BY author
ORDER BY citing_works DESC
LIMIT 15
```

Authors by distinct citing works; project `primary_location.source.display_name` to rank venues instead. (verified 2026-09-25)

**Which arXiv papers are nearest to an embedded passage about sparse autoencoders?**

```sql
SELECT arxiv_id, title, published_year, cited_by_count,
       scry_vector_topk_distance(embedding_voyage4, @acad_sae_probe) AS distance
FROM embeddings.arxiv_papers
ORDER BY distance ASC
LIMIT 1 BY arxiv_id
LIMIT 10
```

Nearest chunk per paper with title and citedness; read titles, then re-embed in the corpus's wording. (verified 2026-09-25)

**Which papers do phase 3 obesity trials with posted results cite most?**

```sql
SELECT pmid, title, venue, published_year, cited_by_count
FROM academic.catalog
WHERE pmid IN (
  SELECT arrayJoin(referenced_pmids) FROM trials.studies
  WHERE has(conditions, 'Obesity') AND has(phases, 'PHASE3') AND has_results = true
)
ORDER BY cited_by_count DESC
LIMIT 10
```

Catalog rows keyed by the trials' PMIDs; the `IN` set keeps the read indexed. (verified 2026-09-25)

## Traps

- Time: `observed_on` dates a fold or sync, not a paper. `publication_date` on works and on `openalex.cited_by` floors missing dates at 1900-01-01, and some run past the present. Trial dates are strings, some partial (`2025-09`).
- Unscoped scans: `arrayExists` over `authorships` or `has(corresponding_author_ids, ...)` for works by author; a `citing_work_id` predicate alone; `decodeURLComponent(paper_key) = ...`; `count()` over `embeddings.academic_paper_chunks`; `OR` between `doi_norm` and `hasToken` on works.
- Near-miss columns: works `doi` is the URL form and reads the whole relation, `doi_norm` is the key; `embeddings.openalex_works.work_id` is bare while works `id` and citation edges carry the full URL; `type` and `publication_year` refine but do not prune works.
- Retractions: `is_retracted` also flags the notices; exclude `has(pub_types, 'Retraction Notice')` and titles starting `Retraction` on the catalog, `type = 'retraction'` on works. OpenAlex merges works and drops the losing id.
- Duplicates: works, edges and assessment keys can briefly appear twice; papers can carry two rows from two buckets.
- References: `referenced_works` is empty for most recent works and most arXiv-hosted ones; walk citations from the journal version or `openalex.cited_by`. An arXiv DOI and its journal DOI are two works with separate counts.
- Case and encoding: `hasToken` is case-sensitive on catalog `title` and papers `text`; `hasTokenCaseInsensitive` skips the index; `positionCaseInsensitive` is substring containment. `paper_key` percent-encodes slashes in lowercase. Trial `interventions` mix case; group on `lower()`.
- ANN: predicates beyond the key scope post-filter a bounded candidate window; empty under one is not absence. `embeddings.arxiv_papers` offsets index TeX source, not served text.
- Assessments are model-derived evidence, not facts; NULL is inapplicable, not low; absence means the drain has not reached the paper.

## Cross-family joins

- `academic.catalog.pmid` joins `trials.studies.referenced_pmids` (unnest with `arrayJoin`); `openalex.works.doi_norm = lower(academic.catalog.doi)` joins the two metadata surfaces.
- `openalex.authors.orcid_norm` is the bridge out of academia; name matches elsewhere are leads, not identities.
- Hacker News, forums, and the historical Twitter archive locate a paper by its arXiv id or DOI as a phrase in `search_text_lc` (token first, then `positionCaseInsensitive`).
