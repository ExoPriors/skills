---
name: scry-prior-art
description: >-
  Use when the question is when or where an idea, technique, phrase, or product
  first appeared and the answer must be dated rows: earliest mention, first
  paper, first patent claim, first repository or package. Walks Hacker News,
  the historical Twitter archive, the academic catalog and OpenAlex, patents
  and claims, GitHub, the package catalog, mailing lists and observed web
  pages, each on its own clock, with a sense anchor so a phrase from another
  field does not pass as prior art.
---

# Prior art

Prior art is the earliest dated evidence that an idea, technique, or product existed: patent claims, papers, repositories, packages, list messages, community posts, each on its own clock and cited by its own key.

## When to use

- When did a phrase or technique first appear, and in which venue: post, paper, patent, code, or list?
- Is there a publication or claim before a given priority date that describes this method?
- Who wrote about this before the person credited with it, and where?
- Did the name exist earlier in another field, so the phrase is older than the idea?
- What is the earliest repository, package, or release that implements this?

The core `scry` skill (authentication, the query door, response fields) is assumed loaded.

## Method

1. Fix the sense before the date: the phrase plus two or three anchor tokens that co-occur only in the intended sense; a shared phrase returns another field's older rows first. Prior art is lexical: `hasAllTokens` on the family's indexed expression, the phrase confirmed with `positionCaseInsensitive(col, 'phrase') > 0`. Semantic search (`scry_lex`) only finds the vocabulary an idea had before its name.
2. Community clocks first. `hackernews.items` (key `hn_id`, clock `original_timestamp`, text `search_text_lc`), bounded on `original_timestamp`. Then `twitter.tweets` (key `tweet_id`, bound by `bucket_date`, order by `original_timestamp`, fold with `LIMIT 1 BY tweet_id`): one month of `bucket_date` around the candidate date, widened by year when empty; a window that cuts moves to `x_open.tweets`.
3. Papers. `academic.catalog` (key `paper_key`; `title` is word-indexed case-sensitively: `hasAnyTokens(title, ['Prompt', 'prompt'])`; clock `published_at`, often year precision; an arXiv id's yymm prefix is the posting month). Cross-check `openalex.works` (key `id`, `search_text_lc` is the title only, clock `publication_date`, count with `uniq(id)`).
4. Patents. `patents.publications` (key `country_code, publication_number, language`) has no text index: bound by office and number range, chain `hasToken(lower(abstract), '…')` (`hasAllTokens` is refused there), require `priority_date > 0`, order by `priority_date`, fold with `LIMIT 1 BY publication_number`. Then `patents.claims` on the same key, `empty(parent_claim_numbers)` for the independent claims, the text prior art is read against.
5. Code. `github.documents` rows with `kind = 'repository'` carry the forge clock as `JSONExtractString(metadata, 'repo', 'created_at')`, blank on many rows; `github.repos` (key `owner_lc, name_lc`) has only archive-visit clocks: existence, never a date. `packages.catalog` (key `package_key`, text `name`) dates the first release by `first_published_at`.
6. Mailing lists. `mailing_lists.messages` (key `message_key`, text `lower(payload)`, clock `original_timestamp` from the Date header); count with `uniqExact(message_id)` (cross-posts repeat across `list_key`).
7. Observed web pages. `crawl.pages` (key `url, observed_on`) only with a `host` bound and `extraction = 'ok'`, folded `LIMIT 1 BY url`; `observed_on` is the observation, the publication date is in the URL path or the page text.
8. Assemble one row per family on its authored clock, and say what the earliest row is earliest among: rows the scan reached, inside the bound window, under the sense anchor, in the families searched. A rate or share names its divisor: HN items with the phrase in a year over `count()` of HN items that year; tweets folded by `tweet_id`; messages by `uniqExact(message_id)`.

## Worked walk

When and where did "prompt injection" in the language-model-attack sense first appear?

**Step 1: Hacker News, bounded on the authored clock.**
```sql
SELECT hn_id, original_author, original_timestamp, title, uri
FROM hackernews.items
WHERE original_timestamp < '2023-01-01'
  AND hasAllTokens(search_text_lc, ['prompt', 'injection'])
  AND positionCaseInsensitive(search_text_lc, 'prompt injection') > 0
ORDER BY original_timestamp ASC
LIMIT 5
```
Five rows: hn_id 32817941 by simonw at 2022-09-12 22:25 UTC, "Prompt injection attacks against GPT-3", then four comments on it. (verified 2026-09-25)

**Step 2: the historical Twitter archive, one month of bucket_date, folded by tweet_id.**
```sql
SELECT tweet_id, author_handle, original_timestamp, text
FROM twitter.tweets
WHERE bucket_date >= '2022-09-01' AND bucket_date < '2022-10-01'
  AND hasAllTokens(search_text_lc, ['prompt', 'injection'])
  AND positionCaseInsensitive(search_text_lc, 'prompt injection') > 0
ORDER BY original_timestamp ASC
LIMIT 1 BY tweet_id
LIMIT 10
```
Ten rows, all on 2022-09-12; the earliest, tweet 1569154185806942208 at 02:41 UTC, precedes the HN item by most of a day; `author_handle` is often blank, the `tweet_id` permalink is the citation. (verified 2026-09-25)

**Step 3: paper titles, case-sensitive tokens.**
```sql
SELECT paper_key, arxiv_id, doi, published_year, published_at, title, sources
FROM academic.catalog
WHERE hasAnyTokens(title, ['Injection', 'injection'])
  AND hasAnyTokens(title, ['Prompt', 'prompt'])
  AND positionCaseInsensitive(title, 'prompt injection') > 0
  AND published_at IS NOT NULL
ORDER BY published_at ASC
LIMIT 10
```
Ten rows: a 1982 solar-physics paper first, arXiv 2206.11349 (2022-05-31) in another sense, and the first attack-sense title arXiv 2302.12173 at 2023-02-23; the phrase is older than the idea. (verified 2026-09-25)

**Step 4: US patents by priority date, bound by office and number range.**
```sql
SELECT publication_number, kind_code, priority_date, filing_date, publication_date, title, source_url
FROM patents.publications
WHERE country_code = 'US' AND language = 'en'
  AND publication_number >= 'US2023' AND publication_number < 'US2026'
  AND hasToken(lower(abstract), 'prompt') AND hasToken(lower(abstract), 'injection')
  AND positionCaseInsensitive(abstract, 'prompt injection') > 0
  AND priority_date > 0
ORDER BY priority_date ASC
LIMIT 1 BY publication_number
LIMIT 10
```
Ten rows; the earliest is US20240386103A1, priority 20230517, filed 20230819, published 20241121; `source_url` is the citation. (verified 2026-09-25)

**Step 5: its independent claims, a keyed read.**
```sql
SELECT claim_number, substring(text, 1, 300) AS claim
FROM patents.claims
WHERE country_code = 'US' AND publication_number = 'US20240386103A1' AND language = 'en'
  AND empty(parent_claim_numbers)
ORDER BY claim_number ASC, precedence DESC
LIMIT 1 BY claim_number
LIMIT 5
```
Three rows, claims 1, 9 and 16; claim 1 is the text a candidate prior-art row is read against. (verified 2026-09-25)

**Step 6: packages on the registry's clock.**
```sql
SELECT package_key, first_published_at, latest_release_at, repository_url, sources
FROM packages.catalog
WHERE hasAllTokens(name, ['prompt', 'injection'])
  AND first_published_at IS NOT NULL
ORDER BY first_published_at ASC
LIMIT 10
```
Ten rows; the earliest is go/github.com/sinanw/llm-security-prompt-injection at 2023-12-18; `sources` names which registry set the clock. (verified 2026-09-25)

## Reading the answer

- The citation is the family's key and time column from the table below plus author and link: `original_author` and `uri` on Hacker News, mailing lists and GitHub documents; `https://x.com/i/status/<tweet_id>` for tweets; `arxiv_id` or `doi` for papers; `source_url` for patents; `repository_url` for packages. Name the clock ("priority 20230517").
- Coverage comes from the response's `coverage[]` entry for the relation: `extent.column`, `extent.min`, `extent.max` give the clock and its reach; `known_holes[]` the declared gaps; `freshness_lag_seconds` the tail; `empty_result_means` what zero rows may claim; top-level `completeness` whether the scan finished. Say it as searched: "hackernews.items over original_timestamp within its extent, one declared hole, scan finished".
- An empty result means the probe was wrong before it means absence: `zero_rows.cause` of `deadline_cut` establishes nothing; a token in the wrong case or over an unindexed expression matches nothing; a bound outside the extent finds nothing; another sense may own the phrase. Absence is only "no row in this relation's extent under this predicate".

## Traps

- Alias collisions: `search_text_lc` is title and body on `hackernews.items`, the tweet body on `twitter.tweets`, the title only on `openalex.works`; `text` is a claim, a tweet, or a page body; `title` on `academic.catalog` is case-sensitive words; `name` on `packages.catalog` is indexed bare (a token function over `lower(name)` is refused), `github.repos` indexes `name_lc`.
- Time columns differ per family: patent dates are yyyymmdd integers, 0 when unknown; `academic.catalog` `published_at` is often the first day of the year; `github.repos` has no creation date; `crawl.pages` `observed_on` is an upper bound; `packages.catalog` `first_published_at` is a per-source clock (libraries_io rows read as early 2015 whatever their age; crates and maven stop at early 2020), so an upper bound.
- Duplicates across observations: tweet revisions (`LIMIT 1 BY tweet_id`), patent precedence (`LIMIT 1 BY country_code, publication_number, language`), cross-posts (one `message_id` under several `list_key` values), OpenAlex ids (`uniq(id)`), page observations (`LIMIT 1 BY url`), repository summaries and tombstones (`LIMIT 1 BY external_id`, `NOT JSONExtractBool(metadata, 'deleted')`).
- A token that means two things: "prompt injection" is solar physics in 1982, a magnetopause process in 2018, a VoIP list topic in 2016, a parameterization method in mid-2022, and the attack from 2022-09-12; the earliest row is the phrase's until the anchor tokens pin the sense.
- A family whose extent does not reach the window: `packages.catalog` and `academic.catalog` index extents are on `observed_on`, a fold day, silent on the authored clock; `openalex.works` is a dated snapshot, works after its release date are absent; the GitHub, page, list and patent relations declare no extent: read `coverage` from the response.
- Wide reads: `name_lc LIKE '%x%'` on `github.repos` reads most of the relation; an unbounded text search on `crawl.pages` is cut; full text in `academic.papers` cuts at 20 seconds on a rare pair.
- A family missing from `?mode=index` is reviewed access; request it by writing to hi@scry.io.

## Families

| relation | key | time column | text column |
|---|---|---|---|
| `patents.publications` | `country_code, publication_number, language` | `priority_date`, `filing_date`, `publication_date` | `lower(abstract)` |
| `patents.claims` | key above plus `claim_number` | the publication's dates | `text` |
| `academic.catalog` | `paper_key` | `published_at` | `title` (case-sensitive words) |
| `openalex.works` | `id` | `publication_date` | `search_text_lc` (title only) |
| `github.repos` | `owner_lc, name_lc` | `first_full_visit_at` (archive visit) | `name_lc` |
| `github.documents` | `source, external_id` | `metadata.repo.created_at` (forge), `original_timestamp` | `lower(content_text)` |
| `packages.catalog` | `package_key` | `first_published_at`, `latest_release_at` | `name` |
| `mailing_lists.messages` | `message_key` | `original_timestamp` | `lower(payload)` |
| `hackernews.items` | `hn_id` | `original_timestamp` | `search_text_lc` |
| `twitter.tweets` | `tweet_id, version` | `original_timestamp` (bound by `bucket_date`) | `search_text_lc` |
| `crawl.pages` | `url, observed_on` | `observed_on` (observation only) | `lower(text)` |
