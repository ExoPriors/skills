---
name: scry-video
description: >-
  Use when a question is about YouTube or TikTok: what a video or creator said
  (captions, and the second a word is spoken), what commenters wrote under a
  video, which videos or channels mention a term, engagement snapshots,
  reposts, and a term's share of TikTok comments by month. Covers
  youtube.videos (the frozen 2021 census), youtube.videos_live,
  youtube.channels, youtube.transcripts, youtube.comments,
  youtube.campaign_jobs, tiktok.videos, tiktok.transcripts, tiktok.comments,
  tiktok.reposts and tiktok.reposters.
---

# Video platforms

YouTube and TikTok as observed archives: video metadata with engagement snapshots, channels and creators, captions, comments, and repost feeds. Rows are observations: a video can recur, and YouTube's time column is the observation day, not the upload day.

## When to use

- What a video or creator said, and the second a word is spoken.
- Which videos, channels or creators mention a term, ranked by views or engagement.
- What commenters wrote under a video or channel, and which videos drew the most comments.
- A term's share of TikTok comments month by month, with its denominator.
- A creator's videos joined to captions and engagement; the TikToks the repost feeds carry most.

The core `scry` skill (auth, query door, response fields) is assumed loaded.

## Doors

The family is depth tier throughout; lag is the index line's.

| Relation | One row is | Key | Time column | Text column(s) | Notes |
| --- | --- | --- | --- | --- | --- |
| `youtube.videos` | a census video: title, uploader, counts, flags, description | `video_id` | `observed_on`; `upload_date` is `YYYYMMDD` text | title and description, see Idioms | frozen, lag 7d; near-census of public YouTube at 2021-11/12; `uploader_id`, `view_count >= n` indexed |
| `youtube.videos_live` | an observation from 2026-08 onward: channel, title, labels, playability | `video_id`, version `observed_hour` | `observed_on`, `observed_hour` | none indexed | daily, lag 3d; `observed_on`, `channel_id`, `video_id IN (...)` prune; `lower(channel_name)` filtered |
| `youtube.channels` | a partial sum per (channel_id, handle): observation mass, first and last day | `channel_id`, `handle` | `first_seen_on`, `last_seen_on` | `handle = '@name'`, exact | frozen, lag 21h; identity hub; sum on read |
| `youtube.transcripts` | an observed caption track: `payload` one cue per line, `event_starts_ms` aligned | `video_id`, `language`, `is_auto_caption` | `observed_on` | `lower(payload)` via `hasToken`, weakly selective | daily, lag 3d; hydrate by `video_id`, never scan by word |
| `youtube.comments` | a comment: `payload`, `author` as '@handle', `author_channel_id`, labels | `video_id`, `comment_id` | `observed_on`; `published_label` is text | `lower(ifNull(payload, ''))` via `hasToken` | frozen, lag 6d; `video_id` prunes; `author_channel_id`, `lower(author)` indexed |
| `youtube.campaign_jobs` | a finished `index_request` job: operation, tier, terminal class | `campaign_id`, `job_id` | `observed_on` | none | frozen, lag 3d; status only |
| `tiktok.videos` | an observed public video from a `source` branch (tiktok, kuben4b, tiago) | `id` with `handle` | `create_time` authored; `observed_on` | `lower(description)` via `hasToken` | daily, lag 2m; `handle` prunes, `id` alone refused; `url` is the citation |
| `tiktok.transcripts` | a caption per (video_id, lang): `text` flat, `vtt` timed, `source` creator / ASR / MT | `video_id`, `lang` | `create_time`; `observed_on` | `hasToken(text, 'Word')` case-sensitive; `lower(text) LIKE` | daily, lag 2m; `handle`, `author_id`, `create_time` day window indexed |
| `tiktok.comments` | a comment on a public video: text, parent, likes, language, commenter hash | `video_id`, `id` | `create_time`, month partitions; `observed_on` | `lower(text)` via `hasToken` | frozen, lag 2d; the cheap text door; window beside token |
| `tiktok.reposts` | a (reposter, video) edge from an observed repost feed, with rank | `reposter_hash`, `video_id` | `first_seen`, `last_seen` | none | frozen, lag 18h; small, any predicate is fast |
| `tiktok.reposters` | a reposter as hashes, with repost count and hidden flag | `sec_hash` | `first_seen`, `last_crawled` | none | frozen, lag 4d; joins only `tiktok.reposts` |

