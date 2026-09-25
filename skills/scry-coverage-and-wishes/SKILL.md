---
name: scry-coverage-and-wishes
description: >-
  Use when the question is whether Scry holds enough of a source to answer,
  why a query came back empty, or how to ask for what is not held: reading
  the coverage block on a query response, sizing and starting an on-demand
  embedding-coverage run over a source window (coverage_estimate,
  coverage_request, coverage_status, embeddings.coverage_cells), asking for
  a URL to be indexed (index_request), sending a wish to the operators
  (wish), and reading the query market and slot reservations (market_status,
  reservations). Catalog reads go through scry.relations and scry.columns.
---

# Coverage, wishes, and index requests

The coverage block, the catalog relations and the estimate tool say what is
indexed and searchable; the request, index and wish tools ask for what is not.

## When to use

- A query returned zero rows: absence, a declared hole, or an unindexed range?
- A source window needs vectors its native semantic relation does not carry, and you want the cost and storage verdict first.
- A source with no semantic relation (github, mailing_lists, forums, bluesky) should become searchable by vector.
- A YouTube channel or playlist should be indexed into the youtube.* relations.
- Something is missing, wrong, or wanted and the operators should hear it.
- A long job needs the posted price, the door's load, or a booked slot window first.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.
Plain SQL is the better tool when the relation has an `embeddings.*` companion with `serves_ann: true`: search there and skip the request.

## Surfaces

| name | what it does | required arguments or columns | what comes back | cost or limit the contract states |
| --- | --- | --- | --- | --- |
| `coverage_estimate` (MCP) | Sizes an embedding-coverage run over rows selected from a source | `selector.source`, `model`, `max_chunks`; optional `selector.ids`, `kinds`, `since`, `until` | `selected {matching, covered, native_lane{relation, sampled, searchable}}`, `requested_missing_chunks`, `estimated_*`, `eta`, `storage_admission{admits, smaller_request_can_help}` | Free. `estimated_*` are worst-case ceilings; `storage_admission` is the global reserve's verdict, not an account quota. |
| `coverage_request` (MCP) | Starts the idempotent run the estimate sized | `selector`, `idempotency_key`; `model`, `max_chunks` | `id`, `status`, `spec`, `estimate`, `selector_fully_covered`, `next_action` | Same spec and key return the existing run; settles to actual tokenizer usage. |
| `coverage_status` (MCP) | One run's state, cells, spend, failures | `request_id` (the `id` from `coverage_request`) | `status` (`queued`, `completed`, `failed`, `cancelled`), chunk counters, `actual_*`, `bytes_written`, `next_action` | Owner-scoped. |
| `embeddings.coverage_cells` (SQL) | One row per chunk embedded on demand | filter `request_id`, or `source` plus `model` | `source`, `external_id`, `kind`, `chunk_index`, `model`, `embedding`, `input_tokens`, `observed_on` | No ANN; rank row-wise with `scry_cosine_similarity(embedding, @handle)`; raw `count()` converges downward until merges finish. |
| `index_request` (MCP) | Asks for a URL to be indexed | `target` | `status` (`unsupported` writes nothing and says why) or a queued job with a SQL query for its progress | Best-effort. At this listing: YouTube; a watch, handle or channel URL indexes that channel, a playlist URL its videos. |
| `wish` (MCP) | Sends a wish of any sort to the operators | `content`; optional `channel`, `page_url`, `metadata` | `id`, `feedback_type: wish`, `created_at`, `message` with a short reference | `metadata` is stored as given. |
| `market_status` (MCP) | The query market's posted state | none | `c_now`, `congestion_pricing_active`, `census` (`expected_wait_seconds`, queue depth), `admission`, `lanes` (vector, attest, sample, embed), `reservations.available`, `charge_law` | Free; poll it instead of probing with queries. |
| `reservations` (MCP), `GET /v1/scry/reservations` | Booked slot windows and market terms | none | `reservations[]`, `slot_second_nanodollars`, `sellable_slots_max`, `booking_horizon_seconds`, `min_window_seconds`, `forward_law` | Booking is `POST /v1/scry/reservations` under `forward_law`, c locked at purchase. |
| `scry.relations` (SQL) | The served catalog as a relation | `relation`, `tier`, `extent_min`, `extent_max`, `lag_seconds`, `total_rows`, `purpose` | One row per relation the key can see | Read whole per predicate; `total_rows` runs ahead of `extent.rows`, NULL for views. |
| `scry.columns` (SQL) | One row per column of those relations | `relation`, `name`, `type`, `ordinal`, `filter_first`, `indexed` | Join `scry.relations` on `relation` | Rows follow your reach. |

