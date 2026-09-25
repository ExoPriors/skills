---
name: scry-patents
description: >-
  Use when a question is about patents: which publications claim or describe a
  technique, who is assigned or named as inventor on them, how filings in a CPC
  or IPC class move year over year, what the independent claims of a given
  publication say, which publications a patent cites or shares a family with,
  and how an office (US, CN, JP, EP, WO, KR, DE and more) publishes in its own
  language versus English. Covers patents.publications (full text, dates,
  parties, classes, citations) and patents.claims (one row per claim with its
  dependency parents), queried through Scry SQL.
---

# Patents

Patent publications from the offices of the world, one row per publication per
language, with the claims also served claim by claim. Each row names the
source it came from and a precedence that says how authoritative its text is.

## When to use

- Which publications describe or claim a technique, phrase, or component, and when the earliest appeared.
- Who files in a class: assignees, applicants, inventors ranked over a window.
- How a CPC or IPC class grows as a share of an office's grants per year.
- What the independent claims of one publication say, in the office language.
- What a publication cites, what claims priority to it, and its family across offices.
- Whether an English row is the applicant's wording or a machine translation.

The core `scry` skill (authentication, the query door, response fields) is assumed loaded.

## Doors

| Relation | One row is | Key | Time column | Text columns | Notes |
| --- | --- | --- | --- | --- | --- |
| `patents.publications` | one publication in one language: title, abstract, description, flattened claims, dates, parties, CPC/IPC, citations, legal status, provenance | `country_code, publication_number, language`; version `precedence` | `publication_date` (yyyymmdd integer; `filing_date`, `grant_date`, `priority_date` likewise; 0 when unknown); `observed_on` is Scry's observation date | `title`, `abstract`, `description`, `claims`; no lowered text column, text predicates scan the office | depth tier, freshness daily, lag 20m on the index line; `sections` names which of abstract, description, claims the row carries; scan `title`/`abstract`, `description` is the heavy column |
| `patents.claims` | one claim of one publication in one language, with `parent_claim_numbers` (empty for an independent claim) | `country_code, publication_number, language, claim_number`; version `precedence` | `observed_on` only; take the patent's dates from the publication row | `text` | depth tier, lag 20m; a projection of publication rows whose `sections` include claims; prefer it to the flattened `claims` column whenever claim structure matters |

Coverage in the contract's words: the Google Patents Public Datasets snapshot to
2026-04-21 in the office language, plus English where the snapshot carries it; US
full text from the snapshot; other offices' full text as source-language pages land.

## Idioms

- **Bound by office and number range.** The sort key is office, number, language:
  `country_code = 'US' AND publication_number >= 'US2023' AND publication_number <
  'US2024'` is a key range, everything else filters inside it. The leading digits are
  the year for JP, WO and the US 20xx series; a CN number is sequential (`CN2020…U` is a
  2011 utility model), so window CN by `publication_date` and use a prefix only to keep a scan inside the deadline.
- **Token search lowers the column.** No `search_text_lc` here: `hasToken(lower(abstract),
  'transformer') AND hasToken(lower(abstract), 'attention')`, then confirm the
  phrase with `positionCaseInsensitive(abstract, 'large language model') > 0`.
  `hasAllTokens` is refused on these relations (no words index); chain `hasToken`.
  Chinese and Japanese text has no token boundaries: `position(title, '神经网络') > 0` on the office-language row.
- **Dedup by precedence.** A key can carry several rows (a landing beside its merge, a
  metadata-only row beside full text): `ORDER BY precedence DESC LIMIT 1 BY country_code,
  publication_number, language`, or `uniqExact(publication_number)` inside one office and
  language. Precedence: 40 office original, 30 open corpus with text, 20 source-language page, 15 mirror, 10 machine translation, 5 metadata only.
- **Dates are integers.** `publication_date >= 20230101 AND publication_date <
  20240101`; the year is `intDiv(publication_date, 10000)`; drop unknowns with
  `publication_date > 0`. `kind_code` separates applications (`A1`) from grants
  (`B1`, `B2`): count one or the other, never both as "patents".
- **Language and translation.** An office publishes in its language; the `en` rows of
  CN, JP and KR publications are mostly machine translations or snapshot abstracts.
  `language = 'en' AND is_machine_translation = 0` is original English wording; `sections LIKE '%claims%'` keeps rows that carry claims.
- **Claims as rows.** `empty(parent_claim_numbers)` is the independent claims; `ORDER BY
  claim_number ASC, precedence DESC LIMIT 1 BY claim_number` reads one document in order.
  Dependency phrases are parsed per office language (根据权利要求1所述, 請求項1に記載, according to claim 1).
- **Parties and classes are arrays.** `ARRAY JOIN assignees AS assignee`,
  `has(cpc, 'G06N3/08')`, `arrayExists(c -> startsWith(c, 'G06N'), cpc)`. Names are
  as the office printed them (`applicants` `RAYTHEON CO`, `assignees` `Raytheon
  Company`): group on `upper()` when merging offices.
- **Citation and identity.** Cite `source_url` (a patents.google.com page for snapshot
  rows) with `publication_number` and `publication_date`. `citations` and `priority_claims`
  hold numbers in the `publication_number` form, so a cited patent is a key read:
  `country_code = substring(c, 1, 2) AND publication_number = c`. `family_id` groups one
  invention across offices; a lookup by `family_id` alone reads the whole relation, a few seconds, fine once and never in a loop.

