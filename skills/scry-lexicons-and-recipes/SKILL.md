---
name: scry-lexicons-and-recipes
description: >-
  Use when a question is vocabulary-shaped: what a word means or which parts
  of speech it takes (lexicons.entries, Wiktionary and GCIDE/Webster 1913
  records); how to write a phrase, proximity, regex, or negated search as one
  SQL predicate (scry_lex); how to select, score, or meter rows by a named
  term set such as hedging or certainty (scry_recipe, scry_recipe_score,
  scry_recipe_density, scry_recipe_near); how to expand a seed vocabulary
  from one relation with document-frequency denominators (recipe_derive); or
  how to publish and version a reusable keyword instrument (recipes,
  recipe_write).
---

# Lexicons and lexical recipes

Two dictionaries as a relation, the search grammar as a SQL operand, and a shared shelf of measured term sets that select, score, and version under one name. Each turns a vocabulary into a predicate that counts with a denominator and cites its rows.

## When to use

- What a word means, which parts of speech it takes, which senses Wiktionary or Webster 1913 lists for it.
- Which rows match a phrase, a proximity window, a regex, or a negated line, inside a GROUP BY or a countIf.
- How much hedging, certainty, or polarity a cohort carries, compared across sources, months, or authors.
- Which surface forms a concept takes in one community, with the document frequency of each candidate.
- Publishing a curated vocabulary as a named, versioned recipe that any statement can reuse and pin.

The core `scry` skill is assumed loaded: authentication, the query door, and the response fields are its material. Plain SQL is the better tool when one known token answers the question: `hasToken(search_text_lc, 'term')` is the floor each helper compiles down to.

## Surfaces

| Surface | What it does | Required | Returns | Contract limits |
|---|---|---|---|---|
| `lexicons.entries` | Wiktionary (kaikki.org) and GCIDE/Webster 1913 records, one JSON envelope each | `source_key` (`wiktionary_kaikki` or `gcide_websters1913`); the record is `payload.record`; `hasToken(lower(payload), '<token>')` engages the index | Rows; fields via `JSONExtractString(payload, 'record', '<field>')` | Frozen snapshot, no `extent`; a GROUP BY needs a literal LIMIT |
| `scry_lex('<line>'[, text])` | Compiles the search grammar (words, "phrases", `/regex/`, OR, `-`negation, `NEAR/k`, `"phrase"~n`, filters) into the relation's index-engaging predicate | One relation per statement, or a relation-qualified text argument | UInt8 | At most 8 calls per statement; an operator the bound text cannot express is a hard error; `word~` fuzzy is refused |
| `scry_recipe('<slug>'[, text])` | Membership in a shared recipe; the one helper with algebra: `a - b`, `a & b`, `a ^ b` | Slug or expression | UInt8 | Operators whitespace-separated, one kind per call, no parentheses, `^` takes two operands |
| `scry_recipe_score('<slug>'[, text])` | Weighted member occurrences per token of the text | One positive slug | Float64 | Token members by frequency, phrase and regex by occurrence; at most 256 phrase/regex members |
| `scry_recipe_density('<slug>'[, text])` | Weighted member occurrences per 1,000 characters | One positive slug | Float64 | At most 256 members, one regex pass per member per row; adds no membership predicate |
| `scry_recipe_near('<a>', '<b>', k[, text])` | True where token-form members of `a` and `b` fall within k tokens | Two positive slugs, 1 ≤ k ≤ 64 | UInt8 | Per-row position scan: co-membership-prefiltered subquery, LIMIT ≤ 500; phrase and regex members ignored |
| `recipes` (MCP) | Lists the shelf or reads one recipe | None to list; `slug`; optional `version`, `history`, `full`, `diff: [a, b]`, `limit`, `after` | Listing: slug, kind, stance, n_terms, has_measurements, next_after; by slug: terms, options.blind_to, measurements, head_version | `limit` at most 500 (default 100); a version the slug lacks is refused |
| `recipe_derive` (MCP) | Read-only candidate terms from one relation with document-frequency denominators | `seeds` (1 to 8, phrases up to 4 words), `relation`; optional `source`, `window_days` (default 240), `prefixes`, `contrast` (slug or seeds), `exclude` (slug) | `candidates[]` (`t`, `kind` prefix or cooccur, `df_matched`, `df_relation`, `salience`), `cohort`, `window`, `notes` | One relation per call |
| `recipe_write` (MCP) | Publishes a whole recipe version under compare-and-swap | `slug`, `if_version`, `kind` (concept, affect, stance, register, structural), `stance`, `license`, `terms[]` (`t`, `form`, `w`), `options`, `provenance`, `measurements`; optional `note`, `agent` | `{slug, version, n_terms}` | Slug 1 to 64 chars of `[a-z0-9_-]`; at most 16000 terms; later versions owner-only (`lexical_recipe_owned`) |

