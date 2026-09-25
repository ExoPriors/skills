---
name: scry-grants-and-funders
description: >-
  Use when a question is about grants, funders, donors or philanthropy in and
  around the AI-safety area: who funded whom, how much and when (the Trace
  grant ledger and its organization directory), which funders exist and take
  applications (the aisafety.com funding directory), grantmaking.ai pages
  and their source and identity links, Manifund projects, comments and
  amounts raised, and US nonprofit Form 990 returns.
  Covers trace.grants, trace.orgs, aisafety.funders, grantmaking_ai.pages,
  grantmaking_ai.links, manifund.content and irs.form990.
---

# Grants, funders, and philanthropy

Grant records with funder, recipient, date and dollars; the organizations
behind those names; a funder directory; two grant-platform corpora with page
text and links; e-filed Form 990 returns as the public ledger of US nonprofits.

## When to use

- Who funded whom: grants to one recipient or from one funder, regrants, a year's money by funder or cause.
- Which funders exist, what kind they are, whether they take applications.
- What a grantmaking.ai page says, which sources it cites, which profiles its people link to.
- Manifund: which proposals got funded, how much was raised, what the comments say.
- The Form 990 return behind a funder: filer, tax year, revenue, the grants it lists.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Doors

| relation | one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `trace.grants` | one grant or donation in Trace (trace.manifund.org, by Manifund, CC0), a ledger of AI-safety-area money compiled from public feeds and Form 990 filings | `grant_id` | `date` (authored; NULL when unknown; `date_precision` day, month or year) | `purpose`, `funder`, `recipient` by `lower(col) LIKE`; no index | depth, frozen, lag 12h. Names equal `trace.orgs.name` exactly; `source = 'fund_estimates'` rows are funder-level totals; `amount_is_estimate` marks inferred figures; some non-AI-safety grants arrive from upstream feeds |
| `trace.orgs` | one funder or recipient organization | `slug` (`name` unique) | none | `name` | depth, frozen, lag 11h. `org_type`: organization, individual, fund, foundation, government; `website` mostly empty |
| `aisafety.funders` | one record of the aisafety.com/funding directory | `record_id` | `date_added`, `last_modified` | `name`, `description`, `accepting_applications` | depth, frozen, lag 11h. `funder_type`: Fund, Grant program, Platform; `accepting_applications` is free text |
| `grantmaking_ai.pages` | one grantmaking.ai page: `entity_kind` grant, project, person, listing, round | `page_url` | `observed_on` | `content_text` (case-sensitive word index); `lower(concat(title, ' ', content_text))` (3-gram `LIKE`) | depth, frozen, lag 6d. `entity_id` is the site uuid; `sections_json` holds headed sections |
| `grantmaking_ai.links` | one edge from a page section: external source, project or person reference, team member, platform identity | `from_url, to_url, source_section, block_index, anchor_text` | `observed_on` | `anchor_text` (scan) | depth, frozen, lag 6d. `platform` is web, linkedin, x, lesswrong, ea_forum, github, ... |
| `manifund.content` | one Manifund project or comment (`record_kind`) from the open public API, unioned with retained history | `record_kind, manifund_id` | `created_at` (authored), `observed_on` | `content_text`, `title` (case-sensitive word index); 3-gram `LIKE` as above | depth, daily, lag 12h. `project_type` grant or cert; `stage` is `proposal`, `active`, `not funded` or `complete`; `transactions`, `bids`, `causes` are JSON strings; comments carry `project_slug` |
| `irs.form990` | one envelope row per e-filed Form 990 return; `payload.record.xml` is the return | `source_key, source_record_id` (+ `payload_hash`); the 18-digit object id in `source_record_id` is the filing | `observed_on` (load day; the tax year is in the XML) | none; `extractAll(JSONExtractString(payload, 'record', 'xml'), '<Tag>([^<]+)<')[1]` | depth, frozen, lag 7d. IRS TEOS XML batches, tax years 2016 onward and mostly two years behind; amended returns re-load; public domain |

## Idioms

