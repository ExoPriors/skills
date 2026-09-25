---
name: scry-first-mention
description: >-
  Use when a question asks when or where a term, name, phrase, or handle was
  first said, who said it first, whether a use predates a claimed coinage, or
  how a word entered a community. It orders each family by its own authored
  clock, bounds the wide relations at the running earliest, and reads the sense
  of the earliest rows. Families: hackernews.items, reddit.comments,
  twitter.tweets, x_open.tweets, forums.posts, mailing_lists.messages,
  academic.catalog, openalex.works, crawl.pages, wikipedia.articles. Traps
  named: co-occurrence, aliases, backfilled dates, a phrase older than its name.
---

# First mention

Find the earliest row carrying a string in each family, ordered by that family's own authored clock, then read the earliest rows to settle which is the first use in the asked sense. The answer is where and when a term entered the record Scry holds, with its window beside it.

## When to use

- When was "<phrase>" first said, and where: forum, list, Hacker News, Reddit, the historical Twitter archive, or a paper title.
- Who said "<phrase>" before <the credited coiner>.
- Did a name or handle exist before a given date in any family.
- When did a term enter one community, against its earliest use anywhere else.
- Which of two spellings or aliases came first.

The core `scry` skill (authentication, the query door, response fields) is assumed loaded.

## Method

