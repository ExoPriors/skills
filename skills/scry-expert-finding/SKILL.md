---
name: scry-expert-finding
description: >-
  Use when a question asks who speaks about a topic with authority: who the
  experts are, who wrote about it longest, whose research is most cited, which
  handles answer it well, or whether a name on one platform is the same person
  elsewhere. Walks openalex.works, openalex.authors and openalex.author_works
  for citation and tenure; hackernews.items, stackexchange.posts,
  reddit.comments, forums.posts, quora.answers and quora.writers for volume and
  reception; the historical Twitter archive with twitter.users for
  self-description; persons.links for cross-source resolution.
---

# Expert finding

One aggregate per source family, keyed on its author column, ranks who writes about a topic by volume, tenure, reception and citation; open leads then decide which handles are one person. It settles "who should I read on this" with a cited row behind each name.

## When to use

- Who are the experts on X, and by which measure: volume, tenure, reception, citation.
- Whose research on X is most cited, and where those authors sit.
- Which handles answer X questions well on Stack Exchange, Reddit, Hacker News, forums or Quora.
- Who has written about X longest.
- Is this handle the same person as that author.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Method

1. Fix the topic as tokens: the rarest token (`hasToken(search_text_lc, 'homomorphic')`), the phrase confirmed with `positionCaseInsensitive` when the token has a second meaning. Lexical, not semantic: a ranking is a count and needs an exact predicate; semantic retrieval only widens the phrase list beforehand.
2. Citation authority on `openalex.works`, keyed on `a.author.id` from `ARRAY JOIN authorships AS a`, `LIMIT 1 BY id` before the join: `sum(cited_by_count)`, `count()`, `min`/`max(publication_year)`. Profile the leaders in `openalex.authors` by `id IN (...)`: `tupleElement(summary_stats, 'h_index')`, `orcid_norm`, `last_known_institutions[1].display_name`; career tenure from `openalex.author_works` keyed `author_id`, `publication_year > 0`.
3. Discussion volume, tenure and reception: one aggregate per family, `GROUP BY` its author key, with `count()`, `min`/`max` of its time column and its reception column (Families below), the cheap partition filtered first (`site`, `subreddit` with `created_utc` bounds, `site_key`, `kind`). Academic step for a topic with a literature, discussion families for one with a practice, the whole set when the question asks who bridges both.
4. Cheap sibling before wide relation: `reddit.comments_popular` before `reddit.comments`, `x_open.tweets` before `twitter.tweets`; the historical Twitter archive is read one `bucket_date` month at a time, revisions folded (Traps below). Widen when the sibling's roster is thin.
5. Denominator discipline: volume nominates, never ranks. For each family's leaders divide on-topic items by that author's total items in the same family (`countIf(hasToken(...)) / count()` under `original_author IN (...)`); a share is stated with what it divides by, a rate with its window. Reception is per family and never summed across families (citations, story upvotes, accepted answers, comment score, forum upvotes and Quora `signal` are different units): one table per family, the same person appearing in several.
6. Resolve to a person from open leads first: `orcid_norm` and `display_name` on `openalex.authors`; `display_name`, `website` and `hasToken(bio_lc, ...)` on `twitter.users`, the indexed way in; Stack Exchange `uri`; forum `author_profile_url`. `persons.links` carries resolved clusters; access is reviewed and requested by writing to hi@scry.io. `persons.link_coverage` is open and gives the linked share per platform, the denominator of a resolution claim.

## Worked walk

Question: who speaks with authority about homomorphic encryption?

