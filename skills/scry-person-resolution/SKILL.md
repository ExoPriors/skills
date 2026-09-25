---
name: scry-person-resolution
description: >-
  Use when a question is about one person across sources: resolving a handle,
  ORCID, name or slug to its account key, reading the latest profile behind an
  author column, following the same public name from the historical Twitter
  archive to OpenAlex, Quora, Prediction Archive, conference records or the
  frozen social archives, or measuring how much of a corpus is attributable to
  a resolved person. Relations: persons.links, persons.link_coverage,
  persons.content_coverage, events.records, twitter.users, x_open.users,
  social.users, openalex.authors, quora.writers, predictionarchive.predictors.
---

# Person and identity resolution

Each corpus family names its authors with its own key; the profile relations here turn that key into a person-shaped row, and the `persons.*` views measure how far cross-platform linking reaches, deterministically over self-published identifiers, never stylometry or behavioral inference.

## When to use

- A handle, ORCID, name or slug needs its account key before the family's content relation can be read by author.
- The latest profile (bio, followers, affiliations, scorecard) behind an author column.
- The same public name followed across families, each hit citing the family's own key.
- Which platforms person linking covers, and what share of a corpus source is attributable to a resolved person.
- Who attended or spoke at a conference, with the links they published.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.
Plain SQL on the family's content relation is the better tool when the question is about what was said, not who said it; come here to resolve or hydrate the author.

## Surfaces

| relation | what it does | required arguments or columns | what comes back | cost or limit the contract states |
| --- | --- | --- | --- | --- |
| `persons.links` | one row per linked public account, grouped by `person_id` | `subject_namespace`, `subject_external_id` or `person_id`; `generation` | `person_id`, `cluster_size`, `namespaces`, `key_kinds`, `method` | reviewed access; the public projection has no rows by declaration |
| `persons.link_coverage` | per platform and generation, linked accounts over the known account population | `generation`, `platform` | `linked_accounts`, `total_accounts`, `coverage`, `observed_on` | daily; one row set per generation |
| `persons.content_coverage` | per corpus source and generation, content items attributable to a resolved person | `generation`, `source` | `state`, `reason`, `content_total`, `content_linked`, `fraction` | daily; `fraction` is meaningful on `state = 'measured'` |
| `events.records` | conference records as JSON envelopes; the record is `payload.record`, `source_record_id` is `<record_type>/<key>` | `source_key`; `startsWith(source_record_id, '<type>/')` | attendee `name`, `headline`, `urls`, `profile_url`; session `title`, `host_name`, `date`; attendee_record and event_record `display_name`, `event_slug` | scan; identity-resolution record types are row-filtered (reviewed access); applications are redacted |
| `twitter.users` | profiles from the historical Twitter archive, one observation per row | `author_id` is the only keyed read; `bio_lc` tokens are indexed | `handle`, `bio`, `followers`, `account_created_at`, `role`, `observed_on` | `handle = ...` reads the whole relation; `argMax(col, observed_on) GROUP BY author_id` |
| `x_open.users` | latest-known profile per author of `x_open.tweets` | `author_id` or `handle` | `handle`, `followers`, `x_open_posts`, `slices`, `first_post`, `last_post`, `follower_band` | hourly; duplicate refreshes coexist briefly, `argMax(col, observed_hour)` for exact latest |
| `social.users` | profiles of the frozen voat, parler, telegram and truth_social archives | `platform` first, then `username` or `native_id`; `user_key = '<platform>/<native_id>'` | `username`, `bio`, `follower_count`, raw `payload` | frozen; four-branch union, gab and discord ship no profile rows |
| `openalex.authors` | OpenAlex author profiles | `id`, `orcid_norm` (bare uppercase), `search_text_lc` tokens | `display_name`, `works_count`, `cited_by_count`, `summary_stats`, `affiliations`, `topics` | frozen; an author's works come from `openalex.author_works`, not here |
| `quora.writers` | one scored row per writer | `slug`, `ai_farm` | `answers_scored`, `median_upvotes`, `signal`, `observed_on` | rank by `signal * answers_scored / (answers_scored + 5)`; `topic`/`topics` nearly always empty |
| `predictionarchive.predictors` | one row per tracked predictor with the site's headline scorecard | `predictor_id`; `name` is a scan | `name`, `about`, `accuracy_pct`, `graded`, `total_predictions`, `pending`, `uri` | figures are the site's own at `observed_on`; `graded` excludes indeterminate |

