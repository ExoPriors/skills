---
name: scry-social-posts
description: >-
  Use when a question is about public posts, profiles, follow or reply edges,
  or communities on Bluesky, Mastodon, Nostr, Threads, VK, Instagram, or the
  frozen voat, parler, gab, telegram, discord and truth_social archives in
  social.posts: who said a term on a network and when, which servers, channels
  or walls carried it, how its share moved by month, which accounts rank by
  followers or engagement, thread and timeline rebuilds, and semantic
  neighbors over the Bluesky embeddings. Relations: social.*, bluesky.posts,
  mastodon.*, nostr.events, threads.*, vk.*, instagram.*,
  embeddings.bluesky_posts.
---

# Social posts across networks

Posts, profiles, edges and community directories from public networks, one relation family per network, plus six frozen archives folded into `social.posts` under a plain `platform` column. Each network keeps its own key, clock and text column; the contract is the authority.

## When to use

- Who said a term on a network, when, cited by post key.
- A term's share of a community's posts by month, denominator beside it.
- Which servers, channels or community walls carried a topic.
- Which accounts rank by followers, engagement or output.
- Rebuilding a Bluesky thread or author timeline, or a VK post with its comments.
- Semantic neighbors of a passage among Bluesky posts, then the text behind them.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Doors

| relation | one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `social.posts` | archive post, comment or chat message | `(platform, kind, native_id)`; `post_key` is a lookup handle | `created_at` | `search_text_lc` (indexed on discord only) | primary, lag 1d. Always `platform = '<p>'`; `created_at` prunes discord |
| `social.users` | profile (voat, parler, telegram, truth_social) | `(platform, native_id)` | `created_at` | `bio` (scan) | depth, lag 1d. gab and discord ship none; `native_id` = `social.posts.author` and the edge endpoints |
| `social.edges` | follows, replied_to or quoted edge | `(platform, kind, src_user, dst_user)` | none | none | depth, lag 1d. gab by username, truth_social by numeric id; `dst_post` = `social.posts.native_id` |
| `social.communities` | voat subverse or telegram channel | `(platform, community)` | `created_at` | `title`, `description` (scan) | depth, lag 1d. Telegram `community` is the channel id; the name is in `title` |
| `bluesky.posts` | one post record | `at_uri` | `created_at_source` (no date index) | `lower(payload)` token; trigram | depth, lag 2m. Identity is `author_did`; read `extent` and `known_holes` |
| `mastodon.posts` | one observation of a status | `uri` (`id` is instance-local) | `created_day` prunes; `created_at` is the clock | `content` token (case-sensitive); `lower(content)`; trigram | depth, lag 5m. `ORDER BY engagement DESC LIMIT 1 BY uri`; count with `uniqExact(uri)` |
| `mastodon.profiles` | deduped profile | `acct_global` | `created_at`, `last_status_at` | `note` token (case-sensitive); trigram | depth, lag 65m |
| `nostr.events` | relay event | `event_id` | `created_at` (unix seconds) | `JSONExtractString(payload, 'content')` (scan) | depth, lag 2m. `kind` 1 notes, 0 profiles, 3 contacts, 6 reposts, 7 reactions; a relay sample, not a census |
| `threads.posts` | Threads post | `(author_username, code)` | `taken_at`; `observed_on` prunes | `caption` (scan) | depth, lag 12d. Author predicate prunes; `uniqExact(code)` |
| `threads.profiles` | Threads profile | `username` | `observed_on` | `biography` (scan) | depth, lag 8d. Joins `threads.posts.author_username` |
| `vk.posts` | community wall post | `(owner_id, post_id)`, `owner_id` negative | `date`; `created_day` prunes | `lower(text)` token; trigram | depth, lag 2m. `-owner_id` = `vk.communities.id` |
| `vk.comments` | comment under a wall post | `(owner_id, post_id, comment_id)` | `date`; `created_day` | `lower(text)` token; trigram | depth, lag 4m. `from_id` is the commenter; `reply_to_comment` threads |
| `vk.communities` | community | `id` | `observed_on` | `description` token | depth, lag 8h. `LIMIT 1 BY id` before joining |
| `instagram.profiles` | public profile | `handle` | `observed_on` | `lower(concat(username, ' ', full_name, ' ', biography))` token | depth, lag 6h. `LIMIT 1 BY handle` |
| `instagram.posts` | recent post | `(owner_handle, shortcode)` | `taken_at` | `lower(caption)` token; trigram | depth, lag 7h. The recent edge of each profile, not a history; `uniqExact(shortcode)` |
| `embeddings.bluesky_posts` | Voyage-4 chunk of a post | `at_uri` | `observed_on` | vectors | depth, lag 44d, `serves_ann`; hydrate on `bluesky.posts.at_uri` |

