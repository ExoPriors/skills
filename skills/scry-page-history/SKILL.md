---
name: scry-page-history
description: >-
  Use when a question asks what a URL said on a date or at an instant, whether
  a page changed and when, what the earlier and later texts of an edit were,
  which days a site's pages moved most, when a host flipped category between
  Common Crawl epochs, how to cite a dated capture, or what the Internet
  Archive catalog holds for an identifier. Uses the page_as_of and fetch MCP
  tools over crawl.pages (versions, not observations), crawl.changes (edits,
  hydrated by hash), crawl.host_transitions and internet_archive.items, with
  the Internet Archive's nearest capture as the fallback on a corpus miss.
---

# Page history and time travel

A URL in Scry is a sequence of retained text versions on a second clock:
`page_as_of` reads the one standing at an instant, `crawl.changes` the edits,
and the Internet Archive the years before the corpus.

## When to use

- What did this URL say on a date, and which capture do I cite?
- Has this page changed since a date, and what were the texts before and after?
- Which of a site's pages moved most in a window, and on which days?
- When did a host go parked, or come back alive, between Common Crawl epochs?
- Is there an archived capture older than anything the corpus holds?
- What does the Internet Archive catalog record for an identifier or collection?

The core `scry` skill (authentication, the query door, response fields) is assumed loaded.
Plain SQL is the better tool for lexical or aggregate questions over many URLs; this surface is one URL's timeline and its citations.

## Surfaces

| surface | what it does | required arguments or columns | what comes back | cost or limit the contract states |
| --- | --- | --- | --- | --- |
| `page_as_of` (MCP tool) | newest usable capture of one URL at or before an instant; scheme, `www.` and trailing-slash variants match | `url`; optional `as_of` (RFC 3339 or `YYYY-MM-DD`, omitted = latest), `archive`, `max_chars`, `max_seconds`, `spotlight` | one row: `versions_at_or_before`, `versions_after`, `capture_ts`, `capture_at`, `nearest_after_ts`, `capture_url`, `capture_status`, `title`, `text`; an `archive` block on a miss; `compiled_sql`, `record_id` | `max_seconds` default and ceiling 60; `max_chars` default 40000, text cut past it |
| `fetch` (MCP tool) | hydrates one record by the `record_ref` a `sql` q row returned, or reads a query back by `record_id` | `id`; optional `offset`, `limit`, `spotlight` | `text`, `title`, `url`, `metadata.original_timestamp`, `metadata.provenance_audit`; for a `record_id` the statement and meter, never rows | `limit` capped at 200000 characters |
| `crawl.pages` | one row per distinct extracted text of a URL | `host` first, then `url`; `observed_on` (day), `observed_at` (second), `normalized_text_hash`, `extraction` | `title`, `text`, `text_bytes`, `status`, `quality` | primary tier; token index on `lower(text)`; a `url` without `host` reads the whole relation |
| `crawl.changes` | one row per pair of consecutive text versions of a URL that differ, within one `extraction_version` | `host`, `url`, `observed_on` first | `prev_hash`, `hash`, `prev_observed_hour`, `observed_hour`, `bytes_delta` | depth tier; scan class, no text column |
| `crawl.host_transitions` | one row per category flip of a host between its consecutive Common Crawl appearances | `facet`, `from_value`, `to_value`, `from_crawl`, `to_crawl`, `host` | `from_score`, `to_score`, `method`, `host_rev` | depth tier; transition-only, both scores past the 0.35 floor |
| `internet_archive.items` | one archive.org item-metadata JSON per (`source_key`, identifier) observation | `source_key` first; `source_record_id` and `payload_hash` each have a bloom filter | `payload` JSON (identifier, title, creator, date, mediatype, collection, …), `observed_on` | primary tier; scan class, catalog only, each query bounded by LIMIT |

## Idioms

