# Calibration Guide

How to validate rerank quality, compare tiers, and record results as judgements.

## Why calibrate

Rerank is only as good as the LLM's judgement on your specific attribute and domain. Calibration answers: "does this model, on this attribute, agree with my expert evaluation of these documents?" Without calibration, you are trusting the model blindly.

Calibration also reveals which attributes and tiers are worth paying for. A `fast` tier that agrees with `quality` 90% of the time on your domain saves you 10x in cost.

## The calibration loop

1. **Select a test set.** 20-50 entities from your target domain. Small enough to review manually.
2. **Establish ground truth.** Rank the test set yourself (or with domain experts) on each attribute. Even a partial ordering (top-5, bottom-5, middle) is valuable.
3. **Run rerank.** Use the same test set, same attributes, across tiers.
4. **Compare.** Measure agreement between LLM rankings and your ground truth.
5. **Iterate.** Adjust attribute prompts, switch tiers, or refine your ground truth.

## Step 1: Select a test set

Good test sets have:
- **Variance.** Include clearly good, clearly bad, and ambiguous items. All-good sets cannot distinguish models.
- **Domain coverage.** Represent the actual distribution you will rerank in production.
- **Manageable size.** 20-50 items. More is better but the bottleneck is human review.

```json
{
  "sql": "SELECT id, content_text FROM scry.entities WHERE kind='post' AND source='lesswrong' AND content_risk IS DISTINCT FROM 'dangerous' ORDER BY random() LIMIT 30",
  "attributes": [{"id":"clarity","prompt":"clarity","weight":1.0}],
  "topk": {"k": 30},
  "model_tier": "fast",
  "cache_results": true,
  "cache_list_name": "calibration-set-clarity-v1"
}
```

Cache the result so you can rerun on the same entities with different tiers.

## Step 2: Establish ground truth

Review the top-k output. For each entity, note:
- Your personal ranking (or bucket: top-tier / mid-tier / bottom-tier).
- Any entities the model ranked surprisingly high or low.
- Whether the model's judgement aligns with your reading of the attribute prompt.

You do not need a complete ranking. Partial truth is sufficient:
- "These 5 are clearly the best on clarity."
- "These 5 are clearly the worst."
- "The rest are roughly interchangeable."

Record this in a structured format:

```
# Calibration: clarity on lesswrong posts
# List: calibration-set-clarity-v1
# Date: YYYY-MM-DD

## Human top-5 (ordered)
1. entity-uuid-a  -- "Extremely clear writeup on coordination failures"
2. entity-uuid-b  -- "Well-structured argument with defined terms"
3. entity-uuid-c  -- "Clean prose, logical flow"
4. entity-uuid-d  -- "Good structure despite complex topic"
5. entity-uuid-e  -- "Clear but slightly meandering"

## Human bottom-5 (unordered)
- entity-uuid-x  -- "Dense jargon, no definitions"
- entity-uuid-y  -- "Stream of consciousness"
- entity-uuid-z  -- "Multiple unconnected threads"
...

## Surprises
- entity-uuid-f ranked #3 by model but I put it mid-tier. Re-reading: model may be right, it IS quite clear despite being boring.
- entity-uuid-g ranked #25 by model but I thought it was clear. On re-read: the opening is clear but it degrades into jargon in the second half. Model saw the whole text.
```

## Step 3: Run across tiers

Rerank the cached list with each tier:

```bash
for tier in fast balanced quality; do
  echo "=== $tier ==="
  curl -s "${EXOPRIORS_API_BASE:-https://api.scry.io}/v1/scry/rerank" \
    -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"list_id\": \"CACHED_LIST_ID\",
      \"attributes\": [{\"id\":\"clarity\",\"prompt\":\"clarity\",\"weight\":1.0}],
      \"topk\": {\"k\": 30},
      \"model_tier\": \"$tier\"
    }" | jq '.rerank.entities[:10] | .[] | {id, rank, score: .scores.clarity.score}'
done
```

## Step 4: Measure agreement

### Rank correlation

Compare the model's ranking to your ground truth ordering. Useful metrics:

**Top-k overlap:** What fraction of your human top-5 appear in the model's top-5?
```
overlap = |human_top5 ∩ model_top5| / 5
```

Good: >= 0.6 (3/5 overlap). Excellent: >= 0.8 (4/5).

**Kendall tau on top-k:** Rank correlation restricted to items both you and the model rank highly. More sensitive to ordering within the top set.

**Inversion count:** How many of your "clearly better than" pairs does the model reverse? If you said A > B and the model ranked B above A, that is an inversion.

### Practical shortcut

