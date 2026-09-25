---
name: scry-books
description: >-
  Use when a question needs books: which books or passages say a phrase and
  where, what editions, identifiers (ISBN, DOI, OCLC, Open Library keys),
  publisher or year a title has, how much extracted text is held for an author,
  format, language or year range, which authors dominate a topic, semantic
  search over Open Library work and edition records, or FanFiction.net stories
  by fandom, author, date and length. Covers the unified bibliographic catalog
  (file-backed, journal and library metadata records), extracted works,
  passages, whole texts, Open Library embeddings and the fan fiction archive.
---

# Books

One bibliographic catalog, the text extracted from book, magazine and standards files packed into passages, Open Library work and edition embeddings for semantic search, and a static FanFiction.net index.

## When to use

- Which books contain a phrase, and where in the book.
- What editions, identifiers, publisher and year a title has.
- How much readable text is held per author, format, language or year, with the denominator.
- Which authors or publishers dominate a topic in the file-backed catalog.
- Which Open Library works or editions read like a described book.
- Fan fiction by fandom, author, publication date and length.

The core `scry` skill (authentication, the query door, response fields) is assumed loaded.

## Doors

| relation | what one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `books.catalog` | one source record; a title in several catalogues appears once per `id_prefix`; `family` is `files`, `journals` or `metadata` | `record_id` (`<id_prefix>:<id>`: `md5:<hash>`, `ol:OL…M`, `oclc:…`) | `year` (publication, 0 when unknown); `snapshot` dates the load | `search_text_lc` (token index: title, author, publisher); `search_text_cjk` (`LIKE`) | primary, lag 42d, loaded whole per snapshot; metadata only |
| `books.works` | one extracted file with its matched catalog identity (empty `record_id` when unmatched) | `book_id` (32 hex) | `year`; `observed_on` dates the projection | `title`, `author`, `publisher` (plain columns) | depth, lag 60m; cheap sibling for author, format, year, language filters |
| `books.passages` | one packed passage (at most 1,024 tokens, section, offsets) with `title`, `author`, `language` repeated | (`book_id`, `passage_index`), versioned by `observed_on` | `observed_on` (projection) | `text` (token index; `lower(text)` twin) | depth, lag 58m; the reading surface over `books.texts` |
| `books.texts` | one extracted file's whole text | `book_id`; `md5` | `observed_on` | `text` (no index, whole-book length) | depth, lag 58m; `quality_label = 'good'` for reading; `zero_text`/`unsupported_format` rows have empty text |
| `embeddings.openlibrary_works` | one voyage-4-nano chunk of an Open Library work record | (`openlibrary_key` = `/works/OL…W`, `chunk_index`) | `observed_on` | none (`embedding_voyage4` is ANN-only) | depth, lag 120d, `serves_ann`; hydrate through `books.catalog.openlib` |
| `embeddings.openlibrary_editions` | one voyage-4-nano chunk of an Open Library edition record | (`openlibrary_key` = `/books/OL…M`, `chunk_index`) | `observed_on` | none | depth, lag 120d, `serves_ann`; hydrate by `record_id = 'ol:OL…M'` |
| `scry_fanfic.works` | one FanFiction.net story; `uri` is its URL | `story_id` | `published`, `updated` (authored, revised) | `summary`, `body` (no index; columns parsed at read time) | depth, lag 44d; static index, stories published 1998 through 2015; no point lookups |

## Idioms

