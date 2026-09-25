---
name: scry-sec-filings
description: >-
  Use when a question is about SEC EDGAR filings: which filings a company
  made in a window (10-K, 10-Q, 8-K, proxy, prospectus, 13G/13D, Form 4),
  what a filing says (a term, a phrase, an Item across filers), how the share
  of filings mentioning a topic moves month by month, who filed a form most,
  a filer's CIK, names or tickers, PDF exhibits as text, or the sec.gov URL
  that cites a document. Covers sec.edgar_documents, sec.edgar_markdown,
  sec.edgar_pdf_text and sec.filers, the electronic dissemination era onward.
---

# SEC filings

SEC EDGAR as disseminated: one row per text document within a filing, the
same document rendered to markdown for reading, PDF exhibits as extracted
text, and the filer registry that turns a CIK into a name and tickers.

## When to use

- Which filings a company made in a window, from its ticker or a name token.
- Which filings of a form type use a term or phrase, quoted by accession number.
- How the share of a form's filings mentioning a topic moves month by month.
- Who filed a form most in a window, resolved to filer names.
- Which filings carry readable PDF exhibits, and the sec.gov URL of any document.
- A lexical instrument (hedging, a recipe of your own) measured per filing.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Doors

Lag is as read from the schema index on 2026-09-25; the live index is the authority.

| relation | one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `sec.edgar_documents` | one text-class document of one filing (primary form, `EX-*` exhibits, XBRL renderings) with `ciks`, `form_type` and the verbatim `body` | `accession_number, sequence`; version `observed_on` | `date_filed` (filed); `feed_day` (dissemination day) | `body` (no text index) | depth, lag 15h; metadata scans are cheap, `body` reads are not; raw HTML and pre-2000 plain text live here only |
| `sec.edgar_markdown` | the same document rendered to markdown (HTML bodies), with `tok_cov`, `num_cov`, `issues` | `accession_number, sequence`; access key `date_filed, accession_number, sequence` | `date_filed`; `feed_day` | `markdown`: token index on `lower(markdown)`, trigram lane `lower(ifNull(markdown, '')) LIKE` | depth, lag 12h; the cheaper sibling for any text question; no `ciks` column |
| `sec.edgar_pdf_text` | one PDF exhibit as extracted text with `quality_label` and `text_ratio` | `accession_number, sequence` | `observed_on` only | `text` (no text index) | depth, lag 12d; no form, date or CIK: join `sec.edgar_documents` by `accession_number` |
| `sec.filers` | one CIK with its current `name`, its listed `names` (current and former), and `tickers` | `cik` (10-digit, zero-padded) | `source_observed_on` (snapshot day) | `name` mixed case (`hasTokenCaseInsensitive`), `names` uppercase (`LIKE`, `arrayExists`) | depth, lag 12d; a hand-loaded snapshot, the newest `source_observed_on` wins |

## Idioms

