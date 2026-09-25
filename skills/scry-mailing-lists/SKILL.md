---
name: scry-mailing-lists
description: >-
  Use when a question is about mailing-list or Usenet archive messages: when
  a term or phrase first appeared on a list and who wrote it, which lists
  carried a topic and what share of their traffic it was, who posted on a
  list or where one author posted across lists, rebuilding a thread from its
  root message, finding a message by Message-ID or archive URL, or semantic
  search over list posts. Covers mailing_lists.messages (extropians, SL4,
  linux-kernel, public Google Groups, Usenet groups), the per-list roster
  mailing_lists.catalog, and embeddings.mailing_list_messages.
---

# Mailing lists

Public mailing-list and Usenet archive messages as one relation, threaded by
parent and root keys, beside a per-list catalog and a chunk-embedding sibling.
The lists the catalog names run from extropians and SL4 through linux-kernel,
public Google Groups, and Usenet groups from Internet Archive collections.

## When to use

- When a word or phrase first appeared on a list, and who wrote it.
- Which lists carried a topic, and what share of each list's traffic it was.
- A thread rebuilt from its root message, in posting order.
- One author's posting history across lists, or the loudest voices on one list.
- A message by Message-ID or archive URL, and its copies on cross-posted lists.
- Semantic search over list posts when the vocabulary is unknown.

The core `scry` skill (authentication, the query door, response fields) is assumed loaded.

## Doors

