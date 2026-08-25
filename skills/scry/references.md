# Scry references

## Deep research operations

The higher-order loop for multi-step research over Scry: plan surfaces, fan
out lexically, keep a probe ledger, escalate to semantic ranking only over
bounded candidates, adjudicate with explicit denominators, and end in an
artifact another agent can pick up.

### Operating loop

1. **Frame.** State the question and several labeled hypotheses. For each,
   name what evidence would confirm or refute it and which source families
   could plausibly hold that evidence.
2. **Plan surfaces manually.** Read `/v1/scry/schema`, then enumerate the
   partition values of every candidate relation (e.g.
   `SELECT source, count() FROM forums.posts GROUP BY source`) so the lane
   plan starts from the full source roster, not from guessed names. Assign
   each hypothesis the enabled relations whose source family could hold its
   evidence, one lane per family. (`POST /v1/scry/route` is a usable
   first-step shortlist — never a substitute for this enumeration
   discipline.)
3. **Fan out lexically** (below) inside each lane.
4. **Probe bounded, record every probe** in the ledger (below).
5. **Escalate to semantic ranking** only over a bounded candidate set.
6. **Adjudicate** with explicit coverage denominators.
7. **Externalize** the result and the ledger.

### Lexical fanout

The dominant failure mode in corpus research is missing vocabulary, not
misreading rows. Before concluding absence — and before any semantic or
judgement-heavy step — expand each hypothesis into term variants:

- insider jargon and community shorthand alongside formal names;
- exact phrases and quoted strings; product, project, and code names;
- abbreviations, hyphenation variants, and common misspellings;
- per-source dialects — the same idea is worded differently in Hacker News
  titles, Reddit bodies, and Mastodon posts, so vary terms per relation.

Variants cost little to score and to harvest: run each variant as a
sub-second count-only probe before any retrieval, and mine new variants
from the corpus itself with the co-occurrence pattern
(§ Shape probes, § Vocabulary expansion).
A variant's count is its ledger row; zero-count variants are vocabulary
findings, not dead ends.

Run one bounded probe per variant. Typed search:

```
POST /v1/scry/search
{"query": "…", "method": "lexical", "limit": 20,
 "sources": [...], "kinds": [...], "from": "…", "to": "…"}
```

`method` is `lexical`, `hybrid`, or `rerank`; `limit` is capped at 20; `from`
and `to` are RFC 3339. For token-level SQL fanout, use the enabled
parameterized search relations advertised by `/v1/scry/schema`.

Keep fanning while marginal probes still surface new relevant records. Stop
when two consecutive rounds of fresh variants produce nothing new — a fixed
probe count is not a stopping rule.

### Probe ledger

One row per probe, kept as you go and preserved in the final artifact:

| field | content |
| --- | --- |
| hypothesis | the label this probe serves |
| query | exact query text or SQL |
| scope | relation or sources/kinds, time window |
| result | `row_count`, duration, truncation state |
| verdict | what the rows confirmed, ruled out, or left open |
| next move | widen, narrow, swap source, escalate, or stop |

The ledger is what makes an answer auditable: it shows which vocabulary and
which sources the conclusion actually rests on.

### Candidate reuse and hydration

A search response carries `candidate_set.record`. Pass it back as
`candidate_record` to refine (`hybrid` or `rerank`) against the same
shortlist instead of re-retrieving. Search results and query rows arrive as
plain JSON. Hydrate a source record with
`GET /v1/scry/search/records/{record_ref}`.

### Semantic escalation

Use registered vector helpers and relations (§ Registered vector
helpers) for semantic
ordering over a candidate list you already trust lexically. Every semantic
ordering is a ranking hypothesis: confirm top rows against lexical evidence
and provenance before reporting a semantic conclusion.

### Adjudication and denominators

- Keep claims separate: relevance, coverage, freshness, and provenance are
  different assertions with different evidence.
- State the denominator: which relations, sources, and time windows were
  actually searched, against what exists (`/v1/scry/schema`, `GET /v1/stats`,
  and route `coverage_warnings`).
- Absent rows prove absence from the searched corpus slice, not absence in
  the world. A recent load time does not imply a recent source event.
- When lanes disagree, report the disagreement and what would resolve it;
  do not average it away.

### Report integrity

Retrieval discipline alone does not make the artifact honest. Before you
externalize a report or share, apply these write-side rules. They are the
gate between the probe ledger and the delivered text.

**Read first, write after.** Hydrate a record before you describe its
content. A title or snippet does not license a claim about the body.

**Trace each claim.** Each number, name, quotation, and direction in the
report must match a hydrated record or a ledger row. Remove or flag a claim
that has no probe behind it.

**Flag, do not fill.** Mark an unverified fact with a visible
`[UNVERIFIED: …]` marker in the artifact. A silent fill is a fabrication,
and one fabricated attribution poisons trust in the full report.

**Fabrication patterns.** Examine each paragraph against the known failure
shapes:

- an author, handle, or source name that no retrieved row contains;
- a statistic more exact or more favorable than the rows show;
- a priority claim — "first", "earliest", "only" — that no probe tested;
- a description of record content written from its title alone;
- a reference to a record that no ledger row returned.

**Calibrate strength to evidence.** When two or more independent sources
agree, state the finding directly. When one source speaks, attribute it in
the sentence. When the searched slice holds no evidence, say so with the
denominator. Do not hedge as a default register: filler such as "may
suggest" or "promising" signals an unread source, not caution.

**Take positions.** A neutral catalog of findings is the default failure
mode. Where the evidence licenses a verdict, write one clear verdict
sentence and bound it by the stated denominator.

### Continuation

End in artifacts another agent can pick up: shares
(`POST /v1/scry/shares`, then `PATCH /v1/scry/shares/{slug}`) hold the
narrative, the ledger, and open hypotheses. Confirm a surface's presence in
the live context `endpoint_access` before depending on it.

**Orientation shares.** At the end of a multi-session investigation, save
one share per relation you worked: its observed extent edges, the value
spaces you verified (real subreddit/lang spellings), the vocabulary map
your fanout converged on (variants with counts, including the zero-count
findings), and the probe shapes that worked. Resuming means running that
share, not re-deriving corpus shape from scratch — recomputing this
knowledge costs real probes every session; a share replays it for the
price of one call.

### Budget discipline

Start with a small `LIMIT` before wide scans; widen only after a relevant
bounded probe. Spend tokens on more probes and better vocabulary before
spending on wider row counts.

## Comparative study design

Governs any Scry study that compares cohorts or tests a hypothesis ("do X-people
do Y more?") rather than retrieving facts. Retrieval discipline (vocabulary
fanout, probe ledgers, coverage denominators) is § Deep research operations;
this section governs inference. The core stance: **a lexicon is an instrument, not a
definition** — it has a bandwidth, a stance it selects for, and a
false-positive profile that varies by community register.

### Before querying

1. **Pre-state the refuter.** Write down, before the first query, what result
   would refute the hypothesis and which single query would discriminate. If
   no result could refute it, the design is circular — redesign.
