# Academic papers and reviewer discovery

The academic estate joins scholarly metadata, the citation graph, author
profiles, full text, and full-text embeddings in one SQL surface. Its
premier journey is reviewer discovery: given a paper or topic, find **all**
strong candidate reviewers — not a handful — then screen and rank them.
Confirm every relation and column against `/v1/scry/schema` before use.

## The estate

Row counts, coverage, and freshness come from `GET /v1/scry/schema` and each
query's coverage block — read them there before stating any denominator.

| Relation | What it holds |
| --- | --- |
| `openalex.works` | Title, venue, year, DOI, authorships (author id, name, ORCID, institutions), topics, concepts, funders, OA locations, `cited_by_count`, `referenced_works` citation graph. Physical rows can outnumber unique works while background merges run — count works with `uniq(id)`, never `count()`. |
| `openalex.authors` | Names + alternatives, ORCID, `works_count`, `cited_by_count`, h-index (`summary_stats`), affiliation history, per-topic counts and shares, yearly output. |
| `academic.papers` | One deterministic full-text revision per source paper, keyed by DOI. Filter `quality_label = 'good'` for faithful text. |
| `embeddings.academic_paper_chunks` | voyage-4-nano semantic chunks over current full text; check the live schema freshness metadata. |

Join keys:

- **Metadata ↔ full text (the DOI bridge):**
  `works.doi_norm = decodeURLComponent(papers.paper_key)`.
  `doi_norm` is the lowercase bare DOI (bloom-indexed). Bridge reliability is
  directional. Full text → metadata: near-total (4999/5000 in a live sample).
  Metadata → full text: most works have no full text — the full-text corpus
  covers a minority of DOI-bearing works and skews toward older long-tail
  literature. Expect zero full-text rows for many recent papers, and treat
  zero as "not in the full-text corpus."
- **Work ↔ author:** authorship author ids equal `authors.id`
  (`https://openalex.org/A...`).
- **ORCID:** `authors.orcid_norm` is the uppercase bare id.

Flatten nested authorships with the arrayJoin *function* in a subquery —
the reliable path; the `ARRAY JOIN` clause is accepted only in one
restricted `LEFT ARRAY JOIN` form:

```sql
SELECT
  tupleElement(tupleElement(a, 'author'), 'id') AS author_id,
  tupleElement(tupleElement(a, 'author'), 'display_name') AS name,
  tupleElement(tupleElement(a, 'author'), 'orcid') AS orcid
FROM (
  SELECT arrayJoin(authorships) AS a
  FROM openalex.works
  WHERE doi_norm = '10.1016/j.cell.2021.04.048'
)
LIMIT 50
```

## Finding a paper comfortably

- **By DOI:** `WHERE doi_norm = '<lowercase-bare-doi>'` on works. `paper_key`
  is the lowercase DOI with the first slash literal and every later slash
  percent-encoded lowercase (`%2f`), for example
  `10.18653/v1%2f2024.acl-long.331`. Build it client-side from the DOI. The
  exact-key predicate `WHERE paper_key = '<paper-key>'` uses the bloom index;
  `WHERE decodeURLComponent(paper_key) = '<doi>'` forces a full scan.
- **By title:** `WHERE hasToken(search_text_lc, '<lowercase-token>')` on
  works; add `publication_year` bounds and `ORDER BY cited_by_count DESC`.
- **By content:** `hasToken(text, '<token>')` on `papers` (token-indexed;
  rare method terms work best), or semantic search over
  `embeddings.academic_paper_chunks`.
- **Abstract:** `abstract_inverted_index` is an OpenAlex word→positions
  JSON map, not prose. Read title + full text instead when you need clean
  words; decode the map only when the abstract is all you have.

## Reviewer discovery is a coverage problem

The corpus advantage is exhaustiveness. A top-k query answers "some
reviewers"; the journey demands "all strong candidates, then ranked."
Treat it like the deep-research loop: enumerate pools, measure
denominators, keep a ledger, and stop only when new lanes stop yielding.