- Catalog search: set `family` first, then `hasAllTokens(search_text_lc, tokens('<lowercase words>'))`; it takes `tokens()`, never a raw string; substring `LIKE` there is unindexed. Diacritics are not folded (`godel` misses `gödel`): probe both spellings or pick tokens without them. CJK titles go through `search_text_cjk LIKE '%量子力学%'`.
- Passage search: `hasToken(text, 'term')` with a lowercase token; either case via `hasAnyTokens(text, ['Term', 'term'])` or `hasToken(lower(text), 'term')`; never `hasTokenCaseInsensitive` (no index). Confirm a phrase with `positionCaseInsensitive(text, 'the phrase') > 0` after the token filter and `LIMIT 1 BY book_id` for distinct books. Read a book by `book_id` and `passage_index BETWEEN a AND b`, deduped by `ORDER BY observed_on DESC LIMIT 1 BY passage_index`.
- Cheap sibling first: filter author, format, year, language on `books.works`, then reach passages through `book_id IN (SELECT book_id FROM books.works WHERE …)` with a small id set; a whole-author aggregate over passages outruns an ordinary deadline. Read `books.texts` only by `book_id` or `md5` point lookup, via `substring(text, 1, N)` or `length(text)`.
- Identity: `book_id` names one file across works, passages and texts. A nonempty `books.works.record_id` is a point lookup into `books.catalog`; for md5-keyed files it is `concat('md5:', md5)`. Empty `record_id` means unmatched, not untitled.
- Open Library keys: on `id_prefix = 'ol'` rows `openlib` carries the edition key `OL…M` and the work key `OL…W`, the work key being `arrayFilter(x -> endsWith(x, 'W'), openlib)[1]`. An ANN hit `/works/OL…W` hydrates via `id_prefix = 'ol' AND hasAny(openlib, ['OL…W', …])`; a hit `/books/OL…M` via `record_id IN ('ol:OL…M', …)`.
- Semantic search: mint a handle with `POST /v1/scry/embed`, rank with one `scry_vector_topk_distance(embedding_voyage4, @name) AS distance … ORDER BY distance ASC LIMIT k` standalone, then hydrate in a second statement; a WHERE there post-filters a bounded neighbour window.
- Citation: a passage is `books:<book_id>#<passage_index>` (the `fetch` record ref); a catalog record is its `record_id` with `isbn13`, `doi` or `openlib` (`OL…M` resolves at `https://openlibrary.org/books/OL…M`); a story is its `uri`.
- Denominators: replays can transiently double a catalog `record_id` or a texts `book_id`, so `uniq()` for exact counts; `countIf(record_id != '')` measures matched coverage on works.
- Fan fiction: bound first, filter the bound: `FROM (SELECT … FROM scry_fanfic.works LIMIT 200000) WHERE fandom = '…'`. It is a physical-order sample, not the corpus: empty is not absence. Select only needed columns (`body` is heavy); never a global ORDER BY over the family.

## Worked queries

**Which books discuss the phlogiston theory, one passage per book?**

```sql
SELECT book_id, title, author, passage_index, section, substring(text, 1, 160) AS snippet
FROM books.passages
WHERE hasToken(text, 'phlogiston') AND positionCaseInsensitive(text, 'phlogiston theory') > 0
LIMIT 1 BY book_id LIMIT 10
```

One row per book with citation fields and a snippet; an empty `title` means unmatched metadata, not a missing book. (verified 2026-09-25)

**Of good-quality fiction files by publication year, what share is Russian-language?**

```sql
SELECT year, count() AS books, countIf(has(language_codes, 'ru')) AS russian,
       round(100 * russian / books, 1) AS pct
FROM books.works
WHERE quality_label = 'good' AND content_type = 'book_fiction' AND year BETWEEN 2000 AND 2019
GROUP BY year ORDER BY year LIMIT 20
```

One row per year with numerator, denominator and share; `year` is bounded on both ends because 0 and future values exist. (verified 2026-09-25)

**Which of an author's extracted epubs carry passages, one passage per book?**

```sql
SELECT book_id, title, passage_index, section
FROM books.passages
WHERE book_id IN (SELECT book_id FROM books.works
                  WHERE author = 'Ursula K. Le Guin' AND quality_label = 'good' AND format = 'epub')
LIMIT 1 BY book_id LIMIT 10
```

The works filter is the cheap side; passages are reached only through the id list. (verified 2026-09-25)

**Which authors have the most file-backed records on quantum mechanics?**

```sql
SELECT author, count() AS records, countIf(has_file = 1) AS with_file
FROM books.catalog
WHERE family = 'files' AND hasAllTokens(search_text_lc, tokens('quantum mechanics')) AND author != ''
GROUP BY author ORDER BY records DESC LIMIT 10
```