## Idioms

- Climb the ladder: one token, then a `scry_lex` line, then a recipe. Check the shelf with `recipes` before writing a keyword list; a slug's `measurements.doc_precision.read_as` is its honest usage.
- Pick the plane by match rate: near zero on your relation makes a selector (`scry_recipe` in WHERE), near one a scorer (density or score). Compare register across sources or document lengths with density, never raw membership share; a char-weighted trend is `sum(density * length(text)) / sum(length(text))` per period.
- Score, density, and near meter each row they touch and engage no index: bound them with membership in WHERE or a LIMITed subquery, and inside a subquery pass the text explicitly (`scry_recipe_density('slug', lower(body))`).
- Algebra is membership-only. `countIf(scry_recipe('a & b'))` beside each count measures overlap instead of assuming disjointness; a per-cohort ratio of two membership counts cancels base rates; a composition worth reusing is published as its own slug, which also makes it scoreable.
- `scry_lex` binds the relation's search text unless the second argument pins another expression (`scry_lex('rust', title)`); `lower()` a mixed-case expression when case must not matter.
- Read `lexicons.entries` through `source_key` first, then the record: Wiktionary words are lowercase with `pos` and `senses[].glosses`; GCIDE headwords are capitalized (`Hedge`) with the entry as markup in `raw`; the equality on `word` narrows the index hits to the headword.
- Derive before hand-writing. Seeds must occur as whole lowercase tokens in the window; stems go in `prefixes`; rank `cooccur` candidates by `salience` (`df_matched / df_relation`), never by `df_matched`, which returns function words; a cohort of few `matched_docs` is noise, so widen the window. A stance pair derives with `contrast` and `exclude`; `diff: [a, b]` on `recipes` reports Jaccard and asymmetric terms.
- Publish with `if_version: 0` to create, or with the `head_version` that `recipes` reports; stance is identity, so a different reading contract is another slug, not another version. The `sql` tool's `recipe_versions: {"slug": N}` pins operands; shares freeze their pins at create.
- Each helper is a predicate over rows, so results cite by the relation's row key with the denominator in the same statement; a lexicon row cites `source_key` plus `source_record_id`.

## Worked calls

**Which senses and parts of speech does Wiktionary give "hedge"?**
```sql
SELECT JSONExtractString(payload, 'record', 'pos') AS pos, arrayMap(s -> JSONExtractString(s, 'glosses'), JSONExtractArrayRaw(payload, 'record', 'senses')) AS glosses FROM lexicons.entries WHERE source_key = 'wiktionary_kaikki' AND hasToken(lower(payload), 'hedge') AND JSONExtractString(payload, 'record', 'word') = 'hedge' LIMIT 3
```
One row per part of speech with its ordered gloss list; the noncommittal-statement sense sits beside the garden one. (verified 2026-09-25)

**Which September 2026 stories carry "rust" in the title?**
```sql
SELECT hn_id, title FROM hackernews.items WHERE original_timestamp >= '2026-09-20' AND hn_type = 'story' AND scry_lex('rust', title) ORDER BY original_timestamp DESC LIMIT 3
```
Story rows with their ids; the line is bound to `title`, so the body is not consulted. (verified 2026-09-25)

