---
name: scry-chat-logs
description: >-
  Use when a question is about chat logs or stream chat: what a Discord
  server's channels said about a topic, which channels or speakers carried it,
  reading a support thread whole, what Twitch chat said in a channel on a day
  and how many spoke, sub and raid events, which channels mentioned a term,
  VOD replay chat with the offset into the video and a citable VOD link, or
  which archived Twitch and Kick VODs exist for a channel. Covers
  discord.live_messages, discord.knowledge, twitch.messages, twitch.knowledge,
  streams.vod_chat and streams.vods.
---

# Chat logs and stream chat

Messages from Discord servers listed in Discord's public Server Discovery directory, Twitch IRC chat from channels while they streamed, and replayed chat of archived Twitch and Kick VODs with the VOD roster. Each platform has an identity-bearing relation and a public face with identity projected out.

## When to use

- What a Discord server said about a term, in which channels, by how many speakers, with a permalink per message.
- Reading a Discord thread whole: the asker, the answerer, the follow-up, in send order, one row per message.
- What one Twitch channel's chat said on a day, with the denominator: messages, speakers, sub and raid events, share mentioning a term.
- Which Twitch channels mentioned a term in a window, and who said it.
- Where in a VOD a phrase was said, as a link into the video at that offset; which VODs a channel has and their titles.

The core `scry` skill (authentication, the query door, response fields) is assumed loaded.

## Doors

