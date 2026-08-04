# Comparative study design

Governs any Scry study that compares cohorts or tests a hypothesis ("do X-people
do Y more?") rather than retrieving facts. Retrieval discipline (vocabulary
fanout, probe ledgers, coverage denominators) lives in `deep-research.md`; this
file governs inference. The core stance: **a lexicon is an instrument, not a
definition** — it has a bandwidth, a stance it selects for, and a
false-positive profile that varies by community register.

## Before querying

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

## Design mechanics

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

## After rows come back

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

## Interpretation ladder

Licensed: predictive claims scoped to corpus, language, lexicon band, and
window. Not licensed without further evidence: causal or psychological
stories (a common cause usually fits equally well), off-platform
generalization, and absence claims outside the instrument's band — passive
aggression, sarcasm, and concern trolling are invisible to overt lexicons, so
"not found" means "not found in this band"; escalate to semantic measures to
probe further. Scope every conclusion by moderation survivorship (hostile
accounts get suspended) and by crawl selection of the corpus.
