---
name: scry-china
description: >-
  Use when a question is about Chinese companies or Chinese court judgments:
  a company's registry record from its name, Unified Social Credit Code
  (USCC) or legal representative (status, capital, address, scope,
  industry); companies of a kind established in a window or a city; which
  judgments mention a term, company or person, by case type, cause of
  action, court or year; a topic's share of judgments by year; which courts
  decided a cause most; the wenshu link citing a judgment. Covers
  cn_enterprise.companies (GSXT registry) and courts.china_judgments (China
  Judgments Online, 1985-2021).
---

# Chinese enterprise and court records

The GSXT enterprise registry as one best row per company keyed by its Unified
Social Credit Code, and the China Judgments Online archive of published
judgments with Chinese full text and structured case metadata, frozen at the
source's 2021 cutoff.

## When to use

- A company's registry record from its name, USCC or legal representative: status, registered capital, establishment date, address, business scope, company type, industry.
- Which companies of a type, industry or status were established in a window, or are registered in a city.
- Which judgments mention a term, a company or a person, narrowed by case type, cause of action (案由), court or judgment year, cited by case number and wenshu link.
- How the share of judgments on a topic moves year by year, with the year's own denominator.
- Which courts or provinces decided the most cases of a cause in a window.
- Which registered companies a set of judgments names, through the USCC written in the judgment text.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Doors

Lag is the index line on 2026-09-25; `schema?mode=index` is the authority. Neither relation is reviewed-access.

| relation | one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `cn_enterprise.companies` | one company-proper (USCC beginning 91) with name, legal representative, capital (`reg_capital_text`, parsed `reg_capital_cny`), status, address, scope, type, industry; provenance in `sources`, `source_count` | `uscc` | `establish_date` (authored); `first_observed`, `last_observed` (observed) | `name`, `business_scope`, `legal_rep`, `reg_address`: no text index; text predicates scan | primary, `frozen` 17d; sole proprietors and raw multi-source rows are held back; `reg_status`, `company_type`, `industry` are cheap low-cardinality filters |
| `courts.china_judgments` | one published judgment: `case_number`, `case_name`, `court`, `region`, `case_type`, `procedure_stage`, `parties`, `cause`, `legal_basis`, `full_text`, `text_length`, `uri`, `metadata` | `doc_id` (the wenshu docId) | `judgment_date` (authored); `publish_date` (source publication); `first_observed_on`, `observed_on` (observed) | `full_text`: 2-character-gram index serving `LIKE '%needle%'` and `hasAllTokens(full_text, tokens(...))` | primary, `frozen` 3d, extent 1985-01-01..2021-10-20; filter `judgment_date`, `court`, `region`, `case_type`, `cause` first |

## Idioms

