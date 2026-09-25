---
name: scry-public-records
description: >-
  Use when a question is about US public records: which nonprofit filed a
  Form 990 for a tax year and with what revenue (irs.form990), which drug or
  device maker paid which physician, hospital or research program
  (cms.open_payments), what consumers complained about a company and how it
  responded (cfpb.complaints), what a city or county council introduced or
  passed (legistar.matters), who held or sought an office, where and when
  (government.positions, government.officeholder_records), and how a contest
  split by candidate, party, county or precinct (government.election_results).
---

# US public records

Federal, state and municipal records as their publishers release them:
nonprofit returns, industry-to-provider payments, consumer finance complaints,
council matters, and who held, sought or won which office. Five envelope
relations carry the upstream record under `payload`; two typed relations
carry a text index.

## When to use

- Which nonprofit filed a return for a tax year, with what revenue, and who names its EIN.
- Which manufacturer or GPO paid a physician, hospital or research program, and how much.
- What consumers complained about a company, in their own words where published, and how it responded.
- What a city or county council introduced, passed or filed on a topic, by client and month.
- Who held or sought an office in a state or city, with terms, party and the record behind it.
- How a contest split by candidate, party, county or precinct, with its denominator.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Doors

Lag as read from the schema index on 2026-09-25, which is the authority.

| relation | one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `irs.form990` | one e-filed return from an IRS TEOS XML batch, `record.xml`; amended returns re-loaded | `source_key, source_record_id` (`<batch>/<object id>_public.xml:0`); Filer EIN in the XML | `observed_on`; `<TaxYr>` in the XML | `payload` (no index) | depth, lag 7d, frozen; tax years 2016+, mostly two years behind; bound by year prefix |
| `cms.open_payments` | one Open Payments record; family = `source_record_id` prefix (`OP_DTL_GNRL_`, `OP_DTL_RSRCH_`, `PBLCTN_*`, profiles) | `source_key, source_record_id`; `record.Record_ID` | `record.Date_of_Payment` (MM/DD/YYYY text), `record.Program_Year` | `payload` (no index) | depth, lag 7d, frozen; research aggregates whole, general needs a year and recipient filter |
| `cfpb.complaints` | one complaint per weekly snapshot | `record."Complaint ID"`; `source_record_id` is a per-snapshot ordinal | `record."Date received"`; `observed_on` picks the snapshot | `narrative` (no index) | depth, lag 16h, periodic; upstream carries no narratives from 2026-06-01, the column keeps each complaint's last published text |
| `legistar.matters` | one matter per daily snapshot of the most recent matters per client; history is the union | `source_record_id` = `record.MatterGuid`; `record.MatterId` | `record.MatterIntroDate` (ISO text, verbatim) | `payload` (no index) | depth, lag 17h, daily; client slug in `artifact.url` |
| `government.positions` | one person, office, place and term, once per source roster | `wikidata_qid`, `bioguide_id`, `other_person_id`; `(source_key, source_record_id)` | `year`, `term_start`, `term_end`, `election_date` | `search_lc` (indexed), `person_lc`, `office_lc`, `place_lc` | depth, lag 5h; many countries, scope `country = 'USA'` |
| `government.election_results` | one candidate's votes in one contest cell (precinct, county or jurisdiction) per `vote_mode` | `contest_key`, `candidate_id` | `election_date`, `election_year` (partition) | `search_lc` (indexed), `candidate_lc`, `office_lc` | depth, lag 4h, daily; several sources per state and year: one `source_key` per denominator, `vote_mode = 'total'` |
| `government.officeholder_records` | one upstream record per snapshot behind the typed relations | `source_key, source_record_id`; `payload_hash` | `observed_on` | `payload` (no index) | depth, lag 14h, periodic; the wide door, entered from positions |

## Idioms