## Worked queries

**Earliest US applications whose abstract says "large language model".**

```sql
SELECT publication_number, publication_date, title, source_url
FROM patents.publications
WHERE country_code = 'US' AND language = 'en' AND publication_number >= 'US2023' AND publication_number < 'US2024'
  AND hasToken(lower(abstract), 'language') AND hasToken(lower(abstract), 'model')
  AND positionCaseInsensitive(abstract, 'large language model') > 0
ORDER BY publication_date ASC LIMIT 1 BY publication_number LIMIT 10
```

One row per application, earliest first; `source_url` is the citation. (verified 2026-09-25)

**Share of US grants per year in CPC G06N, with the grant count as denominator.**

```sql
SELECT intDiv(publication_date, 10000) AS year, uniqExact(publication_number) AS grants,
       uniqExactIf(publication_number, arrayExists(c -> startsWith(c, 'G06N'), cpc)) AS g06n,
       round(g06n / grants, 4) AS share
FROM patents.publications
WHERE country_code = 'US' AND language = 'en' AND kind_code = 'B2' AND publication_date >= 20150101 AND publication_date < 20250101
GROUP BY year ORDER BY year LIMIT 20
```

One row per year: distinct B2 grants, the G06N subset, the ratio; `uniqExact` absorbs duplicate key rows. (verified 2026-09-25)

**Independent claims of the earliest 2023 US applications on large language models.**

```sql
SELECT publication_number, claim_number, substring(text, 1, 400) AS claim
FROM patents.claims
WHERE country_code = 'US' AND language = 'en' AND empty(parent_claim_numbers)
  AND publication_number IN (
    SELECT publication_number FROM patents.publications
    WHERE country_code = 'US' AND language = 'en' AND publication_number >= 'US2023' AND publication_number < 'US2024'
      AND hasToken(lower(abstract), 'language') AND positionCaseInsensitive(abstract, 'large language model') > 0
    GROUP BY publication_number ORDER BY min(publication_date) ASC LIMIT 5)
ORDER BY publication_number, claim_number ASC, precedence DESC LIMIT 1 BY publication_number, claim_number LIMIT 20
```

Independent claims of five applications, one row per claim after the precedence dedup; the subquery is the join. (verified 2026-09-25)

**Who was granted the most G06N patents in the US in 2023.**

```sql
SELECT assignee, uniqExact(publication_number) AS n
FROM patents.publications ARRAY JOIN assignees AS assignee
WHERE country_code = 'US' AND language = 'en' AND kind_code = 'B2' AND publication_date >= 20230101 AND publication_date < 20240101
  AND arrayExists(c -> startsWith(c, 'G06N'), cpc)
GROUP BY assignee ORDER BY n DESC LIMIT 15
```

Assignee strings as printed on the grant, distinct grants each; merge spellings with `upper()` before comparing offices. (verified 2026-09-25)

**The same phrase through the lexical helper, with one word of slop.**

```sql
SELECT publication_number, publication_date, title
FROM patents.publications
WHERE country_code = 'US' AND language = 'en' AND publication_number >= 'US2023' AND publication_number < 'US2024'
  AND scry_lex('"large language model"~1', abstract)
ORDER BY publication_date ASC LIMIT 1 BY publication_number LIMIT 10
```

`scry_lex` takes the column as its text argument; the slop admits "large pretrained language model". (verified 2026-09-25)

**The claims of one CN grant in the office language, with their dependency parents.**

```sql
SELECT claim_number, parent_claim_numbers, substring(text, 1, 200) AS claim
FROM patents.claims
WHERE country_code = 'CN' AND publication_number = 'CN112233445B' AND language = 'zh'
ORDER BY claim_number ASC, precedence DESC LIMIT 1 BY claim_number LIMIT 20
```

A key read: claim 1 has no parents, the rest name the claim they depend on, parsed from 权利要求. (verified 2026-09-25)

## Traps

- A text predicate without `country_code` and a number range reads the whole relation
  and cuts at the deadline: `deadline_partial` true with no rows is a wrong probe, not an absence.
- `observed_on` and `source_observed_at` are when Scry observed the row, never the
  patent's date; the patent's dates are integers, so a string date literal does not compare.
- Counting rows counts duplicate landings and metadata-only twins: count distinct `publication_number` or dedup by precedence first.
- `description` and `claims` are empty on metadata-only rows (`sections` is `abstract`
  or empty); `legal_status` is empty on most rows, so empty is unknown, never "no status".
- An `en` row with `is_machine_translation = 1` is not the applicant's wording; quote the office-language row.
- `hasToken` is case-sensitive: lower the column, pass lowercase tokens. It finds nothing inside Chinese or Japanese text; use `position`.
- CPC and IPC codes are exact strings without spaces (`G06N3/08`): `has` needs the full code, a class prefix needs `arrayExists` with `startsWith`.
- Application and grant of one invention are separate publications with different
  `kind_code`; a later `Withdrawn` or `Abandoned` status does not remove a row.

## Cross-family joins

- `patents.publications` to itself: `citations` and `priority_claims` are
  publication numbers, a key read each; `family_id` groups offices.
- `cn_enterprise.companies.name` matches CN `applicants` and `assignees` strings
  as registered company names; the registry row carries the USCC and address.
- `sec.filers.name` and `names` match US `assignees` on upper-cased name, a
  string match with no shared key; then `cik` opens the `sec.*` filings.