2. **Selection–outcome independence.** If any selection term could plausibly
   appear in an outcome-positive row, the finding is a tautology ("people who
   say 'shame on you' also insult people"). Audit the two lexicons for
   semantic overlap first; excluding matched rows from the outcome does not
   repair selection-level circularity.
3. **Stance, not just topic.** A lexicon selects a speech act: broadcast
   ("kindness matters"), accusation ("have some empathy"), self-description
   (display-name branding). Conclusions can invert across stance variants of
   the same topic — run them. Verified example: non-directed virtue talk
   predicted below-baseline reply hostility while directed moral accusation
   predicted 2–3× baseline, in the same windows with the same outcome lexicon.

### Design mechanics

4. **Temporal holdout.** Same-window selection and outcome co-occur in the
   same conversations, so one bad week produces both. Select in window 1,
   measure in a disjoint later window; a trait claim requires cross-window
   stability.
5. **Controls through the same pipeline.** Draw the baseline from the same
   relation, filters, and thresholds — e.g. a hash slice
   (`intHash64(author_id) % N = 0`) — never from a different surface or a
   differently-filtered run. Compare only within-run; a `HAVING` change moves
   the baseline.
6. **Rates over counts, both means, plus a tail.** Per-author rates with
   minimum denominators (e.g. ≥20 replies). Report macro (mean of author
   rates) and micro (pooled posts) — divergence flags a few heavy authors.
   Add a tail statistic (fraction of authors above a threshold); means hide
   bimodality.
7. **Power before narration.** Compute the binomial SE at the observed cell
   size; a 72-author cell cannot resolve differences under ~10 points. Treat
   sub-noise differences and non-monotonic small cells as noise until
   replicated.

### After rows come back

8. **Read the matches, per cohort.** Sample matched rows from every cohort
   including the control and count false positives separately — register
   differs across communities, so lexicon noise is not symmetric. Known
   traps: match terms inside @handles and URLs, quotations, banter and hype
   usage, self-deprecation. Strip mentions before matching when terms could
   appear in handles.
9. **Check who the cohort is.** Heavy signalers especially include brands,
   bots, and content mills. Inspect handles, follower counts, and reply
   ratios before interpreting a cohort as "people".
10. **Exploratory vs confirmatory.** An operationalization invented after the
    first one failed is exploratory: label it, replicate on an untouched
    window before claiming, and report the failed operationalizations in the
    final artifact alongside the one that worked.

### Interpretation ladder

Licensed: predictive claims scoped to corpus, language, lexicon band, and
window. Not licensed without further evidence: causal or psychological
stories (a common cause usually fits equally well), off-platform
generalization, and absence claims outside the instrument's band — passive
aggression, sarcasm, and concern trolling are invisible to overt lexicons, so
"not found" means "not found in this band"; escalate to semantic measures to
probe further. Scope every conclusion by moderation survivorship (hostile
accounts get suspended) and by crawl selection of the corpus.

## Orthogonal enumeration

The ask: "diverse sources on X", "what other communities discuss Y",
"angles I'm not seeing", "more hypotheses", "phrasings for the embedding
probe". The failure: one stream of recall, anchored on its first three
items, reported as coverage. The fix is § Deep research operations with
the possibility space made explicit — a field, covered, with a
denominator — in four steps.

### 1. Frame

State the deliverable (source families? probe phrasings? rival
hypotheses?) and what a strong member must satisfy. Separate hard
constraints (converge on them last) from the open space (diverge over it
first). If the open space is a measured column, go to the roster; if it
is not, build a field.

### 2. Roster

When the space is a categorical spine column, enumerate it rather than
recall it: the schema's `value_spaces` are the roster for most spines,
and a GROUP BY is the roster for the rest.

```sql
SELECT source, count() AS n FROM forums.posts GROUP BY source ORDER BY n DESC
SELECT relation, count() AS n FROM internet.text WHERE hasToken(search_text_lc, 'ipfs') GROUP BY relation ORDER BY n DESC
```

Diverse across a roster means spread, not top-N: one member per family
or per size band (the long tail is where the unexpected lives), and let
the corpus draw the order where you would otherwise pick favourites:

```sql
SELECT source FROM forums.posts GROUP BY source ORDER BY rand() LIMIT 12
```

Report the roster size beside the chosen members: "12 of 61 forum
sources, one per size decile" is a denominator; "a diverse set of
forums" is not.

### 3. Field

When no column names the space, name the axes yourself. An axis changes
the mechanism of a candidate, not its adjective — if you cannot say what
an axis changes about the output, cut it. For "diverse sources or angles
on X" these usually earn their place:

- venue family — forum; mailing list or Usenet; academic; code and issue
  trackers; social; news and blogs; markets; government and legal
- era — before the thing existed; first contact; mature; after a failure
- stance — builder, critic, user, bystander, regulator, competitor
- register — insider jargon; vernacular; journalistic; primary-source
  period diction; machine-readable (logs, code, data)
- scale — one person; a small group; an institution; a field; a society
- inversion — the party who would never discuss it; the medium that
  blocks it; the cost that filters who still comes

Two to six values per axis; drop incoherent conjunctions explicitly.
Cover the cells: exhaustive when the product is small (about a dozen),
otherwise draw cells with corpus entropy — the model cannot make a random
choice, and a hand-picked subset is the mode again:

```sql
SELECT arrayElement(['forum','mailing list','academic','social','news','code'], 1 + rand() % 6) AS venue,
       arrayElement(['builder','critic','user','bystander','regulator'], 1 + rand() % 5) AS stance,
       arrayElement(['jargon','vernacular','journalistic','period'], 1 + rand() % 4) AS register
FROM forums.posts LIMIT 8
```

Any registered relation serves as the row source; `LIMIT 8` reads one
granule. Generate one candidate per cell, from the cell alone — a source
family, a probe phrasing, a hypothesis — and before proposing it list
five properties the conjunction implies (who writes there, in what
words, what they take for granted, what they would never say, when). In
a multi-agent harness, one fresh context per cell; in one context, write
each cell's candidate before reading the next and never revise an
earlier cell in light of a later one — and label the result honestly: a
single-context walk is a list, not a covered field, so report its grid
as what you tried, never as coverage. A candidate any cell would have
produced is the mode leaking back: drop it and redraw.

### 4. Converge

Apply the hard constraints last. Deduplicate by the dimension that
changed, not by surface wording. Turn each surviving direction into a
count-first probe (§ Shape probes) with a ledger row: cell, candidate,
relation, probe, count. Report the grid — cells drawn, cells that
yielded, cells that came back empty — as the denominator of "diverse".
The stopping rule is § Lexical fanout's.

### The outsized endpoint

`POST /v1/creativity/outsized` runs the divergent half of steps 3–4 as a
black box, for an open-ended brief where you want a field wider than one
context produces:

```
POST /v1/creativity/outsized
{"brief": "Enumerate orthogonal source families and probe phrasings for <X>: for each, the community that would hold it, the words it would use, and the register to embed.", "shots": 12, "field": "inquiry"}
```

`brief` is at most 16 KB; `shots` is 4–24 (default 12); `field` picks
the axis bank — `inquiry` (venue, era, stance, register, scale,
inversion) for research direction, `artifact` (the default: lever,
scale, time, inversion, audience, form, stance) for deliverables. The
response
carries `field: [{id, text}]` — one independent candidate per surviving
shot, each written from its own server-drawn cell on its own small model
— a consolidated `nugget` (`consolidated: false` when the consolidation
pass failed; the field still stands), `shots: {requested, returned,
failed}`, `usage: {input_tokens, output_tokens, cost_usd}`, and
`elapsed_ms`. On MCP the same call is `scry_creativity {brief, shots}`.
It settles against the account's Scry balance only (a caller-supplied
provider key is refused: the fleet stays a black box), takes one to four
minutes, and is marked experimental. Treat the candidates as directions
to probe, never as findings: step 4 still runs, and only rows ship.

Know the instrument. The artifact bank is built for rules, objects,
scenes, and clauses; run on a research brief it returns a field about
half costume (measured 2026-08-22 on the Usenet brief above, 12/12
shots, 103 s, $0.026: a six-community taxonomy, a who-benefits audit,
and a legal frame beside a child's parable, a hive analogy, and a
"domestic ritual"). `field: "inquiry"` exists for exactly that reason —
its axes change who holds a direction, when, at what scale, and from
which side, not how it is voiced. Either way, read the nugget's `## Span`
for content mechanisms, discard register-only entries, and keep the
roster and field steps as the primary instrument; the endpoint is the
wide net behind them.

## What lexical search makes possible

Read this when a question looks like it needs a model and might not. The
text indexes (`hasToken`/`hasAnyTokens` posting lists, trigram n-grams for
substrings and regex prefilters) answer over hundreds of millions of rows
in seconds, and every answer carries a denominator. That combination —
speed plus a count you can defend — is what makes the shapes below
possible at all. Each one is a plain SQL statement; nothing here needs an
embedding until the last rung.

### The ladder of abstraction

Climb it; most questions resolve before the top.

1. **Token** — `hasToken(search_text_lc, 'mechinterp')`. One word, one
   posting list, sub-second anywhere.
2. **Phrase and proximity** — `scry_lex('"scaling laws"')`,
   `scry_lex('interpretability NEAR/50 circuits')`: recall on tokens,
   decide on positions.
3. **Pattern** — `scry_lex('/GPT-[0-9]+(\.[0-9]+)?/')`: a regex over the
   whole estate, prefiltered by its required literals so the index still
   prunes; `scry_compile` with `explain: true` prices it before you spend.
4. **Recipe** — `scry_recipe('mech_interp')`: every surface form someone
   already derived and measured, as one operand; `scry_recipe_score
   ('vader_polarity')` as a per-row weighted signal. Recipes are what turn
   a vocabulary you found into an instrument others reuse.
5. **Cohort** — a recipe or lex line as a *selector*: authors, threads,
   days that match, then measure something else about them
   (§ Comparative study design owns the discipline).
6. **Time series** — the same predicate under `GROUP BY
   toStartOfMonth(...)`: a term's birth date, its peak, its decay. Every
   concept has one; `mechinterp` did not exist in 2019.
7. **Estate sweep** — `scry_compile` with `relation: "*"` and `counts:
   true`: where a vocabulary lives across every corpus, with per-relation
   denominators, in one call. This is the "which community talks like
   this" question answered without reading anything.
8. **Semantic escalation** — only now: `scry_embed` neighbors to find the
   vocabulary you could not guess, fed back down the ladder as tokens.

### The ladder of proof

Each rung above can be asserted at several strengths; name the one you
are at.

- **Existence** — one row with a source id. Enough for "this was said".
- **Count with denominator** — `countIf(scry_lex(...)) / count()` inside
  a window and a source. Enough for "how common".
- **Rate against a control** — the same predicate over a hash slice
  (`intHash64(author_id) % 20 = 0`) or a disjoint window. Enough for
  "more than baseline".