- Chinese text search is `full_text LIKE '%<needle of 2+ characters>%'`: the gram index serves it, it is the phrase test itself, and it is case-sensitive. Several needles: AND more LIKEs, or `hasAllTokens(full_text, tokens('<needle>', 'ngrams', 2))`; alternatives are `LIKE ... OR LIKE ...`. There is no `search_text_lc` here, `hasToken` is wrong for CJK and unindexed, and a multi-character string passed as one array element to `hasAllTokens` matches nothing.
- Latin needles in judgments keep their case: `LIKE '%USDT%'` and `LIKE '%usdt%'` are different reads; OR the casings you mean. `positionCaseInsensitive` scans.
- Bound `judgment_date` first, then `case_type` or `cause`, then the text predicate; metadata-only predicates are cheap, and `ORDER BY judgment_date DESC` under them is fine.
- A share over a window is two index-engaging subqueries joined on the bucket: `count()` per year without the text predicate for the denominator, `count()` per year with it for the numerator. `countIf(full_text LIKE ...)` inside one aggregate reads the window's whole text and is stopped by the deadline.
- One row per key on both relations: `doc_id` and `uscc` need no `LIMIT 1 BY`. Use `LIMIT 1 BY` on the far side of a cross-family join when that relation keeps revisions (the historical Twitter archive).
- Cite a judgment by `case_number` and `uri` (the wenshu.court.gov.cn docId link, served on the row); `metadata` is source-archive provenance (file member, row number, archive year), not case fields. Cite a company by `uscc` with `sources` and `last_observed`; the registry has no URL column.
- Where: `court` carries its province in the leading characters for most courts; `region` is the locality as the source wrote it and is sometimes empty; the province code is the character after the year in `case_number`, `substringUTF8(case_number, 7, 1)` on the `（2020）粤0118民初1905号` form (粤, 京, 沪 ...).
- Registry lookups are scans and still quick: `name LIKE '%<distinctive fragment>%'`, `legal_rep = '<name>'`, and the low-cardinality columns. `business_scope` is the widest column: filter on `establish_date`, status or industry before `position(business_scope, '<term>') > 0`. `position(reg_address, '<city>') > 0` scopes a city; addresses do not always begin with the province.
- USCCs written in judgment text bridge the two relations: `arrayJoin(extractAll(full_text, '91[0-9A-HJ-NP-RTUWXY]{16}')) AS uscc` from a bounded judgments subquery, joined to `cn_enterprise.companies` on `uscc` with the registry on the left. `parties` names the parties but carries no code.
- `scry_lex` compiles a quoted Chinese phrase with negation against the gram index: `scry_lex('"虚拟货币" -比特币')`.

## Worked queries

**Which registry rows carry a company name fragment (乐视网), and from which source?**

```sql
SELECT uscc, name, legal_rep, reg_status, establish_date, reg_capital_cny, sources, last_observed
FROM cn_enterprise.companies
WHERE name LIKE '%乐视网%'
LIMIT 10
```

One row per USCC, branch offices (分公司) and both parenthesis spellings included; `sources` says whether the row is refreshed or the 2019 snapshot. (verified 2026-09-25)

**Which criminal judgments of 2018 mention bitcoin (比特币), newest first?**

```sql
SELECT doc_id, case_number, court, judgment_date, uri
FROM courts.china_judgments
WHERE judgment_date >= '2018-01-01' AND judgment_date < '2019-01-01'
  AND case_type = '刑事案件'
  AND full_text LIKE '%比特币%'
  AND is_deleted = 0
ORDER BY judgment_date DESC
LIMIT 10
```

Ten judgments newest first, each with its wenshu link; year and `case_type` narrow before the index-served text read. (verified 2026-09-25)

**What share of criminal judgments mention virtual currency (虚拟货币), by year?**

```sql
SELECT d.y, d.judgments, m.mentioning, round(m.mentioning / d.judgments, 5) AS share
FROM (SELECT toYear(judgment_date) AS y, count() AS judgments
      FROM courts.china_judgments
      WHERE judgment_date >= '2016-01-01' AND judgment_date < '2022-01-01' AND case_type = '刑事案件'
      GROUP BY y) d
LEFT JOIN (SELECT toYear(judgment_date) AS y, count() AS mentioning
           FROM courts.china_judgments
           WHERE judgment_date >= '2016-01-01' AND judgment_date < '2022-01-01' AND case_type = '刑事案件'
             AND full_text LIKE '%虚拟货币%'
           GROUP BY y) m ON m.y = d.y
ORDER BY d.y
LIMIT 10
```

One row per year with the year's own denominator; each subquery engages the index and the join is on the bucket. (verified 2026-09-25)

**Which registered companies does a week of sales-contract judgments name by USCC?**

```sql
SELECT c.uscc, c.name, c.reg_status, c.industry, j.doc_id, j.case_number, j.judgment_date
FROM cn_enterprise.companies c
JOIN (SELECT doc_id, case_number, judgment_date, arrayJoin(extractAll(full_text, '91[0-9A-HJ-NP-RTUWXY]{16}')) AS uscc
      FROM courts.china_judgments
      WHERE judgment_date >= '2020-06-01' AND judgment_date < '2020-06-08'
        AND cause = '买卖合同纠纷'
        AND full_text LIKE '%统一社会信用代码%'
      LIMIT 20) j ON j.uscc = c.uscc
LIMIT 20
```

