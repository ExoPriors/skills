# Advanced Vector Algebra Patterns

Patterns for composing vector operations beyond basic search and debiasing. Covers operation ordering, multi-concept composition, failure mode detection, and diagnostic workflows.

## The Operations and What They Do

Every operation either preserves or removes signal. None can add information that was not in the input vectors.

| Operation | What it does | Signal effect |
|-----------|-------------|---------------|
| `scale_vector(v, s)` | Scalar multiplication | Preserves direction, changes magnitude |
| `v1 + v2` | Vector addition | Blends directions; magnitude depends on angle between v1 and v2 |
| `contrast_axis(pos, neg)` | `unit_vector(pos - neg)` | Cancels shared semantics, amplifies differences |
| `debias_vector(axis, topic)` | Removes projection onto topic | Removes signal along one direction |
| `debias_safe(axis, topic, cap)` | Capped removal | Removes up to `cap` fraction of energy |
| `project_onto(axis, topic)` | Extracts the removed component | The complement of debias_vector |
| `unit_vector(v)` | Normalizes to unit length | No effect on cosine distance ranking |

## Pattern 1: Weighted Multi-Concept Search

**Goal:** Search for documents at the intersection of 2-3 concepts with different importance weights.

```sql
-- 60% mech interp, 40% oversight
SELECT uri, title,
       embedding_voyage4 <=> (
         scale_vector(@mech_interp, 0.6) + scale_vector(@oversight, 0.4)
       ) AS distance
FROM scry.mv_high_score_posts
ORDER BY distance
LIMIT 20;
```

**How weights work:** The mixed vector points toward a direction between the two concepts, pulled toward whichever has higher weight. Since cosine distance is scale-invariant, what matters is the *ratio* of weights, not their absolute values. `(0.6, 0.4)` is equivalent to `(3.0, 2.0)`.

**When the angle matters:** If `@mech_interp` and `@oversight` are nearly parallel (high cosine similarity), their sum points in roughly the same direction regardless of weights. If they are nearly orthogonal, the weights strongly control the search direction. Check with `cosine_similarity(@mech_interp, @oversight)`.

**Three or more concepts:**
```sql
embedding_voyage4 <=> (
  scale_vector(@interp, 0.5) + scale_vector(@oversight, 0.3) + scale_vector(@governance, 0.2)
) AS distance
```

Each additional concept dilutes the specificity. Three concepts is practical; beyond that, the mixed direction becomes so broad it matches everything vaguely.

## Pattern 2: Mix Then Debias

**Goal:** Search for the intersection of two concepts, then remove an unwanted direction.

```sql
-- Mech interp + oversight, minus hype
SELECT uri, title,
       embedding_voyage4 <=> debias_vector(
         scale_vector(@mech_interp, 0.6) + scale_vector(@oversight, 0.4),
         @hype
       ) AS distance
FROM scry.mv_high_score_posts
ORDER BY distance
LIMIT 20;
```

**Step by step:**
1. Mix: Combine mech_interp and oversight into a single query direction.
2. Debias: Remove the component along `@hype`.
3. Result: "technical interp + oversight methodology" with generic AI excitement removed.

**Always diagnose:**
```sql
SELECT debias_removed_fraction(
  scale_vector(@mech_interp, 0.6) + scale_vector(@oversight, 0.4),
  @hype
);
```

If this returns 0.65 (as it did in the quality report for these specific concepts), 65% of the mixed vector was removed. The results are focused but the surviving direction is narrow. Consider using `debias_safe` with a 0.4 cap.

## Pattern 3: Contrast Then Debias (Tone Search)

**Goal:** Find documents written in a specific *style*, not documents *about* that style.

This is the hardest vector algebra task because tone is a weak signal in embedding space compared to topic.

**Step 1: Create the contrastive axis.**
```sql
-- @humble_tone and @proud_tone should describe the same *domain* but opposite *styles*
contrast_axis(@humble_tone, @proud_tone)
```

This cancels shared semantics (both are "about epistemic stances") and extracts the humble-vs-proud discrimination direction.

**Step 2: Debias against the topic.**
```sql
debias_vector(
  contrast_axis(@humble_tone, @proud_tone),
  @humility_topic
)
```

The contrastive axis removed *some* topic signal (shared between poles), but a dedicated topic vector captures "about humility" more precisely. This second pass cleans remaining topic contamination.

**Step 3: Validate the pipeline.**
```sql
-- Check pole quality
SELECT cosine_similarity(@humble_tone, @proud_tone) AS pole_similarity;
-- Sweet spot: 0.4-0.8

-- Check axis-topic overlap
SELECT debias_removed_fraction(
  contrast_axis(@humble_tone, @proud_tone),
  @humility_topic
) AS topic_removal;
-- Below 0.4 is safe. Above 0.5 means the axis was mostly topic, not tone.
```