## Idioms

- Token search uses each relation's own lowercase expression (no `search_text_lc`): youtube.videos `hasToken(lower(concat(ifNull(title, ''), ' ', ifNull(description, ''))), 'word')`. Confirm a phrase with `positionCaseInsensitive(col, 'the phrase') > 0` after `hasAllTokens`. tiktok.transcripts `text` is case-sensitive: `hasAnyTokens(text, ['word', 'Word'])`.
- Candidates upstream, captions by key: find ids in youtube.videos, youtube.videos_live or youtube.comments, then `youtube.transcripts WHERE video_id IN ('a', 'b')` as literals. A subquery of many ids runs to the deadline; a few literal ids read in seconds.
- Dedupe observations: `ORDER BY word_count DESC LIMIT 1 BY video_id, language` (youtube.transcripts), `LIMIT 1 BY video_id, lang` (tiktok.transcripts), `LIMIT 1 BY id` or `uniq(id)` (tiktok.videos), `argMax(title, observed_hour) ... GROUP BY video_id` (youtube.videos_live); count videos with `uniq(video_id)`.
- Time: TikTok has authored `create_time`, and tiktok.comments partitions by its month, so bind a window to each token. YouTube has observation time only; label strings ('2 years ago', '6.47K subscribers') parse with `extractAll`.
- Cheap sibling first: youtube.videos for a YouTube word; tiktok.comments for a TikTok word; tiktok.videos and tiktok.transcripts by `handle`; youtube.videos_live by `channel_id` or `observed_on`. Pre-flight the rest with `x-scry-explain: 1`.
- Citation: `https://www.youtube.com/watch?v=<video_id>`, plus `&t=<seconds>s` from `event_starts_ms[line]` where `line` indexes `splitByChar(char(10), payload)`; on TikTok the `url` column or `https://www.tiktok.com/@<handle>/video/<id>`.
- Identity: `youtube.channels.channel_id` = `youtube.videos.uploader_id` = `youtube.videos_live.channel_id` = `youtube.comments.author_channel_id`; TikTok `handle` and `author_id` match across tiktok.videos and tiktok.transcripts; `user_hash` and `sec_hash` join nothing else. Fixpoint edges: `youtube.uploader`, `youtube.commenters`, `tiktok.videos_of`.

## Worked queries

**Which YouTube videos mention Rowhammer, by views at the census?**

```sql
SELECT video_id, title, uploader, upload_date, view_count
FROM youtube.videos
WHERE hasToken(lower(concat(ifNull(title, ''), ' ', ifNull(description, ''))), 'rowhammer')
  AND view_count >= 10000
ORDER BY view_count DESC
LIMIT 10
```

The cheap YouTube word door: the token index prunes and the counter floor bounds the read; `upload_date` text sorts as a timeline. (verified 2026-09-25)

**Where did "brain rot" land in TikTok comments in 2024, by likes?**

```sql
SELECT video_id, id, create_time, like_count, text
FROM tiktok.comments
WHERE create_time >= '2024-01-01' AND create_time < '2025-01-01'
  AND hasAllTokens(lower(text), ['brain', 'rot'])
  AND positionCaseInsensitive(text, 'brain rot') > 0
ORDER BY like_count DESC
LIMIT 10
```

The most-liked comments carrying the phrase inside the year's partitions; the creator's `handle` from tiktok.videos completes the citation. (verified 2026-09-25)

**How much of TikTok comment traffic mentioned Ozempic, month by month?**

```sql
SELECT toStartOfMonth(create_time) AS month,
       count() AS comments,
       countIf(hasToken(lower(text), 'ozempic')) AS ozempic,
       round(1000000 * ozempic / comments, 1) AS per_million
FROM tiktok.comments
WHERE create_time >= '2023-07-01' AND create_time < '2025-01-01'
GROUP BY month
ORDER BY month
LIMIT 20
```

One row per month: comments as the denominator, matches, and matches per million; the window bounds the partitions read. (verified 2026-09-25)

**A creator's captioned TikToks with their engagement**