## Idioms

- Name the platform first on `social.posts`: `platform = '<p>'` prunes to one branch. Add `kind` (`post`, `comment`, `message`) and a `created_at` window; on discord `hasToken(search_text_lc, '<lc token>')` engages the index, elsewhere text is parsed from `payload`.
- Token search spells the indexed expression exactly as the Doors column does; `hasAnyTokens(content, ['X', 'x'])` covers Mastodon's case-sensitive index. Confirm a phrase with `positionCaseInsensitive(col, 'the phrase') > 0`; substring needles of three or more characters ride `lower(ifNull(col, '')) LIKE '%needle%'`.
- Observations repeat: `LIMIT 1 BY uri` (Mastodon), `LIMIT 1 BY owner_handle, shortcode` (Instagram), `argMax(col, observed_on)` by key (Threads, VK); count identities with `uniqExact(key)`, never `count()`.
- Pick the pruning clock: `created_day` on Mastodon and VK, `observed_on` on Threads, `created_at` on discord, `created_at >= toUnixTimestamp('2026-09-01 00:00:00', 'UTC')` on Nostr. Bluesky has no date index: token filter first, window of days.
- Bluesky identity is `author_did`; an author's posts are the prefix range `at_uri >= 'at://<did>/' AND at_uri < 'at://<did>0'`; `reply_root_uri = '<at_uri>'` rebuilds a thread, `reply_parent_uri` reads direct replies; `is_deleted = 0` drops withdrawn records.
- Citations: Bluesky `https://bsky.app/profile/<author_did>/post/<rkey>` (last segment of `at_uri`); Mastodon `uri`; Threads `https://www.threads.com/@<author_username>/post/<code>`; VK `https://vk.com/wall<owner_id>_<post_id>`; Instagram `https://www.instagram.com/p/<shortcode>/`; Nostr `event_id`; the archives `post_key`.
- Semantic discovery: mint a handle with `POST /v1/scry/embed {text, name}` from an answer-shaped passage, rank `embeddings.bluesky_posts` standalone (`LIMIT 1 BY at_uri` is refused there), hydrate `bluesky.posts` by `at_uri` in a second statement.

## Worked queries

**Who mentioned Ollama on Bluesky on one day, newest first**

```sql
SELECT at_uri, author_did, created_at_source, payload
FROM bluesky.posts
WHERE hasToken(lower(payload), 'ollama')
  AND created_at_source >= '2026-09-24' AND created_at_source < '2026-09-25'
  AND is_deleted = 0
ORDER BY created_at_source DESC
LIMIT 10
```

Ten posts with DID and text; the token index prunes, the date window post-filters. (verified 2026-09-25)

**Mastodon statuses naming Anthropic in a week, one row per status**

```sql
SELECT uri, created_at, account_id, reblogs_count, favourites_count, content
FROM mastodon.posts
WHERE created_day >= '2026-09-18' AND created_day < '2026-09-25'
  AND hasAnyTokens(content, ['Anthropic', 'anthropic'])
  AND positionCaseInsensitive(content, 'anthropic') > 0
ORDER BY engagement DESC
LIMIT 1 BY uri
LIMIT 10
```

Ten statuses by engagement, `content` as HTML; `LIMIT 1 BY uri` keeps one observation per status. (verified 2026-09-25)

**Share of VK wall posts mentioning neural networks, by month, with the denominator**

```sql
SELECT toStartOfMonth(created_day) AS month,
       uniqExactIf((owner_id, post_id), hasToken(lower(text), 'нейросеть')) AS mentioning,
       uniqExact((owner_id, post_id)) AS posts,
       round(1000.0 * mentioning / posts, 2) AS per_mille
FROM vk.posts
WHERE created_day >= '2025-01-01' AND created_day < '2025-07-01'
GROUP BY month
ORDER BY month
LIMIT 20
```