Author strings as catalogued; placeholders such as `Unknown` and `Desconocido` rank beside real names; exclude them by name. (verified 2026-09-25)

**Which Open Library works read like a novel about an isolated lighthouse keeper?** Mint `books_skill_probe` via `/v1/scry/embed` from an answer-shaped paragraph, then:

```sql
SELECT openlibrary_key, chunk_index,
       scry_vector_topk_distance(embedding_voyage4, @books_skill_probe) AS distance
FROM embeddings.openlibrary_works ORDER BY distance ASC LIMIT 10
```

```sql
SELECT arrayFilter(x -> endsWith(x, 'W'), openlib)[1] AS work_key, record_id, title, author, year
FROM books.catalog
WHERE id_prefix = 'ol' AND hasAny(openlib, ['OL19736941W', 'OL20059589W', 'OL17690726W', 'OL17367563W', 'OL19979232W'])
LIMIT 1 BY work_key LIMIT 10
```

The first returns work keys by distance; the second one edition row per work key. (verified 2026-09-25)

**Longest Harry Potter stories first published in 2010, within a bounded sample?**

```sql
SELECT story_id, title, author, published, words, uri
FROM (SELECT story_id, title, author, fandom, published, words, uri FROM scry_fanfic.works LIMIT 200000)
WHERE fandom = 'Harry Potter' AND published >= '2010-01-01' AND published < '2011-01-01'
ORDER BY words DESC LIMIT 10
```

Stories from the sampled prefix, longest first, with URLs; the order holds within the sample only. (verified 2026-09-25)

## Traps

- Time: `observed_on` on works, passages and texts dates the projection, never publication; the publication columns are `year` (catalog, works) and `published` (fan fiction). `year` is 0 when unknown and has values past the present: bound both ends.
- Unscoped scans: the catalog without a `family` or token predicate; `books.texts.text` over many rows; `positionCaseInsensitive` without a token filter; `hasTokenCaseInsensitive` anywhere.
- Identifier arrays are cluster evidence: `has(isbn13, '<isbn13>')` answers with several records across `id_prefix` families merged into one cluster; check title and author before trusting a hit.
- Author strings are not normalized: one author appears in several orders (`Le Guin, Ursula K`, `Ursula K. Le Guin`); list variants with `positionCaseInsensitive(author, 'le guin') > 0` on `books.works` before an equality filter.
- Empty descriptive fields: `title`, `author`, `publisher` are empty on a large share of catalog and works rows (`mostly_empty_columns` in the contract); passages of unmatched books carry empty `title` and `author`.
- Case and encoding: `search_text_lc` is lowercased, not accent-folded; `tokens()` wants lowercase; `search_text_cjk` needs two or more characters; `char_start`/`char_end` count Unicode scalar values of normalized text.
- Duplicates: several catalog records per title across `id_prefix` (dedup by `openlib` work key or title and author); several passages per book per token (`LIMIT 1 BY book_id`); several versions of one passage (`ORDER BY observed_on DESC LIMIT 1 BY passage_index`).
- Fan fiction: an empty bounded sample is not absence; a `story_id` equality is a family scan; an aggregate, even over a bounded subquery, is sized at the whole family and refused at ordinary deadlines (verified 2026-09-25): count client-side over a bounded row read.
- ANN: an emptied neighbour window is not absence; no JOIN in an ANN statement; hydrate separately.

## Cross-family joins

- `books.catalog.doi` entries (bare, `has(doi, '<doi>')`) match `openalex.works.doi` as `concat('https://doi.org/', '<doi>')` and `academic.catalog.doi` as-is.
- `books.catalog.openlib` keys (`OL…W`, `OL…M`) join `embeddings.openlibrary_works` / `_editions` on `openlibrary_key` with the `/works/` and `/books/` prefixes.
- `books.catalog.identifiers['ocaid']` joins `internet_archive.items.source_record_id`.
- `books.works.record_id` joins `books.catalog.record_id`; `book_id` joins works, passages and texts.