**1. Citation authority: works on the phrase, unnested to authors.**
```sql
SELECT a.author.id AS author_id, a.author.display_name AS name, count() AS works,
       sum(cited_by_count) AS cited, min(publication_year) AS first_year, max(publication_year) AS last_year
FROM (SELECT id, authorships, cited_by_count, publication_year FROM openalex.works
      WHERE hasAllTokens(search_text_lc, ['homomorphic', 'encryption'])
        AND positionCaseInsensitive(search_text_lc, 'homomorphic encryption') > 0
      ORDER BY updated_date DESC LIMIT 1 BY id) ARRAY JOIN authorships AS a
GROUP BY author_id, name ORDER BY cited DESC LIMIT 20
```
Gentry, Vaikuntanathan, Brakerski, Halevi and Cheon lead by citation while Cheon leads by work count; both orders go in the answer; `openalex.authors` on these ids adds h-index, ORCID and institution (verified 2026-09-25)

**2. Hacker News volume, kind, reception and tenure.**
```sql
SELECT original_author AS author, count() AS items, countIf(kind = 'post') AS stories,
       sumIf(upvotes, kind = 'post') AS story_upvotes, min(original_timestamp) AS first_seen, max(original_timestamp) AS last_seen
FROM hackernews.items
WHERE hasToken(search_text_lc, 'homomorphic') AND NOT is_deleted AND NOT dead
GROUP BY author ORDER BY items DESC LIMIT 20
```
zacchj leads on items, almost entirely story submissions; blintz has fewer items but the most story upvotes; godelski only comments: volume, kind and reception disagree, so step 3 asks how focused each is (verified 2026-09-25)

**3. Denominator: on-topic share of each handle's whole output.**
```sql
SELECT original_author AS author, countIf(hasToken(search_text_lc, 'homomorphic')) AS on_topic,
       count() AS total, round(on_topic / total, 3) AS share
FROM hackernews.items
WHERE original_author IN ('zacchj', 'blintz', 'rhindi', 'godelski') AND NOT is_deleted AND NOT dead
GROUP BY author ORDER BY share DESC LIMIT 20
```
zacchj about two thirds on topic, rhindi a third, blintz under a tenth, godelski a rounding error; the generalist drops out, the focused handles stay (verified 2026-09-25)

**4. Reddit regulars in the topic's subreddits, readings folded.**
```sql
SELECT author, count() AS comments, sum(score) AS score, min(created_utc) AS first_seen, max(created_utc) AS last_seen
FROM (SELECT id, author, score, created_utc FROM reddit.comments
      WHERE subreddit IN ('crypto', 'cryptography') AND created_utc >= '2015-01-01'
        AND hasToken(search_text_lc, 'homomorphic') AND author != '[deleted]'
      ORDER BY state_observed_at DESC LIMIT 1 BY id)
GROUP BY author ORDER BY comments DESC LIMIT 20
```
Natanael_L leads on comments and score with tenure across the window and the rest far behind: one regular, not a community, and the answer says so (verified 2026-09-25)

**5. Resolution lead: self-descriptions in the archive's user profiles.**
```sql
SELECT author_id, argMax(handle, observed_on) AS handle, argMax(display_name, observed_on) AS name,
       argMax(followers, observed_on) AS followers_latest, argMax(website, observed_on) AS website,
       left(argMax(bio, observed_on), 100) AS bio
FROM twitter.users
WHERE hasToken(bio_lc, 'homomorphic')
GROUP BY author_id ORDER BY followers_latest DESC LIMIT 20
```
Projects and companies outrank people on followers; jeremyjkun names the field, an employer and a website, a lead to confirm against `openalex.authors.display_name`, not yet a resolution (verified 2026-09-25)

## Reading the answer

- Cite the row, not the aggregate: one item row per named author from the ranking family, with its id, url column (`uri` on Hacker News, Stack Exchange and forums; `id` and `link_id` on Reddit; `doi` or work `id` on OpenAlex; `url` on Quora), time column and author key.
- State the window each family reached from the response `coverage` block and the `bucket_date` months read on the archive; a family whose extent ends before the question's window ranks the older period, said as such.
- Empty means a wrong probe before it means absence: the token spelled another way, the wrong `site` or `subreddit`, a window outside the extent, `twitter.users` entered by `handle =` instead of `author_id`. `coverage.empty_result_means` says `empty_by_declaration` when the relation is not served to this key (`persons.links` unadmitted), `absent_in_landed_extent` when the window lies outside what landed, `undeclared` when the engine cannot say.

