---
name: scry-literature-review
description: >-
  Use when a question asks for the papers on a topic and how they relate:
  what has been published on a method or a drug and condition pair, which
  works anchor the field, what an anchor built on and what built on it,
  which registry studies cite those papers, whether the full text is
  readable here, and how Hacker News received the work. Walks lexical and
  semantic recall over openalex.works, academic.catalog and the paper
  embedding lanes, citation edges in openalex.cited_by, dedup by DOI, PMID
  and arXiv id, full text in academic.papers, trials.studies links, and
  reception in hackernews.items.
---

# Literature review

Assemble the papers on a question from two recall arms, anchor them by citation, fold duplicates across catalogs, and order the reading by what built on what. The result is a cited list with its coverage stated, never a summary from memory.

## When to use

- What has been published on a topic, a method, or a drug and condition pair, ranked by citedness and by year.
- Which works anchor a field, what the anchor built on, and what built on it.
- Which registry studies cite these papers, and in which conditions.
- Which of these papers are readable in full text here, and which passage answers the question.
- Who the recurring authors are, with their profiles.
- How Hacker News received one paper or the line of work.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Method

1. Selectivity, on `openalex.works.search_text_lc`: `hasAllTokens` over the question's rarest title words, `uniq(id)` per `publication_year`. This is the denominator: a share is matched works over works of the same years, never over the relation.
2. Lexical recall, same relation and tokens, `ORDER BY cited_by_count DESC LIMIT 1 BY id`. Fork: add `positionCaseInsensitive(search_text_lc, '<phrase>') > 0` when the words co-occur in unrelated titles; recall on `academic.catalog.title` (`hasAnyTokens(title, ['Word', 'word'])`, key `paper_key`) only when the question is keyed by PMID or MeSH, since the catalog is the narrower relation for recent years.
3. Semantic recall: mint a handle from an answer-shaped paragraph, rank `embeddings.openalex_works` with `LIMIT 1 BY work_id`, hydrate in a second statement with the literal ids prefixed `https://openalex.org/`. Fork by family: `embeddings.arxiv_papers` (key `arxiv_id`, title and citedness on the row) when the arXiv literature carries the question; for a biomedical question its neighbours are off topic at distances that look close.
4. Anchor: the most cited article (not review) from step 2. Backward: `openalex.works.referenced_works` of the anchor, hydrated by `id IN (SELECT arrayJoin(referenced_works) ...)`. Forward: `openalex.cited_by WHERE cited_work_id = '<anchor id>'`, hydrated through `openalex.works WHERE id IN (SELECT citing_work_id ...)`; a trajectory is `uniqExact(citing_work_id)` per `toYear(publication_date)`.
5. Fold across catalogs on `doi_norm`, then `academic.catalog WHERE paper_key IN (...)` (the DOI lowercased, later slashes as `%2f`) for `pmid`, `pmcid`, `arxiv_id`, `sources`, `has_fulltext`, `is_retracted`. One row per `paper_key`; the catalog `doi` is the journal DOI where one exists.
6. Authors: `arrayJoin(authorships)` over the works already selected, grouped by author id with `author_id IS NOT NULL`; hydrate `openalex.authors` by `id` for `orcid_norm`, `works_count` and `tupleElement(summary_stats, 'h_index')`.
7. Full text: `academic.papers WHERE paper_key IN (...) AND quality_label = 'good' LIMIT 1 BY paper_key`. A key absent there is checked in `academic.extractions` by `paper_key`: an error row is attempted and failed, no row is not attempted. Inside one paper, rank `embeddings.academic_paper_chunks WHERE paper_key = '<key>'` with `scry_cosine_similarity(embedding, @handle)`, then `substring(text, byte_start + 1, byte_end - byte_start)` on the papers row whose `text_sha256` equals the chunk's `source_text_sha256`.
8. Registry: `trials.studies WHERE hasAny(referenced_pmids, [<pmids from step 5>])`, filtered on `conditions` when the trials must match the question, since a landmark paper is cited by trials in other conditions.
9. Reception: `hackernews.items` twice, the topic tokens with `kind = 'post' ORDER BY upvotes DESC`, and the DOI suffix as a token (`hasAnyTokens(search_text_lc, ['nejmoa2032994'])`) for the posts and comments about one paper; cite `uri`.
10. Reading order: reviews from steps 2 and 3 first, the anchor and its references next, then the citers by year, each marked readable or not from step 7.