**Alternative: Debias each pole first, then contrast.**
```sql
contrast_axis(
  debias_vector(@humble_tone, @humility_topic),
  debias_vector(@proud_tone, @humility_topic)
)
```

This removes topic from each pole *before* contrasting, which can be cleaner when both poles share heavy topic contamination. It requires two debias operations but each operates on a less-contaminated input.

## Pattern 4: Diagnostic-First Workflow

Before running a complex composition, diagnose every pair of vectors:

```sql
-- Step 1: Check all pairwise similarities
SELECT
  cosine_similarity(@mech_interp, @oversight) AS interp_oversight,
  cosine_similarity(@mech_interp, @hype) AS interp_hype,
  cosine_similarity(@oversight, @hype) AS oversight_hype;

-- Step 2: Check removal fractions for planned debias
SELECT
  debias_removed_fraction(@mech_interp, @hype) AS interp_minus_hype,
  debias_removed_fraction(@oversight, @hype) AS oversight_minus_hype,
  debias_removed_fraction(
    scale_vector(@mech_interp, 0.6) + scale_vector(@oversight, 0.4),
    @hype
  ) AS mix_minus_hype;

-- Step 3: Full diagnostics on the planned operation
SELECT * FROM debias_diagnostics(
  scale_vector(@mech_interp, 0.6) + scale_vector(@oversight, 0.4),
  @hype
);
```

**Reading the diagnostics table:**
- `axis_norm`: Length of the input vector. After mixing, this depends on the angle between components.
- `topic_norm`: Length of the debias target. Should be non-zero.
- `debiased_norm`: Length after debiasing. If this is near zero, the operation destroyed the signal.
- `axis_topic_cosine`: How aligned axis and topic are. High absolute value = heavy overlap = aggressive removal.
- `removed_component_norm`: Length of what was removed.
- `removed_fraction`: Energy fraction removed (cos^2 of the angle). The single most important diagnostic number.

## Pattern 5: Inspecting What Was Removed

`project_onto` extracts the component that `debias_vector` removes:

```sql
-- What does the "hype" component of my interp query look like?
-- Search for documents similar to the REMOVED direction
SELECT uri, title,
       embedding_voyage4 <=> project_onto(@mech_interp, @hype) AS distance
FROM scry.mv_high_score_posts
ORDER BY distance
LIMIT 10;
```

This shows you what debiasing is filtering out. If the removed component matches generic AI hype articles, the debiasing is working as intended. If it matches substantive interp papers, you are losing signal.

**Decomposition check** (should reconstruct the original):
```sql
-- project_onto(a, t) + debias_vector(a, t) should approximately equal a
-- Verify by checking that the distance between the reconstruction and original is near zero
SELECT cosine_similarity(
  project_onto(@mech_interp, @hype) + debias_vector(@mech_interp, @hype),
  @mech_interp
) AS reconstruction_similarity;
-- Should be ~1.0 (minor floating-point loss from halfvec precision)
```

## Failure Modes and How to Detect Them

### 1. Over-Debiasing (Most Common)

**Symptom:** Results are focused but unexpected or tangential. Distances are high (0.35+).

**Detection:**
```sql
SELECT debias_removed_fraction(@axis, @topic);
-- Danger: > 0.5. Garbage: > 0.85.
```

**Fix:** Use `debias_safe(@axis, @topic, 0.4)` to cap removal. Or choose a more orthogonal debias target -- embed a narrower, more specific concept for `@topic`.

### 2. Near-Zero Residual

**Symptom:** Query returns no results or random-looking results.

**Detection:**
```sql
SELECT (SELECT debiased_norm FROM debias_diagnostics(@axis, @topic));
-- Danger: < 0.05
```

**Root cause:** `@axis` and `@topic` are nearly parallel. `debias_vector` removes almost everything, leaving floating-point noise. `unit_vector` on the result returns NULL (the safety guard).

**Fix:** Do not debias nearly-parallel vectors. If `cosine_similarity(@axis, @topic) > 0.9`, find a different approach (e.g., lexical exclusion, or a less-related debias target).

### 3. Unbalanced Contrastive Poles

**Symptom:** Contrastive axis returns documents similar to one pole but not the other.

**Detection:**
```sql
SELECT
  vector_norm(@pos_pole::vector) AS pos_norm,
  vector_norm(@neg_pole::vector) AS neg_norm,
  cosine_similarity(@pos_pole, @neg_pole) AS pole_similarity;
-- Norms should be similar. Similarity between 0.4-0.8.
```

**Root cause:** One pole's embedding text is much richer/longer than the other, so it dominates the difference vector.

**Fix:** Use `contrast_axis_balanced(@pos, @neg)` which normalizes both poles before subtracting. Or rewrite the shorter pole's text to be comparably detailed.