One row per month: matching posts, the denominator, and the ratio, keys deduped on both sides. (verified 2026-09-25)

**Which VK communities carry that term, joined to the roster**

```sql
SELECT c.name, c.screen_name, uniqExact(p.post_id) AS posts, sum(p.likes) AS likes
FROM vk.posts AS p
INNER JOIN (
  SELECT id, name, screen_name FROM vk.communities
  ORDER BY observed_on DESC LIMIT 1 BY id
) AS c ON c.id = -p.owner_id
WHERE p.created_day >= '2025-01-01' AND hasToken(lower(p.text), 'нейросеть')
GROUP BY c.name, c.screen_name
ORDER BY posts DESC
LIMIT 10
```

Ten communities by matching posts with summed likes; the subquery dedupes the roster before the join. (verified 2026-09-25)

**Which Discord servers talked about ChatGPT in the week of the GPT-4 release**

```sql
SELECT JSONExtractString(payload, 'guild_id') AS server, uniqExact(community) AS channels,
       count() AS messages, uniqExact(author) AS voices
FROM social.posts
WHERE platform = 'discord'
  AND created_at >= '2023-03-14' AND created_at < '2023-03-21'
  AND hasToken(search_text_lc, 'chatgpt')
GROUP BY server
ORDER BY messages DESC
LIMIT 10
```

Ten servers with channel and voice counts; `community` is the channel name, so group on `guild_id` to keep servers apart. (verified 2026-09-25)

**Bluesky posts nearest to a passage about running models locally, then their text**

```sql
SELECT at_uri, scry_vector_topk_distance(embedding_voyage4, @bsky_localllm) AS distance
FROM embeddings.bluesky_posts
ORDER BY distance ASC
LIMIT 10
```

```sql
SELECT at_uri, author_did, created_at_source, payload
FROM bluesky.posts
WHERE at_uri IN ('at://did:plc:7t2jq65wa4izs766ccownejk/app.bsky.feed.post/3lbnmpcskj227',
                 'at://did:plc:326ht3oy5t7djhni2crrzh34/app.bsky.feed.post/3mg7v2g2rks2y')
LIMIT 10
```

Ten chunk keys by distance, then the chosen keys hydrated with author, time and text. (verified 2026-09-25)

## Traps

- `social.posts` without `platform` reads six archives. Discord `author` is a pseudonym, ids are truncated hashes. Voat submissions and comments share one id space: join on `(platform, kind, native_id)`, not `post_key`.
- A Bluesky handle predicate over recent time returns nothing: `author_handle` is sparse and resolves for no row after 2026-02-19. Filter `at_uri`, never `uri` (identical bytes, unindexed). Read `extent` and `known_holes` before calling a missing range absence.
- Mastodon `count()` counts observations. Rows dated 1970-01-01 are unparsed client dates and some carry forged future dates: bound `created_day` to the published extent, especially under `ORDER BY created_at DESC`.
- Threads and Instagram hold observed profiles, not the network: an absent author is not yet observed. Caption and `taken_at` predicates scan; scope by author first. Counts are snapshots as of `observed_on`.
- VK `owner_id` is negative; a `LIKE` not spelled `lower(ifNull(text, ''))` scans; tokens are lowercase in the text's own script.
- Nostr `created_at` is the event's own clock, unverified; `observed_on` is the relay day. `content` on `kind = 0` is a JSON profile, not prose.
- Telegram in `social.posts` keys on `community` and `author`; a text predicate alone reads the archive. Gab edges may list one relationship twice: dedupe on `(src_user, dst_user)`.

## Cross-family joins

- Cross-platform identity is `persons.links` (access is reviewed and requested by writing to hi@scry.io); without it, handles from `mastodon.profiles`, `threads.profiles` and `instagram.profiles` match names in the historical Twitter archive (`twitter.users`) or `hackernews.items` as leads, not identities.
- Fixpoint programs pivot with `bluesky.by`/`posts_of` and `instagram.posts_of` beside the historical Twitter archive, Hacker News and forum edges.
- One Voyage-4 handle ranks `embeddings.bluesky_posts`, `embeddings.tweets` and `embeddings.hackernews_items` alike.