## Worked walk

Question: what is the literature on psilocybin for depression, and how was it received?

**Lexical recall ranked by citedness**

```sql
SELECT id, doi_norm, publication_year, type, cited_by_count, title
FROM openalex.works
WHERE hasAllTokens(search_text_lc, ['psilocybin', 'depression'])
ORDER BY cited_by_count DESC
LIMIT 1 BY id
LIMIT 20
```

The 2016 open-label study and the 2021 and 2022 controlled trials at the head, reviews marked by `type`; the 2021 trial `W3156937150` is the anchor. (verified 2026-09-25)

**Semantic recall from an answer-shaped passage**

```sql
SELECT work_id, scry_vector_topk_distance(embedding_voyage4, @lr_psilo) AS distance
FROM embeddings.openalex_works
ORDER BY distance ASC
LIMIT 1 BY work_id
LIMIT 20
```

Bare work ids; hydrated through `openalex.works` they are reviews and later trials the title tokens missed, plus one supplementary-material record with its own DOI, dropped. (verified 2026-09-25)

**Backward walk: what the anchor built on**

```sql
SELECT id, doi_norm, publication_year, cited_by_count, title
FROM openalex.works
WHERE id IN (SELECT arrayJoin(referenced_works) FROM openalex.works WHERE id = 'https://openalex.org/W3156937150')
ORDER BY cited_by_count DESC
LIMIT 1 BY id
LIMIT 20
```

The anchor's own references ranked: the antidepressant comparisons it was measured against and the earlier psilocybin studies, which fixes the start of the reading order. (verified 2026-09-25)

**Forward walk: what built on the anchor**

```sql
SELECT id, doi_norm, publication_year, type, cited_by_count, title
FROM openalex.works
WHERE id IN (SELECT citing_work_id FROM openalex.cited_by WHERE cited_work_id = 'https://openalex.org/W3156937150')
ORDER BY cited_by_count DESC
LIMIT 1 BY id
LIMIT 20
```

The citers ranked: the later trials and the mechanism papers, `type` separating reviews from articles. (verified 2026-09-25)

**Fold across catalogs and find the full text**

```sql
SELECT paper_key, pmid, pmcid, arxiv_id, published_year, cited_by_count, has_fulltext, is_retracted, sources
FROM academic.catalog
WHERE paper_key IN ('10.1177/0269881116675513', '10.1177/0269881116675512', '10.1016/s2215-0366(16)30065-7', '10.1056/nejmoa2032994', '10.1056/nejmoa2206443', '10.1007/s00213-017-4771-x', '10.3389/fphar.2017.00974', '10.1038/s41598-017-13282-7', '10.1038/s41591-022-01744-z', '10.1016/j.psychres.2020.112749')
ORDER BY cited_by_count DESC
LIMIT 20
```

One catalog row per DOI with PMID and PMCID; `has_fulltext` is set on the open-access rows and not on the journal-only trials, so the reading list says which are readable here. (verified 2026-09-25)

**Reception on Hacker News**

```sql
SELECT hn_id, kind, original_author, original_timestamp, upvotes, comment_count, title, uri
FROM hackernews.items
WHERE kind = 'post' AND hasAllTokens(search_text_lc, ['psilocybin', 'depression'])
ORDER BY upvotes DESC
LIMIT 20
```

Stories ranked by score with author, date and permalink; the 2019 FDA breakthrough-therapy story leads and the trials appear through their press coverage, so the DOI-token probe of step 9 finds the direct discussion. (verified 2026-09-25)

## Reading the answer