## Idioms

- Estimate before request, and read `selected` first: a low `covered` beside a high `native_lane.searchable` means the window is searchable through the named native relation and needs no run; `covered` counts only this model's paid cells.
- The selector is `source` plus AND-ed narrowing: `ids` (at most 10,000), `kinds`, `since` and `until` as full RFC 3339 date-times; omit a filter to leave it open, an explicit `[]` is refused.
- Coverage sources: twitter, hackernews, forums, bluesky, mailing_lists, github. A relation with a native ANN companion is searched through it; reddit is not a coverage source.
- Use an `idempotency_key` you can regenerate: a retry returns the same run. Follow `next_action`: `coverage_status` with the run's `id` as `request_id`, then the `sql` over the cells.
- Cells this run wrote have `request_id = '<id>'`; the cohort with cells already present is `source` plus `model`. Rank them with an `embed` handle, `scry_cosine_similarity(embedding, @handle) AS sim ... ORDER BY sim DESC` (verified 2026-09-25), and hydrate text by `external_id` on the source relation (`tweet_id`, `hn_id`, `post_key`).
- Read the coverage block before reading absence: `extent {min, max, newest_event_at, computed_at, rows}`, `known_holes` with `reason`, `from`, `to`; a zero-row reply adds `zero_rows {cause, establishes}` and a `predicate_matched_nothing` warning when `read_rows` is 0 (verified 2026-09-25 on `hackernews.items`); a virtual or derived relation carries `extent_unavailable_reason` instead.
- Catalog questions are SQL: `scry.relations` for tier, extent span and lag, `scry.columns` for which relations carry a column, joined on `relation`; the same rows `GET /v1/scry/schema?mode=index` lists.
- Before a long job read `market_status`: `c_now` against your `max_multiplier`, `census.expected_wait_seconds`, `lanes.vector.ok` for ANN over `embeddings.*`; a booked window redeems at any posted price.
- A wish is prose to a person: what was wanted, what was tried, ids and repro steps in `metadata`, the public page in `page_url`.
- Reviewed-access relations: access is reviewed and requested by writing to hi@scry.io.

## Worked calls

**Is one hour of Hacker News already searchable by vector, and what would covering it cost?**

```bash
curl -s https://api.scry.io/mcp -H "Authorization: Bearer $SCRY_API_KEY" -H 'content-type: application/json' -H 'accept: application/json' -H 'mcp-protocol-version: 2025-06-18' -H 'mcp-method: tools/call' -H 'mcp-name: coverage_estimate' -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"coverage_estimate","arguments":{"selector":{"source":"hackernews","since":"2026-09-20T00:00:00Z","until":"2026-09-20T01:00:00Z"},"model":"voyage-4-nano","max_chunks":5}}}'
```

`native_lane.searchable` is near `sampled` on `embeddings.hackernews_items`, so the hour is searchable there and needs no run; `storage_admission.admits` and `estimated_charge_nanodollars` size one anyway. (verified 2026-09-25)

**Start that run anyway, capped at two chunks, under a key a retry can reuse.**