One row per (company, judgment); an empty `reg_status` marks a snapshot-only registry row, and a code the registry lacks drops out of the inner join. (verified 2026-09-25)

**Which courts decided the most private-lending disputes (民间借贷纠纷) in 2020?**

```sql
SELECT court, count() AS n
FROM courts.china_judgments
WHERE judgment_date >= '2020-01-01' AND judgment_date < '2021-01-01' AND cause = '民间借贷纠纷'
GROUP BY court ORDER BY n DESC LIMIT 10
```

One row per court; `cause` and the year window are metadata-only, so no text is read. (verified 2026-09-25)

**Which 2019 judgments discuss virtual currency without saying bitcoin, through the search grammar?**

```sql
SELECT doc_id, case_number, judgment_date
FROM courts.china_judgments
WHERE judgment_date >= '2019-01-01' AND judgment_date < '2020-01-01' AND scry_lex('"虚拟货币" -比特币')
LIMIT 10
```

Ten judgments; `scry_lex` compiles the quoted phrase and the negation against the gram index. (verified 2026-09-25)

## Traps

- `judgment_date` is when the court decided; `publish_date` is when the source published it, often months later; `observed_on` is when the archive row was seen. "When" is `judgment_date`.
- Post-2021 judgments are absent by construction: a zero after the extent's end is not a quiet year. `empty_result_means` is undeclared on both relations: an empty result says nothing until a metadata-only count in the same window is nonzero.
- A share of judgment rows have empty `full_text` (`text_length` 0), unevenly by period: a text predicate silently excludes them; count `text_length > 0` beside the window's count before reading absence.
- `cause`, `legal_basis`, `region` and `procedure_stage` are null or empty for a share of rows, and their vocabularies are the source's own: `procedure_stage` holds both `一审` and `民事一审`, `case_type` carries stray document-title values. GROUP BY the column in your window before filtering on one value.
- A single-character needle falls below the gram size and scans; pre-filter on metadata. A common term (判决) matches most rows, so the index prunes little.
- `is_deleted` is the removal flag; keep `is_deleted = 0` in counts.
- `scry_lex` with a bare Latin word matched nothing where `LIKE` matched rows (2026-09-25); use LIKE for Latin needles.
- Registry rows carried only by the 2019 registration snapshot have empty `reg_status`, `company_type` and `industry`, `last_observed` on the snapshot day, and half-width parentheses in `name` (`(北京)`), while refreshed rows use full-width （北京）: an exact `name =` lookup misses one form; LIKE on a distinctive fragment finds both.
- `establish_date` has sentinel values (1970-01-01, a few beyond today) and nulls: bound windows on both sides. `reg_capital_cny` is null where `reg_capital_text` did not parse; `reg_capital_text` keeps the source's units (万元).
- `legal_rep` is a name string, not an identity: a common name spans unrelated people.
- `judgements.*` (Scry's cardinal judgement scores) is a different family; court judgments are `courts.china_judgments`.

## Cross-family joins

- No other family carries `uscc` or `doc_id`; the bridge is lexical. A company or person name goes into the historical Twitter archive (`twitter.tweets`) as `lower(text) LIKE '%乐视网%'` with `LIMIT 1 BY tweet_id`, and into `reddit.comments` (`lower(body)`), `hackernews.items` and `crawl.pages` (`lower(ifNull(text, ''))`) on their substring doors.
- A USCC quoted in any text column joins the registry: the same `extractAll(<text>, '91[0-9A-HJ-NP-RTUWXY]{16}')` over a page's `text` or a judgment's `full_text`, then `cn_enterprise.companies` on `uscc`.