- Names live in `sec.filers` alone; the filing relations carry CIKs. Look the CIK up first (`has(tickers, 'OKLO')`, or `hasTokenCaseInsensitive(name, 'oklo')`), then filter documents with `has(ciks, '<cik>')`. `ciks` lists each CIK on the filing, issuer and Form 4 reporting owners alike, so `has()` returns filings by and about the company; filter `form_type` when you mean one side.
- Resolve a filing's filer by unnesting: `arrayJoin(ciks) AS cik` in a subquery, then `LEFT JOIN sec.filers f ON f.cik = cik`. Never `JOIN sec.filers f ON has(d.ciks, f.cik)`: that is a cross join with a filter.
- Bound `date_filed` first on both filing relations, then `form_type`, then `sequence = '1'` for the primary form document. An `accession_number` predicate is a point lookup. A text predicate with no date bound reads the whole relation; the token index narrows granules, not the read.
- Token search runs on `lower(markdown)`: `hasToken(lower(markdown), 'ransomware')`, `hasAllTokens(lower(markdown), [...])`, `hasAnyTokens` for spellings. Tokens are whole lowercase words; confirm a phrase after the prefilter with `positionCaseInsensitive(markdown, 'cybersecurity incident') > 0`.
- Read `sec.edgar_markdown` for text: it is the same document at a fraction of the bytes, inline-XBRL pruned, tables as pipe markdown. Read `markdown_bytes` before selecting `markdown`, and select it only under tight filters and a small LIMIT.
- Dedup across observations: a feed revision briefly coexists with the row it replaces, so `ORDER BY observed_on DESC LIMIT 1 BY accession_number, sequence`. `sec.edgar_pdf_text` serves the latest text per document already.
- A document's URL from a documents row is `concat('https://www.sec.gov/Archives/edgar/data/', toString(toUInt64(ciks[1])), '/', replaceAll(accession_number, '-', ''), '/', filename)`; the filing index is the same directory plus `<accession_number>-index.htm`. Markdown rows have no `ciks`: join documents by `(accession_number, sequence)` for the URL.
- Primary versus exhibit: `sequence = '1'` is the form itself (`doc_type = form_type`); exhibits are `doc_type` `EX-*`; XBRL renderings are rows too (`doc_type` `XML`, `R1.htm`), so `doc_type NOT LIKE 'EX-%'` does not isolate the form. Form spellings shifted: `SC 13G` and `SC 13D` end 2024-12-17, `SCHEDULE 13G` and `SCHEDULE 13D` continue, so match `form_type LIKE '%13G'` or an IN list.
- PDF plane: join `sec.edgar_pdf_text` to a date-bounded documents subquery on `accession_number`, filter `quality_label = 'good'` before touching `text`; `skipped_binary_docs` on the documents row counts the filing's PDF members.
- Recipes on this family take the relation-qualified text argument, `scry_recipe_density('hedging', sec.edgar_markdown.markdown)` (a bare macro or `lower(m.markdown)` is refused beside a second relation), and are per-document heavy: scope them to an accession set, not a window.

## Worked queries

**Which 8-K primary documents in two months report a ransomware cybersecurity incident?**

```sql
SELECT accession_number, date_filed, markdown_bytes
FROM sec.edgar_markdown
WHERE date_filed >= '2025-01-01' AND date_filed < '2025-03-01'
  AND form_type = '8-K' AND sequence = '1'
  AND hasAllTokens(lower(markdown), ['ransomware', 'cybersecurity'])
  AND positionCaseInsensitive(markdown, 'cybersecurity incident') > 0
ORDER BY observed_on DESC
LIMIT 1 BY accession_number, sequence
LIMIT 10
```

One row per filing, newest observation kept; the token prefilter prunes, the phrase test confirms the wording, and the window sets the cost. (verified 2026-09-25)

**What share of 10-K primary documents mentioned stablecoins, month by month?**

```sql
SELECT a.m, a.filings, coalesce(b.mention, 0) AS mention,
       round(coalesce(b.mention, 0) / a.filings, 3) AS share
FROM (SELECT toStartOfMonth(date_filed) AS m, count() AS filings
      FROM sec.edgar_markdown
      WHERE date_filed >= '2025-01-01' AND date_filed < '2025-07-01'
        AND form_type = '10-K' AND sequence = '1'
      GROUP BY m) a
LEFT JOIN (SELECT toStartOfMonth(date_filed) AS m, count() AS mention
      FROM sec.edgar_markdown
      WHERE date_filed >= '2025-01-01' AND date_filed < '2025-07-01'
        AND form_type = '10-K' AND sequence = '1'
        AND hasAnyTokens(lower(markdown), ['stablecoin', 'stablecoins'])
      GROUP BY m) b ON a.m = b.m
ORDER BY a.m
LIMIT 12
```

One row per month, the metadata-only denominator beside the index-pruned hits; a `countIf` over the token would read the body of each 10-K instead. (verified 2026-09-25)

**Which filings did Apple make in a year, by ticker?**

```sql
SELECT accession_number, form_type, date_filed, filename
FROM sec.edgar_documents
WHERE date_filed >= '2025-01-01' AND date_filed < '2026-01-01'
  AND sequence = '1'
  AND has(ciks, (SELECT cik FROM sec.filers WHERE has(tickers, 'AAPL') LIMIT 1))
ORDER BY date_filed DESC
LIMIT 1 BY accession_number
LIMIT 20
```

One row per filing that names the CIK, its own 10-K and 8-Ks beside Form 4s filed by its insiders; filter `form_type` to keep one side. (verified 2026-09-25)

**Who filed the most 8-Ks in a month?**

