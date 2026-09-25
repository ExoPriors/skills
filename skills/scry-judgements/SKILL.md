---
name: scry-judgements
description: >-
  Use when a question is about model-made rankings of corpus entities or the
  first appearance of an exact phrase: which lenses and axes hold cardinal
  scores, the top of one ladder with its uncertainty, whether two judging
  models or two prompt phrasings agree, the raw pairwise trace behind a score
  with refusals and errors, or when a phrase must be dated per corpus with
  verbatim and word-only counts on the claimed-authorship and
  estate-observation clocks. Relations judgements.scores_current,
  judgements.scores, judgements.comparisons; MCP tool attest; GET
  /v1/judgements/attributes.
---

# Judgements and attestations

The judgements relations are a public ledger of model-made pairwise comparisons between corpus entities, fitted into cardinal scores per lens (campaign) and axis (attribute prompt); a row is evidence about the judging model's output, never a fact about the entity. The `attest` tool dates an exact phrase per corpus: verbatim and distinctive-word counts, and the earliest match on two clocks.

## When to use

- Which lenses and axes hold scores, over how many entities, and when the latest fit landed.
- The top of one ladder: the highest-scored entities on one axis, with uncertainty.
- Whether two judging models, or two phrasings of one axis, rank the same entities the same way.
- The raw pairwise trace behind a score, refusals and provider errors included.
- When and where an exact phrase first appears, per corpus, and how many documents carry it verbatim versus only its words.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.
Plain SQL is the better tool for anything about the entities themselves, and for a substring or count over one relation (`position(search_text_lc, '<phrase>') > 0` with a long `max_seconds`); `attest` is the cross-corpus first-date instrument.

## Surfaces

| Name | What it does | Required arguments or columns | What comes back | Cost or limit the contract states |
| --- | --- | --- | --- | --- |
| `judgements.scores_current` (primary) | Latest public score per (lens, axis_key, entity_id, entity_hash) across models, harnesses and runs | Filter `lens`, `axis_key`, `entity_id` first; `run_id = '<id>'` optional | `rank`, `latent_mean`, `latent_std`, `z_score`, `percentile`, `entity_text`, run metadata (`model`, `harness`, `item_count`, `comparisons_used`, `stop_reason`, `topk_error`, `run_cost_nanodollars`) | Metered as any statement; `ORDER BY rank ASC` compares within one `run_id` |
| `judgements.scores` (depth) | One row per (run, entity) for each fitted run, replaced fits included | Filter `lens`, `axis_key`, `run_id`, `entity_id` first | The same columns | Metered as any statement |
| `judgements.comparisons` (depth) | Raw pairwise measurements, refusals and provider errors included | Filter `lens`, `axis_key`, `run_id` first; `refused = 0` optional | `comparison_index`, `entity_a_id`, `entity_b_id`, `swapped`, `cached`, `refused`, `higher_ranked` (`A`, `B`, or empty), `ratio`, `confidence`, `error`, token and cost columns, `completion` where retained | Metered; filter before reading raw traces |
| `attest` (MCP tool) | Per-corpus verbatim attestation of an exact phrase inside the documents holding its distinctive words | `phrase` (1-400 characters, one alphanumeric word of 3+); optional `lanes` (relation names), `max_seconds` (1-120) | `verdict`, `verbatim_matches`, `verbatim_documents`, `token_matches`, `first_content`, `first_observed`, per-lane rows, `complete`, `partial`, `headline_scope`, `deadline_note`, `semantics` | Unmetered, never charged; lanes run in parallel under per-lane budgets (10-45 s by default), wall time is the slowest lane |
| `GET /v1/judgements/attributes` | The lens and axis catalog | Bearer key, no arguments | One row per (lens, axis_key): `axis_prompt`, `axis_prompt_hash`, `prompt_variants`, `entity_count`, `last_scored_at` | Free read |

No relation here is reviewed-access.

## Idioms

