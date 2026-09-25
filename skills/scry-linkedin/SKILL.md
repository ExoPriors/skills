---
name: scry-linkedin
description: >-
  Use when a question is about public LinkedIn posts (who posted on a topic,
  when, with what like and comment counts, and what the captured comment
  thread said), LinkedIn member profiles (name, headline, current company,
  work and education history, location, follower count), or LinkedIn company
  pages (industry, headcount band, headquarters, founding year, specialties,
  follower count), as reconstructed from Internet Archive Wayback captures.
  Relations: linkedin.posts, linkedin.profiles, linkedin.companies.
---

# LinkedIn posts, profiles, and companies

Public LinkedIn pages as the Internet Archive captured them, reconstructed into three relations: posts with their comment threads, member profiles, and company pages. Each is a set of dated captures, so most questions dedupe to the newest capture before they count.

## When to use

- Which LinkedIn posts mention a phrase, by whom, when, and how they were received.
- How a topic's share of posts moved month by month or year by year.
- Who posts most about a topic, and how large their audience is.
- A person's headline, current company, work history and location; who lists a company in their history.
- Companies by industry, country, headcount band or page text, ranked by followers.
- The captured comment thread under a post.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Doors

Tier and lag are the `schema?mode=index` line as read 2026-09-25; the live index is the authority. None of these relations is reviewed-access. Coverage is what the Archive captured, historical and discontinuous: an absent row is not-captured.