| relation | one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `mailing_lists.messages` | one archived message of one list or group | `message_key` = `<list_key>::<id>`; `message_id` is the Message-ID header | `original_timestamp` (authored: the parsed Date header, nullable); `observed_on` versions a key | `payload` (the body), indexed as `lower(payload)` for words and 3-gram substrings; `lower(original_author)` indexed; `title`, `normalized_subject` unindexed | primary, lag 12m; `list_key = '<list>'` reads one list alone; `is_deleted = 0` is the optional predicate |
| `mailing_lists.catalog` | one list per `list_key`: archive URL, `message_count` (read from messages once a day), `estimated_message_count` (the source's own figure), first and last message times | `list_key` | `first_message_at`, `last_message_at` (domain); `observed_on` | `list_name` (no index) | depth, lag 59m; the cheap roster and denominator; a list absent here can still have rows in messages |
| `embeddings.mailing_list_messages` | one Voyage-4 chunk of one message | `message_key`, `chunk_index`, `id` | `observed_on` | none; hydrate text from messages | depth, lag 4m; serves ANN; `startsWith(message_key, '<list_key>::')` scopes to one list |

## Idioms

- Roster first. `SELECT list_key, message_count, first_message_at, last_message_at, canonical_archive_url FROM mailing_lists.catalog ORDER BY message_count DESC LIMIT 20` names the lists; `list_key = '<list>'` on messages then reads that list's rows alone, because the sort key is `<list_key>::<id>`. One list can sit under several keys: `org.kernel.vger.linux-kernel` and `gmane.linux.kernel` are two collections of one list, `extropians`, `alt.extropians` and `usenet_alt_extropians` three of another.
- Tokens go through `lower(payload)`: `hasToken(lower(payload), 'rust')` and `hasAllTokens(lower(payload), ['seed', 'ai'])` with lowercase tokens; a predicate on bare `payload` is a scan. Confirm a phrase with `positionCaseInsensitive(payload, 'seed AI') > 0`. A substring of three or more characters takes the n-gram lane, `lower(ifNull(payload, '')) LIKE '%friendliness%'`. There is no `search_text_lc` on this family.
- People are a token, never an equality. `original_author` is the raw From header (name plus address, with spelling and encoding that vary by era); `hasToken(lower(original_author), 'yudkowsky')` is indexed.
- The clock is `original_timestamp`, and its bounds have their own index: a count over a window reads the index alone, while a row fetch over a long window is scattered across the lists, so pair the window with `list_key`. Values are as the sources wrote them, NULL where the header did not parse; the raw header survives in `metadata`.
- Denominators come from a second index-only count. `countIf(hasToken(lower(payload), ...))` over a window reads that window's bodies and fails the deadline on a large list; put the token in WHERE, and join the per-bucket count to a per-bucket total from the same window without the token.
- Dedup with `LIMIT 1 BY message_key` on row fetches (`observed_on` versions a key). A cross-posted message is one row per list it reached; `message_id = '<Message-ID>'` returns the copies together, so count `uniqExact(message_id)` when the unit is the message and `message_key` when it is list traffic.
- Threads: `root_message_key = '<message_key>'` returns a thread with its root, `parent_message_key = '<message_key>'` the direct replies. Both are empty on much of the older archives; `normalized_subject` within one list and window is the fallback.
- Citation: `uri` is the per-message archive page (lore.kernel.org, pipermail, nntp, mirror pages) where the source has one; otherwise the catalog's `canonical_archive_url` plus the `message_id`. Cite `message_key` as the stable Scry id.
- Semantic: mint a handle (`POST /v1/scry/embed {text, name}`), rank over `embeddings.mailing_list_messages`, hydrate by `message_key IN (...)`.

## Worked queries

**When did "seed AI" first appear on SL4, and who wrote it?**

```sql
SELECT message_key, original_author, original_timestamp, title, uri
FROM mailing_lists.messages
WHERE list_key = 'sl4'
  AND hasAllTokens(lower(payload), ['seed', 'ai'])
  AND positionCaseInsensitive(payload, 'seed AI') > 0
  AND is_deleted = 0
ORDER BY original_timestamp ASC
LIMIT 1 BY message_key
LIMIT 10
```

Earliest first, one row per message: author, subject, and the archive page in `uri`. (verified 2026-09-25)

**Which lists carried "transhumanist", against each list's size?**

```sql
SELECT m.list_key, count() AS hits, any(c.message_count) AS list_messages, any(c.canonical_archive_url) AS archive
FROM mailing_lists.messages AS m
LEFT JOIN mailing_lists.catalog AS c ON c.list_key = m.list_key
WHERE hasToken(lower(m.payload), 'transhumanist')
GROUP BY m.list_key
ORDER BY hits DESC
LIMIT 20
```

One row per list: hits beside the catalog's `message_count` and archive URL; `archive` is NULL where the catalog holds no URL. (verified 2026-09-25)

**How did Rust talk grow on linux-kernel, year by year?**

```sql
SELECT d.year, d.messages, h.rust_messages, round(h.rust_messages / d.messages, 4) AS share
FROM (
  SELECT toYear(original_timestamp) AS year, count() AS messages
  FROM mailing_lists.messages
  WHERE list_key = 'org.kernel.vger.linux-kernel'
    AND original_timestamp >= '2019-01-01' AND original_timestamp < '2026-01-01'
  GROUP BY year
) AS d
LEFT JOIN (
  SELECT toYear(original_timestamp) AS year, count() AS rust_messages
  FROM mailing_lists.messages
  WHERE list_key = 'org.kernel.vger.linux-kernel'
    AND original_timestamp >= '2019-01-01' AND original_timestamp < '2026-01-01'
    AND hasToken(lower(payload), 'rust')
  GROUP BY year
) AS h ON h.year = d.year
ORDER BY d.year
LIMIT 20
```

One row per year: the year's messages from the index alone, the messages naming the token, and their share; the same window with `countIf` over `payload` fails the deadline. (verified 2026-09-25)

**Rebuild the thread under the first Rust-support RFC on linux-kernel.**

```sql
SELECT message_key, parent_message_key, original_author, original_timestamp, title
FROM mailing_lists.messages
WHERE root_message_key = 'org.kernel.vger.linux-kernel::20210414184604.23473-1-ojeda@kernel.org'
ORDER BY original_timestamp ASC
LIMIT 1 BY message_key
LIMIT 20
```

The thread in posting order, one row per message, `parent_message_key` giving the reply edge; widen LIMIT for the whole thread. (verified 2026-09-25)

**Where did one author post, across lists?**

```sql
SELECT list_key, count() AS messages, min(original_timestamp) AS first_post, max(original_timestamp) AS last_post
FROM mailing_lists.messages
WHERE hasToken(lower(original_author), 'yudkowsky')
GROUP BY list_key
ORDER BY messages DESC
LIMIT 20
```

One row per list with the author's rows and posting span; the same person appears under several From spellings, which the token absorbs and an equality would split. (verified 2026-09-25)

**Semantic: SL4 posts arguing that the goal system must be right before the first run.** Mint the handle first, `POST /v1/scry/embed` with `{"text": "<the paragraph you hope to find>", "name": "ml_seed_ai"}`, then rank and hydrate.

```sql
SELECT message_key, chunk_index, scry_vector_topk_distance(embedding_voyage4, @ml_seed_ai) AS distance
FROM embeddings.mailing_list_messages
WHERE startsWith(message_key, 'sl4::')
ORDER BY distance ASC
LIMIT 10
```

```sql
SELECT message_key, original_author, original_timestamp, title, uri
FROM mailing_lists.messages
WHERE message_key IN ('sl4::BAY101-F3FC4CF7DE877550C49EE5AC740@phx.gbl', 'sl4::LNBBLCJHMFLNLMBEDJDNGEHMCFAA.peter@optimal.org', 'sl4::3D7DF7B3.10305@pobox.com')
LIMIT 1 BY message_key
LIMIT 20
```

Nearest chunks first, one row per chunk with its distance; copy the distinct keys into the second statement for author, subject, and archive page. (verified 2026-09-25)

## Traps

- Case and column: the index is on `lower(payload)`, so `hasToken(lower(payload), 'Rust')` matches nothing and `hasToken(payload, 'rust')` scans.
- Bodies in an aggregate: `countIf` over `payload` across a long window on a large list reads the bodies and fails the deadline (measured 2026-09-25 on linux-kernel over seven years); use the two-subquery denominator shape.
- A window without a list: `original_timestamp` bounds alone fetch rows scattered across the lists; add `list_key`.
- The clock as written: far-future, pre-1980 and NULL `original_timestamp` values exist; bound windows explicitly, and read a `toYear` bucket outside the window as a source error, not traffic.
- The same list twice, the same message many times: two collections of one list and cross-posts under each list's key; a count over `list_key IN (...)` double counts unless it is `uniqExact(message_id)`.
- Threading is only as good as the headers: `root_message_key` is empty on a large share of rows, the whole extropians archive included; a rebuild returning one row is a missing header, not a one-message thread.
- ANN collapse: `LIMIT 1 BY message_key` on the ANN statement over this relation trips the compiled-statement byte ceiling (measured 2026-09-25); rank chunks plainly and collapse to distinct keys when hydrating. A prefix predicate post-filters a bounded candidate window, so a keyed empty result is not absence.
- Encoding as the source wrote it: MIME encoded words (`=?utf-8?q?...?=`) in `original_author` and `title`, HTML entities (`&quot;`) in subjects from mirror pages; search bodies by token and subjects through `normalized_subject`.
- `quality_score` is NULL throughout; never filter on it. Catalog `message_count` is a daily reading and `estimated_message_count` the source's own figure; count on messages by `list_key` for the current number.

## Cross-family joins

- `embeddings.mailing_list_messages.message_key = mailing_lists.messages.message_key` hydrates a ranking; `mailing_lists.catalog.list_key = mailing_lists.messages.list_key` supplies roster, denominator, and archive URL.
- There is no shared person id: an author's history across `hackernews.items` (`original_author`), `forums.posts`, and here is one name or handle token per relation, each anchored with a token or a window.
- A list URL cited in `hackernews.items` or `crawl.pages` resolves to its message by `uri` (lore.kernel.org/r/<Message-ID>, pipermail, mirror pages), or by Message-ID in `message_id`.