- Token search only on the typed relations: `hasToken(search_lc, 'sanders')`, `hasAllTokens(search_lc, ['bernard', 'sanders'])`, then `positionCaseInsensitive(search_lc, 'bernard sanders') > 0` for the phrase; tokens lowercase. `scry_lex('"bernard sanders" vermont')` compiles the same predicate.
- Envelopes have no index: bound the scan by a `source_record_id` prefix (irs `'2024_TEOS_XML_%'`, cms `'OP_DTL_RSRCH_%'`) or one pinned snapshot (a `max(observed_on)` subquery), then prefilter raw `payload` with `position` or `positionCaseInsensitive` before any JSON read.
- Fields: `JSONExtractString(payload, 'record', '<Field>')`, `JSONExtractFloat`, `JSONExtractArrayRaw`. IRS XML is one string: `extract` on the raw payload is the cheapest read and `.*?` spans the escaped line breaks.
- Snapshots re-load rows: `ORDER BY observed_on DESC LIMIT 1 BY source_record_id` keeps the latest, `uniq(source_record_id)` counts once; on cfpb dedup on `Complaint ID` or pin one `observed_on`.
- The time column is the event's, never `observed_on` (Doors lists them). Window on both sides; upstream dates include far-future typos.
- Cheap sibling first: the typed relations (indexed, sorted by region, place, office) before `government.officeholder_records`; cms research before general; one legistar snapshot before the union; one irs year prefix before the relation.
- Citations: cfpb `https://www.consumerfinance.gov/data-research/consumer-complaints/search/detail/<Complaint ID>`; legistar `https://<client>.legistar.com/LegislationDetail.aspx?ID=<MatterId>&GUID=<MatterGuid>`, `client` = `extract(JSONExtractString(payload, 'artifact', 'url'), 'legistar\\.com/v1/([^/]+)/')`; others cite `payload.artifact.url` plus `member` or `ordinal`.
- Ids: Filer EIN, `Covered_Recipient_NPI`, `Complaint ID`, `MatterGuid`, `wikidata_qid` and `bioguide_id` are the stable identities; see Cross-family joins.

## Worked queries

**Which complaints in the latest CFPB snapshot mention Zelle, and how did the company respond?**

```sql
SELECT JSONExtractString(payload, 'record', 'Complaint ID') AS id,
  JSONExtractString(payload, 'record', 'Company') AS company,
  JSONExtractString(payload, 'record', 'Date received') AS received,
  JSONExtractString(payload, 'record', 'Company response to consumer') AS response,
  substring(narrative, 1, 200) AS text
FROM cfpb.complaints
WHERE source_key = 'cfpb_complaints'
  AND observed_on = (SELECT max(observed_on) FROM cfpb.complaints)
  AND positionCaseInsensitive(narrative, 'zelle') > 0
LIMIT 10
```

Ten complaints with id, company, date, closure and the first 200 characters of text; `id` is the citation key. An ORDER BY here reads the whole snapshot. (verified 2026-09-25)

**How did New Hampshire split for president in 2024, against the state total?**

```sql
SELECT candidate, party, v, round(100 * v / sum(v) OVER (), 2) AS pct
FROM (SELECT candidate, party, sum(votes) AS v
  FROM government.election_results
  WHERE source_key = 'medsl_precinct_2024' AND election_year = 2024 AND region = 'NH'
    AND office_lc = 'us president' AND stage = 'general' AND vote_mode = 'total'
  GROUP BY candidate, party)
ORDER BY v DESC
LIMIT 10
```

Candidates ranked by votes over one source's precincts, `pct` against the sum of the same rows; `source_key` changes grain and denominator. (verified 2026-09-25)

**Which record stands behind Bernard Sanders's congressional row, and how many terms does it list?**

```sql
SELECT r.source_key, r.source_record_id, r.observed_on,
  JSONExtractString(r.payload, 'record', 'name', 'official_full') AS name,
  length(JSONExtractArrayRaw(r.payload, 'record', 'terms')) AS terms,
  JSONExtractString(r.payload, 'artifact', 'url') AS url
FROM government.officeholder_records AS r
WHERE (r.source_key, r.source_record_id) IN
  (SELECT source_key, source_record_id FROM government.positions
   WHERE scry_lex('"bernard sanders"', government.positions.search_lc)
     AND source_key = 'us_congress_legislators')
ORDER BY r.observed_on DESC
LIMIT 1 BY r.source_key, r.source_record_id
LIMIT 5
```

The typed key walks into the envelope: one record (bioguide id as `source_record_id`), its latest snapshot, official name, term count and the file to cite; `scry_lex` is qualified since two relations appear. (verified 2026-09-25)