```sql
SELECT f.name, d.cik, count() AS filings
FROM (SELECT accession_number, arrayJoin(ciks) AS cik
      FROM sec.edgar_documents
      WHERE date_filed >= '2025-06-01' AND date_filed < '2025-07-01'
        AND form_type = '8-K' AND sequence = '1'
      LIMIT 1 BY accession_number, cik) d
LEFT JOIN sec.filers f ON f.cik = d.cik
GROUP BY f.name, d.cik
ORDER BY filings DESC
LIMIT 10
```

One row per filer with its resolved name; the unnest-then-equi-join is the fast shape. (verified 2026-09-25)

**Which form types carried PDF exhibits in a month, and how many were readable?**

```sql
SELECT d.form_type, count() AS pdf_exhibits, countIf(p.quality_label = 'good') AS readable
FROM sec.edgar_pdf_text p
JOIN (SELECT accession_number, form_type
      FROM sec.edgar_documents
      WHERE date_filed >= '2024-06-01' AND date_filed < '2024-07-01'
        AND sequence = '1'
      LIMIT 1 BY accession_number) d ON d.accession_number = p.accession_number
GROUP BY d.form_type
ORDER BY pdf_exhibits DESC
LIMIT 15
```

One row per form type; `readable` over `pdf_exhibits` is the share whose `text` is worth selecting. (verified 2026-09-25)

**How hedged are the 10-Ks filed on one day?**

```sql
SELECT accession_number, date_filed,
       round(scry_recipe_density('hedging', sec.edgar_markdown.markdown), 3) AS hedging_per_1k
FROM sec.edgar_markdown
WHERE accession_number IN (SELECT accession_number FROM sec.edgar_documents
                           WHERE date_filed = '2025-10-31' AND form_type = '10-K' AND sequence = '1'
                           LIMIT 10)
  AND sequence = '1'
ORDER BY hedging_per_1k DESC
LIMIT 10
```

One row per filing with weighted hedging terms per 1k characters; widen by adding accession numbers, a week of 10-Ks cuts the deadline. (verified 2026-09-25)

## Traps

- `feed_day` is the dissemination day and differs from `date_filed` for a share of filings; `observed_on` is the load day. "When filed" is `date_filed`.
- Any token, LIKE or position predicate without a `date_filed` bound reads the whole relation. `body` and `text` have no text index at all: filter on metadata and LIMIT before selecting them.
- `hasToken` is case-sensitive and the index is on `lower(markdown)`: `hasToken(markdown, 'Ransomware')` skips the index. `names` in `sec.filers` is uppercase, `name` mixed case.
- Tokens are whole words: `microreactor` and `microreactors` are different tokens; `hasAnyTokens` with both spellings, or a phrase test, or the trigram lane.
- `lower(markdown) LIKE '%needle%'` is refused; only the verbatim `lower(ifNull(markdown, '')) LIKE '%needle%'` is served.
- A name token matches many filers (`apple` alone resolves to many CIKs, few of them listed): `LIMIT 1` on a name lookup picks an arbitrary filer. Prefer the ticker, or read the roster and choose the CIK.
- `has(ciks, cik)` returns filings about the company as well as by it (Form 4 rows carry the issuer's CIK beside the reporting owner's).
- `known_holes` in the contract names any span not loaded; a `date_filed` window inside it reads absence, not a filer's silence.
- `quality_label = 'good'` is uneven across accession years and a recent year can be entirely `zero_text` (empty `text`): count the label split for your window before reading an empty exhibit as absence.
- Feed revisions coexist briefly: counts without `LIMIT 1 BY accession_number, sequence` can double a filing.
- Small HTML bodies, XBRL instances and binaries have no markdown row; pre-2000 filings are plain text in `sec.edgar_documents` only.

## Cross-family joins

- No other family carries `cik` or `accession_number`: the bridge is lexical. Take the filer's name token or ticker into `hackernews.items`, `reddit.posts` or the historical Twitter archive (`twitter.tweets`) on `search_text_lc`, windowed around `date_filed`.
- `crawl.pages` with `host = 'www.sec.gov'` holds sec.gov pages; the accession directory in `url` (`/Archives/edgar/data/<cik>/<accession without dashes>/`) is the join to a filing.
- `sec.filers.tickers` is the ticker door for any relation whose text carries cashtags or symbols; match the ticker as a token.
