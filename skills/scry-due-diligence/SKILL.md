---
name: scry-due-diligence
description: >-
  Use when asked for the standing background of a company, nonprofit or
  person: SEC filings by form and date, its YC card, LinkedIn page or China
  registry row, CFPB complaints, Form 990 returns, grants given or received,
  what its job board is hiring for, how often Hacker News and Reddit mention it
  by month, and which of its pages changed. Walks sec.filers,
  sec.edgar_documents, yc.companies, linkedin.companies,
  cn_enterprise.companies, cfpb.complaints, irs.form990, trace.grants,
  jobs.postings, hackernews.items, reddit.posts, crawl.changes and crawl.pages.
---

# Due diligence

One subject, one key per family, one name token across the text families: resolve the subject in each registry, read what the record, regulator, funder, job board, forums and its own site say, each rate over its own denominator, and name where a family never reached.

## When to use

- What did it file, in what shapes, over the last year?
- Is it what it claims: batch and status, headcount band, registration status, legal representative?
- What do consumers complain about, which products, since when?
- Who funded this nonprofit, and what do its returns say it is?
- Is it hiring, on which board, is the count moving?
- How does forum attention move month by month, and did its site change?

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Method

1. Identity on each registry's own key: `sec.filers.cik` via `has(tickers, '<T>')` or `hasTokenCaseInsensitive(name, '<word>')`; `yc.companies.slug`, newest `observed_on`; `linkedin.companies.slug`, newest `archive_captured_at`; `cn_enterprise.companies.uscc` via `position(name, '<汉字>')`, `LIMIT 1 BY uscc`; an EIN for `irs.form990`; the exact `trace.orgs.name` for `trace.grants`. One `UNION ALL` reads several registries per call.
2. Filings on `sec.edgar_documents`: `has(ciks, '<cik>')`, a `date_filed` window, `sequence = '1'`, `ORDER BY observed_on DESC LIMIT 1 BY accession_number`, grouped by `form_type`. `ciks` also names reporting owners, so Form 4 and 144 are filings about the subject; restrict `form_type` for its own voice; read text on `sec.edgar_markdown`.
3. `cfpb.complaints`: pin `observed_on = (SELECT max(observed_on) FROM cfpb.complaints)`, prefilter `positionCaseInsensitive(payload, '<name>')`, group on `record.Company` and `record.Product`. `irs.form990`: `position(payload, '<EIN>…</EIN>')` under a `LIMIT`, no `ORDER BY` (a sort holds rows until the scan ends); `TaxYr` and `ReturnTypeCd` by `extractAll` over `record.xml`. `trace.grants`: `recipient = '<name>'` or `lower(recipient) LIKE`, sum `amount_usd`, exclude `source = 'fund_estimates'`.
4. `jobs.postings`: `source_key = '<platform>_boards'`, a few days of `observed_on`, the board by `positionCaseInsensitive(payload, 'boards/<slug>')`, named by `JSON_VALUE(payload, '$.artifact.url')`; a day's openings are `uniqExact(source_record_id)` within one board.
5. Reception on `hackernews.items` (`original_timestamp`) and `reddit.posts` (`created_utc`), both on `search_text_lc`, posts before comments. Lexical, since a company name is a rare token `hasToken` prunes on; semantic lanes serve a name that is also a word. Share is mentions over the venue's items that month, the divisor a metadata-only count joined on month (`countIf` reads the whole window's text). Links: `reddit.posts.domain`, `domain(outbound_url)` on Hacker News.
6. `crawl.changes`: `host IN (...)` beside `observed_on >= today() - N`, grouped by `host, extraction_version`, ranked by `abs(bytes_delta)` inside one lineage; hydrate both texts from `crawl.pages` by `normalized_text_hash`, never by time. `url` without `host` reads the whole relation.
7. Each rate names its divisor: the venue's items that month, the company's complaints in that snapshot, the board's openings that day, the host's URLs in one lineage.

## Worked walk

**Who is Coinbase in each registry?**