- Citation per family: works `id` (the OpenAlex URL) and `doi_norm` as `https://doi.org/<doi>` with `publication_year`; catalog `paper_key`, `pmid` as `https://pubmed.ncbi.nlm.nih.gov/<pmid>/`, `arxiv_id` as `https://arxiv.org/abs/<id>`; trials `nct_id` as `https://clinicaltrials.gov/study/<nct_id>`; Hacker News `uri`, `original_author`, `original_timestamp`. Authors come from `authorships`, never from memory.
- Coverage: the response's `coverage` entry per relation carries `extent` (column, min, max, computed_at), `freshness_lag_seconds`, `known_holes` and `empty_result_means`. State the extent and lag of each relation used; the citation edges advance only with the OpenAlex snapshot, whose release date is in the relation's `description`.
- Denominators: matched works over works of the same years; readable papers over the folded list; citers per year as `uniqExact(citing_work_id)`, never row counts.
- An empty result is a wrong probe first: a case-sensitive token on `academic.catalog.title`, a DOI in URL form against `openalex.works.doi`, a `paper_key` with an unencoded second slash, a keyed ANN prefilter (a bounded probe, not absence), or a window past the relation's `extent.max`.

## Traps

- Author ids split one person: the same name sits under two ids, each with its own works and h-index, sometimes with two ORCIDs; fold by name after hydrating `openalex.authors`, and drop the NULL author id, which pools the unresolved authorships of many people.
- Time columns differ: `publication_year` and `publication_date` on works and edges are publisher dates; the catalog has `published_year`; `observed_on` on the catalog, papers, chunks and trials is a fold or sync day; Hacker News `original_timestamp` is authored time. A citer dated before the anchor's own year is a publisher date defect; drop those years from a trajectory.
- Duplicates: works and edges can appear twice (`LIMIT 1 BY id`, `uniq(id)`, `uniqExact(citing_work_id)`); a paper has one `academic.papers` row per source bucket (`LIMIT 1 BY paper_key`); a preprint and its journal version are two works with separate citation counts; supplementary material has its own DOI and work row.
- A token means two things: `depression` in a title is also economic and signal depression, so keep a second rare token or the phrase test; a DOI suffix token on Hacker News matches the link in a story and the pasted link in a comment alike, so read `kind`.
- ANN lanes always return k rows: distances are not comparable across relations, and the arXiv lane answers a biomedical question with unrelated papers at close distances.
- Extent: the catalog is a batch fold and the citation edges a snapshot, so the youngest papers have no citers yet and few recent works have full text; Hacker News is refreshed hourly and reaches the present.
- `referenced_works` is empty for many works, so a backward walk from a preprint is anchored on the journal version.

## Families

| relation | key | time column | text column |
| --- | --- | --- | --- |
| `openalex.works` | `id` (URL), `doi_norm` | `publication_year`, `publication_date` | `search_text_lc` (title only) |
| `openalex.cited_by` | `cited_work_id` | `publication_date` (citing work) | none |
| `openalex.authors` | `id`, `orcid_norm` | `updated_date` | `search_text_lc` (names) |
| `academic.catalog` | `paper_key`; `arxiv_id`, `pmid`, `pmcid` | `published_year`; `observed_on` (fold day) | `title` (mixed case) |
| `academic.papers` | `paper_key` | `observed_on` | `text` (case-sensitive) |
| `academic.extractions` | `paper_key` + `observed_on` | `observed_on` | `text` |
| `embeddings.openalex_works` | `work_id` (bare) | `observed_on` | vector index |
| `embeddings.arxiv_papers` | `arxiv_id` + `chunk_index` | `observed_on` | vector index; `title` on the row |
| `embeddings.academic_paper_chunks` | `paper_key` + `source_text_sha256` | `observed_on` | readable `embedding`, no ANN |
| `trials.studies` | `nct_id` | `observed_on` (sync day); `start_date` string | `lower(concat(brief_title, ' ', official_title, ' ', brief_summary))` |
| `hackernews.items` | `hn_id` | `original_timestamp` | `search_text_lc` |
