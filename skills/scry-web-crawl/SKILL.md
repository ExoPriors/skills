---
name: scry-web-crawl
description: >-
  Use when a question is about web pages and the link graph in Scry: what a
  page said as of a date, how a page or a host changed, who links to a URL or
  a host and with what anchor text, where a site links out to, a host's
  category or web centrality, what Common Crawl holds for a URL or domain
  (index, text, distillate), the frozen internet.documents archive, and
  semantic search over embedded pages. Covers crawl.*, commoncrawl.*,
  internet.documents and their embeddings.
---

# Web pages and the link graph

Observed web pages as text versions, their edits, links between pages and
hosts, per-host judgments, the Common Crawl index, text and webgraph, the
frozen internet.documents archive, and two embedded families.

## When to use

- What did this URL say as of a date, and how has its text changed since?
- Who links to this page or host, with what anchor text, and where does a site link out to?
- Which hosts are blogs, shops or parked domains, and which flipped category between Common Crawl epochs?
- How central is a domain, and what did Common Crawl capture for it (URLs, MIME, digest, WARC triple)?
- What does the open web say about a topic, lexically or semantically, on named hosts or in a date window?

The core `scry` skill (authentication, the query door, response fields) is assumed loaded.

## Doors

Lag is the index line on 2026-09-25; `schema?mode=index` is the authority.

| relation | one row is | key | time column | text | notes |
| --- | --- | --- | --- | --- | --- |
| `crawl.pages` | a distinct extracted text of a URL | `url` versioned by `observed_on`; scope `host` | `observed_on` day, `observed_at` second | `lower(text)`, `title` | primary, `live` 3m; body rows `extraction = 'ok'` |
| `crawl.changes` | consecutive text versions of a URL, one `extraction_version` | `host, url, extraction_version` | `observed_on` prunes, `observed_hour` orders | none; hydrate by hash | depth, `live` 2m |
| `crawl.backlinks` | a cross-host link into a page | `target_url` | `observed_at`, source last seen | `anchor`, unindexed | depth, `live` 3m |
| `crawl.outlinks` | backlinks keyed by the linking page | `source_url` | `observed_at` | `anchor` | depth, `live` 3m |
| `crawl.host_links` | a host pair with its count of linking pages | `source_host` | `first_observed_on`, `last_observed_on` | none | depth, `live` 3m; cheaper than `crawl.outlinks` |
| `crawl.host_backlinks` | host_links keyed by target | `target_host` | same | none | depth, `live` 3m |
| `crawl.hosts` | a root host with facets pivoted | a GROUP BY view over `crawl.host_facets` | `observed_on` | none | depth, `frozen` 7d; rank on `crawl.host_facets` |
| `crawl.host_facets` | a (host, facet, method) verdict with score | `facet, method, host` | `observed_on` | none | depth, `frozen` 7d |
| `crawl.host_transitions` | a host's category flip between consecutive Common Crawl epochs | `facet, method, host, to_crawl` | `from_crawl`, `to_crawl` epoch ids | none | depth, `frozen` 33d |
| `commoncrawl.distillate` | a selected clean page per epoch (article, forum, mailing_list) | `crawl, genre, url` | `observed_on`, `crawl` | `lower(text)` | primary, `frozen` 2d |
| `commoncrawl.index` | a CDX capture row: URL parts, MIME, digest, WARC triple | `crawl, url_host_registered_domain, url_surtkey` | `fetch_time` | none | depth, `frozen` 1d; existence, no text cost |
| `commoncrawl.pages` | whole-page WET text per capture, boilerplate in | `crawl, url_host_registered_domain, url, fetch_time` | `fetch_time` | `text`, substring only | depth, `frozen` 1m; hydrate after the distillate |
| `commoncrawl.domains` | a host or registered domain with harmonic and PageRank ranks | `graph, level, name_rev` | `observed_on` | none | depth, `frozen` 17d; `name_rev` is reversed |
| `commoncrawl.host_links` | a host pair of the webgraph release | `source, target` | none | none | depth, `frozen` 2h |
| `commoncrawl.host_backlinks` | host_links keyed by target | `target, source` | none | none | depth, `frozen` 2d |
| `internet.documents` | a document of the frozen archive, by `source` | `id`; filter `source` first | `original_timestamp` authored, `observed_on` refreshed | `search_text_lc`, `content_text` | depth, `frozen` 65d; `is_deleted = 0` |
| `embeddings.crawl_pages` | a chunk vector of a `crawl.pages` row | `url, chunk_index`; ANN prefilter `host` | `observed_on` | vectors | depth, `hourly` 3m; ANN |
| `embeddings.internet_documents` | a chunk vector of an `internet.documents` row | `target_type, target_id, chunk_index` | `observed_on` | vectors | depth, `frozen` 44d; ANN |