```sql
SELECT family, key, name, detail, as_of
FROM (
  (SELECT 'sec.filers' AS family, cik AS key, name, arrayStringConcat(tickers, ',') AS detail, toString(source_observed_on) AS as_of
   FROM sec.filers WHERE has(tickers, 'COIN') LIMIT 3)
  UNION ALL
  (SELECT 'yc.companies', toString(yc_id), name, concat(batch, ' ', status, ' team ', toString(team_size)), toString(observed_on)
   FROM yc.companies WHERE slug = 'coinbase' ORDER BY observed_on DESC LIMIT 1)
  UNION ALL
  (SELECT 'linkedin.companies', slug, name, concat(industry, ' ', employee_range, ' ', website), toString(archive_captured_at)
   FROM linkedin.companies WHERE slug = 'coinbase' ORDER BY archive_captured_at DESC LIMIT 1)
)
LIMIT 5
```

One row per registry with its own key and clock; the CIK opens the filings, the slugs the cards. (verified 2026-09-25)

**What did it file in the last year, by form?**

```sql
SELECT form_type, count() AS filings, min(date_filed) AS first_filed, max(date_filed) AS last_filed
FROM (SELECT accession_number, form_type, date_filed
      FROM sec.edgar_documents
      WHERE date_filed >= '2025-09-01' AND date_filed < '2026-09-25'
        AND sequence = '1' AND has(ciks, '0001679788')
      ORDER BY observed_on DESC
      LIMIT 1 BY accession_number)
GROUP BY form_type
ORDER BY filings DESC
LIMIT 20
```

Form 4 and 144 lead, insiders filing about the company; 8-K, 10-Q, 10-K, proxy and 13G are its own year. (verified 2026-09-25)

**What do consumers complain about?**

```sql
SELECT JSONExtractString(payload, 'record', 'Company') AS company,
       JSONExtractString(payload, 'record', 'Product') AS product,
       count() AS complaints,
       min(JSONExtractString(payload, 'record', 'Date received')) AS first_received
FROM cfpb.complaints
WHERE source_key = 'cfpb_complaints'
  AND observed_on = (SELECT max(observed_on) FROM cfpb.complaints)
  AND positionCaseInsensitive(payload, 'Coinbase') > 0
GROUP BY company, product
ORDER BY complaints DESC
LIMIT 10
```

One company string, a product ladder led by money transfer and virtual currency; the divisor is this snapshot's complaints. (verified 2026-09-25)

**Is it hiring?**

```sql
SELECT JSON_VALUE(payload, '$.artifact.url') AS board, observed_on, uniqExact(source_record_id) AS postings
FROM jobs.postings
WHERE source_key = 'greenhouse_boards'
  AND observed_on >= today() - 3
  AND positionCaseInsensitive(payload, 'boards/coinbase') > 0
GROUP BY board, observed_on
ORDER BY observed_on DESC, postings DESC
LIMIT 10
```

One board, one row per snapshot day, openings near-flat across the days. (verified 2026-09-25)

**How does forum attention move?**

```sql
SELECT a.m AS month, coalesce(b.mention, 0) AS mention, a.total AS total, round(1000000 * coalesce(b.mention, 0) / a.total, 1) AS per_million
FROM (SELECT toStartOfMonth(original_timestamp) AS m, count() AS total FROM hackernews.items
      WHERE original_timestamp >= '2026-03-01' AND original_timestamp < '2026-09-01' GROUP BY m LIMIT 6) a
LEFT JOIN (SELECT toStartOfMonth(original_timestamp) AS m, count() AS mention FROM hackernews.items
      WHERE original_timestamp >= '2026-03-01' AND original_timestamp < '2026-09-01' AND hasToken(search_text_lc, 'coinbase')
      GROUP BY m LIMIT 6) b ON a.m = b.m
ORDER BY month
LIMIT 6
```

Six months, each rate over that month's items, one month spiking; the same shape over `reddit.posts` on `created_utc` unions in as a second venue. (verified 2026-09-25)

**Which of its pages changed this month?**

```sql
SELECT host, extraction_version, count() AS edits, uniqExact(url) AS urls, min(observed_on) AS first_edit, max(observed_on) AS last_edit
FROM crawl.changes
WHERE host IN ('www.coinbase.com', 'help.coinbase.com', 'docs.cdp.coinbase.com')
  AND observed_on >= today() - 30
GROUP BY host, extraction_version
ORDER BY edits DESC
LIMIT 12
```