| relation | what one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `linkedin.posts` | one capture of one public post: author slug and name, URL, type, headline, body, counts at capture, comment thread as JSON | `post_id` | `date_published` (the post's clock; `1970-01-01` when the page did not expose it); `archive_captured_at` (capture) | tokens on `lower(concat(headline, ' ', body))`; 3-grams on `lower(ifNull(concat(headline, ' ', body), ''))` | depth, lag 17s. The wide relation; `post_id` and the text lanes prune, nothing else does |
| `linkedin.profiles` | one capture of one member profile: name, headline, description, current company, `works_for` and `alumni_of` history as JSON, location, follower count | `public_id` | `archive_captured_at` only | tokens on `lower(concat(name, ' ', headline, ' ', description))`; 3-grams on the `ifNull` form | depth, lag 30m. The small sibling for who-questions; only `public_id` prunes |
| `linkedin.companies` | one capture of one company page: name, slogan, description, website, headcount and band, industry, founding string, type, address, specialties, followers | `slug` | `archive_captured_at` only | tokens on `lower(concat(name, ' ', slogan, ' ', description, ' ', specialties))`; 3-grams on the `ifNull` form | depth, lag 3d. The small sibling for company questions; only `slug` prunes |

## Idioms

- Token first, phrase second. The text lanes are expressions, not columns: `hasToken(lower(concat(headline, ' ', body)), 'stellarator')` or `hasAllTokens(..., ['room', 'temperature'])` with lowercase tokens, then `positionCaseInsensitive(body, 'room temperature superconductor') > 0` to confirm the phrase. A hyphenated needle goes to the 3-gram lane: `lower(ifNull(concat(headline, ' ', body), '')) LIKE '%lk-99%'`. `scry_lex('"high temperature superconductor" -fusion')` expands to the relation's own lanes.
- Newest capture wins. `ORDER BY archive_captured_at DESC LIMIT 1 BY post_id` in a subquery, then order the outer query as the question wants; `uniqExact(post_id)` counts posts. The same with `public_id` on profiles and `slug` on companies. Like and comment counts differ between captures of one post, so sum them only after the dedup.
- Dated posts. `date_published` is the post's clock; add `date_published >= '2003-01-01'` to drop the `1970-01-01` sentinel. A window on it does not prune; the token does, so anchor the token first.
- Small sibling first. A who-question starts on `linkedin.profiles`, a company question on `linkedin.companies`, both cheap to read whole under a `LIMIT`; then `linkedin.posts` with `author_public_id = '<slug>'` for the page's posts.
- Keyed reads. `post_id = '<id>'`, `public_id = '<slug>'` and `slug = '<slug>'` are the indexed paths. A join from posts to profiles is `public_id IN (SELECT author_public_id FROM linkedin.posts WHERE <token lane>)`, which the engine prunes.
- Source URL from a row: posts carry `url`; a profile is `same_as` when set, else `concat('https://www.linkedin.com/in/', public_id)` (legacy `pub/...` ids sit under `/pub/`); a company is `concat('https://www.linkedin.com/company/', slug)`.
- Ids across the family. `author_public_id` is the posting page's slug: a member's `public_id` or a company's `slug`, so join both and see which side answers. A profile's employers are slugs inside `works_for`: `extractAll(works_for, '/company/([^"/?]+)')` lines up with `linkedin.companies.slug`.
- JSON columns. `works_for`, `alumni_of`, `member_of`, `comments`, `posts` and `raw_jsonld` are JSON strings. A comment thread is `arrayJoin(JSONExtractArrayRaw(comments)) AS c` over the newest capture, read with `JSONExtractString(c, 'author_name')`, `'text'`, `'date'`, `JSONExtractUInt(c, 'likes')`; `comments_captured` counts them.

## Worked queries

**Which posts say "room temperature superconductor", newest first?**

```sql
SELECT post_id, author_public_id, author_name, date_published, like_count, url
FROM (
  SELECT post_id, author_public_id, author_name, date_published, like_count, url, body
  FROM linkedin.posts
  WHERE hasAllTokens(lower(concat(headline, ' ', body)), ['room', 'temperature', 'superconductor'])
  ORDER BY archive_captured_at DESC
  LIMIT 1 BY post_id
)
WHERE positionCaseInsensitive(body, 'room temperature superconductor') > 0
ORDER BY date_published DESC
LIMIT 10
```

One row per post at its newest capture, with its URL; the tokens govern the read, the phrase check runs on the deduped rows. (verified 2026-09-25)

**Of dated posts published each month of 2025, what share mention layoffs?**

```sql
SELECT toStartOfMonth(date_published) AS month, uniqExact(post_id) AS posts,
       uniqExactIf(post_id, hasToken(lower(concat(headline, ' ', body)), 'layoffs')) AS layoffs_posts,
       round(layoffs_posts / posts, 4) AS share
FROM linkedin.posts
WHERE date_published >= '2025-01-01' AND date_published < '2026-01-01'
GROUP BY month
ORDER BY month
LIMIT 12
```

One row per month, the denominator (`posts`) beside the numerator, both on distinct ids; the window reads the relation whole, a few seconds. (verified 2026-09-25)

**Who wrote about stellarators, and how large is each author's audience?**

```sql
SELECT p.post_id, p.author_public_id, pr.name, pr.headline, pr.follower_count, p.like_count, p.date_published
FROM (
  SELECT post_id, author_public_id, like_count, date_published
  FROM linkedin.posts
  WHERE hasToken(lower(concat(headline, ' ', body)), 'stellarator')
  ORDER BY archive_captured_at DESC LIMIT 1 BY post_id
) AS p
INNER JOIN (
  SELECT public_id, name, headline, follower_count
  FROM linkedin.profiles
  WHERE public_id IN (SELECT author_public_id FROM linkedin.posts WHERE hasToken(lower(concat(headline, ' ', body)), 'stellarator'))
  ORDER BY archive_captured_at DESC LIMIT 1 BY public_id
) AS pr ON pr.public_id = p.author_public_id
ORDER BY pr.follower_count DESC, p.date_published DESC
LIMIT 10
```

Both sides deduped to the newest capture before the join; company-authored posts drop out, since their slug lives in `linkedin.companies` (same join on `slug`). (verified 2026-09-25)

**Which pages post most about stellarators?**

```sql
SELECT author_public_id, any(author_name) AS author, uniqExact(post_id) AS posts, sum(like_count) AS likes, max(date_published) AS latest
FROM (
  SELECT post_id, author_public_id, author_name, like_count, date_published
  FROM linkedin.posts
  WHERE hasToken(lower(concat(headline, ' ', body)), 'stellarator')
  ORDER BY archive_captured_at DESC LIMIT 1 BY post_id
)
GROUP BY author_public_id
ORDER BY posts DESC, likes DESC
LIMIT 10
```

One row per posting page, member or company; `likes` is honest only because the inner dedup ran first. (verified 2026-09-25)

**Where are the fusion energy companies, and how big are they?**

```sql
SELECT address_country, uniqExact(slug) AS companies, countIf(employees > 0) AS with_headcount,
       quantileExactIf(0.5)(employees, employees > 0) AS median_employees, max(followers) AS top_followers
FROM (
  SELECT slug, address_country, employees, followers
  FROM linkedin.companies
  WHERE hasAllTokens(lower(concat(name, ' ', slogan, ' ', description, ' ', specialties)), ['fusion', 'energy'])
  ORDER BY archive_captured_at DESC LIMIT 1 BY slug
)
GROUP BY address_country
ORDER BY companies DESC
LIMIT 10
```

One row per ISO country code, the empty code being pages without an address; `with_headcount` is the median's denominator, a 0 headcount being an unparsed field. (verified 2026-09-25)

**How did LK-99 sit inside the superconductor conversation, year by year?**

```sql
SELECT toYear(date_published) AS year, uniqExact(post_id) AS posts,
       uniqExactIf(post_id, scry_lex('lk-99')) AS lk99_posts
FROM linkedin.posts
WHERE scry_lex('superconductor') AND date_published >= '2003-01-01'
GROUP BY year
ORDER BY year
LIMIT 20
```

`scry_lex` expands each line against the relation's own lanes, so the cohort and the sub-cohort share one grammar; the sentinel year is excluded by the date floor. (verified 2026-09-25)

## Traps

- Time. Profiles and companies have no authored clock: `archive_captured_at` is when the Archive saw the page, and employment dates live inside `works_for` as `start` and `end` strings. On posts, `archive_captured_at` is never the publish date.
- Case. The token lanes are lowered, so an uppercase needle is refused by the door (`uppercase_needle_on_lowercased_column`) rather than returned empty. `hasToken(body, ...)` is case-sensitive and not the indexed lane. Exact matches on `name`, `current_company` and `industry` are case-sensitive scans.
- Value spaces. `post_type` is lowercase `post` or `video`; the contract's `'Article'` example matches nothing. Profile `location_country` mixes names and ISO codes (`'United States'` and `'US'`, `'United Kingdom'` and `'GB'`): filter with `IN` over both. Company `address_country` is ISO codes. An empty string means the page did not carry the field.
- Duplicates. Several captures of one post, each with counts as of that capture: a bare `count()` or `sum(like_count)` inflates. Dedupe to the newest capture, count with `uniqExact`.
- Old captures. Legacy `pub/<name>/<a>/<b>/<c>` public_ids, empty `job_titles`, `follower_count` 0 and empty `works_for` urls come from older page layouts: a 0 there is not-exposed before zero. `value_score` is a ranking signal, not a LinkedIn field.
- Absence. An empty result says not-captured. Counts are snapshots at capture time and say nothing about whether the post still exists on LinkedIn.
- Scans. `author_public_id`, `post_type`, a `date_published` window and a `scry_lex('/.../')` regex read the posts relation whole: cheap under a `LIMIT`, but the token anchor comes first.
- Page posts. A profile's or company's `posts` JSON holds that page's captured posts (`post_count` of them), separate from `linkedin.posts` rows.

## Cross-family joins

- `linkedin.companies.website` meets `crawl.pages.host` and `crawl.hosts.host` on `domain(website)` and `cutToFirstSignificantSubdomain(website)` (`host` is literal, `www` included or not); the same domain joins `yc.companies.website`, `twitter.users.website` and `domain(hackernews.items.outbound_url)`.
- The page URLs (`linkedin.posts.url`, a profile's `same_as`, `concat('https://www.linkedin.com/company/', slug)`) are `crawl.backlinks.target_url` under `target_host IN ('www.linkedin.com', 'linkedin.com')`: who links to a page.
- `linkedin.companies.name` and `sec.filers.name` or `names` share a company name; match lowercase, then read the `sec.*` relations by `cik` in a second statement.