```bash
curl -s https://api.scry.io/mcp -H "Authorization: Bearer $SCRY_API_KEY" -H 'content-type: application/json' -H 'accept: application/json' -H 'mcp-protocol-version: 2025-06-18' -H 'mcp-method: tools/call' -H 'mcp-name: coverage_request' -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"coverage_request","arguments":{"selector":{"source":"hackernews","since":"2026-09-20T00:00:00Z","until":"2026-09-20T01:00:00Z"},"model":"voyage-4-nano","max_chunks":2,"idempotency_key":"skill-draft-scry-coverage-and-wishes-2026-09-25"}}}'
```

`id`, `status: queued`, `selector_fully_covered: false` (the cap excluded matching chunks), and `next_action` naming `coverage_status` with that `id` as `request_id`. (verified 2026-09-25)

**Did the run finish, what did it write, and what did it charge?**

```bash
curl -s https://api.scry.io/mcp -H "Authorization: Bearer $SCRY_API_KEY" -H 'content-type: application/json' -H 'accept: application/json' -H 'mcp-protocol-version: 2025-06-18' -H 'mcp-method: tools/call' -H 'mcp-name: coverage_status' -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"coverage_status","arguments":{"request_id":"0835e000-1a2e-be34-e946-336442d372d2"}}}'
```

`status: completed`, `completed_chunks: 2`, `failed_chunks: 0`, `actual_input_tokens`, `actual_charge_nanodollars`, `bytes_written`, and a `next_action` carrying the SQL over the cells. (verified 2026-09-25)

**Which cells did this run write?**

```sql
SELECT source, model, external_id, kind, chunk_index, input_tokens, observed_on
FROM embeddings.coverage_cells
WHERE request_id = '0835e000-1a2e-be34-e946-336442d372d2'
ORDER BY external_id, chunk_index
LIMIT 10
```

One row per chunk with the source id in `external_id`; the coverage entry carries `grain {logical_key: [source, entity_id], version_column: observed_on}` and an `extent_unavailable_reason`, not an extent. (verified 2026-09-25)

**Which primary relations carry an observed_on column, and how far does each extend?**

```sql
SELECT c.relation, r.tier, r.extent_max
FROM scry.columns AS c
INNER JOIN scry.relations AS r ON r.relation = c.relation
WHERE c.name = 'observed_on' AND r.tier = 'primary'
ORDER BY c.relation
LIMIT 8
```

Relation names with a measured `extent_max` (NULL where no date basis is declared); both catalog relations appear in the coverage block as virtual. (verified 2026-09-25)

## Traps

- `coverage_request` returns the run under `id`; `coverage_status` takes it as `request_id`. Anything else is refused (`request_id must be a UUID`), and the same string in a cells predicate fails to parse.
- `selector_fully_covered: false` with `status: completed` is a capped run, not a failed one: raise `max_chunks` under a different key or narrow the window. `completed_chunks` counts this run's writes only.
- `estimated_charge_nanodollars: 0` is the local lane under slack, not a fixed price: the run settles to actual usage; the lane is the estimate's `execution`.
- `storage_admission.admits: false` is global pressure, not your quota; `smaller_request_can_help: true` says a narrower selector may pass.
- `embeddings.coverage_cells` refuses `scry_vector_topk_distance`; project `embedding` only under a tight LIMIT.
- `index_request` on a host no lane claims answers `status: unsupported` with nothing written; progress on a supported host is the returned SQL.
- `market_status.lanes` is the engine's state, not this key's scopes (`whoami`).
- The admission law the market tools cite is the MCP `schema` tool's `mode: "contract"` (key `admission`); REST `?mode=contract` is refused.

## Composes with

- The core `scry` skill supplies the query door, the `schema` tool, and the full reading of `zero_rows` and `known_holes`; this skill adds the on-demand vectors and the asking surfaces.
- `embed` mints the `@handle` that ranks coverage cells and `vector_delete` removes it; hydrate ranked `external_id`s through the per-source skill (`scry-hackernews`, `scry-twitter-archive`, `scry-forums-and-qa`, `scry-mailing-lists`, `scry-github`).
- `whoami` lists the key's scopes and tool gates; `scry-video` reads the youtube.* relations an `index_request` fills.