## Idioms

- Resolve the key, then read by key. `twitter.author_timeline(handle = '<handle>', limit = 1)` returns `author_id` for the archive; `orcid_norm = '<BARE-UPPERCASE-ORCID>'` or `hasAllTokens(search_text_lc, ['<first>', '<last>'])` returns the OpenAlex `id`; Quora is keyed by `slug`, Prediction Archive by `predictor_id`, the frozen archives by `(platform, username)` or `(platform, native_id)`.
- Author columns are the joins: `twitter.tweets.author_id` and `x_open.tweets.author_id` to their profile relations; `social.posts.author` to `social.users.native_id` within one `platform`; `openalex.author_works.author_id` to `openalex.authors.id`; `quora.answers.author_slug` to `quora.writers.slug`; `predictionarchive.predictions.predictor_id` to `predictors`.
- Latest state on observation relations: `argMax(col, observed_on) GROUP BY author_id` on `twitter.users`, output aliases distinct from filtered column names; `max(followers)` is the peak, not the latest. Dated profile history is `twitter.user_observations` by `author_id`.
- Discovery without a key: a rare bio token on `twitter.users` (`hasToken(bio_lc, '<token>')`), name tokens on `openalex.authors`, `positionCaseInsensitive(name, '<name>') > 0` on predictors, `lower(ifNull(slug, '')) LIKE '%<needle>%'` on writers.
- Generations: both coverage views publish under one ISO-timestamp `generation`; filter `generation = (SELECT max(generation) FROM <view>)`. `platform` holds flat namespace names plus `forum:<name>` rows.
- Events: `source_key` first, then the record type prefix, then `JSONExtractString(payload, 'record', '<field>')` for scalars and `JSONExtractRaw` for arrays; the event is `record.event_slug`.
- One statement across families: `SELECT * FROM ((SELECT ... LIMIT n) UNION ALL (SELECT ... LIMIT n)) LIMIT m`, each branch labelled with a `source` column and the family's key column.
- Cite by key: `author_id` with `observed_on`, the OpenAlex `id` URL, `predictor_id` and `uri`, the Quora `slug`, `user_key`, `source_record_id`.

## Worked calls

**Which platforms does person linking reach, in the latest generation?**
```sql
SELECT platform, linked_accounts, total_accounts, round(coverage, 3) AS coverage
FROM persons.link_coverage
WHERE generation = (SELECT max(generation) FROM persons.link_coverage)
ORDER BY linked_accounts DESC
LIMIT 12
```
One row per platform namespace; `coverage` is `linked_accounts / total_accounts`, so read it beside the denominator. (verified 2026-09-25)

**What share of each corpus source is attributable to a resolved person?**
```sql
SELECT source, state, reason, content_total, content_linked, round(fraction, 4) AS fraction
FROM persons.content_coverage
WHERE generation = (SELECT max(generation) FROM persons.content_coverage)
ORDER BY fraction DESC
LIMIT 50
```
One row per source; `state = 'measured'` rows carry a fraction, the other states explain themselves in `reason`. (verified 2026-09-25)

**Resolve a handle and read its latest profile from the historical Twitter archive.**
```sql
SELECT author_id, argMax(handle, observed_on) AS handle_latest,
       argMax(followers, observed_on) AS followers_latest,
       argMax(bio, observed_on) AS bio_latest, count() AS observations
FROM twitter.users
WHERE author_id IN (SELECT author_id FROM twitter.author_timeline(handle = 'NeelNanda5', limit = 1))
GROUP BY author_id
LIMIT 10
```
One row for the account; `observations` counts the profile rows folded, and the response's `coverage` block names the grain. (verified 2026-09-25)