## Traps

- Alias collisions: `api` is a Hacker News handle and a common token; a Reddit `author`, a Hacker News `original_author` and an archive handle spelled alike are three accounts until a lead (ORCID, website, bio, profile URL) joins them.
- Time columns differ per family and `bucket_date` is the archive's partition, not the post time; tenure is `min`/`max` of the family's own column. OpenAlex `min(publication_year)` can predate a career through merged author records, and `last_known_institutions` can name the wrong body: cite both as OpenAlex's fields.
- Duplicates across observations: works across snapshots (`LIMIT 1 BY id`), archive tweets across revisions (`argMax(col, version) GROUP BY tweet_id`), Reddit comments across readings (`ORDER BY state_observed_at DESC LIMIT 1 BY id`), twitter.users across days (`argMax(col, observed_on) GROUP BY author_id`; `max(followers)` is a peak). An unfolded count ranks who was observed most often.
- A token that means two things: `homomorphic` also names hashing and signatures; confirm the phrase with `positionCaseInsensitive` or `hasAllTokens` before quoting a number.
- Extent that does not reach the window: Stack Exchange ends per site on the date the index line gives, OpenAlex is a dated snapshot, `reddit.comments_popular` lacks the latest days, and `quora.writers` is a scored roster from which a `quora.answers` volume leader can be absent. Read `?mode=index` before stating a period.
- Volume ranks promoters: a month of the archive on this topic ranks a promotional cluster and Quora's top answerer by volume is farm-shaped; reception, share and tenure decide.
- Author columns differ per forum site: `original_author` on lesswrong and devto, `author_handle` on Discourse sites, hence `coalesce(nullIf(author_handle, ''), original_author)` under `site_key`; Stack Exchange `original_author` is mostly empty, so its key is `original_author_id`.

## Families

- `openalex.works`: key `a.author.id` from `ARRAY JOIN authorships AS a`; time `publication_year`; text `search_text_lc` (title); reception `cited_by_count`.
- `openalex.authors`: key `id`; time `updated_date`; text `search_text_lc` (names); `orcid_norm`, `summary_stats.h_index`, `cited_by_count`.
- `openalex.author_works`: key `author_id`, `work_id`; time `publication_year`; no text.
- `hackernews.items`: key `original_author`; time `original_timestamp`; text `search_text_lc`; reception `upvotes` on `kind = 'post'`.
- `stackexchange.posts`: key `original_author_id` under `site`; time `original_timestamp`; text `search_text_lc`; reception `score`, `is_accepted`.
- `reddit.comments` (sibling `reddit.comments_popular`): key `author` under `subreddit`; time `created_utc`; text `search_text_lc`; reception `score`.
- `forums.posts`: key `coalesce(nullIf(author_handle, ''), original_author)` under `site_key`; time `original_timestamp`; text `lower(payload)`; reception `upvotes` where the site scores.
- `twitter.tweets`, the historical Twitter archive (sibling `x_open.tweets`): key `author_id`; time `original_timestamp`, partition `bucket_date`; text `search_text_lc`; reception `like_count`.
- `twitter.users`: key `author_id`; time `observed_on`; text `bio_lc`; `handle`, `display_name`, `website`, `followers`.
- `quora.answers`: key `author_slug`; time `creation_time`; text `search_text_lc`; reception `num_upvotes`.
- `quora.writers`: key `slug`; time `observed_on`; text `topics`; `signal` shrunk by `answers_scored / (answers_scored + 5)` with `ai_farm = 0`.
- `persons.links`: key `person_id` over `subject_namespace`, `subject_external_id`; time `observed_on`; no text column; reviewed access, `persons.link_coverage` open.