1. **Bound the paper's territory.** Pull its works row: `primary_topic`,
   `topics`, `referenced_works`, authorships (for conflicts). Pull its
   full text or abstract for method vocabulary. If it is not in the
   corpus, build the territory from its closest indexed neighbors.
2. **Enumerate every candidate pool, with denominators.** One lane per
   pool; record each pool's size before sampling from it:
   - *Topical cohort:* authors of well-cited recent works sharing the
     paper's topics.
   - *Citation neighborhood:* authors of `referenced_works`, and authors
     of works whose `referenced_works` include the paper or its key
     references (inbound citers).
   - *Semantic neighbors:* nearest full-text chunks → `paper_key` →
     DOI bridge → works → authors. State the live embedded-coverage
     denominator (read it from the schema; the chunk row count is not a
     unique-paper count).
   - *Lexical method cohort:* rare method/term tokens over full text —
     catches work the topic taxonomy misses.
   - *Venue cohort:* frequent authors in the same journals or
     proceedings (`primary_location` source ids).
3. **Union into a candidate ledger.** One row per (author_id, lane,
   evidence work ids). An author surfaced by three independent lanes is
   a different object than one surfaced by one.
4. **Screen independence.** Drop recent coauthors (shared works within
   ~5y), same-institution candidates (`last_known_institutions` vs the
   paper's authorship institutions), and the paper's own authors.
5. **Rank with explicit axes.** Topical affinity (`topic_share`),
   authority (`summary_stats.h_index`, citations of their cohort works),
   recency (`counts_by_year` — active in the last 2–3 years), and lane
   multiplicity from the ledger. Report the axes with the shortlist.
6. **Stop on exhaustion, not on count.** Fresh lanes or term variants
   that produce no new candidates two rounds running end the search.
   Report pool sizes and coverage limits with the result — the
   denominators are the evidence that the search dominated the space.

## Worked pool queries

Topical cohort (topic → recent cited works → flattened authors):

```sql
SELECT
  tupleElement(tupleElement(a, 'author'), 'id') AS author_id,
  count(DISTINCT work_id) AS works_in_pool,
  max(cited) AS best_citations
FROM (
  SELECT id AS work_id, cited_by_count AS cited, arrayJoin(authorships) AS a
  FROM openalex.works
  WHERE hasToken(search_text_lc, 'interpretability')
    AND publication_year >= 2021 AND cited_by_count >= 25
)
GROUP BY author_id
ORDER BY works_in_pool DESC, best_citations DESC
LIMIT 100
```

Citation neighborhood (who the paper builds on). Outbound references are
inexpensive (one id lookup then a bounded id set). Inbound citers — works whose
`referenced_works` contain the paper — have no inverse index yet and scan
the full array column; always bound that direction with a
`hasToken(search_text_lc, ...)` or `publication_year` pre-filter and state
the cost:

```sql
SELECT
  tupleElement(tupleElement(a, 'author'), 'display_name') AS name,
  count() AS referenced_works_authored
FROM (
  SELECT arrayJoin(authorships) AS a
  FROM openalex.works
  WHERE id IN (
    SELECT arrayJoin(referenced_works)
    FROM openalex.works
    WHERE doi_norm = '<lowercase-doi>'
  )
)
GROUP BY name
ORDER BY referenced_works_authored DESC
LIMIT 100
```

Candidate hydration (profile, activity, authority):

```sql
SELECT id, display_name, orcid_norm, works_count, cited_by_count,
       tupleElement(summary_stats, 'h_index') AS h_index,
       last_known_institutions
FROM openalex.authors
WHERE id IN ('https://openalex.org/A...', 'https://openalex.org/A...')
```

## Digital signals

ORCID is the bridge out of academia: `authors.orcid_norm` joins curated
external ids (Google Scholar, Twitter/X, GitHub, Mastodon) as identity
relations become available — check `/v1/scry/schema` for what is
registered today. Already queryable now: candidate names and handles over
`mastodon.profiles`, `hackernews.items`, `forums.posts`, and
`stackexchange.posts` — treat name-based matches as
leads, not identities, and say so in the report.