- Indexed text (`manifund.content`, `grantmaking_ai.pages`): the word index is case-sensitive, so `hasAnyTokens(content_text, ['interpretability', 'Interpretability'])` covers both spellings and `positionCaseInsensitive(content_text, 'mechanistic interpretability') > 0` confirms the phrase; the 3-gram lane `lower(concat(title, ' ', content_text)) LIKE '%needle%'` is case-folded. Trace and the directory have no index; `lower(purpose) LIKE '%interpretab%'` scans in milliseconds.
- Trace money: sum `amount_usd`, never `amount`; exclude `source = 'fund_estimates'`; `countIf(amount_is_estimate = 1)` over `count()` is the inferred share; `date IS NULL` rows fall out of any window and year-precision rows sit on January 1.
- Names line up exactly: `LEFT JOIN trace.orgs AS o ON o.name = g.recipient` (or `g.funder`, `g.via`) adds `org_type` and `website`; `via != ''` selects regranted money; a directory `name` carries a program suffix, so `lower(trim(splitByString(':', name)[1]))` matches `lower(trace.orgs.name)`.
- Citations: Trace `url`; Manifund `concat('https://manifund.org/projects/', project_slug)` for projects and comments alike; grantmaking.ai `page_url`; the directory's `url`; a return as `https://projects.propublica.org/nonprofits/organizations/<ein>/<object_id>/full`, the shape Trace's `*_990` rows use.
- Manifund money: raised is `arraySum(arrayMap(x -> JSONExtractFloat(x, 'amount'), JSONExtractArrayRaw(transactions)))`, the ask `funding_goal` and `min_funding`, the outcome `stage`.
- Form 990: filter `source_key = 'irs_form990_xml'`, name the filing by `extractAll(source_record_id, '([0-9]{18})_public')[1]` (leading four digits: filing year), and enter by object id, `observed_on` or a tight `LIMIT`. The filer is `(?s)<Filer>.*?<BusinessNameLine1Txt>([^<]+)<`, since the first BusinessNameLine1Txt in a return is the preparer.
- grantmaking.ai: a grant `title` reads "funder → recipient: purpose" and `content_text` opens with site navigation; join `links` on `l.from_url = p.page_url` and keep external sources with `to_url NOT LIKE 'https://app.grantmaking.ai/%'`; `actor_platform_identity` rows carry one profile URL per `platform`.

## Worked queries

**How did AI-safety grantmaking grow year by year, and how much of it is estimated?**

```sql
SELECT toYear(date) AS year, count() AS grants, uniq(funder) AS funders, uniq(recipient) AS recipients,
  round(sum(amount_usd)) AS usd, round(100 * countIf(amount_is_estimate = 1) / count(), 1) AS pct_estimated
FROM trace.grants
WHERE date >= '2016-01-01' AND date < '2026-01-01' AND source != 'fund_estimates'
GROUP BY year
ORDER BY year
LIMIT 20
```

One row per year; `grants` is the denominator of `pct_estimated`, funder-level totals are excluded, undated rows fall outside the window. (verified 2026-09-25)

**Who received the most in 2025, and what kind of entity are they?**

```sql
SELECT g.recipient, any(o.org_type) AS org_type, any(o.website) AS website, count() AS grants, uniq(g.funder) AS funders, round(sum(g.amount_usd)) AS usd
FROM trace.grants AS g
LEFT JOIN trace.orgs AS o ON o.name = g.recipient
WHERE g.date >= '2025-01-01' AND g.date < '2026-01-01' AND g.source != 'fund_estimates'
GROUP BY g.recipient
ORDER BY usd DESC
LIMIT 15
```

Recipients ranked by dollars with the count of distinct funders behind each; `org_type` comes through the exact-name join. (verified 2026-09-25)

**Which grantmaking.ai grant pages mention mechanistic interpretability, and what sources do they cite?**

```sql
SELECT p.title, p.page_url, l.platform, l.to_url
FROM grantmaking_ai.pages AS p
JOIN grantmaking_ai.links AS l ON l.from_url = p.page_url
WHERE p.entity_kind = 'grant'
  AND hasAnyTokens(p.content_text, ['interpretability', 'Interpretability'])
  AND positionCaseInsensitive(p.content_text, 'mechanistic interpretability') > 0
  AND l.relation_kind = 'external_source_reference'
  AND l.to_url NOT LIKE 'https://app.grantmaking.ai/%'
ORDER BY p.observed_on DESC, p.page_url
LIMIT 1 BY p.page_url, l.to_url
LIMIT 15
```

One row per (grant page, external source); the `LIMIT 1 BY` folds an edge repeated across page sections. (verified 2026-09-25)

**What do the Form 990 returns behind Trace's 990-sourced grant rows say?**