For most use cases, eyeball the top-10 from each tier and ask:
1. Are the top-3 items genuinely good on this attribute?
2. Are any clearly-bad items in the top-10?
3. Does the ranking make sense relative to your human judgement?

If the answer to all three is "mostly yes," the tier is good enough. If not, try:
- A different tier.
- A refined attribute prompt (the most common fix).
- A different domain filter in the SQL.

## Step 5: Tier comparison matrix

Build a matrix of tier-vs-tier agreement and tier-vs-human agreement:

```
                  human    fast    balanced    quality
human              --       0.6      0.8        0.9
fast              0.6       --       0.7        0.7
balanced          0.8      0.7       --         0.85
quality           0.9      0.7      0.85        --
```

This tells you:
- `quality` agrees with your judgement 90% of the time: worth using for final rankings.
- `balanced` agrees 80%: good enough for most use cases at 1/3 the cost.
- `fast` agrees 60%: useful for rough filtering but not final decisions.

These numbers will vary by domain and attribute. Technical depth on ML papers will calibrate differently than clarity on blog posts.

## Recording results as judgements

Once you have validated a tier's quality, you can feed your human calibration back into ExoPriors as explicit pairwise comparisons. This improves future warm-start accuracy.

### Via the persist mechanism

If you have a rater UUID and attribute UUIDs, you can persist comparisons directly through the rerank API:

```json
{
  "list_id": "CACHED_LIST_ID",
  "attributes": [{"id":"clarity","prompt":"clarity","weight":1.0}],
  "topk": {"k": 30},
  "model_tier": "quality",
  "persist": {
    "attribute_map": {"clarity": "UUID_OF_CLARITY_ATTRIBUTE"},
    "rater_id": "UUID_OF_YOUR_RATER",
    "refresh_scores": true
  }
}
```

This stores the LLM's comparisons in `public_binary_ratio_comparisons` under your rater ID. Future reranks involving the same entity pairs will warm-start from these, reducing both cost and latency.

### Manual human judgements

For human-provided ground truth, you can record explicit pairwise comparisons via the comparisons API. Each comparison is: "entity A is X times better than entity B on attribute Y."

This is the most powerful calibration tool: it anchors the solver to human judgement, and the IRLS solver downweights outlier LLM comparisons that conflict with high-confidence human anchors.

## Attribute prompt iteration

The single highest-leverage calibration activity is refining attribute prompts. Common failure modes and fixes:

### Model ranks entertaining content highest on "clarity"

**Problem:** The prompt does not exclude entertainment value from clarity.

**Fix:** Add exclusion: "Do not conflate clarity with entertainment value, persuasiveness, or writing style."

### Model ranks short content highest on "technical_depth"

**Problem:** Short, focused pieces can appear deep because the model compares density, not absolute depth.

**Fix:** Add anchor: "Judge absolute depth of engagement, not density relative to length. A 500-word post that mentions a mechanism is less deep than a 5000-word analysis of that mechanism."

### Model gives inconsistent rankings across runs

**Problem:** The attribute prompt is ambiguous; the model resolves ambiguity differently each time.

**Fix:** Add concrete examples of high/low to the prompt. More structure = more consistency.

### Model conflates two dimensions

**Problem:** Attribute measures "insight AND clarity" implicitly.

**Fix:** Split into two attributes with separate weights. Conflated attributes produce unstable rankings because the model randomly emphasizes one dimension or the other in each comparison.

## When NOT to use rerank

Rerank is not always the right tool:

- **Simple ordering by a known signal** (date, score, upvotes): use `ORDER BY` in SQL. Zero cost, deterministic.
- **Binary classification** (relevant/irrelevant): use a gate, not a ranking attribute. Gates are cheaper.
- **Very large candidate sets (>500)**: pre-filter with SQL and embeddings first. Rerank is a precision tool, not a recall tool.
- **Reproducibility requirements**: LLM judgements have inherent variance. If you need bit-for-bit reproducible rankings, use the cached scores from a previous run rather than re-running.

## Calibration checklist

- [ ] Selected 20-50 representative entities as test set
- [ ] Cached the test set with `cache_results: true`
- [ ] Established human ground truth (at least top-5 and bottom-5)
- [ ] Ran rerank with `fast`, `balanced`, and `quality` tiers
- [ ] Measured top-k overlap between human and each tier
- [ ] Identified attribute prompt issues from surprising rankings
- [ ] Refined prompts and re-ran if needed
- [ ] Chose a tier that balances accuracy and cost for this use case
- [ ] Recorded validated comparisons via `persist` for warm-start benefit