The docs host moves most, marketing and help barely; a host appears once per lineage; read edits inside one `extraction_version`. (verified 2026-09-25)

## Reading the answer

- Citation: the family's key and clock (Families), its author column where one exists, and the page: a documents row's sec.gov URL, `url` on YC, Trace and `crawl.*`, the LinkedIn slug, the Reddit id, the `hn_id`, the board URL plus `record`'s link, `record.Complaint ID`, the object id in `source_record_id`, and for an edit `url` plus both hashes.
- `coverage` carries one entry per relation touched: `extent`, `freshness_lag_seconds`, `known_holes`, `empty_result_means`; state each family's extent or snapshot day beside its rate; quote `deadline_partial` and `truncated` before a count.
- Empty is a wrong key before it is absence: bare host beside `www.`, a name where the family keys on ticker or slug, an uppercase token on a lowered lane, a window outside the extent, a missed snapshot day; `empty_result_means` names the reading (`absent_in_landed_extent` on `sec.filers` and `reddit.posts`, `not_covered` on `linkedin.companies`, `undeclared` elsewhere).
- Access to the reviewed relations is reviewed and requested by writing to hi@scry.io.

## Traps

- Aliases: `name` has four casings (mixed on `sec.filers`, uppercase in `names`, lowered on the LinkedIn lane, Chinese in the China registry); `url` is the outbound link on `reddit.posts`, the card on `yc.companies`, the source on `trace.grants`, the page on `crawl.*`; `payload` is JSON on envelope relations, plain text on `hackernews.items`.
- Clocks: `date_filed` is filed, `feed_day` and `observed_on` are load; `original_timestamp` and `created_utc` are authored; `record.Date received`, `record.updated_at` and `TaxYr` sit inside JSON while `observed_on` is the snapshot day; `archive_captured_at` is the Archive's capture; `crawl.changes` clocks are observation, not publication.
- Duplicates: a filing re-emitted on a later `feed_day` (`LIMIT 1 BY accession_number, sequence`), a YC card per change (`LIMIT 1 BY yc_id`), a LinkedIn capture (`LIMIT 1 BY slug`), a complaint per weekly snapshot and a posting per day (pin `observed_on`), an amended return re-loaded, a Reddit id read twice (`LIMIT 1 BY id`), an edit per lineage.
- Two meanings: `has(ciks, cik)` returns filings by and about the subject; a name that is also a word (`apple`, `oracle`) needs a ticker, slug or phrase test; a famous Chinese name fronts namesake shells (read `uscc` and `establish_date` first); the first `BusinessNameLine1Txt` in a return is the preparer, the filer's follows `<Filer>`.
- Extent short of the window: `jobs.postings` begins at its first snapshot day and a platform's day can be missing; `cfpb.complaints` narratives stop at the `known_holes` date; `irs.form990` tax years run about two years behind; `trace.grants` is AI-safety-area money; the Reddit tail month is thin.

## Families

- `sec.filers`: key `cik`; time `source_observed_on`; text `name`.
- `sec.edgar_documents`: key `accession_number, sequence`; time `date_filed`; text on `sec.edgar_markdown`.
- `yc.companies`: key `yc_id`; time `observed_on`; text `one_liner`, `long_description`.
- `linkedin.companies`: key `slug`; time `archive_captured_at`; text `description`.
- `cn_enterprise.companies`: key `uscc`; time `establish_date`, `last_observed`; text `name`, `business_scope`.
- `cfpb.complaints`: key `record.Complaint ID`; time `record.Date received`, snapshot `observed_on`; text `narrative`.
- `irs.form990`: key `source_record_id`; time `TaxYr` in the XML, load `observed_on`; text `record.xml`.
- `trace.grants`: key `grant_id`; time `date`, `date_precision`; text `purpose`.
- `jobs.postings`: key board URL plus `source_record_id`; time `observed_on`; text `record` per platform.
- `hackernews.items`: key `hn_id`; time `original_timestamp`; text `search_text_lc`.
- `reddit.posts`: key `id`; time `created_utc`; text `search_text_lc`.
- `crawl.changes`: key `url` within `extraction_version`; time `observed_on`, `observed_hour`; text by hash from `crawl.pages`.
- `crawl.pages`: key `url` per `observed_on`; time `observed_at`; text `lower(text)`, `title`.