- **Temporal holdout** — select in window 1, measure in window 2.
  Enough for a trait claim.
- **Read matches** — twenty rows per cohort, false positives counted,
  row ids kept. Without this rung a lexicon is a guess with a number
  on it; with it the number has a precision. Recipes store this rung.

### Wild things that are already routine

- **Who said it first** — `min(original_timestamp)` over a phrase across
  every relation: the earliest use of a coinage in 200M documents, in
  one sweep, with the row to cite.
- **Jargon salience by community** — a term's share inside a source ÷
  its share in the estate (§ Vocabulary expansion). Ranks a community's
  private vocabulary without a model.
- **Stance inversion** — the same topic under two stance recipes
  (`empathy_broadcast` vs `empathy_accusation`) gives opposite reply
  hostility; a topic lexicon alone would have averaged the sign away.
- **Vocabulary birth and death** — monthly rates for a recipe's terms
  one by one: which surface form is winning (`sae` overtaking `sparse
  autoencoder`), which is dying.
- **Cross-corpus migration** — the month a term first appears in each
  relation, ordered: LessWrong → arXiv → Hacker News → Reddit is a
  measurable diffusion path, not a story.
- **Blind-band honesty** — a recipe declares what it cannot see
  (sarcasm, passive aggression); an absence claim is scoped to the band
  automatically instead of overreaching.
- **Cross-source person contrast** — the same person, different
  vocabulary in different venues. `persons.links` joins platform
  accounts under a `person_id` (deterministic public keys only); group
  each side by author with a recipe score, join on the linked pair.
  Measured 2026-08-24: of 502 persons active on both reddit and Hacker
  News, mean hedging density is 2x higher on HN (0.0035 vs 0.0018) —
  register belongs to the venue, and per-person outliers who flip the
  gradient are individually retrievable. Same shape works for any
  recipe pair: certainty-at-work vs apology-at-home, jargon on one
  platform vs plain speech on another.
- **Derivation from the corpus itself** — prefix lexicon + co-occurrence
  salience + embedding neighbors, seeded from an index-engaging term,
  yields the variant list in seconds; curate, measure, publish as a
  recipe. Ten SQL calls today, one `scry_recipe_derive` call next.

## The quantifier chain — operators search forgot

Web search trained everyone to ask one shape of question: *which
documents match P*. SQL over the estate answers questions with a second
variable quantified — authors, threads, communities, time, the graph —
and every predicate below may be a token, a phrase, a `NEAR` window, or
a `scry_recipe(...)`. Each rung is one subquery; `IN (subquery)` on the
bloom-indexed author/id columns keeps them sub-second when the inner set
is bounded. Measured shapes, 2026-08-24:

**Rung 0 — document.** `WHERE P(d)`. What search does.

**Rung 1 — within-author, elsewhere (∃).** Documents by people who have
said Q *anywhere*, including another relation:

```sql
SELECT count() AS n, uniq(author) AS authors FROM reddit.posts
WHERE subreddit = 'MachineLearning' AND created_utc >= '2025-01-01'
  AND author IN (SELECT original_author FROM hackernews.items
                 WHERE hasToken(search_text_lc, 'interpretability'))
```
38 posts by 9 authors, 1.0 s. Recipes ride multi-relation statements
with the text column explicit: `scry_recipe('slug', search_text_lc)`.

**Rung 1′ — within-author, never (∄).** Said X, never said Y — always
with the denominator:

```sql
SELECT countIf(said_y = 0) AS x_never_y, count() AS x_total FROM (
  SELECT author, countIf(hasToken(search_text_lc, 'alignment')) AS said_y
  FROM reddit.posts WHERE subreddit = 'MachineLearning' AND created_utc >= '2024-01-01'
    AND author IN (SELECT DISTINCT author FROM reddit.posts
                   WHERE subreddit = 'MachineLearning' AND created_utc >= '2024-01-01'
                     AND hasToken(search_text_lc, 'interpretability'))
  GROUP BY author)
```
176 of 195 r/ML interpretability-mentioners never wrote "alignment"
there. An absence claim without `x_total` is not a finding.

**Rung 2 — counting quantifiers.** Habitual (`HAVING count() >= N`),
sustained (`uniq(toStartOfMonth(t)) >= N`), ratio (`avg(score_x) /
avg(score_y)`), majority (`countIf(P) > count() / 2`). 6,170 reddit
authors have ≥5 `mech_interp`-matching posts since 2025 — and that
number is the lesson: a concept recipe curated on LessWrong (circuits,
steering, probes) is noisy on reddit. Measure a recipe on the relation
you quantify over before trusting the count.

**Rung 3 — temporal order.** First mention per author (adoption curve:
`min(t) GROUP BY author`, then bucket the minima); sequence (`minIf(t,
X) < minIf(t, Y)` per author — who was skeptical *before* convinced);
pre/post (cohort fixed at T₀, measured at T₁); sign-flip (a recipe score
crossing zero between periods). These are the arcs — conversion,
radicalization, adoption — that no per-document search can see.

**Rung 4 — thread and audience.** The *audience* of P, not its
speakers: comments under posts matching P.

```sql
SELECT count() AS comments, uniq(author) AS commenters FROM reddit.comments
WHERE created_utc >= '2026-01-01'
  AND link_id IN (SELECT concat('t3_', id) FROM reddit.posts
                  WHERE created_utc >= '2026-01-01' AND subreddit = 'MachineLearning'
                    AND scry_recipe('mech_interp', search_text_lc))
```
1,075 comments by 405 commenters, 6.6 s. Rung 1 with recipes on both
sides — hedged reddit posts by people who wrote with `certainty` on HN
— returns 36,148 posts by 6,138 people in 33 s. HN threads chain the same way through `parent_hn_id` / `story_hn_id`.
Audience quantifiers compose with rung 1: *people who replied to X and
later posted Y themselves*.

**Rung 5 — community-conditioned.** P where P is rare (surprise), P's
share inside a source ÷ its share in the estate (salience, § Vocabulary
expansion), P under the community's own polarity lexicon
(`socialsent_*`). The same words mean different things in different
rooms; this rung says which room.

**Rung 6 — graph.** People followed by people who say P
(`twitter.following` / `twitter.followers`); people who are the same
person on another platform (`persons.links`) — the cross-source person
contrast in § What lexical search makes possible.

**Rung 7 — provenance.** Documents whose *links* match P — `outbound_url`
/ domain predicates on reddit and HN, tweets pointing at papers whose
text matches Q — joined through the URL, not the prose. HN items
linking arxiv whose text says "interpretability": 32 items by 28
posters, 0.2 s.

Rungs stack: *comments (4) by habitual (2) HN-interpretability people (1)
who hedge more than they did last year (3, recipe)* is four subqueries
and one afternoon. Two disciplines hold across the chain: every
quantifier over authors carries its denominator, and every recipe in a
multi-relation statement names its text column.

## The operator space

The quantifier chain is one column of a larger map. Every search operator
is an arrow between sorts — term → span → doc → thread → author → cohort →
community → time → graph — and enumerating by signature is what makes the
space finite and the gaps visible. Four literatures were paneled to fill
it (raw surveys with citations:
`~/Projects/scratch/operator-space-2026-08-25/`): the operator-richest
query languages ever built (INQUERY/Indri, Westlaw/Lexis, CQP, Lucene
spans, Sphinx, Xapian, PubMed), formal algebras (generalized quantifiers,
Allen intervals, temporal logic, relational division, Kleene algebra),
stance linguistics (Hyland, Appraisal, factuality, modality,
evidentiality), and the LLM-era retrieval literature. The planes below are
the deduplicated result, each with its idiom on this surface. Everything
here rides plain SQL — only table functions are gated, so `groupArray`,
`sequenceMatch`, `windowFunnel`, `match` all pass the validator.

**1. Term forms.** Tokens, phrases, `/regex/`, `word~1` fuzzy, substrings
— and recipes are this surface's synonym operator (Indri `#syn`), with
weights (`#wsyn`). The PubMed lesson: every automatic expansion needs an
off-switch — when a stem or recipe expansion misleads, drop to quoted
phrase or a narrower recipe rather than fighting the expansion.

**2. Windows and spans.** `NEAR/k` (unordered, characters) and
`"phrase"~n` slop exist; ordered/directional proximity, sentence scope,
and span algebra (containing/before/overlaps — ES `intervals` is the
model) are not yet operators. Short ordered windows can ride re2:
`match(text, '(?i)trigger(\\W+\\w+){0,5}\\W+response')`. The
recipe-proximity operator (`hedge within k tokens of a prediction`) is
planned — `docs/execplans/lexical_recipes.md`.

**3. Doc booleans, quorum, frequency.** Boolean composition is § Composing
recipes (SKILL). Two gates the professional languages kept and consumer
search lost, both expressible today as residuals behind an index-engaging
recall leaf:
- **quorum** (Sphinx `"…"/3`): ≥k distinct recipe terms present —
  `arrayCount(t -> has([...terms...], t), arrayDistinct(tokens(text))) >= k`
  — a far sharper selector than any-token membership for broad recipes;