- Instant, not day: `as_of` as RFC 3339 resolves on the second clock; as `YYYY-MM-DD` it is inclusive through the end of that day; omitted, the latest capture. `capture_at` is the instant you cite, `capture_ts` its day.
- Read the counts before the text: `versions_at_or_before` and `versions_after` count usable captures (accepted extractions) on either side; `versions_after` above zero means the text changed later, and `nearest_after_ts` is when.
- The archive block is consulted only when the corpus has no capture at or before `as_of`: `archive.found` true carries `capture_ts`, `replay_url` and `body`; false means the index answered and has nothing in range; null means it did not answer and the same call may be retried. `archive: false` skips it.
- The reply's `compiled_sql` is the exact statement: rerun it through `sql` at another instant, or without the bound for the whole version list.
- Version history in SQL: `crawl.pages WHERE host = '<h>' AND url = '<u>' ORDER BY observed_at DESC`; one row per distinct text, `observed_on` its first sighting; `host IN ('<h>', 'www.<h>')` when a site serves both.
- Edits, then hydration by hash: rank `crawl.changes` by `abs(bytes_delta)` within one `extraction_version`, then read both texts from `crawl.pages` with `WHERE host = '<h>' AND url = '<u>' AND normalized_text_hash IN ('<prev_hash>', '<hash>')`; never by time, since `prev_observed_on` is the old text's last sighting and `crawl.pages` keeps its first.
- A host's movement: `crawl.changes` grouped by `observed_on` for edit days and churn; `crawl.host_transitions` for category flips (`from_value = 'parked_or_expired'` coming alive, `to_value = 'parked_or_expired'` dying); epoch ids `CC-MAIN-YYYY-WW` sort chronologically.
- Hydrating a search hit: a `sql` call with `q` on `crawl.pages` returns `record_ref` as `crawl:<url>`; `fetch` on that id returns one text of the URL with `metadata.original_timestamp` and a provenance audit, `offset`/`limit` windowing a long text.
- Citing: from `page_as_of`, `capture_url` and `capture_at` (on an archive hit `replay_url` and `capture_ts`); from SQL, `url`, `observed_at`, `normalized_text_hash`; from `fetch`, `record_ref` and `metadata.original_timestamp`. `spotlight: "datamark"` marks corpus text with the token in `datamark`.

## Worked calls

**What did a page say at 20:00 UTC on 2026-09-18, and when did it next change?**

```bash
curl -s https://api.scry.io/mcp -H "Authorization: Bearer $SCRY_API_KEY" \
  -H 'content-type: application/json' -H 'accept: application/json' \
  -H 'mcp-protocol-version: 2025-06-18' -H 'mcp-method: tools/call' -H 'mcp-name: page_as_of' \
  --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"page_as_of","arguments":{"url":"https://www.anthropic.com/news/the-long-term-benefit-trust","as_of":"2026-09-18T20:00:00Z","max_chars":4000}}}'
```

One row: the capture standing at that instant, `capture_at` earlier that evening, `nearest_after_ts` two hours on, the verbatim `capture_url`, status, title and a text cut at `max_chars` with `truncated_cells` set. (verified 2026-09-25)

**Is there a capture of a URL from before the corpus began?**

```bash
curl -s https://api.scry.io/mcp -H "Authorization: Bearer $SCRY_API_KEY" \
  -H 'content-type: application/json' -H 'accept: application/json' \
  -H 'mcp-protocol-version: 2025-06-18' -H 'mcp-method: tools/call' -H 'mcp-name: page_as_of' \
  --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"page_as_of","arguments":{"url":"http://info.cern.ch/hypertext/WWW/TheProject.html","as_of":"2005-01-01","max_chars":6000}}}'
```

`versions_at_or_before` is zero with `versions_after` and `nearest_after_ts` set, and the `archive` block carries `found: true`, a 2002 `capture_ts`, the `replay_url` to cite and the archived `body`. (verified 2026-09-25)

**On which days did a site's pages move, and how much?**

```sql
SELECT observed_on, count() AS edits, uniqExact(url) AS urls, sum(abs(bytes_delta)) AS churn_bytes
FROM crawl.changes
WHERE host = 'www.anthropic.com'
  AND extraction_version = 'markdown-v2'
  AND observed_on >= today() - 14
GROUP BY observed_on
ORDER BY observed_on DESC
LIMIT 14
```