- A ladder is one run: `rank`, `item_count`, `percentile` and `z_score` belong to a `run_id`. Compare ranks inside one run; match an entity across runs or axes by `entity_hash` (sha256 of `entity_text`): one `entity_id` with different text is two rows.
- Entity ids are `source:key` (`hackernews:48882716`, `twitter:2078983078341722487`, `arxiv:1207.0580`, `lesswrong::<id>`). Hydrate from the source relation by its row key with an IN-list, never a join: a join scans the source relation end to end and silently drops the entities from other sources.
- Axis families carry phrasing variants after `#` (`novel-world-expanding-hit#a`, `#b`); rank agreement across the variants is the coherence evidence for the axis. The same join on `entity_hash` measures agreement between two models on one axis.
- A pair is asked in both orders: `swapped = 1` marks the reversed presentation of the pair before it, so half a run's rows are position controls; `cached = 1` reused a stored verdict; a refusal or provider error keeps its row with `higher_ranked` empty, `ratio` and `confidence` NULL.
- Cite a score as model, lens, axis, run, rank of `item_count`, and mean with `latent_std`; cite the entity by its source row, never by the judgement row.
- `attest` cost follows the rarest distinctive word: choose a phrase anchored on a rare word, narrow with `lanes`, widen with `max_seconds` up to 120. Verdicts: `verbatim_found`, `tokens_only` (the words but not the phrase), `absent` (no lane holds even the words, and each queried lane completed), `inconclusive` (a lane that did not finish may hold it). An unknown lane name's error lists the roster.
- Two clocks: `first_content` is the oldest matching document's own creation time (backdatable, and an edited document dates under its creation); `first_observed` is when this estate's text index landed the row, an upper bound on public availability.

## Worked calls

**Which lenses and axes hold scores, over how many rows and runs, and how recent is the latest fit?**

```sql
SELECT lens, axis_key, uniqExact(run_id) AS runs, count() AS rows_, max(observed_on) AS latest FROM judgements.scores_current GROUP BY lens, axis_key ORDER BY lens, axis_key LIMIT 40
```

One row per (lens, axis) with its entity count and the date of the standing fit; `runs` above one means two runs share the latest fits. (verified 2026-09-25)

**Top of one ladder, with uncertainty.**

```sql
SELECT rank, entity_id, substring(entity_text, 1, 60) AS head, round(latent_mean, 3) AS mu, round(latent_std, 3) AS sigma, round(percentile, 1) AS pct, model, run_id FROM judgements.scores_current WHERE lens = 'query-board' AND axis_key = 'corpus-reach' ORDER BY rank ASC LIMIT 5
```

Five rows from one `run_id` with the fitted mean and standard deviation; two entries whose intervals overlap are not ordered by this evidence. (verified 2026-09-25)

**Do two judging models rank one axis the same way?**

```sql
SELECT count() AS shared, round(corr(a.latent_mean, b.latent_mean), 3) AS r, round(avg(abs(toInt64(a.rank) - toInt64(b.rank))), 2) AS mean_rank_gap FROM judgements.scores AS a INNER JOIN judgements.scores AS b ON a.entity_hash = b.entity_hash WHERE a.lens = 'arxiv' AND a.axis_key = 'interestingness' AND b.lens = 'arxiv' AND b.axis_key = 'interestingness' AND a.run_id = 'jrun_27fd4f5190504938bc1d8871f8599ef8' AND b.run_id = 'jrun_b61f63f83cef4f46bf41d90d70194688' LIMIT 1
```

One row: shared entities, the correlation of the two fitted latents, and the mean absolute rank gap; the join needs its literal `LIMIT 1` even though it returns one aggregate row. (verified 2026-09-25)

**The pairwise trace behind one run, position controls visible.**

```sql
SELECT comparison_index, entity_a_id, entity_b_id, swapped, higher_ranked, ratio, confidence, refused, error FROM judgements.comparisons WHERE lens = 'query-board' AND axis_key = 'corpus-reach' AND run_id = 'jrun_b853fa84177d4ab18fb65262cc386887' ORDER BY comparison_index ASC LIMIT 5
```

