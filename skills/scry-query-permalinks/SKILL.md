---
name: scry-query-permalinks
description: >-
  Use when a query should outlive the session or be handed to someone: save a
  parameterized Scry SQL statement, datalog program, or semantic join as a
  scry.io permalink whose page renders each parameter as a control; re-run a
  saved query by slug with other values; find saved queries in a fresh
  session; retitle, revise, or withdraw one while the link stays; post a
  standing research question and hang contributions on it; enter an inquiry
  on the query board. Uses the share, share_get, share_list, share_run and
  share_update MCP tools, their REST twins under /v1/scry/shares, and the
  scry.io/s pages.
---

# Query permalinks and shares

A share is an addressable scry.io link: a parameterized query that re-runs
under controls on its page, a write-up, or a standing research question with
contributions, which a person or agent can cite, replay, and adjust.

## When to use

- A query is worth keeping: save it once with typed placeholders and hand out the permalink instead of the SQL.
- A reader should adjust the question themselves: a date window, a token, a floor, as controls on the page.
- A returning session needs its saved queries back without knowing their slugs.
- A saved query should run again with other values, from an agent or from curl, under the same safeguards as `sql`.
- Someone voiced a research want: post it verbatim as a question and publish findings as contributions.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.
Plain SQL is the better tool for a one-off read; a share earns its slug when the query will be re-run, cited, or adjusted by someone else.

## Surfaces

| name | what it does | required | what comes back | cost or limit the contract states |
| --- | --- | --- | --- | --- |
| `share` (`POST /v1/scry/shares`) | creates a share (`kind` query, markdown, insight, chat, rerank, question) | `kind`, `title` (180 chars), `payload`; optional `summary` (800), `is_public`, `answers`, `board` | `share_slug`, `permalink`, the stored `payload`, `is_public`, `answers` | private unless `is_public: true`; a query payload holds one of `sql`, `program`, `semantic_join`; `board: true` queues a judging round on your wallet |
| `share_get` (`GET /v1/scry/shares/{slug}`) | reads one share | `slug` | kind, title, summary, payload with declared params, permalink; a question's `contributions` | public reads without a key; a private share is `not_found` to anyone but its owner |
| `share_list` (`GET /v1/scry/shares?kind=`) | your shares newest first, or the public question index | none; `kind` one of query, chat, rerank, markdown, insight, question | `{shares: [...]}` (slug, permalink, kind, title, summary, is_public, created_at) or `{questions: [...]}` | own listing needs your key; the question index needs none |
| `share_run` (`POST /v1/scry/shares/{slug}/run`) | runs the stored envelope through its own metered lane | `slug`; `params` by name (sql shares only) | the `sql` response (rows, coverage, `deadline_partial`, `record_id`) plus `params` as bound and `share_slug` | `max_seconds` default 15, max 2000; `max_staleness_seconds` default 60; the other `sql` safeguards by name; program and semantic-join shares need a key |
| `share_update` (`PATCH /v1/scry/shares/{slug}`) | revises title, summary, payload, visibility, or board entry; `detach` unhooks a contribution | `slug` plus at least one field | the share as stored | owner only; nothing deletes (REST `DELETE` is 405); `is_public: false` withdraws; a public share's update reports its edge purge in `edge` |
| page `https://scry.io/s/{slug}` | renders each parameter as a control and re-runs as the reader adjusts | none | HTML; `?format=md` is the markdown twin (SQL, params, metrics, preview) | a private page is 404 to anyone but the owner |
| `https://scry.io/s`; `GET /v1/scry/board` | the open question index; the judged inquiry ranking (criteria, weights, tiers) | none | HTML; JSON | no credential |

## Idioms

- Placeholders are `{name:Type}` in the WHERE clause: String, UInt8..UInt64, Int8..Int64, Float32, Float64, Date, DateTime, Bool, and Array or Nullable over them. `LIMIT` stays a literal integer. A declared parameter carries a `default`.
- Hints shape the page's controls, and only `name`, `type`, `default` bind values: `label`, `description`, `placeholder`, `choices` (buttons), `min`/`max`/`step` on a numeric type (a slider), `widget` to override.
- Make the default run cheap: a time-bound parameter whose default covers months, not the whole relation. One hinted template beats several near-duplicate saves.
- Pick the envelope by what is shared: `sql` for a statement, `program` for a procedure (the datalog JSON as the `datalog` tool takes it, `params: []`), `semantic_join` for a join. The latter two run only under a key.
- Bind values one way per parameter: the MCP `params` object, REST `param_<name>` in the URL, or REST JSON `{"params": {...}}`. Unsupplied names take their defaults.
- Cite the `permalink` the create response returns, never a constructed URL; a run's `record_id` is its evidence; rows cite sources through the id and timestamp columns the statement selects.
- Shares are private by default. `is_public: true` publishes to `scry.io/s`; `is_public: false` withdraws; the slug never changes across updates.
- A question is `kind: "question"` with `payload.prompt` in the asker's words verbatim, optional `brief` (markdown on how to attack it) and `asked_in`. A contribution sets `answers` to the question's slug at creation, immutable after; a hinted query share is the best contribution, since the question's page then has a playground.
- A board entry is a sql query share with `board: true`, `payload.question` (300 chars, verbatim) and `payload.approach` (4,000): the statement runs once, its first 200 rows freeze as the snapshot, and a judging round is queued on your wallet. Enter only an answer worth keeping.
- Open a returning session with `share_list` `kind: "query"`, then `share_get` for the stored envelope.

## Worked calls