- **atleast** (Westlaw `ATLEASTn`): one term repeated ≥n times —
  `countMatchesCaseInsensitive(text, 'term') >= n` — "about X", not
  "mentions X".

**4. Score plane.** Match/score decoupling is native here: WHERE gates,
ORDER BY scores, and the two never need to agree (Indri `#filreq`).
Graded negation beats hard NOT when the exclusion is soft — demote by
subtracting: `scry_recipe_score('a') - 0.5*scry_recipe_score('b')` (ES
`boosting`). Soft-AND over m weak signals = sum of indicators with a
threshold, the continuous cousin of quorum.

**5. Quantifier plane.** The whole monadic zoo — every / some / no /
at-least-k / at-most / exactly / most / fewer-than-p% / more-X-than-Y —
is tests on `(countIf, count)` pairs from one `GROUP BY author`; name the
quantifier you mean and its denominator. Three named idioms kill standing
error classes:
- **division** ("in ALL of these"): `uniqExactIf(community, cond) = N` —
  never the double-NOT-EXISTS;
- **anti** ("never"): `countIf(P) = 0` as a HAVING, absence typed as a
  result set;
- **group-wise first/top-k**: `argMin`/`LIMIT k BY key`, not window
  ceremony.
Honesty metadata comes free: upward-monotone quantifiers (at-least-k)
are stable as ingest continues; downward-monotone ones (every, no,
at-most) are provisional — the cohort can only shrink as data arrives.
Say which kind a claim is.

**6. Temporal plane.** Derive spans per (author[, recipe]) —
`[min(t), max(t)]` or quantile-trimmed — and Allen's 13 relations become
endpoint comparisons: `contains` the hype cycle = veterans, `during` =
tourists, `meets` = the topic handoff, `overlaps` = the conversion window.
LTL words that analysts already use have direct shapes: *once*
(`countIf > 0` before t), *since* (condition on every post after pivot),
*until* (arc with pivot), bounded response `G(trigger → F≤Δ response)` =
`sequenceMatch('(?1)(?t<Δ)(?2)')(t, trigger, response)`; `windowFunnel`
for multi-step chains. The cheapest profound operator on this surface is
the **life-history regex**: per author, order posts by time, map each to
one letter of a small declared recipe alphabet, and
`match(arrayStringConcat(groupArray(letter), ''), '^s+h*b+$')` runs a
career-shaped query — skeptic-to-booster converts, `a$` (last word an
apology), criticism-never-followed-by-apology via `NOT match`. One
grouped scan; the alphabet is the curated asset.

**7. Thread and graph plane.** Rungs 4 and 6 generalized: edges can be
text-conditioned (replies **to posts matching P**), cones can be any
depth where parent chains exist (`parent_hn_id`/`story_hn_id`), and reply
trees are branching time — "every branch stayed civil" vs "some path
reached an apology" are grouped every/some over descendants, distinct
questions from any linear timeline.

**8. Epistemic plane.** The reasoning-register recipes are operators for
*how a text knows what it claims*. The families worth holding (licenses
in the survey): hedge/booster; Appraisal ENGAGEMENT (entertain /
attribute-acknowledge vs attribute-distance / proclaim / disclaim — the
dogmatism-vs-dialogism dial); evidential source-type (perception,
inference, assumption, reportative, quotative); attribution-verb
factuality (*shows/proves* co-signs, *claims/alleges* distances); modal
flavor (epistemic "must have" vs deontic "must do" — the word alone
carries only force); counterfactual constructions (*would have* + *had X
not* — a small closed set of tense/modal forms); speech-act denominators
(hedging rate per **assertion**, not per post). Two distinction
disciplines: *never affirmed* ≠ *denied* — keep silence and
counter-assertion separately queryable; and *exposed* (replied to/quoted
the correction) ≠ *knew* — name the proxy. The common-ground detector is
allusion-without-link: the date after which posts use the event as an
unexplained premise.

**9. Reverse plane.** Standing queries — a document arriving and asking
"which stored queries match it" (ES percolate) — exist nowhere on this
surface and, per the 2023–2026 literature, nowhere in LLM-era research
either. Recipes are already stored queries; a percolation lane over fresh
ingest is the natural future operator (execplan).

The LLM-operator failure literature says where discipline must live, and
this surface already encodes most of it: negation and set logic stay
symbolic (dense retrieval scores below random on negation — NevIR);
compositional intent must not collapse to a token bag ("X for Y" is a
phrase or a NEAR, never `X AND Y`); after zero results broaden, never
re-specify (agents demonstrably fail to); add no filter the question did
not ask for; and measured recipes are the standing antidote to
hallucinated term sets — the systematic-review literature finds LLM
boolean queries precision-heavy, recall-poor, with invented controlled
vocabulary, and guided seeding is what fixes them.

## The recipe shelf

`GET /v1/scry/recipes` (MCP `scry_recipes`) is the live catalog; this
table is the shelf as measured on lesswrong 2026-01-01.. (2026-08-24).
`match` = share of documents containing ≥1 term; `score` = mean
`scry_recipe_score` over a 200-hit sample (weighted token recipes only).

| slug | kind | terms | what it is | match | score |
|---|---|---|---|---|---|
| `mech_interp` | concept | 14 | mechanistic-interpretability surface forms, token + phrase | 0.044 | +0.009 |
| `vader_polarity` | affect | 7,234 | social-media valence, -4..+4 human means (MIT) | 0.953 | +0.051 |
| `afinn_polarity` | affect | 3,351 | microblog valence, signed integers -5..+5 (Apache-2.0) | 0.936 | +0.036 |
| `hu_liu_polarity` | affect | 6,775 | opinion words ±1, review register (free w/ attribution) | 0.930 | +0.016 |
| `hu_liu_positive` | affect | 2,005 | positive half, membership | 0.870 | — |
| `hu_liu_negative` | affect | 4,776 | negative half, membership | 0.782 | — |
| `labmt_happiness` | affect | 10,091 | word happiness norms, centered happs-5 (CC-BY) | 0.9996 | +0.368 |
| `emoji_polarity` | affect | 751 | emoji sentiment, phrase form, weights are reader data (CC BY-SA) | 0.009 | — |

Choosing:

- **Selector vs scorer.** match near 0 (`mech_interp`) is a selector —
  put it in WHERE. match near 1 (`labmt_happiness`, whose vocabulary is
  the common tongue) is a scorer — it meters every document; apply the
  hedonometer lens (drop |w|<1 terms) on read. The polarity lexicons sit
  between: WHERE-able on small corpora, scorers on large ones.
- **Polarity on general prose**: `vader_polarity` first (widest coverage,
  slang included), `afinn_polarity` when you want small and legible.
  `hu_liu_*` for opinion/review registers and membership cohorts.
- **`emoji_polarity` is corpus-diagnostic**: 0.9% on lesswrong; expect
  real rates on social corpora. Phrase-form, so `scry_recipe_score`
  ignores it — read the stored weights yourself.
- **All the seeds are overt-band**: blind to negation, sarcasm, and
  domain reversal by construction, and each recipe's `options.blind_to`
  says so. Scope absence claims to the band.
- **`scry_recipe_score` re-tokenizes every row it touches** — always
  bound it with a sampled subquery (`... WHERE scry_recipe('slug') LIMIT
  200`), never a bare full-relation aggregate.
- **Derive before you hand-write**: `scry_recipe_derive(seeds, relation,
  source)` returns prefix-lexicon and co-occurrence candidates with
  relation-wide denominators. Sort co-occurrence candidates by
  `salience`, not `df_matched` — df ranking surfaces stopwords. Curate,
  read matches, then publish with `scry_recipe_write`.
- **Stance is identity**: the same word list under a different reading
  contract is a different recipe, not a new version.

The **epistemic/logical tranche** (original curation, CC0 — no upstream
license): these read the *reasoning register* of text rather than its
topic or valence, and their cross-corpus contrasts are the point.
Measured lesswrong-2026 vs reddit-2026H2 match rates:

| slug | kind | reads | lesswrong | reddit |
|---|---|---|---|---|
| `hedging` | stance | epistemic softening (maybe/arguably/"i could be wrong") | 0.658 | 0.100 |
| `certainty` | stance | epistemic hardening (obviously/undoubtedly/"no question") | 0.272 | 0.067 |
| `absolutist` | register | black-and-white thinking (Al-Mosaiwi & Johnstone 2018) | 0.466 | 0.187 |
| `causal_reasoning` | structural | argument connectives (therefore/"it follows that") | 0.328 | 0.048 |
| `disagreement` | stance | overt refutation (strawman/"doesn't follow") | 0.157 | 0.013 |
| `evidence_citing` | stance | appeals to data/studies ("peer reviewed"/"effect size") | 0.313 | 0.028 |
| `gratitude` | affect | expressed appreciation | 0.096 | 0.040 |
| `apology` | stance | self-repair ("i was wrong"/"i stand corrected") | 0.032 | 0.009 |
| `question_asking` | stance | help-seeking ("does anyone know"/eli5) | 0.259 | 0.135 |
| `hype_promotion` | register | marketing superlatives ("game changer"; LLM-slop proxy) | 0.037 | 0.004 |
| `urgency_alarm` | register | time pressure/threat framing ("act now"/imminent) | 0.100 | 0.026 |
| `complaint` | stance | consumer grievance (scam/"waste of money") | 0.050 | 0.013 |