## Idioms

- Text search is on `lower(text)` (`crawl.pages`, `commoncrawl.distillate`) and `search_text_lc` (`internet.documents`): `hasToken` / `hasAllTokens` with lowercase tokens (the rarest governs cost), then `positionCaseInsensitive(text, '<phrase>') > 0` confirms the phrase.
- Scope before text: `crawl.pages` by `host` (`host IN ('<h>', 'www.<h>')`) and a date window; `commoncrawl.*` by `crawl` and `url_host_registered_domain`; `internet.documents` by `source`. A URL lookup carries its host, or epoch and registered domain.
- Versions, not observations: one row per distinct text of a URL; `observed_on` is the day that text was first seen, not publication; `observed_at` orders same-day versions. `ORDER BY observed_on DESC LIMIT 1 BY url` is the current text; `WHERE url = '<u>' AND observed_on <= '<D>' ORDER BY observed_on DESC LIMIT 1` is the page as of D (the `page_as_of` tool); unbounded, the history.
- Edits: `crawl.changes` is the derivative of `crawl.pages`; count within one `extraction_version`; hydrate texts by `(url, normalized_text_hash = hash)` and `= prev_hash`, never by time.
- Cheaper sibling first: the host link graphs before the page-level twins; `commoncrawl.index` for existence, `commoncrawl.distillate` for indexed text, `commoncrawl.pages` only to hydrate; `crawl.host_facets` for a ranked list, `crawl.hosts` for a few named hosts. Common Crawl epoch ids `CC-MAIN-YYYY-WW` sort chronologically.
- Citation: `crawl.pages` cites verbatim `url` and `observed_on`; Common Crawl cites `url` and `crawl`, and its WARC triple (`warc_filename`, `warc_record_offset`, `warc_record_length`) re-derives the record from `https://data.commoncrawl.org/`; `internet.documents` cites `uri`; link rows carry `anchor` as written.
- Ids: `host` joins `crawl.pages`, `crawl.hosts` and the host link graphs; `host_rev = commoncrawl.domains.name_rev` (`arrayStringConcat(arrayReverse(splitByChar('.', name)), '.')` reverses); `content_digest` dedups captures; `embeddings.crawl_pages.url = crawl.pages.url`; `embeddings.internet_documents.target_id = internet.documents.id`.
- Semantic: rank with `scry_vector_topk_distance(embedding_voyage4, @handle) AS distance`; on `embeddings.crawl_pages` only `host` scopes before ranking, other predicates post-filter; one relation per ANN statement, so hydrate from `crawl.pages` by `host IN (...) AND url IN (...)`.

## Worked queries

**Where does one site use the phrase "constitutional classifiers" in the last month?**

```sql
SELECT url, observed_on, title
FROM crawl.pages
WHERE host IN ('www.anthropic.com', 'anthropic.com')
  AND extraction = 'ok'
  AND observed_on >= today() - 30
  AND hasAllTokens(lower(text), ['constitutional', 'classifiers'])
  AND positionCaseInsensitive(text, 'constitutional classifiers') > 0
ORDER BY observed_on DESC
LIMIT 1 BY url
LIMIT 20
```

One row per URL, newest version first; `observed_on` is when that text was seen, not written. (verified 2026-09-25)

**Week by week, what share of a host's observed pages mention a token?**

```sql
SELECT toStartOfWeek(observed_on) AS week,
       uniqExact(url) AS pages,
       uniqExactIf(url, hasToken(lower(text), 'agentic')) AS mentioning,
       round(mentioning / pages, 3) AS share
FROM crawl.pages
WHERE host IN ('www.anthropic.com', 'anthropic.com')
  AND extraction = 'ok'
  AND observed_on >= today() - 56
GROUP BY week
ORDER BY week
LIMIT 20
```