1. Fix the string. Lowercase its tokens, name the rarest as the prune, and test the phrase with `hasAllTokens(<text_lc>, ['t1', 't2']) AND positionCaseInsensitive(<text>, 't1 t2') > 0`: tokens prove co-occurrence, never order. List aliases first: a hyphenated compound is one token to the word index and goes through the trigram door, `lower(<text>) LIKE '%t1-t2%'`; plurals, abbreviations, and old spellings are separate probes. Lexical, not semantic: first mention is a string question, and embeddings find the idea, which predates the name.
2. Stack the cheap clocks in one statement: `min(<clock>)` and `count()` per family, joined with `UNION ALL`, over `hackernews.items` (`original_timestamp`), `forums.posts` (`original_timestamp`), and `reddit.comments_popular` (`created_utc`). A bare fixed-size aggregate needs no LIMIT. The smallest minimum is the candidate; a family's count says whether it can carry the rest of the walk.
3. Walk the wide relations with the window closed above by the candidate, each on its own clock ascending under a LIMIT: `twitter.tweets` with `bucket_date < '<candidate>'` and `ORDER BY tweet_id ASC, version DESC LIMIT 1 BY tweet_id` (the key orders time and stops at LIMIT; `original_timestamp` sorts the whole match set); `reddit.comments` inside a closed `created_utc` window with `LIMIT 1 BY id`; `mailing_lists.messages` with `original_timestamp` floored at `'1980-01-01'` and capped at `now()`, `LIMIT 1 BY message_key`. An earlier row moves the bound. `x_open.tweets` is the cheap sibling for triage, never the authority: absence there says nothing about the archive.
4. The literature clocks: `openalex.works` on `publication_date` with `LIMIT 1 BY id` (its token index is the lowercased title alone; a January 1 date is usually year precision) and `academic.catalog` on `published_at` (the source's own date, arXiv v1 where one exists; title tokens are case-sensitive: `hasAnyTokens(title, ['Word', 'word'])`).
5. Attestation floors: `crawl.pages` (`observed_on`, `observed_at`) and `wikipedia.articles` (snapshot rows carry NULL `original_timestamp`; the text is the current revision) date Scry's observation. They bound "existed by", never "first said".
6. Read the sense. Hydrate the earliest rows of the winning family (on `twitter.tweets`, `argMax(<col>, version) GROUP BY tweet_id`, a blank `author_handle` resolved through `twitter.users`), read them, and take the first row in the asked sense.
7. Denominators: a share or rate names its divisor, the same window's `count()` on the same relation from a second statement, never a figure from another family, whose clock and grain differ.

## Worked walk

When and where did "mechanistic interpretability" first appear as the name of the field?

**Stack the cheap clocks.**

```sql
SELECT 'hackernews.items' AS family, toDateTime(min(original_timestamp)) AS first_at, count() AS hits FROM hackernews.items WHERE hasAllTokens(search_text_lc, ['mechanistic', 'interpretability']) AND positionCaseInsensitive(search_text_lc, 'mechanistic interpretability') > 0 UNION ALL SELECT 'forums.posts', toDateTime(min(original_timestamp)), count() FROM forums.posts WHERE hasAllTokens(lower(payload), ['mechanistic', 'interpretability']) AND positionCaseInsensitive(payload, 'mechanistic interpretability') > 0 UNION ALL SELECT 'reddit.comments_popular', toDateTime(min(created_utc)), count() FROM reddit.comments_popular WHERE hasAllTokens(search_text_lc, ['mechanistic', 'interpretability']) AND positionCaseInsensitive(search_text_lc, 'mechanistic interpretability') > 0
```

Forums 2021-08-04, Hacker News 2022-08-16, popular Reddit 2023-02-19; the forum row is the candidate and its count carries the walk. (verified 2026-09-25)

**Bound the historical Twitter archive above the candidate.**

```sql
SELECT tweet_id, author_id, original_timestamp, text FROM twitter.tweets WHERE bucket_date < '2021-08-04' AND hasAllTokens(search_text_lc, ['mechanistic', 'interpretability']) AND positionCaseInsensitive(search_text_lc, 'mechanistic interpretability') > 0 AND NOT startsWith(text, 'RT @') ORDER BY tweet_id ASC, version DESC LIMIT 1 BY tweet_id LIMIT 10
```

Two rows, 2019-01-23 and 2019-07-02, both with a blank handle: nothing else in the archive precedes the candidate, and the key made the window cheap. (verified 2026-09-25)

**Hydrate and read the sense.**

```sql
SELECT t.tweet_id, u.handle, t.original_timestamp, t.text FROM (SELECT tweet_id, author_id, argMax(original_timestamp, version) AS original_timestamp, argMax(text, version) AS text FROM twitter.tweets WHERE tweet_id IN (1088136076462604289, 1146154185047584783) GROUP BY tweet_id, author_id) AS t LEFT JOIN (SELECT author_id, argMax(handle, observed_on) AS handle FROM twitter.users WHERE author_id IN (223560830, 49829568) GROUP BY author_id) AS u ON u.author_id = t.author_id ORDER BY t.tweet_id ASC LIMIT 5
```

The handles resolve to a genomics institute and a biotech founder; both posts use the words for drug-discovery models, not the field. The phrase predates its name, and the forum candidate stands. (verified 2026-09-25)

**Walk wide Reddit below the popular first.**

```sql
SELECT id, subreddit, author, created_utc, score FROM reddit.comments WHERE created_utc >= '2016-01-01' AND created_utc < '2023-02-19' AND hasAllTokens(search_text_lc, ['mechanistic', 'interpretability']) AND positionCaseInsensitive(search_text_lc, 'mechanistic interpretability') > 0 ORDER BY created_utc ASC LIMIT 1 BY id LIMIT 5
```

First is 2022-05-26 in r/ControlProblem at a score of 3, nine months before the popular subset's first: the cheap sibling is triage and late by construction. Still after the forum candidate. (verified 2026-09-25)

**The literature clock.**

```sql
SELECT id, publication_date, publication_year, type, title FROM openalex.works WHERE hasAllTokens(search_text_lc, ['mechanistic', 'interpretability']) AND positionCaseInsensitive(search_text_lc, 'mechanistic interpretability') > 0 ORDER BY publication_date ASC LIMIT 1 BY id LIMIT 8
```

Two 2023-01-01 rows sort ahead of the arXiv v1 deposits of 2023-01-11 and 2023-01-12; January 1 is year precision, so the first titled paper is the 2023-01-11 preprint. Verdict: the name enters the record on 2021-08-04 on the EA Forum, in a podcast transcript, after two 2019 plain-language uses. (verified 2026-09-25)

## Reading the answer

- Cite the row: key, URL, authored timestamp, author. Hacker News `hn_id` and `uri`; Reddit `id` and the permalink `concat('https://www.reddit.com/r/', subreddit, '/comments/', substring(link_id, 4), '/_/', id, '/')`; the historical Twitter archive `https://x.com/i/status/<tweet_id>` with the handle from `twitter.users`; forums and lists `uri`; papers `doi_norm` or `arxiv_id`.
- State the window from the response's `coverage` block: "earliest in <relation>, extent <min>..<max>, known holes <list>". A first mention is a claim about that window, never about the world. A relation whose block carries no extent (`mailing_lists.messages`, `crawl.pages`, `wikipedia.articles`) gets "earliest indexed" and no window claim.
- Present per family, then the verdict: the earliest row in the asked sense, earlier plain-language uses listed as such, and the families that returned nothing named with their windows.
- An empty result is a wrong probe before it is an absence. Read `zero_rows.establishes`: `nothing` means widen the alias list or the window; `absent_in_landed` inside a measured extent with no hole is absence from indexed data. Reddit comments removed before capture are absent. Access to a reviewed relation is requested by writing to hi@scry.io.

## Traps

- Co-occurrence is not the phrase: on `forums.posts` the bare token pair first co-occurs on 2018-07-11, three years before the phrase.
- A phrase predates its name: the 2019 archive rows are the words in another field. Read the earliest rows; never take the minimum blind.
- Aliases: `mechanistic-interpretability` is one token to the word index and is found only through the trigram door; "mech interp", plurals, and case variants are separate probes.
- Clocks differ per family: `original_timestamp` or `created_utc` is authored time; `first_observed_on`, `observed_on`, `observed_at`, `state_observed_at`, and `retrieved_on` are reading time and cluster in the months the family was loaded. `crawl.pages` has no authored clock.
- Backfilled and bogus dates: `mailing_lists.messages` keeps the Date header as written, with rows before 1980 and after today, so floor and cap the window; some forum sites read 1970-01-01 where the source had no time; `openalex.works` floors `publication_date` at 1900-01-01 and reads January 1 for year-only dates; `academic.catalog` `published_at` can be NULL or month precision.
- Duplicates across observations: archive revisions (`LIMIT 1 BY tweet_id`, `uniqExact(tweet_id)`), Reddit readings (`LIMIT 1 BY id`), list messages (`LIMIT 1 BY message_key`), page versions (`LIMIT 1 BY url`), works listed twice (`LIMIT 1 BY id`). A duplicate never moves the minimum, but it doubles a count.
- Extent short of the window: `academic.catalog` measures its extent on `observed_on`, a fold date, and says nothing about publication years; `reddit.comments_popular` is the score subset and its first is late; the `x_open.tweets` slice reaches back only through donated archives; `wikipedia.articles` holds the current revision, so an old page's text says nothing about when a term was added.
- Two senses of one token: `transformer`, `agent`, `alignment`; add a discriminating token to the prune, then read.

## Families

| relation | key | time column | text column |
| --- | --- | --- | --- |
| `hackernews.items` | `hn_id` | `original_timestamp` | `search_text_lc` |
| `reddit.comments` | `id` (access key `subreddit, created_utc, id`) | `created_utc` | `search_text_lc` |
| `reddit.comments_popular` | `id` | `created_utc` | `search_text_lc` |
| `twitter.tweets` | `tweet_id`, `version` | `original_timestamp`; order by `tweet_id`, bound `bucket_date` | `search_text_lc` |
| `x_open.tweets` | `tweet_id` | `original_timestamp`; order by `tweet_id` | `search_text_lc` |
| `forums.posts` | `post_key` | `original_timestamp` | `lower(payload)` |
| `mailing_lists.messages` | `message_key` | `original_timestamp` (Date header as written, nullable) | `lower(payload)` |
| `academic.catalog` | `paper_key` | `published_at` (source's own, nullable) | `title`, case-sensitive tokens |
| `openalex.works` | `id` | `publication_date` (floored 1900-01-01) | `search_text_lc` (title only) |
| `crawl.pages` | `url` versioned by `observed_on` | `observed_on`, `observed_at` (observed only) | `lower(text)` |
| `wikipedia.articles` | `page_id` | `original_timestamp` (NULL on snapshot rows) | `lower(payload)` |