LessWrong hedges in 66% of posts vs reddit's 10%, evidence-cites 11x
more, and overtly disagrees 13x more — the register instruments rank
communities before any per-document reading. Pair `hedging` against
`certainty` for an epistemic-humility ratio per cohort.

**The `socialsent_*` family** (16 recipes, ~4,900 terms each, PDDL) is
the community-conditioned reddit formula: SentProp-induced polarity per
subreddit register, where the same word can flip sign across
communities. Each is measured on its own community (reddit.posts, 2026
window); the mean hit scores already rank registers plausibly —
politics -0.097, leagueoflegends -0.118, offmychest -0.078 vs
askscience +0.169, minecraft +0.106. Use the recipe whose community
matches the cohort under study; for a subreddit outside the 16, the
remaining 234 SocialSent lexicons load the same way (fetch + publish
pattern in the campaign scratch dir). Induced from 2014 comments —
treat drifted slang with the temporal-holdout rung.

The **latent-state tranche** (original curation, CC0) instruments what a
person's language betrays about their state, not their topic: cognitive
distortion, orientation toward the future, belonging, group boundary
maintenance, epistemic openness, and machine authorship. All are
overt-band selectors (match ≪ 1 — WHERE-able everywhere). Measured
lesswrong-2026 vs reddit-2026H2 match rates:

| slug | reads | lesswrong | reddit |
|---|---|---|---|
| `catastrophizing` | worst-case cognition ("it's all over"/"never recover") | 0.035 | 0.004 |
| `overgeneralization` | always/never distortion ("every single time") | 0.025 | 0.005 |
| `mind_reading` | assumed hostile intent ("they must think") | 0.003 | 0.0004 |
| `foreclosed_future` | no-path-forward talk ("no point in trying") | 0.032 | 0.008 |
| `agentic_future` | plans and self-efficacy ("my plan is"/"i'm going to build") | 0.078 | 0.023 |
| `external_locus` | outcomes attributed outward ("rigged"/"the system") | 0.019 | 0.002 |
| `internal_locus` | outcomes owned ("my responsibility"/"i chose") | 0.010 | 0.004 |
| `loneliness` | disconnection ("no one to talk to") | 0.012 | 0.005 |
| `exclusion_words` | rejection particles (left out/ignored/excluded) | 0.597 | 0.144 |
| `dehumanization` | vermin/disease metaphor for people | 0.004 | 0.001 |
| `us_vs_them` | in/out-group boundary talk ("those people"/"wake up") | 0.018 | 0.001 |
| `thought_terminating` | cliché as argument-stopper ("it is what it is") | 0.007 | 0.002 |
| `llm_fingerprint` | GPT-register tics (delve/"i hope this helps"/tapestry) | 0.020 | 0.001 |
| `changed_my_mind` | belief revision in the wild ("i was wrong"/"updated my view") | 0.010 | 0.0004 |
| `prediction_stake` | falsifiable commitments ("i predict"/"calling it now") | 0.005 | 0.0002 |
| `gatekeeping` | boundary policing ("not a real fan"/gatekeep) | 0.001 | 0.0006 |
| `welcoming` | newcomer hospitality ("great question"/"happy to help") | 0.006 | 0.001 |
| `recovery_arc` | past-tense struggle narrated from the far side | 0.018 | 0.010 |
| `financial_distress` | money desperation (eviction/"can't afford rent") | 0.006 | 0.004 |
| `burnout` | occupational exhaustion ("running on empty") | 0.004 | 0.003 |

These compose into **indices** — ratios of paired instruments over a
cohort, which cancel base-rate differences the way `hedging`/`certainty`
does:

- **hope** = `agentic_future` vs `foreclosed_future` per cohort-month
  (lesswrong runs 2.4:1 agentic; a cohort trending toward foreclosed is
  a population-level signal worth a study, never a per-person verdict).
- **hospitability** = `welcoming` vs `gatekeeping` per community.
- **polarization** = `us_vs_them` + `dehumanization` rates per
  community-quarter; reddit-wide these are 10–18x rarer than on
  lesswrong's abstract-discussion register, so always compare a
  community against its own history, not across registers.
- **epistemic openness** = `changed_my_mind` + `prediction_stake` per 1k
  posts. Measured league (reddit 2026H2 posts + lesswrong):
  lesswrong 9.8/1k, r/offmychest 8.4, r/relationships 7.3,
  r/changemyview 3.1, r/politics 0.10, r/worldnews 0.016, r/science
  0.0. Caveat: the relationship-sub rates are interpersonal repair
  ("you're right, I'll talk to her"), not belief revision — read a
  sample before naming the construct.
- **contamination curve** = `llm_fingerprint` (or its index-riding token
  subset delve/delves/delving/multifaceted/underscores/tapestry) per
  100k reddit posts by year: 22.9 (2018) declining to 12.6 (2022), then
  42.5 (2023), 56.0 (2024), 43.0 (2025) — a 3.4x discontinuity dating
  machine-register arrival, with the pre-2022 organic decline as the
  natural control and the post-2024 recession tracking newer models
  shedding the tics.

Ethics: the sensitive instruments (`catastrophizing`, `loneliness`,
`foreclosed_future`, `dehumanization`, …) carry
`options.ethics = "population-level research instrument; never a
screening or targeting tool for individuals"` in the catalog. Honor it:
aggregate, trend, and compare cohorts; do not rank or flag people.

License-gated families (NRC, LIWC, SentiStrength data, SenticNet) are
deliberately absent — tracked in `future-ideal-obligations.toml`.

## Scry query patterns (ClickHouse SQL dialect)

Call `GET /v1/scry/schema`, choose an enabled registered relation, then send one
bounded SQL statement to `POST /v1/scry/query`.

> **Historical Twitter archive access:** `twitter.tweets`, `twitter.token_search`, and
> `twitter.vector_search` are not available to public keys — a query naming
> them is refused at admission.
> The patterns transfer unchanged to other text-indexed relations (e.g.
> `reddit.comments`, `forums.posts`).

### Shape probes: count first, retrieve second

Almost every empty result, timeout, and memory cap traces to querying blind —
unknown predicate selectivity, a guessed value that does not exist, or missing
vocabulary. Count-only probes make the shape visible before retrieval. On
token-indexed relations, they usually avoid row retrieval and `ORDER BY`.

**Selectivity probe.** Before any retrieval query, run its WHERE clause as a
count:

```sql
SELECT count() AS hits
FROM reddit.comments
WHERE created_utc >= '2026-05-01' AND created_utc < '2026-06-01'
  AND hasToken(search_text_lc, 'polysemanticity')
LIMIT 1
```

Zero → vocabulary or value problem; fix the terms before widening. Millions →
narrow the window or add a predicate before paying for ORDER BY over the
match set. A handful to thousands → retrieve directly.

**Empty-result bisection.** When a multi-predicate query returns nothing,
re-run the count dropping one predicate at a time. The predicate whose
removal makes the count jump is the killer — usually value shape, not
absence: wrong case (`subreddit = 'machinelearning'` vs `'MachineLearning'`),
an un-lowercased token against a `_lc` column, a prefixed vs bare ID.

**Value-space probe.** Never guess categorical values. One GROUP BY shows
the real value space with its spelling and skew (~2.5s on full-retention
Reddit for a one-month window):

```sql
SELECT subreddit, count() AS c
FROM reddit.comments
WHERE created_utc >= '2026-05-01'
GROUP BY subreddit
ORDER BY c DESC
LIMIT 30
```

**Fan out sequentially — or batch with `countIf` on narrow windows.** For
a day-or-few window, one single-pass `countIf` bundle beats N round-trips:

```sql
SELECT countIf(hasToken(search_text_lc, 'mechinterp')) AS c_mechinterp,
       countIf(hasToken(search_text_lc, 'interpretability')) AS c_interp,
       countIf(hasToken(search_text_lc, 'sae')) AS c_sae
FROM reddit.comments
WHERE created_utc >= '2026-05-20' AND created_utc < '2026-05-21'
LIMIT 1
```

Window-scoping law: `countIf` scans every row the WHERE admits once, so
it wins when the window is narrow; over wide windows (a month or more) a
single common token forces the full scan and sequential single-token
counts win, because each single probe lets the text index prune
independently (~0.7s each, measured). For combined retrieval after the
probes, use one `hasAnyTokens` array, not an OR chain (§Multi-token
search). `UNION` and other set operations are not served, so batching
across variants happens through `countIf` bundles, token arrays, or one
`t IN (...)` pass over `arrayJoin` (§Vocabulary expansion), never through
stitched statements.