`pages` is the denominator, distinct URLs observed that week; read `share` against it, a thin week swings. (verified 2026-09-25)

**Which pages on a host changed most in two weeks, and what are they titled?**

```sql
SELECT c.url, c.prev_observed_on, c.observed_on, c.bytes_delta, p.title
FROM crawl.changes AS c
JOIN (SELECT url, normalized_text_hash, title FROM crawl.pages
      WHERE host = 'www.anthropic.com' AND extraction = 'ok') AS p
  ON p.url = c.url AND p.normalized_text_hash = c.hash
WHERE c.host = 'www.anthropic.com'
  AND c.extraction_version = 'markdown-v2'
  AND c.observed_on >= today() - 14
ORDER BY abs(c.bytes_delta) DESC
LIMIT 1 BY c.url, c.prev_hash, c.hash
LIMIT 20
```

One row per edit, largest first; the subquery's host filter prunes the join side, `LIMIT 1 BY` folds re-observed duplicates; join `c.prev_hash` for the earlier text. (verified 2026-09-25)

**Who links to gwern.net, ranked by how many of their pages do?**

```sql
SELECT source_host, max(pages) AS linking_pages,
       min(first_observed_on) AS first_on, max(last_observed_on) AS last_on
FROM crawl.host_backlinks
WHERE target_host IN ('gwern.net', 'www.gwern.net')
GROUP BY source_host
ORDER BY linking_pages DESC
LIMIT 20
```

One row per linking host; `pages` is an approximate distinct count; the GROUP BY folds re-observed duplicates. (verified 2026-09-25)

**Which observed pages read like a calibration write-up of one's own forecasts?**

```sql
SELECT url, host, chunk_index, observed_on,
       scry_vector_topk_distance(embedding_voyage4, @my_query) AS distance
FROM embeddings.crawl_pages
ORDER BY distance ASC
LIMIT 20
```

Nearest chunks first, several per URL; `@my_query` is minted from an answer-shaped paragraph; hydrate on `crawl.pages` by the returned `host` and `url` values, `LIMIT 1 BY url`. (verified 2026-09-25)

## Traps

- `observed_on` is observation, not publication: a bound before the relation's coverage (see its contract) returns only rows carrying such dates.
- Unscoped reads: a URL alone on `commoncrawl.*` reads across epochs; a URL or `normalized_text_hash` alone on `crawl.pages` reads the whole relation, as does a ranking on `crawl.hosts`; a host prefix is no index on `commoncrawl.host_links`, list the hosts first from `commoncrawl.domains` at `level = 'host'`.
- Aliases and enums: an alias shadowing its column under GROUP BY (`max(pages) AS pages`) is refused; `crawl.hosts.ads != 'present'` includes bodyless hosts; `ads = 'none'` is the ad-free set; the parked category is spelled `parked_or_expired`.
- Duplicates: re-observed rows sit side by side until merged (`LIMIT 1 BY url`, `source_url`, or `host, facet, method`); `commoncrawl.distillate` counts are `count(DISTINCT url)`; `commoncrawl.pages` repeats a URL across epochs, dedup on `content_digest`; `crawl.changes` writes one row per parser lineage.
- Absence: `crawl.pages` and `commoncrawl.index` hold successful fetches only, so a failed page leaves no row; other `extraction` classes are bodyless provenance; `internet.documents` carries `is_deleted`.
- Case and spelling: `hasToken` is case-sensitive, pass lowercase tokens to `lower(text)`; `host` and `url` are verbatim (scheme, www, slash, query); `commoncrawl.domains` names are reversed; `crawl.pages.quality` is not comparable across its 2026-09-07 definition change.
- ANN: `LIMIT 1 BY url` under ANN ranking overflows the compiled-statement byte ceiling with a wide handle; drop it, dedup at hydration; an empty host-scoped ANN result is not absence; a lane timeout says retry as is.

## Cross-family joins

- `hackernews.items.outbound_url` and `domain(outbound_url)` join `crawl.pages.url` / `host` and `crawl.backlinks.target_url`: what a submitted page said, and who else links to it.
- Any host or domain column takes `commoncrawl.domains` as its centrality prior: reverse the name into `name_rev`, read `harmonic_rank`.
- A `record_ref` of the form `<source>:<uuid>` resolves in `internet.documents` by `id`; `forums.posts` holds the current rows of the forums this archive froze.