**Save a hinted, parameterized query as a private permalink.**
```bash
curl -s https://api.scry.io/mcp -H "Authorization: Bearer $SCRY_API_KEY" -H 'content-type: application/json' -H 'accept: application/json' -H 'mcp-protocol-version: 2025-06-18' -H 'mcp-method: tools/call' -H 'mcp-name: share' --data @- <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"share","arguments":{"kind":"query","title":"skill-draft-permalinks: HN stories by token, since a date, above an upvote floor","summary":"skill-draft scratch share; withdrawn after verification","payload":{"sql":"SELECT hn_id, original_author, original_timestamp, upvotes, title FROM hackernews.items WHERE hn_type = 'story' AND hasToken(search_text_lc, {term:String}) AND original_timestamp >= {since:Date} AND upvotes >= {min_upvotes:UInt32} ORDER BY original_timestamp DESC LIMIT 5","params":[{"name":"term","type":"String","default":"rust","label":"Token","description":"one lowercase word","choices":["rust","zig","haskell"]},{"name":"since","type":"Date","default":"2025-01-01","label":"Since"},{"name":"min_upvotes","type":"UInt32","default":100,"label":"Upvote floor","min":0,"max":500,"step":10}]}}}}
EOF
```
The share as stored: `share_slug` (this run: `5ow2dkyz`), `permalink` `https://scry.io/s/5ow2dkyz`, `is_public: false`, the params with their hints; no `snapshot` key when none was sent. (verified 2026-09-25)

**Re-run it with other values.**
```bash
curl -s https://api.scry.io/mcp -H "Authorization: Bearer $SCRY_API_KEY" -H 'content-type: application/json' -H 'accept: application/json' -H 'mcp-protocol-version: 2025-06-18' -H 'mcp-method: tools/call' -H 'mcp-name: share_run' --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"share_run","arguments":{"slug":"5ow2dkyz","params":{"term":"zig","min_upvotes":50},"max_seconds":20}}}'
```
The `sql` response: five rows, `deadline_partial: false`, `record_id`, plus `params` as bound (`since` at its default) and `share_slug`. (verified 2026-09-25)

**Replay a public share through REST with URL-bound parameters.**
```bash
curl -s -X POST 'https://api.scry.io/v1/scry/shares/mmdal7hv/run?param_since=2025-06-01%2000:00:00&param_until=2025-09-01%2000:00:00' -H "Authorization: Bearer $SCRY_API_KEY" -H 'accept: application/json'
```
Monthly rows for the window, `authorized_seconds: 15` by default, `params` echoing both bindings; without a key the same call answers with x402 terms, not rows. (verified 2026-09-25)

**Post a standing research question.**
```bash
curl -s https://api.scry.io/mcp -H "Authorization: Bearer $SCRY_API_KEY" -H 'content-type: application/json' -H 'accept: application/json' -H 'mcp-protocol-version: 2025-06-18' -H 'mcp-method: tools/call' -H 'mcp-name: share' --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"share","arguments":{"kind":"question","title":"skill-draft-question: which languages HN calls memory-safe","payload":{"prompt":"which languages does hacker news call memory-safe, and since when?","brief":"hackernews.items with hasToken(search_text_lc, ...) by month; name the languages and the first month each appears beside the phrase."}}}}'
```
A question share with `share_slug`, `permalink`, `answers: null`; private until `is_public: true`, and `share_get` lists `contributions: []` until a public contribution names it. (verified 2026-09-25)

**Withdraw or annotate while the link stays.**
```bash
curl -s https://api.scry.io/mcp -H "Authorization: Bearer $SCRY_API_KEY" -H 'content-type: application/json' -H 'accept: application/json' -H 'mcp-protocol-version: 2025-06-18' -H 'mcp-method: tools/call' -H 'mcp-name: share_update' --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"share_update","arguments":{"slug":"5ow2dkyz","is_public":false,"summary":"skill-draft scratch share: verified 2026-09-25, withdrawn"}}}'
```
The share as stored with the same `share_slug` and `permalink`, `is_public: false`, `updated_at` moved; no `edge` field on a private share. (verified 2026-09-25)

## Traps

- An undeclared name in `params` is refused (`unknown Query share parameter`). A name in both the URL and the body, or a URL name without the `param_` prefix, is a 400 that names the fix, never a silent default.
- `LIMIT {n:UInt32}` is refused at creation (`non_literal_limit`); a parameter without a `default` is refused; an unknown `kind` is refused with the served kinds listed.
- A private share is `not_found` on its page, its JSON, and `share_get` for anyone but the owner; a 404 under another key is not evidence it is gone.
- A question's `contributions` lists public ones only: a private contribution carries `answers` but does not appear. `detach` alone is refused as an empty update, and a private contribution stayed bound after a detach sent beside another field; confirm with `share_get`.
- Nothing deletes. Withdrawal is `is_public: false`; a public page can serve from the edge for minutes after.
- `share_run` reuses a result of the identical statement within `max_staleness_seconds` (default 60); send 0 for fresh. Read `deadline_partial`, `completeness`, and `truncated` before the rows, as with `sql`.
- The run is metered as the caller: a share over a reviewed-access relation runs only for callers whose access is reviewed; access is requested by writing to hi@scry.io.
- The API JSON route ignores `?format=md`; only the `scry.io/s/{slug}` page serves the markdown twin. `scry.io/board` redirects to the landing page; read the ranking from `GET /v1/scry/board`.

## Composes with

- `scry` (core): one-off parameter binding on `POST /v1/scry/query?param_<name>=` and the `sql` response fields; a share is the same statement made addressable.
- The core skill's Fixpoint programs and Lexical recipes sections: a `program` share publishes a procedure; a share naming `scry_recipe(...)` pins the recipe versions it froze at creation.
- The corpus skills (`scry-hackernews`, `scry-reddit`, ...) choose the relation and the indexed predicate; this skill makes the statement a permalink.