**Token predicate laws.** A `hasToken` needle must be a single token:
a needle containing a separator (`mech-interp`, `mech interp`) is a hard
error, not an empty result — split it into per-token probes, or use the
phrase idiom in §Multi-token search when the phrase itself matters.
Counting note: `count()` over `arrayJoin(tokens(x))` counts occurrences;
wrap in `arrayDistinct` — `arrayJoin(arrayDistinct(tokens(x)))` — to
count documents. Aggregates with unbounded state (`topK`, `uniqExact`,
`groupArray`, `quantileExact` families) are not served; use plain
`GROUP BY … ORDER BY count() DESC LIMIT k` for top-K.

### Multi-token search on text-indexed columns

Schema `query_guidance.indexed_predicates` names each relation's indexed
text column. Three entry points engage the text index:

- `hasToken(col, 'token')` — one token.
- `hasAllTokens(col, ['t1','t2'])` — all tokens, intersected inside the
  index. Measured on one year of `reddit.comments`: 70ms and 4.3M rows
  read, where `hasToken(...) AND hasToken(...)` read 202M rows in 316ms
  for the same 1,636 matches.
- `hasAnyTokens(col, ['t1','t2'])` — any token, one index pass. Measured
  349ms where the equivalent five-way `hasToken` OR took 738ms.

The index stores tokens without positions, so a phrase has no direct index
path. For a phrase, intersect its tokens, then refine with `LIKE`:

```sql
SELECT subreddit, score, body
FROM reddit.comments
WHERE hasAllTokens(search_text_lc, ['lid', 'off'])
  AND search_text_lc LIKE '%lid off%'
ORDER BY score DESC
LIMIT 20
```

Do not send bare `LIKE '%...%'` predicates without a token prefilter: the
engine then reads every row body in the scanned range, which is the common
path to the memory cap.

### Vocabulary expansion from the corpus

The corpus itself is the best thesaurus: rows matching a seed term carry the
community's own jargon, spellings, and adjacent handles. Use one bounded
probe:

```sql
SELECT t AS token, count() AS c
FROM (
  SELECT arrayJoin(tokens(search_text_lc)) AS t
  FROM reddit.comments
  WHERE created_utc >= '2026-05-01' AND created_utc < '2026-06-01'
    AND hasToken(search_text_lc, 'mechinterp')
)
WHERE length(t) > 3
GROUP BY t
ORDER BY c DESC
LIMIT 40
```

Skim past stopwords — the raw counts are co-occurrence, not salience. The
yield is the mid-list tokens you did not know to search for: project names,
insider shorthand, author handles. Feed each candidate back through a
selectivity probe and keep the ones with real signal. This turns lexical
fanout from guessing variants into reading them off the data.

#### Prefix lexicon: spelling and morphology variants with counts

The same `arrayJoin(arrayDistinct(tokens(...)))` shape with a prefix
filter (`WHERE t LIKE 'attent%'`) reads the corpus's own lexicon — case
variants, compounds, misspellings, other-language forms — each with its
frequency. Start with a day window and widen only when one day is too
sparse.

#### Background frequencies and salience

To rank co-occurrence candidates by salience instead of raw count, fetch
their corpus-wide document frequencies in one bounded pass (the same
`arrayJoin(arrayDistinct(tokens(...)))` shape with `WHERE t IN (...)`)
and compare against their frequency inside the matched set — a candidate
is jargon when its share inside the match set far exceeds its share
outside.

#### Term trend lines

Per-month counts for one term use one bounded query:

```sql
SELECT toStartOfMonth(original_timestamp) AS m, count() AS hits
FROM hackernews.items
WHERE original_timestamp >= '2026-01-01'
  AND hasToken(search_text_lc, 'mechinterp')
GROUP BY m
ORDER BY m ASC
LIMIT 24
```

Beware the open month: the current month is a partial aggregate and will
read as a collapse next to closed months. Compare closed months only, or
normalize by the month's total row count.

### Twitter follow graph

One edge set, two physical orderings, one denominator table. Filter the
side the relation is keyed on; handle predicates use the lowercase `*_lc`
columns (bloom-indexed):

```sql
-- whom does @sama follow (twitter.following is keyed follower-first)
SELECT followee_id, followee_handle, last_observed
FROM twitter.following
WHERE follower_handle_lc = 'sama'
ORDER BY last_observed DESC LIMIT 50

-- who, among the walked seeds, follows @karpathy (keyed followee-first)
SELECT follower_id, follower_handle
FROM twitter.followers
WHERE followee_handle_lc = 'karpathy' LIMIT 50

-- was this seed's list actually walked, and how completely?
SELECT handle, captured, declared, coverage_ratio, last_observed
FROM twitter.follow_coverage
WHERE direction = 'following' AND handle_lc = 'sama'
```

The follower side is exactly the ~33k walked seeds (`twitter.follow_coverage`
is their roster); the followee side is anyone a seed follows. Absence of an
edge is evidence only for a seed with high `coverage_ratio`.

### Semantic search from text

Load `SCRY_API_KEY`. Mint one named query vector:

```bash
curl -s https://api.scry.io/v1/scry/embed \
  -H "Authorization: Bearer $SCRY_API_KEY" \
  -H "Content-Type: application/json" \
  --data '{"text":"How do communities govern powerful AI systems?","name":"my_query"}'
```

The normal metered provider call uses `voyage-4-lite`. It stores a
2,048-dimension vector under `my_query`. If the response reports a different
model, trust the response model field. List stored vectors:

```bash
curl -s https://api.scry.io/v1/scry/vectors \
  -H "Authorization: Bearer $SCRY_API_KEY"
```

Use the stored name as the unquoted handle `@my_query` in SQL.

#### Writing the query text: exuberance wins

Embedding search rewards the opposite instinct from keyword search:
spend words. The model places your text in the same space as the
corpus's own paragraphs, so a thin stub names a direction while a rich
passage names a location. Most weak semantic recall traces to thin
query text, not to the index. Slow down, get creative, and be
maximalist about phrasings — probes are quick and composition is free.

- **Write the passage you hope to find, not the question you hold.**
  The nearest neighbors of a question are other questions. "why did
  Usenet decline?" retrieves people asking; "the September that never
  ended: AOL's 1993 gateway flooded Usenet with newcomers faster than
  its norms could absorb them" retrieves people answering. Draft the
  found paragraph — assert, name names, date it, claim the mechanism —
  and embed that.
- **Vividness is signal, not noise.** Concrete nouns, named actors,
  mechanisms, era diction, even emotional register all position the
  vector. "distributed systems debugging" is a genre; "the replica
  went split-brain at 3am and the on-call engineer traced it to a
  fencing token nobody renewed" is a place in that genre.
- **Fan out registers, one handle per phrasing.** The same idea lives
  in many dialects — academic abstract, forum vernacular, journalist's
  lede, practitioner war story, a primary source's own period diction —
  and each phrasing lands in a different neighborhood of the corpus.
  Mint `@x_academic`, `@x_forum`, `@x_news`, run each, union the
  retrievals.
- **Centroid the phrasings into one anchor.** `POST /v1/scry/embed`
  `{"expression": "scry_centroid([@x_academic, @x_forum, @x_news])",
  "name": "x"}` saves the mean direction — more robust than any single
  phrasing. The response's `input_similarity` diagnostics confirm the
  phrasings cohere around one concept, or reveal you minted two
  different ideas.
- **Sharpen polysemy by contrast.** When the word is ambiguous, embed
  what you mean and what you don't, then compose
  `scry_contrast_axis_balanced(@meant, @not_meant)` and rank along the
  axis (§ Composing embeddings into saved handles).
- **Poles beat definitions.** A vivid exemplar marks a direction better
  than a dictionary definition: hunting for burnout narratives, embed
  an unmistakable one, not "employee burnout".
- **Steal the corpus's vocabulary back.** The best rows of a first
  probe carry the words the community actually uses — re-embed with
  the corpus's own diction and probe again.

The stopping rule is the lexical one (§ Lexical fanout): keep minting
while fresh phrasings surface fresh neighborhoods; two rounds of
nothing new is the stop, never a fixed probe count.

#### Embedding corpus catalog

The live schema is the authority for which embedding relations exist, their
row counts, freshness, and which currently serve ANN (`serves_ann: true`).
Hydration joins for the registered families:

| relation | scope column users filter on | hydration join |
| --- | --- | --- |
| `embeddings.academic_paper_chunks` | `source_bucket` or exact `paper_key` | `academic.papers.paper_key = paper_key` |
| `embeddings.forum_posts` | `post_key` prefix, such as `lesswrong%` | `forums.posts.post_key = post_key` |
| `embeddings.reddit_comments` | `subreddit`, then `kind` | `reddit.comments.id = substring(full_id, 4)` for comments |
| `embeddings.hackernews_items` | exact or ranged `hn_id` | `hackernews.items.hn_id = hn_id` |
| `embeddings.stackexchange_posts` | `site`, then `stackexchange_id` | `(stackexchange.posts.id, stackexchange.posts.site) = (stackexchange_id, site)` |
| `embeddings.mailing_list_messages` | `message_key` prefix, such as `xorg-devel::` | `mailing_lists.messages.message_key = message_key` |