| relation | what one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `discord.knowledge` | one message from a listed server, author replaced by `speaker` (hash stable within one server) | `guild_id`, `channel_id`, `message_id` | `sent_at` (authored), `edited_at`, `observed_on` (observation day) | `content` (Discord markdown, no index) | depth, daily, lag 9d; public face, prefer it |
| `discord.live_messages` | the same message with `author_id`, `author_username`, `author_display_name`, `attachment_filenames` | `guild_id`, `channel_id`, `message_id` | `sent_at`, `edited_at`, `observed_on` | `content` (no index) | depth, daily, lag 9d; `author_id` keyed alone; reviewed access |
| `twitch.knowledge` | one IRC message (`msg_kind` privmsg or usernotice), user replaced by `speaker` (stable within one channel) | `channel_login`, `tmi_sent_ms`, `message_id` | `sent_at` (`tmi_sent_ms` is its epoch-ms twin) | `text` (no index) | depth, hourly; public face, prefer it |
| `twitch.messages` | the same message with `user_id`, `user_login`, `display_name`, `badges`, `emotes`, `raw_line` | `channel_login`, `tmi_sent_ms`, `message_id` | `sent_at`, `observed_on` | `text` (words index; `lower(text) LIKE` lane) | depth, hourly, lag 45s; `user_id` keyed alone; reviewed access |
| `streams.vod_chat` | one replayed chat line of an archived Twitch or Kick VOD | `platform`, `channel`, `vod_dir`, `time_sec`, `user_name`, `message` | `vod_date` (the VOD's day); `time_sec` is the offset, `time_str` its h:mm:ss | `message` (words index) | depth, periodic, lag 8h; no message or user ids |
| `streams.vods` | one archived VOD: title, date; Twitch rows carry `vod_id`, `published_at`, `game_name`, `duration`; `info` is the upstream JSON | `platform`, `channel`, `vod_dir` | `vod_date`, `published_at` | `title` (no index) | depth, periodic; Kick rows keep typed columns empty |

Lags are the index line's on 2026-09-25; the index is the authority.

## Idioms

- Token search where the index is: `hasAnyTokens(message, ['Claude', 'claude'])` on `streams.vod_chat` and `hasAnyTokens(text, [...])` on `twitch.messages`; tokens are case-sensitive, so pass both spellings. Confirm a phrase with `positionCaseInsensitive(message, 'claude code') > 0`. `lower(text) LIKE '%claude code%'` is the substring lane on `twitch.messages`; `scry_lex('"claude code"', text)` runs there and on `streams.vod_chat`.
- Bound before you search where there is no index: on `discord.*` name `guild_id` (and `channel_id`) with a `sent_at` window, on `twitch.knowledge` name `channel_login` with a window, then `hasAnyTokens` or `hasAllTokens` over the bounded rows. `scry_lex` is refused on both knowledge relations.
- Keys: `message_id` alone reads the whole relation; bind `guild_id` and `channel_id`, or `channel_login` and a `tmi_sent_ms` range, beside it. `author_id` on `discord.live_messages` and `user_id` on `twitch.messages` are keyed alone; `user_login`, `user_name` and `channel_name` scan. On `streams.*` the fast order is `platform`, `channel`, `vod_dir`.
- Time: `sent_at` is the send time on both platforms (Discord derives it from the snowflake, so a window prunes); `observed_on` is the day the row was observed, never the window for "when it was said". A VOD line has no wall clock: `vod_date` is the VOD's day, `time_sec` the offset.
- Dedup: Discord edits replace the row and duplicates exist, so `ORDER BY sent_at ASC, observed_on DESC LIMIT 1 BY guild_id, channel_id, message_id`; on Twitch `LIMIT 1 BY message_id` and `uniqExact(message_id)` as the denominator; a VOD can sit under two `vod_dir` spellings (non-ASCII flattened to `_` in one) with repeated lines, so `LIMIT 1 BY channel, vod_date, time_sec, user_name, message`.
- Public face first: the knowledge relations carry the same rows with `speaker`, and mentions in text read as `<@speaker>`; a speaker joins nothing across servers or channels and never to a handle. `discord.live_messages` and `twitch.messages` are reviewed access, requested by writing to hi@scry.io.
- Citation: Discord `https://discord.com/channels/<guild_id>/<channel_id>/<message_id>`; Twitch VOD `https://www.twitch.tv/videos/<vod_id>?t=<h>h<m>m<s>s` from `streams.vods.vod_id` and `time_sec` (a Kick VOD has no id: cite `channel`, `vod_date`, `title`, `time_str`); a `twitch.messages` row has no permalink: cite `channel_login`, `sent_at` (UTC), `message_id`.
- Denominators and events: `uniqExact(speaker)` for who spoke; `msg_kind = 'usernotice'` with `notice_type` (sub, resub, subgift, raid) separates events from chat, `bits > 0` cheers; `author_is_bot` and `message_type` (19 is a reply) on Discord; `is_subscriber`, `is_moderator` on VOD lines.

## Worked queries

**Where was "claude code" said in VOD chat, newest first, one row per line?**

```sql
SELECT channel, vod_date, time_str, user_name, message
FROM streams.vod_chat
WHERE hasAnyTokens(message, ['Claude', 'claude'])
  AND positionCaseInsensitive(message, 'claude code') > 0
ORDER BY vod_date DESC, time_sec ASC
LIMIT 1 BY channel, vod_date, time_sec, user_name, message
LIMIT 20
```

One line per hit with its VOD offset; the token index does recall, the phrase check precision, `LIMIT 1 BY` folds repeated lines. (verified 2026-09-25)

**How much of one Twitch channel's chat on a day mentioned Claude, with the denominator?**

```sql
SELECT uniqExact(message_id) AS messages,
       uniqExact(speaker) AS speakers,
       uniqExactIf(message_id, msg_kind = 'usernotice') AS notices,
       uniqExactIf(message_id, hasAnyTokens(text, ['Claude', 'claude'])) AS claude_messages,
       round(claude_messages / messages, 4) AS claude_share
FROM twitch.knowledge
WHERE channel_login = 'xqc'
  AND sent_at >= '2026-09-24' AND sent_at < '2026-09-25'
LIMIT 1
```

One row: messages, speakers, event notices, mentions and their share; the channel bound and day window keep the unindexed text predicate cheap. (verified 2026-09-25)

**Link each "claude code" VOD line to the video at that second.**

```sql
SELECT c.channel, c.vod_date, c.time_str, c.user_name, c.message,
       concat('https://www.twitch.tv/videos/', v.vod_id, '?t=',
              toString(intDiv(c.time_sec, 3600)), 'h',
              toString(intDiv(c.time_sec % 3600, 60)), 'm',
              toString(c.time_sec % 60), 's') AS url
FROM streams.vod_chat AS c
INNER JOIN streams.vods AS v
  ON c.platform = v.platform AND c.channel = v.channel AND c.vod_dir = v.vod_dir
WHERE c.platform = 'twitch'
  AND hasAnyTokens(c.message, ['Claude', 'claude'])
  AND positionCaseInsensitive(c.message, 'claude code') > 0
  AND v.vod_id != ''
ORDER BY c.vod_date DESC, c.time_sec ASC
LIMIT 1 BY c.channel, c.vod_date, c.time_sec, c.user_name, c.message
LIMIT 20
```

Each row's URL opens the VOD at the line's offset; `v.vod_id != ''` keeps the `vod_dir` spelling that carries the Twitch id. (verified 2026-09-25)

**Which channels of the Rust server carry tokio talk, and how many speakers?**

```sql
SELECT channel_id, channel_name, count() AS messages, uniqExact(speaker) AS speakers
FROM discord.knowledge
WHERE guild_id = 273534239310479360
  AND sent_at >= '2026-08-15'
  AND hasAnyTokens(content, ['tokio', 'Tokio'])
GROUP BY channel_id, channel_name
ORDER BY messages DESC
LIMIT 10
```

Channels ranked by mentions with speakers beside them; `guild_id` prunes to one server, so the unindexed token predicate reads only that window. (verified 2026-09-25)

**Read twenty minutes of one Discord channel whole, in send order, latest observation per message.**

```sql
SELECT message_id, speaker, sent_at, reply_to_message_id, substring(content, 1, 100) AS snippet
FROM discord.knowledge
WHERE guild_id = 267624335836053506 AND channel_id = 267624335836053506
  AND sent_at >= '2026-09-10 07:50:00' AND sent_at < '2026-09-10 08:10:00'
ORDER BY sent_at ASC, observed_on DESC
LIMIT 1 BY guild_id, channel_id, message_id
LIMIT 20
```

The conversation as it ran: `speaker` ties an asker to their follow-ups, `reply_to_message_id` (0 when absent) names the message answered, `observed_on DESC` keeps the edited text. (verified 2026-09-25)

**Which Twitch chats said "claude code" in a day, with who said it (reviewed access)?**

```sql
SELECT channel_login, sent_at, display_name, text
FROM twitch.messages
WHERE scry_lex('"claude code"', text)
  AND sent_at >= '2026-09-24'
ORDER BY sent_at DESC
LIMIT 1 BY message_id
LIMIT 20
```

Newest phrase hits across channels with the display name; `scry_lex` uses the words index on `text`; on `twitch.knowledge` the same question needs `hasAnyTokens` plus a `channel_login` bound. (verified 2026-09-25)

## Traps

- A text predicate on `discord.*` or `twitch.knowledge` without `guild_id` or `channel_login` runs past the deadline; a `sent_at` window alone is not a bound there.
- Windowing on `observed_on` answers when the message was observed, not when it was sent.
- `hasToken` is case-sensitive: `hasToken(text, 'claude')` misses "Claude"; pass both spellings to `hasAnyTokens`.
- An empty Twitch result for a channel and time is a gap in the archive, never chat silence: IRC has no replay. A Discord server absent from the rows is not listed in Server Discovery or is gated.
- A statement needs a literal `LIMIT` unless it is a bare fixed-size aggregate; `FROM (SELECT ...)` is a parse error here, so dedup and order live in one `SELECT` with `LIMIT 1 BY`.
- Duplicates: an edited Discord message is a second row with a later `observed_on`; a Twitch message can repeat before merges; a VOD appears under two `vod_dir` spellings, only one carrying `vod_id`.
- `speaker` tokens differ per server or channel for the same account; `channel_name` (Discord) and `user_login`, `display_name` (Twitch) are parsed twins that scan, so filter on ids.
- Kick rows of `streams.vods` have empty `vod_id`, `published_at`, `game_name`, `duration`; read `JSONExtractString(info, 'streamer')` and `title`. `content` carries Discord markdown; Twitch emote spans are in `emotes`, not `text`.

## Cross-family joins

- Twitch logins tie the family together: `twitch.knowledge.channel_login = streams.vod_chat.channel = streams.vods.channel`; `lower(user_name)` on a VOD line usually equals `user_login` on `twitch.messages`, a real Twitch login. There is no message-level key between IRC rows and replayed lines.
- `social.posts` with `platform = 'discord'` is the frozen 2015 to 2024 Discord research archive, pseudonymized with truncated hashed ids: join to `discord.*` by topic and time only, never by id.
- `streams.vods.game_name` and `title` are the text where a stream meets `youtube.videos_live` or `tiktok.videos` by game or creator name.