**How many comments hedge without asserting certainty, and how many do both?**
```sql
SELECT countIf(scry_recipe('hedging - certainty')) AS hedge_only, countIf(scry_recipe('hedging & certainty')) AS both, count() AS n FROM hackernews.items WHERE original_timestamp >= '2026-09-20' AND hn_type = 'comment'
```
Three counts in one row: difference, overlap, denominator; overlap measures disjointness. (verified 2026-09-25)

**Is hedging density in comments drifting month by month?**
```sql
SELECT toStartOfMonth(original_timestamp) AS m, round(sum(scry_recipe_density('hedging') * length(search_text_lc)) / sum(length(search_text_lc)), 3) AS d FROM hackernews.items WHERE original_timestamp >= '2026-06-01' AND hn_type = 'comment' AND scry_recipe('hedging') GROUP BY m ORDER BY m LIMIT 6
```
One row per month, char-weighted; the WHERE membership keeps the density pass off rows with no member. (verified 2026-09-25)

**In how many co-member comments does a hedge sit within twelve tokens of a certainty marker?**
```sql
SELECT countIf(scry_recipe_near('hedging', 'certainty', 12, t)) AS near12, count() AS n FROM (SELECT search_text_lc AS t FROM hackernews.items WHERE original_timestamp >= '2026-09-20' AND hn_type = 'comment' AND scry_recipe('hedging') AND scry_recipe('certainty') LIMIT 500)
```
A count with its denominator over the bounded co-member sample; adjacency separates what co-membership cannot. (verified 2026-09-25)

**Which surface forms does "interpretability" take on LessWrong, with denominators?**
```bash
curl -s -X POST https://api.scry.io/mcp -H "Authorization: Bearer $SCRY_API_KEY" -H 'content-type: application/json' -H 'accept: application/json' -H 'mcp-protocol-version: 2025-06-18' -H 'mcp-method: tools/call' -H 'mcp-name: recipe_derive' --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"recipe_derive","arguments":{"seeds":["interpretability"],"prefixes":["interp"],"relation":"forums.posts","source":"lesswrong","window_days":180}}}'
```
`candidates` mixes `prefix` forms (interpretable, interp, interpreting) and `cooccur` terms, each with `df_matched`, `df_relation`, `salience`; `cohort` gives the matched and comparison counts. (verified 2026-09-25)

## Traps

- An unknown slug is `invalid_request` ("unknown lexical recipe slug"); slugs are exact.
- `scry_recipe_score('a - b')` is refused: score and density take one slug. `scry_recipe_near` refuses k above 64 and sees only token members, so read the term forms first.
- A regex `scry_lex` line pinned to a text expression without a prefilter (`scry_lex('/GPT-[0-9]/', title)` on `hackernews.items`) is refused as `invalid_lex_helper`; the same line on the default search text runs.
- A bare score, density, or near over a whole relation is a scan, and the `scan` warning says so; bound it with membership in WHERE or a subquery LIMIT.
- Membership near one carries little signal: `hedging` matches most of a hedging-rich cohort; its `read_as` line says to rank by density or score there.
- On `lexicons.entries`, `read_rows: 0` with `predicate_matched_nothing` means the token as written is absent from that `source_key` (Webster 1913 lacks later coinages; its headwords are capitalized); check the other source.
- A stale `if_version` answers `lexical_recipe_version_conflict` carrying the head; resend with it. Only the first writer's account publishes later versions.
- Nothing deletes a published recipe: a slug on the shared shelf is permanent, so publish what you would keep and version the rest.
- Reviewed-access relations: access is reviewed and requested by writing to hi@scry.io.

## Composes with

- The core `scry` skill owns the query door, the response envelope, and the `q` line, which resolves the fuzzy and multi-relation sweeps `scry_lex` refuses.
- `schema` with `relation=<name>` shows `text_indexes`, which decides which text expression a regex `scry_lex` line can bind.
- Embedding neighbours (`embed`, `vectors`) supply vocabulary you could not guess, fed back as seeds for `recipe_derive` and tokens for `scry_lex`.
- `share` freezes a statement's recipe pins at create, so a published analysis keeps reading the same terms after the shelf moves.