Unscoped ANN and `count()` over `embeddings.academic_paper_chunks` are
expensive (tens of seconds and large burden). Scope with `paper_key` or
`source_bucket`.

#### Search LessWrong

Rank LessWrong chunks. Keep the model filter:

```sql
SELECT post_key, chunk_index, token_count, model_name,
       scry_vector_topk_distance(embedding_voyage4, @my_query) AS distance
FROM embeddings.forum_posts
WHERE model_name = 'voyage-4-lite'
  AND post_key LIKE 'lesswrong%'
ORDER BY distance ASC
LIMIT 20
```

The table stores each chunk under both `voyage-4-lite` and
`voyage-4-large`. Without `WHERE model_name = 'voyage-4-lite'`, near-duplicate
chunks occupy the result list.

Hydrate text in a second query. Copy the returned keys into `IN`:

```sql
SELECT post_key, title, original_author, original_timestamp, payload
FROM forums.posts
WHERE post_key IN (
  '<post_key from the ANN result>'
)
LIMIT 20
```

The hydration key is
`forums.posts.post_key = embeddings.forum_posts.post_key`.

#### Search Reddit

Scope ANN ranking to one subreddit:

```sql
SELECT full_id, kind, subreddit, original_timestamp, upvotes,
       chunk_index, token_count, model_name,
       scry_vector_topk_distance(embedding_voyage4, @my_query) AS distance
FROM embeddings.reddit_comments
WHERE subreddit = 'CryptoCurrency'
  AND kind = 'comment'
ORDER BY distance ASC
LIMIT 20
```

Replace the subreddit equality with
`subreddit IN ('CryptoCurrency', 'MachineLearning')` to search a small set.
Keep `kind = 'comment'`.

The embedding relation has no text column. Hydrate comment bodies in a second
query. Copy the returned `full_id` values into `substring`:

```sql
SELECT id, subreddit, author, body, created_utc, score
FROM reddit.comments
WHERE subreddit = 'CryptoCurrency'
  AND id IN (
    substring('<full_id from the ANN result>', 4)
  )
LIMIT 20
```

Reddit embedding keys include the thing prefix, such as `t1_112n`. Raw comment
IDs omit it, such as `112n`. The verified hydration key is
`reddit.comments.id = substring(embeddings.reddit_comments.full_id, 4)`.
Keep the subreddit predicate. Add a `created_utc` window from the returned
`original_timestamp` values when hydrating a large result list.

The Reddit embedding corpus is predominantly `voyage-4-nano` with a small
`voyage-4-lite` share. Voyage-4 models share a ranking space, so use the
minted Lite query vector against Nano corpus rows. Check the live schema
freshness metadata before use.

#### Recall audit: semantic sweep over the lexical net

A lexical net cannot measure its own recall. When a question must be
answered exhaustively, close the loop:

1. Run the lexical fanout and keep the matched row IDs.
2. Mint one query vector from the question text (§Semantic search from
   text) and rank the same scope with `scry_vector_topk_distance`.
3. Hydrate the ANN top rows and diff them against the lexical hits.

ANN rows that the lexical net missed are the measured leak. Read them for
the vocabulary you did not search — community phrasings rarely match the
question's words — then add those tokens and probe again. Report recall as
the result of this audit, never as an assertion.

### Academic metadata joins

`openalex.works` carries title, year, authorships, topics, citations,
and `doi_norm` (lowercase bare DOI, bloom-indexed). Full text lives in
`academic.papers`, keyed by percent-encoded DOI. The bridge:

```sql
SELECT w.title, w.publication_year, w.cited_by_count, p.text
FROM openalex.works AS w
INNER JOIN academic.papers AS p
  ON w.doi_norm = decodeURLComponent(p.paper_key)
WHERE w.doi_norm = '10.1093/nq/s11-x.256.418b'
LIMIT 1
```

Semantic result hydration composes the same bridge: chunk search returns
`paper_key`; `decodeURLComponent(paper_key)` equals `works.doi_norm`. For
the full estate map and the reviewer-discovery loop, follow
§ Academic papers and reviewer discovery.

### Registered vector helpers

Vector SQL uses registered helpers advertised by `GET /v1/scry/schema`:

- base algebra: `scry_vec_dot`, `scry_cosine_similarity`, `scry_vector_norm`,
  `scry_unit_vector`, `scry_scale_vector`, `scry_project_onto`,
  `scry_debias_vector`, `scry_debias_removed_fraction`, `scry_debias_safe`,
  `scry_contrast_axis`, `scry_contrast_axis_balanced`, and `scry_centroid`
- ranking: `scry_vector_topk_distance`
- diagnostics: `scry_axis_diagnostics`, `scry_debias_audit`,
  `scry_handle_matrix`, and `scry_seed_centroid`

Unquoted `@handles` are owner-scoped. The query runtime binds their 2,048 Float32
values out of band and accepts placeholders only in registered vector argument
positions; quoted `@handle` text remains literal.
The query runtime expands registered `scry_*` helpers only after deterministic
validation; helper SQL outside those admitted shapes is rejected by design.

Registered embedding relations support exactly one
`scry_vector_topk_distance(embedding, @handle) AS distance` projection from
one ANN relation, optional `WHERE` predicates, `ORDER BY distance ASC`, and
`LIMIT 1` through `100`. The helper is ranking-only. Other vector helpers
retain their algebra semantics.

Confirm the live signature and columns before use. Do not use
database-specific vector operators or assume that an unregistered embedding
table is queryable.

Vectors are ranking hypotheses. Check nearest rows against lexical evidence,
provenance, source coverage, and the intended concept before reporting a
semantic conclusion.

### Composing embeddings into saved handles

`POST /v1/scry/embed` takes `{expression, name}` as the alternative to
`{text, name}`: the expression is the same scry_* vector algebra over your
stored `@handles`, evaluated server-side through the query validator, and the
result is saved as a reusable handle. The expression becomes the handle's
`source_text`, so saved compositions carry their own provenance. The response
returns diagnostics by default — norm, cosine similarity to every input
handle, and warnings — and refuses degenerate results (NULL from the noise
floor, norm ≤ 0.01, near-duplicate of an input) with the reason instead of
storing them.

Workflow discipline: run the matching diagnostic first, follow its
`recommendation`, then save. `GET /v1/scry/schema` serves the canonical
recipes as `vector_recipes`. The core pairs:

| goal | diagnostic first | then compose |
| --- | --- | --- |
| contrast axis A vs B | `scry_axis_diagnostics(@pos, @neg)` | `scry_contrast_axis_balanced(@pos, @neg)` |
| concept centroid | `scry_seed_centroid([@s1, @s2, @s3])` | `scry_centroid([@s1, @s2, @s3])` |
| remove a nuisance | `scry_debias_audit(@axis, @topic)` | `scry_debias_safe(@axis, @topic)` |
| shared component | `scry_cosine_similarity(@topic, @axis)` | `scry_project_onto(@topic, @axis)` |
| compare candidates | `scry_handle_matrix([@a, @b, @c])` | keep the healthy one, delete the rest |

```bash
curl -s https://api.scry.io/v1/scry/embed \
  -H "Authorization: Bearer $SCRY_API_KEY" \
  -H "Content-Type: application/json" \
  --data '{"expression":"scry_contrast_axis_balanced(@pos, @neg)","name":"my_axis"}'
```

A composed handle ranks rows exactly like a minted one:
`scry_vector_topk_distance(embedding_voyage4, @my_axis)`. Composition costs
no embedding tokens.

### Failure recovery

| Status | First move |
| --- | --- |
| `400` | Re-read `/v1/scry/schema`; fix ClickHouse syntax, relation, columns, or missing `LIMIT`. |
| `401` | Reload `SCRY_API_KEY` and remove whitespace. |
| `402` | Inspect account, pricing, and funding state. |
| `403` | Use a key with Scry scope; do not probe engine catalogs. |
| `429` | Respect `Retry-After`. |
| `503` | Tighten the query or retry later. |

If a relation or helper is absent from `/v1/scry/schema`, it is unavailable.
Choose another registered surface or report the coverage gap. Never route the
query to a fallback database.

For slow queries: reduce selected columns, add a selective predicate, lower the
limit, and inspect a recent time window when the schema exposes one. Broaden
only after the bounded retry succeeds.

#### Known failure modes

- `request_timeout` (query execution timeout, HTTP 408): shard by an indexed
  time window instead of retrying the full scan.
- The parser accepts the standard `WITH <name> AS (SELECT ...)` CTE form.
  ClickHouse scalar `WITH <expr> AS <name>` fails as a parse error. Inline the
  expression or use the standard CTE form.
