---
name: scry-wikipedia
description: >-
  Use when a question is about Wikipedia article text (which articles mention a
  term or phrase, what an article says, articles on a topic given in prose),
  about edit activity on Wikimedia projects (who edited a title, bot share of
  edits, which wikis created pages, a page's recent revisions), or about the
  ArchiveTeam wiki registry of website shutdowns and rescue campaigns as current
  text or edit history (when a site died, when its status changed, where the
  dump is). Relations: wikipedia.articles, wikimedia.events,
  archiveteam.wiki_pages, archiveteam.wiki_revisions,
  embeddings.wikipedia_articles.
---

# Wikipedia and wikis

English Wikipedia article text with its semantic companion, Wikimedia recent-change
events (EventStreams recentchange, across projects), and the ArchiveTeam wiki
(wiki.archiveteam.org), the registry of website shutdowns and rescue campaigns, as
current pages and as edit history.

## When to use

- Which Wikipedia articles mention a term or phrase, and what an article says (`wikipedia.articles`).
- Articles about a topic you can describe in a paragraph but not in keywords (`embeddings.wikipedia_articles`, then hydrate).
- Edit activity on Wikimedia projects: who edited a title, the bot share of edits, which wikis created pages, one page's revisions in a window (`wikimedia.events`).
- What the ArchiveTeam wiki says about a site: shutdown date, archived or not, where the dump is (`archiveteam.wiki_pages`).
- When that status changed, who changed it, and text later removed upstream (`archiveteam.wiki_revisions`).

The core `scry` skill (authentication, the query door, response fields) is assumed loaded.

## Doors

| relation | one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `wikipedia.articles` | one English Wikipedia main-namespace page | `page_id` | `observed_on` (index date); `original_timestamp` only on pages that arrived through recent changes, NULL on the 2026-03 load | `payload` (article text; token index on `lower(payload)`) | depth, daily, lag 8m (index 2026-09-25). `title`, `uri`, `categories` (JSON array), `word_count` mostly NULL. Revisions of existing pages are not indexed. |
| `wikimedia.events` | one recent-change event from any Wikimedia project (`edit`, `new`, `log`, `categorize`) | `meta.id` inside `record.data`; `event_rev_id` on edits | `event_timestamp` (unix seconds, the event's own time); `observed_on` prunes | none indexed: title, user, comment, bot are JSON in `record.data` | depth, hourly, lag 9m (index 2026-09-25). Typed columns `event_wiki`, `event_server_name`, `event_type`, `event_namespace`, `event_rev_id`. Events from 2026-09-03. |
| `archiveteam.wiki_pages` | one ArchiveTeam wiki page at its newest indexed revision | `pageid` | `revised_at` | `wikitext` (scan) | depth, daily, lag 14h (index 2026-09-25). `ns = 0` is article content. The cheaper sibling for current text. |
| `archiveteam.wiki_revisions` | one revision of an ArchiveTeam wiki page | `revid` (grain `pageid` by `revised_at`) | `revised_at` | `wikitext` (scan) | depth, daily, lag 14h (index 2026-09-25). History since 2009 across namespaces; revisions deleted upstream persist. |
| `embeddings.wikipedia_articles` | one Voyage-4 chunk of one article | `page_id`, `chunk_index` | `observed_on` | none (vectors only) | depth, frozen, lag 132d (index 2026-09-25). `serves_ann: true`; hydrate through `wikipedia.articles.page_id`. |

## Idioms

- Token search on `wikipedia.articles` is `hasToken(lower(payload), 'term')` or `hasAllTokens(lower(payload), ['a', 'b'])`, lowercase tokens: the index is on `lower(payload)` and there is no `search_text_lc` here. Confirm a phrase with `positionCaseInsensitive(payload, 'the phrase') > 0`. Count before reading.
- Key lookups: `page_id = <id>` or `page_id IN (...)` is the indexed path and needs no LIMIT; `title = '<Title>'` scans, so keep a LIMIT.
- On `wikimedia.events` lead with `source_key = 'wikimedia_eventstreams'`, prune with `observed_on`, then filter the typed columns and `event_timestamp > 0`: that path answers in under a second over a day. Anything read from `payload` (title, user, comment, bot) is a JSON parse per row: bound `event_timestamp` to a few hours first. Fields come out with `JSONExtractString(JSONExtractString(payload, 'record', 'data'), 'title')`, booleans with `JSONExtractBool(...)`.
- Dedup: an edit is one row per event; `LIMIT 1 BY event_rev_id` is the defensive dedup on edits (`meta.id` inside `record.data` is the general identity). Articles are one row per page and need no LIMIT BY.
- The ArchiveTeam relations flatten the raw store at query time and read it end to end whatever the WHERE: select only the columns you need, filter `ns` and `title` first, keep LIMIT small, and give a sorted read `x-scry-max-seconds: 45`, since ORDER BY emits nothing until the scan ends. `archiveteam.wiki_pages` for the current answer, `archiveteam.wiki_revisions` for when it changed.
- Time columns: on `wikipedia.articles` `observed_on` is the index date, not the article's; on `wikimedia.events` `event_timestamp` is the event's own time; on the ArchiveTeam relations `revised_at` is the edit time.
- Citations: `wikipedia.articles.uri` is the article URL. A Wikimedia edit permalink is `concat('https://', event_server_name, '/w/index.php?oldid=', toString(event_rev_id))`. An ArchiveTeam revision is `https://wiki.archiveteam.org/index.php?oldid=<revid>`, a page `https://wiki.archiveteam.org/index.php?title=<title>`.
- Semantic: mint a handle with `POST /v1/scry/embed {text, name}`, rank `embeddings.wikipedia_articles` standalone with `LIMIT 1 BY page_id`, then hydrate titles by `page_id IN (...)`. A `page_id` predicate post-filters the candidate window here, so an empty keyed result is not absence. Check `embeddings.sources` before ranking this family on `embeddings.chunks`.
- Ids across families: `page_id` joins an article to its chunks; `title` joins enwiki events and ArchiveTeam page titles to `wikipedia.articles.title` (exact, case-sensitive, spaces, never `_`).

## Worked queries

**Which Wikipedia articles mention Archive Team?**

```sql
SELECT page_id, title, uri
FROM wikipedia.articles
WHERE hasAllTokens(lower(payload), ['archive', 'team'])
  AND positionCaseInsensitive(payload, 'Archive Team') > 0
ORDER BY page_id
LIMIT 20
```

One row per article; `uri` is the citation. (verified 2026-09-25)

**What share of English Wikipedia main-namespace edits in the last day were by bots?**

```sql
SELECT count() AS edits,
       countIf(JSONExtractBool(JSONExtractString(payload, 'record', 'data'), 'bot')) AS bot_edits,
       round(bot_edits / edits, 3) AS bot_share
FROM wikimedia.events
WHERE source_key = 'wikimedia_eventstreams'
  AND observed_on >= today() - 1
  AND event_timestamp >= toUnixTimestamp(now() - INTERVAL 1 DAY)
  AND event_wiki = 'enwiki' AND event_type = 'edit' AND event_namespace = 0
LIMIT 1
```

One row: `edits` is the denominator, `bot_edits` the numerator, `bot_share` their ratio for the window; the aggregate still needs its `LIMIT 1` because it references aliases. (verified 2026-09-25)

**Which wikis created the most main-namespace pages in the last day?**

```sql
SELECT event_wiki, event_server_name, count() AS new_pages
FROM wikimedia.events
WHERE source_key = 'wikimedia_eventstreams'
  AND observed_on >= today() - 1
  AND event_timestamp >= toUnixTimestamp(now() - INTERVAL 1 DAY)
  AND event_type = 'new' AND event_namespace = 0
GROUP BY event_wiki, event_server_name
ORDER BY new_pages DESC
LIMIT 10
```

One row per wiki, typed columns only, so it answers in well under a second; `event_server_name` is the host to cite. (verified 2026-09-25)

**Who edited one English Wikipedia page in the last six hours, one row per revision?**

```sql
SELECT event_timestamp, event_rev_id,
       JSONExtractString(JSONExtractString(payload, 'record', 'data'), 'user') AS user,
       JSONExtractString(JSONExtractString(payload, 'record', 'data'), 'comment') AS comment,
       concat('https://', event_server_name, '/w/index.php?oldid=', toString(event_rev_id)) AS permalink
FROM wikimedia.events
WHERE source_key = 'wikimedia_eventstreams'
  AND observed_on >= today() - 1
  AND event_timestamp >= toUnixTimestamp(now() - INTERVAL 6 HOUR)
  AND event_wiki = 'enwiki' AND event_type = 'edit' AND event_namespace = 0
  AND JSONExtractString(JSONExtractString(payload, 'record', 'data'), 'title') = 'Deaths in 2026'
ORDER BY event_timestamp DESC
LIMIT 1 BY event_rev_id
LIMIT 20
```

Newest revision first; `comment` is the edit summary (a `/* section */` prefix names the section) and `permalink` opens that revision. (verified 2026-09-25)

**How has the ArchiveTeam status page for GeoCities changed, and who changed it?**

```sql
SELECT revised_at, editor, comment, length(wikitext) AS bytes,
       concat('https://wiki.archiveteam.org/index.php?oldid=', toString(revid)) AS permalink
FROM archiveteam.wiki_revisions
WHERE ns = 0 AND title = 'GeoCities'
ORDER BY revised_at DESC
LIMIT 20
```

One row per revision, newest first; `bytes` jumps mark rewrites, `comment` says what changed. Sorted reads here want `x-scry-max-seconds: 45`. (verified 2026-09-25)

**Which Wikipedia articles describe a website shutting down and volunteers rescuing its content?**

```sql
SELECT page_id, chunk_index, scry_vector_topk_distance(embedding_voyage4, @wp_site_deaths) AS distance
FROM embeddings.wikipedia_articles
ORDER BY distance ASC
LIMIT 1 BY page_id
LIMIT 10
```

```sql
SELECT page_id, title, uri
FROM wikipedia.articles
WHERE page_id IN (17193921, 479913, 65896742, 27707599, 18127538, 995141, 16927550, 12539830, 32452117, 4457481)
```

`@wp_site_deaths` was minted from a paragraph describing a shutdown announcement and a volunteer rescue; the first statement returns one nearest chunk per page, the second hydrates those ids by key (no LIMIT needed). (verified 2026-09-25)

## Traps

- `hasToken(payload, 'Term')` misses: the index is on `lower(payload)`, so write `hasToken(lower(payload), 'term')`.
- `original_timestamp` as an article clock: NULL on the 2026-03 load; window on `observed_on`, or take edit times from `wikimedia.events`.
- A JSON predicate over a day of events with no `event_timestamp` window reads the payload of the whole partition and is cut by the deadline; the typed columns are the cheap path.
- Heartbeat rows (`event_timestamp = 0`, empty `event_wiki`) and log events dated years back: exclude with `event_timestamp > 0`; `min(event_timestamp)` is not the start of the events.
- ORDER BY on the ArchiveTeam relations returns nothing under a short deadline: raise `x-scry-max-seconds` or drop the sort.
- `title` is exact and case-sensitive on each relation here; Wikipedia titles use spaces (`'Deaths in 2026'`), URLs use `_`.
- Pages deleted upstream persist in the ArchiveTeam relations with their last-seen text; `wiki_pages` can hold a page the site no longer shows.
- `word_count` and `quality_score` are mostly NULL on `wikipedia.articles`; a filter on them silently drops most pages.
- `event_wiki` is the database name (`enwiki`, `commonswiki`, `wikidatawiki`), `event_server_name` the host; `event_type` is one of `edit`, `new`, `log`, `categorize`.

## Cross-family joins

- `embeddings.wikipedia_articles.page_id = wikipedia.articles.page_id`: hydrate ANN hits.
- enwiki `wikimedia.events` title (from `record.data`) `= wikipedia.articles.title`: which pages created in a window are already indexed as articles (LEFT JOIN from a bounded event subquery).
- `archiveteam.wiki_pages.title = wikipedia.articles.title` with `ns = 0`: a site's ArchiveTeam status page beside its Wikipedia article, since ArchiveTeam titles are site names.
- `wikipedia.articles.uri = crawl.pages.url` with `crawl.pages.host = 'en.wikipedia.org'`: the same page as a dated web observation.