**Who attended a conference, with the links they published?**
```sql
SELECT JSONExtractString(payload, 'record', 'name') AS name,
       JSONExtractRaw(payload, 'record', 'urls') AS urls,
       JSONExtractString(payload, 'record', 'profile_url') AS profile_url
FROM events.records
WHERE startsWith(source_record_id, 'attendee/')
  AND JSONExtractRaw(payload, 'record', 'urls') NOT IN ('[]', '')
LIMIT 3
```
One row per attendee record; `urls` is a JSON array of self-published links and `profile_url` the citation. (verified 2026-09-25)

**An author by ORCID.**
```sql
SELECT id, display_name, works_count
FROM openalex.authors
WHERE orcid_norm = '0000-0002-9322-3515'
LIMIT 3
```
One row when the ORCID is bound; `id` is the OpenAlex URL that keys `openalex.author_works`. (verified 2026-09-25)

**The same public name across three families in one statement.**
```sql
SELECT * FROM (
  (SELECT 'openalex' AS source, id AS key, display_name AS label FROM openalex.authors
   WHERE hasAllTokens(search_text_lc, ['tyler', 'cowen']) ORDER BY cited_by_count DESC LIMIT 3)
  UNION ALL
  (SELECT 'predictionarchive' AS source, predictor_id AS key, name AS label FROM predictionarchive.predictors
   WHERE positionCaseInsensitive(name, 'tyler cowen') > 0 ORDER BY total_predictions DESC LIMIT 3)
  UNION ALL
  (SELECT 'twitter-archive' AS source, toString(author_id) AS key, author_handle AS label
   FROM twitter.author_timeline(handle = 'tylercowen', limit = 1))
) LIMIT 10
```
One row per candidate per family, keyed by that family; name tokens admit namesakes, so confirm OpenAlex rows by ORCID or affiliation. (verified 2026-09-25)

## Traps

- A statement needs a literal LIMIT unless it is a bare aggregate or a read keyed by the relation's row key; each UNION branch needs its own LIMIT, the outer one sits on the derived table.
- `persons.links` answers with zero rows and `zero_rows.cause = 'empty_by_declaration'`: nothing was searched, so the zero says nothing. Access is reviewed and requested by writing to hi@scry.io.
- The identity-resolution record types of `events.records` (`author_link`, `person_link`, `person_alias`, `person_evidence`, `corpus_match`) are row-filtered from the public projection; a record-type census that lacks them shows the filter, not an absent corpus.
- `handle = '<h>'` on `twitter.users` reads the whole relation; resolve through `twitter.author_timeline` first. `count()` counts observations; count accounts with `uniqExact(author_id)`.
- `x_open.users` holds only authors of the `x_open` slice: a handle absent there (`zero_rows.cause = 'searched'`) can still be in `twitter.users`.
- `social.users`: `user_key` without `platform` scans each branch and answers many times slower; parler rows are opaque ids with bio only.
- `quora.writers`: raw `signal DESC` is dominated by single-answer accounts: rank by the shrunk form, report `answers_scored`, filter `ai_farm = 0`.
- `openalex.authors`: `orcid_norm` is the bare uppercase id, often empty; `h_index` is `tupleElement(summary_stats, 'h_index')`.
- `predictionarchive.predictors`: `accuracy_pct = correct / graded` with indeterminate excluded; one name can sit on two rows (solo and joint bylines).

## Composes with

- `scry-twitter-archive`: an `author_id` from here keys `twitter.tweets`, `twitter.author_tweets`, `twitter.following` and `twitter.followers`; `twitter.follow_coverage` gives the follow-list denominators.
- `scry-academic`: the OpenAlex `id` walks `openalex.author_works` to `openalex.works` and on to `academic.catalog` by DOI.
- `scry-forums-and-qa`, `scry-social-posts`, `scry-prediction-markets`: `quora.answers`, `social.posts` and `predictionarchive.predictions` hydrate by the keys above.
- The core `datalog` pivots (`twitter.by`, `openalex.authors`, `hackernews.by`, `forums.by`, `bluesky.by`) walk from a person key to items and back in one program.