- `query_exposure_exhausted`: raise the per-query ceiling with an
  `x-scry-budget: <nanodollars>` header (e.g. `1000000000` = $1).
- A relation can appear in the schema `surfaces` list yet be denied as
  unregistered at query time; trust the relation list inside the denial error.
- Parallel queries on one key can return `429` above the per-account
  concurrency gate (24). Obey `Retry-After` on retry.
- `hasToken` retrieval cost lives in row reads + ORDER BY, not in matching:
  a common token over a broad window can run for minutes under any `ORDER BY`,
  while the same predicate is suitable for a count-only shape probe. Count
  first; read a retrieval timeout as "match set too wide", then narrow the
  window or predicates before retrying.
- An `OR` between `doi_norm` and `hasToken` predicates on
  `openalex.works` defeats index pruning and times out. Run the exact
  `doi_norm` query first, then the token query as a separate fallback.
- Result rows are plain JSON arrays in column order. An occasional edge `502` with body `error code: 502` is
  transient; retry once.

## Academic papers and reviewer discovery

The academic estate joins scholarly metadata, the citation graph, author
profiles, full text, and full-text embeddings in one SQL surface. Its
premier journey is reviewer discovery: given a paper or topic, find **all**
strong candidate reviewers — not a handful — then screen and rank them.
Confirm every relation and column against `/v1/scry/schema` before use.

### The estate

Row counts, coverage, and freshness come from `GET /v1/scry/schema` and each
query's coverage block — read them there before stating any denominator.

| Relation | What it holds |
| --- | --- |
| `openalex.works` | Title, venue, year, DOI, authorships (author id, name, ORCID, institutions), topics, concepts, funders, OA locations, `cited_by_count`, `referenced_works` citation graph. Physical rows can outnumber unique works while background merges run — count works with `uniq(id)`, never `count()`. |
| `openalex.authors` | Names + alternatives, ORCID, `works_count`, `cited_by_count`, h-index (`summary_stats`), affiliation history, per-topic counts and shares, yearly output. |
| `academic.papers` | One deterministic full-text revision per source paper, keyed by DOI. Filter `quality_label = 'good'` for faithful text. |
| `embeddings.academic_paper_chunks` | voyage-4-nano semantic chunks over current full text; check the live schema freshness metadata. |

Join keys:

- **Metadata ↔ full text (the DOI bridge):**
  `works.doi_norm = decodeURLComponent(papers.paper_key)`.
  `doi_norm` is the lowercase bare DOI (bloom-indexed). Bridge reliability is
  directional. Full text → metadata: near-total (4999/5000 in a live sample).
  Metadata → full text: most works have no full text — the full-text corpus
  covers a minority of DOI-bearing works and skews toward older long-tail
  literature. Expect zero full-text rows for many recent papers, and treat
  zero as "not in the full-text corpus."
- **Work ↔ author:** authorship author ids equal `authors.id`
  (`https://openalex.org/A...`).
- **ORCID:** `authors.orcid_norm` is the uppercase bare id.

Flatten nested authorships with the arrayJoin *function* in a subquery —
the reliable path; the `ARRAY JOIN` clause is accepted only in one
restricted `LEFT ARRAY JOIN` form:

```sql
SELECT
  tupleElement(tupleElement(a, 'author'), 'id') AS author_id,
  tupleElement(tupleElement(a, 'author'), 'display_name') AS name,
  tupleElement(tupleElement(a, 'author'), 'orcid') AS orcid
FROM (
  SELECT arrayJoin(authorships) AS a
  FROM openalex.works
  WHERE doi_norm = '10.1016/j.cell.2021.04.048'
)
LIMIT 50
```

### Finding a paper comfortably

- **By DOI:** `WHERE doi_norm = '<lowercase-bare-doi>'` on works. `paper_key`
  is the lowercase DOI with the first slash literal and every later slash
  percent-encoded lowercase (`%2f`), for example
  `10.18653/v1%2f2024.acl-long.331`. Build it client-side from the DOI. The
  exact-key predicate `WHERE paper_key = '<paper-key>'` uses the bloom index;
  `WHERE decodeURLComponent(paper_key) = '<doi>'` forces a full scan.
- **By title:** `WHERE hasToken(search_text_lc, '<lowercase-token>')` on
  works; add `publication_year` bounds and `ORDER BY cited_by_count DESC`.
- **By content:** `hasToken(text, '<token>')` on `papers` (token-indexed;
  rare method terms work best), or semantic search over
  `embeddings.academic_paper_chunks`.
- **Abstract:** `abstract_inverted_index` is an OpenAlex word→positions
  JSON map, not prose. Read title + full text instead when you need clean
  words; decode the map only when the abstract is all you have.

### Reviewer discovery is a coverage problem

The corpus advantage is exhaustiveness. A top-k query answers "some
reviewers"; the journey demands "all strong candidates, then ranked."
Treat it like the deep-research loop: enumerate pools, measure
denominators, keep a ledger, and stop only when new lanes stop yielding.

1. **Bound the paper's territory.** Pull its works row: `primary_topic`,
   `topics`, `referenced_works`, authorships (for conflicts). Pull its
   full text or abstract for method vocabulary. If it is not in the
   corpus, build the territory from its closest indexed neighbors.
2. **Enumerate every candidate pool, with denominators.** One lane per
   pool; record each pool's size before sampling from it:
   - *Topical cohort:* authors of well-cited recent works sharing the
     paper's topics.
   - *Citation neighborhood:* authors of `referenced_works`, and authors
     of works whose `referenced_works` include the paper or its key
     references (inbound citers).
   - *Semantic neighbors:* nearest full-text chunks → `paper_key` →
     DOI bridge → works → authors. State the live embedded-coverage
     denominator (read it from the schema; the chunk row count is not a
     unique-paper count).
   - *Lexical method cohort:* rare method/term tokens over full text —
     catches work the topic taxonomy misses.
   - *Venue cohort:* frequent authors in the same journals or
     proceedings (`primary_location` source ids).
3. **Union into a candidate ledger.** One row per (author_id, lane,
   evidence work ids). An author surfaced by three independent lanes is
   a different object than one surfaced by one.
4. **Screen independence.** Drop recent coauthors (shared works within
   ~5y), same-institution candidates (`last_known_institutions` vs the
   paper's authorship institutions), and the paper's own authors.
5. **Rank with explicit axes.** Topical affinity (`topic_share`),
   authority (`summary_stats.h_index`, citations of their cohort works),
   recency (`counts_by_year` — active in the last 2–3 years), and lane
   multiplicity from the ledger. Report the axes with the shortlist.
6. **Stop on exhaustion, not on count.** Fresh lanes or term variants
   that produce no new candidates two rounds running end the search.
   Report pool sizes and coverage limits with the result — the
   denominators are the evidence that the search dominated the space.

### Worked pool queries

Topical cohort (topic → recent cited works → flattened authors):

```sql
SELECT
  tupleElement(tupleElement(a, 'author'), 'id') AS author_id,
  count(DISTINCT work_id) AS works_in_pool,
  max(cited) AS best_citations
FROM (
  SELECT id AS work_id, cited_by_count AS cited, arrayJoin(authorships) AS a
  FROM openalex.works
  WHERE hasToken(search_text_lc, 'interpretability')
    AND publication_year >= 2021 AND cited_by_count >= 25
)
GROUP BY author_id
ORDER BY works_in_pool DESC, best_citations DESC
LIMIT 100
```

Citation neighborhood (who the paper builds on). Outbound references are
inexpensive (one id lookup then a bounded id set). Inbound citers — works whose
`referenced_works` contain the paper — have no inverse index yet and scan
the full array column; always bound that direction with a
`hasToken(search_text_lc, ...)` or `publication_year` pre-filter and state
the cost:

```sql
SELECT
  tupleElement(tupleElement(a, 'author'), 'display_name') AS name,
  count() AS referenced_works_authored
FROM (
  SELECT arrayJoin(authorships) AS a
  FROM openalex.works
  WHERE id IN (
    SELECT arrayJoin(referenced_works)
    FROM openalex.works
    WHERE doi_norm = '<lowercase-doi>'
  )
)
GROUP BY name
ORDER BY referenced_works_authored DESC
LIMIT 100
```

Candidate hydration (profile, activity, authority):

```sql
SELECT id, display_name, orcid_norm, works_count, cited_by_count,
       tupleElement(summary_stats, 'h_index') AS h_index,
       last_known_institutions
FROM openalex.authors
WHERE id IN ('https://openalex.org/A...', 'https://openalex.org/A...')
```

### Digital signals

ORCID is the bridge out of academia: `authors.orcid_norm` joins curated
external ids (Google Scholar, Twitter/X, GitHub, Mastodon) as identity
relations become available — check `/v1/scry/schema` for what is
registered today. Already queryable now: candidate names and handles over
`mastodon.profiles`, `hackernews.items`, `forums.posts`, and
`stackexchange.posts` — treat name-based matches as
leads, not identities, and say so in the report.