Consecutive indices come in pairs: index 2 is index 1 with `swapped = 1`, the same two entities in the other order, and the winner should agree while `ratio` may differ. (verified 2026-09-25)

**When did "vibe coding" first appear on Hacker News, and how often?**

```bash
curl -s https://api.scry.io/mcp -H "Authorization: Bearer $SCRY_API_KEY" \
  -H 'content-type: application/json' -H 'accept: application/json' \
  -H 'mcp-protocol-version: 2025-06-18' -H 'mcp-method: tools/call' -H 'mcp-name: attest' \
  --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"attest","arguments":{"phrase":"vibe coding","lanes":["hackernews.items"],"max_seconds":20}}}'
```

`verdict: verbatim_found`, `complete: true`, `verbatim_matches` and `verbatim_documents` for the lane under `token_matches`, `first_content` on 2025-02-03 with its item URI, `first_observed` months later (the index landing). (verified 2026-09-25)

**Is a phrase attested anywhere in the estate, and where first?**

```bash
curl -s https://api.scry.io/mcp -H "Authorization: Bearer $SCRY_API_KEY" \
  -H 'content-type: application/json' -H 'accept: application/json' \
  -H 'mcp-protocol-version: 2025-06-18' -H 'mcp-method: tools/call' -H 'mcp-name: attest' \
  --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"attest","arguments":{"phrase":"Turing-complete search","max_seconds":30}}}'
```

`verdict: verbatim_found` on `reddit.posts` in 2017, but `partial: true`: `headline_scope` names the lanes the counts cover, `lanes_skipped` (`predicted_over_budget`, with `token_hits` as an upper bound where the words index answered) and any `lanes_timed_out` name the rest, and `deadline_note` gives the follow-up call that fits. (verified 2026-09-25)

## Traps

- A query without a literal `LIMIT` is refused (`missing_limit`); the bare-aggregate exemption does not cover a join, so the agreement query carries `LIMIT 1`.
- `ORDER BY rank` without a `run_id` interleaves runs, and `comparison_index` restarts per run, so a trace without `run_id` mixes runs at one index.
- No coverage extent is declared here (`extent_unavailable_reason`) and `empty_result_means: undeclared`: an empty result says nothing about absence; read the attributes catalog before concluding a lens or axis does not exist.
- `completion` and `rendered_prompt_digest` are empty on cached and pre-retention rows; `submitted_by` empty is unattributed. A refused pair still occupies a row.
- `attest` refuses arguments other than `phrase`, `lanes`, `max_seconds`, and unknown lane names. A phrase whose first or last word is a fragment of a longer word in the corpus is outside its population; that question is a `position` predicate in SQL.
- `partial: true` means the headline counts and dates cover the completed lanes only; a lane subset narrows an `absent` claim to those lanes.
- `first_content` dates the oldest document containing the phrase, not the coinage: "vibe coding" on `reddit.posts` dates to a 2019 thread in another sense, so read `earliest_uri`. Lanes with day-precision clocks report midnight.
- `first_observed` is the text index landing, which can be later than the native relation's own first-observed column; `verbatim_matches` counts observation rows (a document observed twice counts twice) and `verbatim_documents` distinct documents, neither the native relation's current-state count.
- `probe.sampled_df` sums a sample of the whole indexed surface, not the queried lanes; it sizes the cost, never the answer.

## Composes with

- The core `scry` skill supplies the door; `rerank` orders documents you already hold, while a ladder with uncertainty over 2-200 entities is commissioned at `POST /v1/judgements/runs` (`entities`, `axis_key`, `axis_prompt`, `requested_k`, `model`, `privacy` public or private, optional `lens`) and its settled rows land in these relations.
- `lens = 'query-board'` is the ledger behind the public board of query shares (`board: true` in `scry-query-permalinks`); `axis_key` is the criterion.
- Hydrate ranked entities through the source skills (`scry-hackernews`, `scry-academic`, `scry-twitter-archive` for the historical Twitter archive) by row key; `scry-lexicons-and-recipes` finds the vocabulary a phrase travels under before `attest` dates it.
