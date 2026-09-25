---
name: scry-jobs-and-startups
description: >-
  Use when a question is about job postings on public applicant-tracking
  boards (which companies are hiring for a role or skill, what a board opened
  or closed this week, a posting's title, location, pay or URL), Y Combinator
  companies (batch, status, industry, tags, location, team size, what a
  company says it does), or Craigslist classifieds by US metro (listing
  counts per section, employers, price or pay). Covers jobs.postings,
  yc.companies and craigslist.searches.
---

# Jobs, startups, and classifieds

Three snapshot relations: daily job postings from public applicant-tracking
boards, the Y Combinator company directory as its cards change, and
Craigslist search pages per US area and section.

## When to use

- Which companies have open postings for a skill or title, on which boards, with the posting URL.
- Which boards opened the most postings this week, against how many they hold; a posting's first day, last day and newest state.
- Which YC companies in a batch describe themselves a certain way, and how a batch's statuses split.
- Which YC companies hold the most open postings on a board platform.
- Which metros have the most Craigslist listings in a section, and which listings match a word.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Doors

Lag is as read from the schema index on 2026-09-25; the served index is the authority.

| relation | one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `jobs.postings` | one posting's state on one daily snapshot; `payload.record` is the board's record verbatim, `payload.artifact.url` the board | board URL plus `source_record_id`; version `observed_on` | `observed_on` (snapshot day) | none indexed; title and body sit in `payload.record` under per-platform names | depth, lag 11m, daily; `source_key` names the platform (`greenhouse_boards`, `lever_postings`, `ashby_boards`, ...); bodies on greenhouse, lever, ashby, teamtailor, breezy, personio, recruitee, pinpoint, oracle_hcm, titles only elsewhere |
| `yc.companies` | one observed state of one company card | `yc_id`; version `observed_on` | `observed_on` | `name`, `one_liner`, `long_description` (typed, no text index) | depth, lag 6d, periodic; arrays `industries`, `tags`, `regions`, `locations`; `status` in `Active`, `Inactive`, `Acquired`, `Public`; the cheap door of the family |
| `craigslist.searches` | one search cell's page at one hour; `payload.record` holds `items`, `decode`, `totalResultCount`, `location` | `source_key` plus `source_record_id` (the search URL); version `observed_hour` | `observed_hour`, `observed_on` | none; titles sit inside `record.items` | depth, lag 11h, hourly; `craigslist_sections` (area by section, hourly) is the cheap sibling of `craigslist_categories` (area by leaf category, daily) |

## Idioms

- Filter `source_key` first on both envelope relations, then bound `observed_on` to one day; `today() - 1` is the newest closed day for postings. A JSON predicate without both reads whole payloads.
- Read record fields with `JSONExtractString(payload, 'record', '<Field>')`, nested ones with `JSON_VALUE(payload, '$.record.location.name')`, the board with `JSON_VALUE(payload, '$.artifact.url')`. Names differ per platform (greenhouse `title`, `content`; lever `text`, `descriptionPlain`; ashby `title`, `descriptionHtml`); the contract's observations list each shape.
- No text index here: bound the rows, extract the field, then `hasToken(lower(<field>), 'rust')`, and confirm a phrase with `positionCaseInsensitive(<field>, 'ai agents') > 0`.
- A posting's identity is the lowercased board URL plus `source_record_id`: `uniqExact((lower(JSON_VALUE(payload, '$.artifact.url')), source_record_id))` counts, `argMax(payload, observed_on)` over that pair gives the newest state, `min` and `max` of `observed_on` its first and last day, read against the board's own newest day.
- YC current state first, then filter: `ORDER BY observed_on DESC LIMIT 1 BY yc_id` in a subquery, or `argMax(<col>, observed_on) GROUP BY yc_id`. Arrays take `has(industries, 'B2B')` and `arrayJoin(tags)`; `batch` is a season letter plus two-digit year (`W22`, `S26`, `F25`, `P26`).
- A Craigslist cell is its search URL: area `extract(source_record_id, '/search/area/([^?]+)')`, section the `cat=` value (`jjj` jobs, `ggg` gigs, `hhh` housing, `sss` for sale, `bbb` services, `ccc` community, `res` resumes, `eee` events). Anchor on `observed_on = (SELECT max(observed_on) FROM craigslist.searches WHERE source_key = 'craigslist_sections')`; a `today()` window can fall past the newest snapshot.
- Items unnest with `arrayJoin(JSONExtractArrayRaw(payload, 'record', 'items'))`: the posting id is `record.decode.minPostingId` plus the item's first element, the title its last, and tagged pairs carry slug (`[6, ...]`), price or pay (`[7, ...]`), employer (`[8, ...]`) and subcategory (`[12, ...]`).
- Citations: a YC row's `url`; a posting's `absolute_url` (greenhouse), `hostedUrl` (lever), `jobUrl` (ashby) or `url` (teamtailor, workable, rippling); a Craigslist listing by area and posting id, its search page as `concat('https:', source_record_id)`.

## Worked queries

**Which companies had Rust in a posting title on Greenhouse boards yesterday?**

```sql
SELECT JSONExtractString(payload, 'record', 'company_name') AS company,
       JSONExtractString(payload, 'record', 'title') AS title,
       JSON_VALUE(payload, '$.record.location.name') AS location,
       JSONExtractString(payload, 'record', 'absolute_url') AS url
FROM jobs.postings
WHERE source_key = 'greenhouse_boards' AND observed_on = today() - 1
  AND hasToken(lower(JSONExtractString(payload, 'record', 'title')), 'rust')
ORDER BY company, title
LIMIT 20
```

One row per posting on the day with its URL as citation; a title open in several locations is one row per location. (verified 2026-09-25)

**Which Ashby boards opened the most postings this week, against what they hold?**

```sql
SELECT p.board, countIf(p.last_seen = b.newest) AS open_now,
       countIf(p.first_seen >= today() - 7 AND p.last_seen = b.newest) AS opened_this_week,
       round(opened_this_week / open_now, 3) AS week_share
FROM (SELECT lower(JSON_VALUE(payload, '$.artifact.url')) AS board, source_record_id,
             min(observed_on) AS first_seen, max(observed_on) AS last_seen
      FROM jobs.postings
      WHERE source_key = 'ashby_boards'
      GROUP BY board, source_record_id) p
JOIN (SELECT lower(JSON_VALUE(payload, '$.artifact.url')) AS board, max(observed_on) AS newest
      FROM jobs.postings
      WHERE source_key = 'ashby_boards'
      GROUP BY board) b ON b.board = p.board
GROUP BY p.board
ORDER BY opened_this_week DESC
LIMIT 20
```

One row per board: postings on its newest day, those first seen inside the week, and the share; `first_seen` is floored at the platform's earliest snapshot. (verified 2026-09-25)

**Which YC companies hold the most open Greenhouse postings?**

```sql
SELECT y.name, y.batch, y.status, count() AS open_postings
FROM (SELECT lower(JSONExtractString(payload, 'record', 'company_name')) AS company, source_record_id
      FROM jobs.postings
      WHERE source_key = 'greenhouse_boards' AND observed_on = today() - 1) j
JOIN (SELECT yc_id, argMax(name, observed_on) AS name, argMax(batch, observed_on) AS batch, argMax(status, observed_on) AS status
      FROM yc.companies
      GROUP BY yc_id) y ON lower(y.name) = j.company
GROUP BY y.name, y.batch, y.status
ORDER BY open_postings DESC
LIMIT 20
```

One row per matched company; the join is exact on the lowercased name, so a differently named board is missed and a shared name merges. (verified 2026-09-25)

**How do statuses split per YC batch?**

```sql
SELECT batch, count() AS companies,
       countIf(status = 'Active') AS active,
       countIf(status = 'Acquired') AS acquired,
       countIf(status = 'Public') AS public,
       countIf(status = 'Inactive') AS inactive,
       round(active / companies, 3) AS active_share
FROM (SELECT yc_id, argMax(batch, observed_on) AS batch, argMax(status, observed_on) AS status
      FROM yc.companies
      GROUP BY yc_id)
GROUP BY batch
ORDER BY companies DESC
LIMIT 20
```

One row per batch over each company's newest card, the four statuses summing to `companies`. (verified 2026-09-25)

**Which metros have the most Craigslist job listings at the freshest snapshot?**

```sql
SELECT extract(source_record_id, '/search/area/([^?]+)') AS area,
       argMax(JSONExtractInt(payload, 'record', 'totalResultCount'), observed_hour) AS listings,
       max(observed_hour) AS as_of
FROM craigslist.searches
WHERE source_key = 'craigslist_sections' AND source_record_id LIKE '%?cat=jjj'
  AND observed_on = (SELECT max(observed_on) FROM craigslist.searches WHERE source_key = 'craigslist_sections')
GROUP BY area
ORDER BY listings DESC
LIMIT 20
```

One row per area with the jobs section's whole count at its newest hour, `as_of` the citation's timestamp. (verified 2026-09-25)

**Which Craigslist job listings mention a forklift, with pay and employer?**

```sql
SELECT area, base + JSONExtractInt(item, 1) AS posting_id,
       JSONExtractString(arrayElement(JSONExtractArrayRaw(item), -1)) AS title,
       JSONExtractString(arrayFirst(e -> startsWith(e, '[7,'), JSONExtractArrayRaw(item)), 2) AS compensation,
       JSONExtractString(arrayFirst(e -> startsWith(e, '[8,'), JSONExtractArrayRaw(item)), 2) AS employer
FROM (SELECT extract(source_record_id, '/search/area/([^?]+)') AS area,
             JSONExtractInt(payload, 'record', 'decode', 'minPostingId') AS base,
             arrayJoin(JSONExtractArrayRaw(payload, 'record', 'items')) AS item
      FROM craigslist.searches
      WHERE source_key = 'craigslist_sections' AND source_record_id LIKE '%?cat=jjj'
        AND observed_on = (SELECT max(observed_on) FROM craigslist.searches WHERE source_key = 'craigslist_sections'))
WHERE hasToken(lower(title), 'forklift')
ORDER BY area, posting_id
LIMIT 20
```

One row per listing on the newest page of each area's jobs cell; pay and employer are free text as posted, empty when absent. (verified 2026-09-25)

## Traps

- `observed_on` is the snapshot day, not the posting date; posting dates sit inside the record as strings (`updated_at`, `createdAt`, `publishedAt`, `postedOn`): `parseDateTimeBestEffortOrNull` before comparing.
- `source_record_id` alone merges employers: bamboohr ids are per company, and `workday_boards`, `oracle_hcm_boards`, `adp_boards` fold the board into the id. The same board under different URL casing counts twice.
- Workable lists a posting open in several locations once per location under one shortcode; greenhouse gives each location its own id. Choose which you are counting.
- Platforms have days without a snapshot: a posting absent on a day, or a day whose count collapses, is a gap, not closure. Read `count() GROUP BY observed_on` for the platform before dating an opening or a closing.
- `yc.companies` holds several rows per `yc_id`; a text filter before dedup matches a superseded card. `status` and `batch` are exact case.
- `hasToken` is case-sensitive, so `lower()` the field; tokens split on punctuation, so `$17/hr` is not one token. `scry_lex` and `hasAllTokens` over an extracted field are refused on this family.
- Craigslist `record.items` is one page; only `totalResultCount` is the cell's whole count. Cells per hour vary, so a cell missing from an hour is a gap. Pay and price are free text.
- The contract's observations spell the Craigslist document as `record.data.*`; the served rows carry `items`, `decode` and `totalResultCount` directly under `record`.

## Cross-family joins

- A YC company's `name` and `slug` are lexical keys: take the name as a token into `hackernews.items` (`search_text_lc`, "Launch HN" titles), `reddit.posts` and the historical Twitter archive (`twitter.tweets`), windowed around the batch.
- `domain(website)` from `yc.companies` joins `crawl.pages` on `host`; a posting's page URL joins the same way.
- `linkedin.companies` and `sec.filers` carry company names for a lowercased name join; `sec.filers.tickers` turns a public YC company into its filings.