**Which manufacturers paid the most for research?**

```sql
SELECT JSONExtractString(payload, 'record', 'Applicable_Manufacturer_or_Applicable_GPO_Making_Payment_ID') AS payer_id,
  any(JSONExtractString(payload, 'record', 'Applicable_Manufacturer_or_Applicable_GPO_Making_Payment_Name')) AS payer,
  count() AS payments,
  round(sum(JSONExtractFloat(payload, 'record', 'Total_Amount_of_Payment_USDollars'))) AS usd
FROM cms.open_payments
WHERE source_key = 'cms_open_payments' AND source_record_id LIKE 'OP_DTL_RSRCH_%'
GROUP BY payer_id
ORDER BY usd DESC
LIMIT 10
```

Payers ranked over the research family by upstream id; `payments` is the record count, `usd` the sum across program years. Over `OP_DTL_GNRL_%` add a `Program_Year` and recipient filter. (verified 2026-09-25)

**Which 2024-batch returns name EIN 20-0049703 (Wikimedia Foundation), and which is the filer's own?**

```sql
SELECT source_record_id,
  extract(payload, '<ReturnTypeCd>([A-Z0-9]+)<') AS form,
  extract(payload, '<Filer>.*?<EIN>([0-9]+)<') AS filer_ein,
  extract(payload, '<Filer>.*?<BusinessNameLine1Txt>([^<]+)') AS filer,
  extract(payload, '<TaxYr>([0-9]{4})<') AS tax_year,
  toInt64OrNull(extract(payload, '<CYTotalRevenueAmt>(-?[0-9]+)<')) AS revenue
FROM irs.form990
WHERE source_key = 'irs_form990_xml' AND source_record_id LIKE '2024_TEOS_XML_%'
  AND position(payload, '<EIN>200049703</EIN>') > 0
ORDER BY filer_ein = '200049703' DESC, tax_year DESC
LIMIT 1 BY source_record_id
LIMIT 10
```

The foundation's own 990 and 990-T come first (filer EIN equal to the probe), then filers whose grant schedules name it; `LIMIT 1 BY` folds re-loaded copies. (verified 2026-09-25)

## Traps

- `observed_on` is when Scry saw the row, not the event date, and filtering it does not shrink an envelope scan: bound by prefix or pin one snapshot.
- Unscoped scans over `irs.form990` or the cms general family read whole records and cut at the deadline (`deadline_partial` true): narrow prefix, year and recipient first.
- cfpb `source_record_id` changes each week for the same complaint; count and join on `Complaint ID`.
- Duplicates: irs and legistar repeat a `source_record_id`; election results carry a contest in several sources and vote modes; a legislator sits in positions once per roster. `LIMIT 1 BY`, `uniq`, one `source_key`, `vote_mode = 'total'`.
- Aliases: a SELECT alias works in WHERE and ORDER BY (`filer_ein`); one that shadows a column name wins over the column.
- Withdrawn and amended: `narrative` is empty for complaints after 2026-06-01; an amended 990 is a second row for the same EIN and tax year; legistar status is mixed-case upstream vocabulary (`Passed`, `PASSED`, `Passed Finally`): `lower()` and `multiSearchAny`.
- Encoding: IRS XML sits in JSON with escaped line breaks and `&amp;` entities; field names with spaces are string arguments (`'Complaint ID'`); cms dates are MM/DD/YYYY text, compare `Program_Year`.
- Case: `*_lc` columns and their tokens are lowercase; `office`, `candidate` and envelope fields keep upstream case, so `positionCaseInsensitive` or `lower()` there.
- Not only US: positions and election results carry other countries; add `country = 'USA'`.

## Cross-family joins

- `government.positions` `(source_key, source_record_id)` is the row key of `government.officeholder_records`; `wikidata_qid` and `bioguide_id` carry a person into any relation keyed on them.
- `government.election_results` meets `government.positions` on `region`, `office_lc`, `election_year` = `year`, `candidate_lc` = `person_lc`: a name match, not a key; confirm with `won` on both sides.
- The scry-grants-and-funders skill enters `irs.form990` by IRS object id from Trace grant URLs; a cfpb `Company` or cms payer name matches `sec.filers.names` by token, never by key.