### 4. Sequential Debias Order Dependence

**Symptom:** Debiasing against topic A then topic B gives different results than B then A.

**Root cause:** Sequential projection removal is not commutative unless the topics are orthogonal.

**Detection:**
```sql
SELECT cosine_similarity(@topic_a, @topic_b) AS topic_correlation;
-- If > 0.3, order matters. If > 0.6, sequential debias will over-remove.
```

**Fix:** Only debias against one direction per query. If you must remove two directions, debias against the more important one and check `removed_fraction`. Proper multi-axis debiasing (projecting out a subspace) is not yet exposed as a SQL function.

### 5. Embedding Text Too Vague

**Symptom:** Search returns a broad, unfocused set of documents.

**Detection:** Compare results to a more specific embedding:
```sql
-- Vague: returns everything about AI
-- "artificial intelligence alignment"

-- Specific: returns focused results
-- "mechanistic interpretability, reverse-engineering learned circuits and features,
--  understanding how specific neurons and attention heads contribute to model outputs,
--  circuit-level analysis of transformer architectures"
```

**Fix:** Make the embedding text longer and more specific. Include technical terms, synonyms, and phrases that appear in the documents you want to find.

## Operation Ordering Rules

1. **Mix before debias.** Combining concepts first gives a stable direction. Debiasing a single concept and then mixing introduces asymmetry (one concept is debiased, the other is not).

2. **Contrast before debias** (usually). Build the discriminative axis first, then clean residual topic contamination. Exception: when both poles share heavy topic contamination, debias each pole separately first.

3. **Diagnose before trusting.** Check `removed_fraction` and `cosine_similarity` between all vector pairs before interpreting results.

4. **One debias per query** (recommended). Each debias removes signal irreversibly. Stacking two debias operations can remove 60%+ of the original energy. If you need to remove two directions, try combining them into a single debias target: `debias_vector(@axis, scale_vector(@topic_a, 0.5) + scale_vector(@topic_b, 0.5))`.

5. **`unit_vector` is rarely needed.** Cosine distance (`<=>`) normalizes internally. Only use `unit_vector` when you need consistent norms for other operations (e.g., as input to `contrast_axis` which already normalizes internally).

## Energy Budget Mental Model

Think of your original vector as having 100% energy (squared norm). Each operation has an energy cost:

| Operation | Energy after |
|-----------|-------------|
| `scale_vector(v, s)` | s^2 * original (scaling changes magnitude) |
| `v1 + v2` | Depends on angle; range from (n1-n2)^2 to (n1+n2)^2 |
| `contrast_axis(pos, neg)` | Always 1.0 (it normalizes) |
| `debias_vector(axis, topic)` | (1 - removed_fraction) * input energy |
| `debias_safe(axis, topic, cap)` | At least (1 - cap) * input energy |

For cosine distance searches, energy does not affect ranking. But it affects the **signal-to-noise ratio** of subsequent operations. A vector with 10% of its original energy has 10x worse SNR against the halfvec(2048) noise floor.

**Practical threshold:** Below ~5% of original energy, the vector is indistinguishable from noise in halfvec precision. This corresponds to two debias operations each removing 50%+, or one removing 95%+.

## Worked Example: Complete Workflow

Goal: Find technically rigorous posts about AI governance that are not generic policy advocacy.

```sql
-- Step 1: Embed concepts (via /v1/scry/embed)
-- @technical_governance: "technical AI governance, compute governance mechanisms,
--   algorithmic auditing frameworks, model evaluation standards, deployment safety
--   requirements, structured access policies"
-- @policy_advocacy: "AI policy advocacy, lobbying for AI regulation, open letters
--   about AI risk, calls to action for policymakers, AI ethics campaigns"

-- Step 2: Diagnose
SELECT
  cosine_similarity(@technical_governance, @policy_advocacy) AS overlap,
  debias_removed_fraction(@technical_governance, @policy_advocacy) AS removal;
-- Suppose: overlap = 0.52, removal = 0.27
-- 0.27 removed_fraction is in the sweet spot. Proceed.

-- Step 3: Search with debiasing
SELECT uri, title, original_author, source,
       embedding_voyage4 <=> debias_vector(@technical_governance, @policy_advocacy) AS distance
FROM scry.mv_high_score_posts
ORDER BY distance
LIMIT 25;

-- Step 4: Inspect what was removed
SELECT uri, title,
       embedding_voyage4 <=> project_onto(@technical_governance, @policy_advocacy) AS distance
FROM scry.mv_high_score_posts
ORDER BY distance
LIMIT 10;
-- Verify these are generic policy/advocacy posts, not technical governance papers.

-- Step 5: Refine if needed
-- If too much technical content appears in the "removed" results,
-- make @policy_advocacy more specific to pure advocacy (less overlap with technical work).
```