One row per day with edits, distinct URLs and byte churn; `observed_on` is when the later text was seen, so a burst marks an observation day, not a publication day. (verified 2026-09-25)

**Which hosts came back from parked at one Common Crawl epoch boundary?**

```sql
SELECT host, facet, from_crawl, to_crawl, from_value, to_value, round(to_score, 2) AS s
FROM crawl.host_transitions
WHERE from_value = 'parked_or_expired' AND to_value != 'parked_or_expired'
  AND from_crawl = 'CC-MAIN-2026-25' AND to_crawl = 'CC-MAIN-2026-30'
ORDER BY to_score DESC
LIMIT 1 BY host, facet, method, to_crawl
LIMIT 5
```

One row per host with the category it arrived at and its score; `LIMIT 1 BY` drops a superseded judgment sitting beside its replacement. (verified 2026-09-25)

**What does the Internet Archive catalog record for a few identifiers?**

```sql
SELECT source_key, source_record_id, JSONExtractString(payload, 'mediatype') AS mediatype,
       JSONExtractString(payload, 'title') AS title, JSONExtractString(payload, 'date') AS date, observed_on
FROM internet_archive.items
WHERE source_key = 'internet_archive_full_catalog'
  AND source_record_id IN ('prelinger', 'gutenberg', 'commoncrawl', 'TheProject')
ORDER BY observed_on DESC
LIMIT 1 BY source_record_id
LIMIT 5
```

One row per identifier with its mediatype and title; `observed_on` is when the catalog entry was recorded, and `date` is empty for collections. (verified 2026-09-25)

## Traps

- Undeclared arguments are refused by name (`page_as_of` takes `archive`, `as_of`, `max_chars`, `max_seconds`, `spotlight`, `url`); a malformed `as_of` is refused the same way.
- `max_chars` below the envelope floor fails with `reply_over_bound` naming the floor, and the statement was still metered; a cut text cell ends in `…[+N chars cut]`.
- Zero and zero is a corpus miss or an unusable page (a noindex or failed extraction stays in `crawl.pages` with the reason in `extraction` and counts as none); zero before with some after means the URL was first observed later than `as_of`, and the archive block covers the earlier range.
- `observed_on`, `observed_at` and the `prev_` pair are observation clocks, never publication dates; a bound before the corpus began returns only rows carrying such dates.
- `fetch` on `crawl:<url>` names a URL, not a version: two calls on the same id returned texts stamped on different days, so a dated read is `page_as_of` or `crawl.pages` by hash.
- A `url` equality on `crawl.pages` or `crawl.changes` without `host` beside it reads the whole relation, as does `normalized_text_hash` alone; `www.` and the bare host are two hosts in SQL, though `page_as_of` matches both.
- `crawl.changes` writes one row per parser lineage, so count or rank within one `extraction_version`; a URL with a single version has no row, and a failed or noindex capture between two texts is not an edit.
- `crawl.host_transitions` is transition-only: an absent host was stable, seen in under two epochs, or flipped below the floor; consecutive appearances are not always adjacent epochs; parked is spelled `parked_or_expired`.
- `internet_archive.items` is catalog metadata, never item files; an identifier recurs under several `source_key` values, so count `DISTINCT source_record_id`; `JSONExtract` scans payloads, so filter `source_key` first and keep LIMIT.

## Composes with

- `scry-web-crawl` owns the rest of `crawl.*` and `commoncrawl.*`: `commoncrawl.index` dates captures by epoch for a URL older than the page corpus, and `crawl.backlinks` says who pointed at the page you dated.
- The core `scry` skill's `sql` q form finds the page; `record_ref` hands it to `fetch`, and `url` hands it to `page_as_of` for the dated text.
- `scry-hackernews` and other item families carry an outbound URL and an author timestamp; `page_as_of` at that timestamp reads what the linked page said when it was posted.