```sql
SELECT extractAll(source_record_id, '([0-9]{18})_public')[1] AS object_id,
  extractAll(JSONExtractString(payload, 'record', 'xml'), '<EIN>([0-9]+)</EIN>')[1] AS ein,
  extractAll(JSONExtractString(payload, 'record', 'xml'), '(?s)<Filer>.*?<BusinessNameLine1Txt>([^<]+)<')[1] AS filer,
  extractAll(JSONExtractString(payload, 'record', 'xml'), '<ReturnTypeCd>([^<]+)<')[1] AS form,
  extractAll(JSONExtractString(payload, 'record', 'xml'), '<TaxYr>([0-9]+)<')[1] AS tax_year,
  extractAll(JSONExtractString(payload, 'record', 'xml'), '<CYTotalRevenueAmt>(-?[0-9]+)<')[1] AS revenue
FROM irs.form990
WHERE source_key = 'irs_form990_xml'
  AND extractAll(source_record_id, '([0-9]{18})_public')[1] IN (
    SELECT extract(url, '/([0-9]{18})/full') FROM trace.grants WHERE source IN ('fli_990', 'lightcone_990', 'irs_990'))
ORDER BY observed_on DESC
LIMIT 1 BY object_id
LIMIT 10
```

One row per return, newest observation kept; the object-id filter runs before any payload is read, and `revenue` is empty on forms other than the 990. (verified 2026-09-25)

**How do interpretability proposals fare on Manifund compared with the rest?**

```sql
SELECT stage, count() AS projects, countIf(scry_recipe('mech_interp', content_text)) AS interp,
  round(100 * countIf(scry_recipe('mech_interp', content_text)) / count(), 1) AS pct_interp
FROM manifund.content
WHERE record_kind = 'project' AND project_type = 'grant' AND stage != ''
GROUP BY stage
ORDER BY projects DESC
LIMIT 10
```

One row per funding stage with the share of its projects matching the recipe's surface forms; `projects` is the denominator. (verified 2026-09-25)

## Traps

- Time: `trace.grants.date` is nullable and precision-flagged; Manifund windows go on `created_at`, not `observed_on`; `irs.form990.observed_on` is the load day and the tax year is inside the XML.
- Unscoped scans: a `LIKE` or `position` over `irs.form990.payload` reads whole returns and cuts at the deadline; bound by object id, `observed_on` or `LIMIT` first. The identity join into `twitter.users` scans profiles and takes seconds.
- Case: `hasToken` on `content_text` and `title` is case-sensitive; a lowercase token misses capitalized mentions. Form 990 names are upper-case and keep XML entities (`&amp;`); `decodeXMLComponent()` restores them.
- Names: `trace.orgs.name` is an exact display name and a near-match is a miss; directory names carry program suffixes.
- Duplicates: a Form 990 filing repeats across observation days and amended returns re-load; dedupe on the object id with `LIMIT 1 BY` after `ORDER BY observed_on DESC`. `grant_id`, `page_url` and `(record_kind, manifund_id)` are unique.
- Totals: `fund_estimates` rows double-count grant sums; `amount_is_estimate = 1` rows carry inferred figures with `estimate_note`.
- Empty strings, not NULL: `via`, `fiscal_sponsor`, `estimate_note`, `trace.orgs.website`, comment-row `blurb` and `description`; test `!= ''`. `not funded` is a Manifund outcome, not a deletion.

## Cross-family joins

- `grantmaking_ai.links` `actor_platform_identity` hrefs join profile relations: `linkedin.profiles.public_id = extract(observed_href, 'linkedin\\.com/in/([^/?#]+)')`; `forums.posts.author_handle = extract(observed_href, 'users/([^/?#]+)')` (sources `lesswrong`, `eaforum`); the historical Twitter archive's `twitter.users.handle` by `lower(extract(observed_href, 'x\\.com/([A-Za-z0-9_]+)'))`.
- `trace.grants.url` joins `manifund.content.project_slug` through `extract(url, 'projects/([^/?#]+)')` for `source = 'manifund'`, and `grantmaking_ai.pages.entity_id` through `extract(url, 'projects/([0-9a-f-]{36})')` for `source = 'grantmaking_ai'`.
- `aisafety.funders` joins `trace.orgs` on the pre-colon name, which then keys the funder's rows in `trace.grants`.