```sql
SELECT t.video_id, t.lang, t.source, t.char_len, v.create_time, v.play_count, v.url
FROM (
  SELECT video_id, lang, source, char_len
  FROM tiktok.transcripts
  WHERE handle = 'khaby.lame'
  ORDER BY char_len DESC
  LIMIT 1 BY video_id, lang
) AS t
INNER JOIN (
  SELECT id, create_time, play_count, url
  FROM tiktok.videos
  WHERE handle = 'khaby.lame' AND source = 'tiktok'
  ORDER BY observed_on DESC
  LIMIT 1 BY id
) AS v ON v.id = t.video_id
ORDER BY v.play_count DESC
LIMIT 10
```

One row per captioned video, both sides deduped before the join; `source = 'tiktok'` keeps creator-attributed rows, `url` is the citation. (verified 2026-09-25)

**Which of a channel's videos carry the most comments in coverage?**

```sql
SELECT video_id, count() AS comments, uniq(author_channel_id) AS commenters
FROM youtube.comments
WHERE video_id IN (SELECT video_id FROM youtube.videos_live WHERE channel_id = 'UCYO_jab_esuFRV4b17AJtAw')
GROUP BY video_id
ORDER BY comments DESC
LIMIT 10
```

Comment rows and distinct commenters per video; `channel_id` is indexed and `video_id` prunes the read. Depth per video is bounded: this ranks coverage, not YouTube. (verified 2026-09-25)

**The second a video says "sigmoid", as a deep link**

```sql
SELECT video_id, language, word_count,
       arrayFirstIndex(l -> positionCaseInsensitive(l, 'sigmoid') > 0, splitByChar(char(10), payload)) AS line_no,
       event_starts_ms[line_no] AS start_ms,
       concat('https://www.youtube.com/watch?v=', video_id, '&t=', toString(intDiv(start_ms, 1000)), 's') AS deep_link
FROM youtube.transcripts
WHERE video_id IN ('aircAruvnKk', 'IHZwWFHWa-w', 'Ilg3gGewQ5U')
  AND language = 'en'
  AND hasToken(lower(payload), 'sigmoid')
  AND length(event_starts_ms) = length(splitByChar(char(10), payload))
ORDER BY word_count DESC
LIMIT 1 BY video_id, language
LIMIT 5
```

One row per video with an intact timed track: `line_no` indexes the cue lines, `event_starts_ms` its start, the link opens there; a fused or untimed track fails the guard and drops out, never mislinks. (verified 2026-09-25)

## Traps

- youtube.videos is a frozen 2021 census: a later video is absent there and lives only in youtube.videos_live, youtube.transcripts or youtube.comments. Absence there is not absence of captions or comments.
- youtube.transcripts: a word scan without `video_id` decompresses whole transcripts and hits any deadline; `has_subtitles` in youtube.videos means captions existed at observation, not a held track.
- Fused tracks: `length(splitByChar(char(10), payload)) = 1 AND length(event_starts_ms) > 1` marks a one-line track, each cue's last word fused to the next's first: `hasToken` misses those words, `word_count` reads low, line-to-time is gone; older rows have an empty `event_starts_ms`. The `word_count DESC` dedupe prefers an intact observation.
- youtube.comments has no typed timestamp; `comment_id` alone reads the whole relation; bind `video_id` beside it; `author = '@Handle'` scans, `lower(author) = '@handle'` is indexed.
- youtube.channels rows are partial sums: `LIMIT 1 BY` or `argMax` drops mass; `handle` is exact, case included.
- tiktok.videos: `id` alone, a `handle` in the wrong case, or a `create_time` window alone is refused; a video appears once per `source`, so `uniq(id)`; engagement is as of `observed_on`; the inline `transcript` column is legacy, captions live in tiktok.transcripts.
- tiktok.comments commenters are hashes; `reply_id = 0` keeps top-level comments.
- tiktok.reposts: a `reposts_hidden = 1` reposter has no edges; an edge carries no `handle`, which tiktok.videos needs beside `id`.

## Cross-family joins

- A video id inside a URL: `hackernews.items.outbound_url`, `reddit.posts.url`, `crawl.pages.url` with `positionCaseInsensitive(url, 'youtube.com/watch?v=<video_id>') > 0`, or `extract(url, 'v=([A-Za-z0-9_-]{11})')` to mint the key; likewise `tiktok.com/@<handle>/video/<id>`.
- TikTok `video_id` = `tiktok.videos.id` across comments, transcripts and reposts; the `source = 'tiago'` branch holds the commented videos.
