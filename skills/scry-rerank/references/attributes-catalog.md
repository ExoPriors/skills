# Attributes Catalog

Attributes define what the LLM judges when comparing pairs of documents. Each attribute has an `id`, a `prompt` (the evaluation criterion), and a `weight` (relative importance in the final composite score).

## Canonical attributes

Canonical attributes are memoized across the entire ExoPriors user base. When two users rerank overlapping entity pairs on the same canonical attribute, the second user benefits from cached comparisons at zero cost.

To use a canonical attribute, set `id` to the canonical name. You can pass a short label as `prompt` and the system auto-fills the full evaluation text.

### clarity

**Short description:** How clear, coherent, and easy to understand the content is.

**Full prompt (auto-filled):**
> Clarity measures how well the content communicates its claims and reasoning to a motivated reader. High clarity has a clear thesis, defined terms, logical flow, and minimal unnecessary jargon. Do not conflate clarity with correctness, novelty, or importance; judge only understandability and explanation quality.

**When to use:** Finding well-communicated content. Sorting through noisy feeds. Identifying authors who write clearly.

**What it does NOT measure:** Whether the content is correct, novel, or important. A crystal-clear summary of a well-known idea scores high on clarity and low on insight.

**Usage:**
```json
{"id": "clarity", "prompt": "clarity", "weight": 1.0}
```

### technical_depth

**Short description:** Depth, rigor, and technical sophistication of the content.

**Full prompt (auto-filled):**
> Technical depth measures how deeply and rigorously the content engages the subject: precise mechanisms, math, formal reasoning, or careful empirical analysis. High depth goes beyond surface summary into detailed, non-trivial structure. Do not reward length or obscurity alone, and do not conflate depth with clarity or novelty.

**When to use:** Finding substantive technical work. Filtering out shallow commentary. Ranking papers or posts by analytical rigor.

**What it does NOT measure:** Whether the content is readable or novel. A rigorous but unoriginal analysis of a known result scores high on depth and low on insight.

**Usage:**
```json
{"id": "technical_depth", "prompt": "technical depth", "weight": 1.0}
```

### insight

**Short description:** Novel, non-obvious ideas or connections that add new understanding.

**Full prompt (auto-filled):**
> Insight measures whether the content contributes a genuinely new idea, connection, or perspective that changes how one thinks about the topic. High insight is non-obvious and yields new implications or understanding. Do not conflate insight with clarity, stylistic quality, or technical density; a clear or deep piece can still be derivative.

**When to use:** Finding original thinking. Discovering surprising connections. Identifying content worth sharing.

**What it does NOT measure:** Whether the content is well-written or technically rigorous. A messy blog post that introduces a genuinely new frame scores high on insight.

**Usage:**
```json
{"id": "insight", "prompt": "insight", "weight": 1.0}
```

## Writing custom attribute prompts

Custom attributes let you rank by any criterion the LLM can evaluate. The prompt is the most important part: it directly controls what the model looks for when comparing two documents.

### Prompt structure

A good attribute prompt has three parts:

1. **What it measures** (1 sentence): the core criterion.
2. **What high/low looks like** (1-2 sentences): concrete anchors for the scale.
3. **What it does NOT measure** (1 sentence): exclusions that prevent conflation.

This structure matches the canonical attributes and gives the LLM clear decision boundaries.

### Template

```
[Criterion name] measures [what]. High [criterion] means [concrete anchor for high end].
Low [criterion] means [concrete anchor for low end]. Do not conflate [criterion] with
[related-but-different things]; judge only [the specific dimension].
```

### Example custom attributes

#### Actionability

```json
{
  "id": "actionability",
  "prompt": "Actionability measures whether the content gives the reader concrete next steps, tools, or procedures they can use immediately. High actionability provides specific instructions, code, frameworks, or decision criteria. Low actionability discusses ideas abstractly without translating them into action. Do not conflate actionability with quality, depth, or novelty; a shallow how-to guide can be highly actionable.",
  "weight": 1.0
}
```

#### Empirical grounding

```json
{
  "id": "empirical_grounding",
  "prompt": "Empirical grounding measures how well the claims are supported by data, experiments, or concrete evidence. High grounding cites specific studies, datasets, measurements, or real-world observations. Low grounding relies on intuition, analogy, or abstract reasoning without empirical support. Do not conflate grounding with technical depth or correctness; a mathematically rigorous proof has depth but not empirical grounding.",
  "weight": 1.0
}
```

#### Intellectual honesty

```json
{
  "id": "intellectual_honesty",
  "prompt": "Intellectual honesty measures whether the author acknowledges uncertainty, limitations, counterarguments, and the strongest version of opposing views. High honesty explicitly states what the author does not know, where the argument is weakest, and what evidence would change their mind. Low honesty cherry-picks evidence, strawmans opposition, or presents uncertain claims as settled. Do not conflate honesty with agreeing with the mainstream or hedging everything.",
  "weight": 1.0
}
```

#### Relevance to a specific topic

```json
{
  "id": "mech_interp_relevance",
  "prompt": "Mechanistic interpretability relevance measures how directly the content addresses understanding the internal computations of neural networks. High relevance presents new circuits, features, activation patterns, or methods for reverse-engineering model behavior. Low relevance discusses AI safety, interpretability, or ML broadly without engaging specific internal mechanisms. Do not conflate relevance with quality; a mediocre paper directly about circuits is more relevant than an excellent paper about RLHF.",
  "weight": 2.0
}
```

#### Writing quality (beyond clarity)

```json
{
  "id": "writing_craft",
  "prompt": "Writing craft measures the aesthetic and structural quality of the prose: precision of language, sentence rhythm, effective use of examples and analogies, and overall readability beyond mere logical coherence. High craft produces writing that is a pleasure to read and that teaches through its form, not just its content. Low craft is functional but flat, generic, or awkward. Do not conflate craft with correctness, technical depth, or agreement with the reader's views.",
  "weight": 0.5
}
```

#### Forecasting relevance

```json
{
  "id": "forecasting_value",
  "prompt": "Forecasting value measures whether the content provides information useful for predicting future events or outcomes. High value offers base rates, trend data, causal models, track records, or frameworks that help calibrate probabilities. Low value discusses topics without connecting them to verifiable future predictions. Do not conflate forecasting value with technical depth or accuracy of past predictions.",
  "weight": 1.0
}
```

### ID naming conventions

- **Canonical attributes**: use the exact canonical name (`clarity`, `technical_depth`, `insight`).
- **Custom attributes**: use descriptive snake_case IDs (`mech_interp_relevance`, `forecasting_value`).
- **Avoid generic IDs** like `quality` or `good` -- they lead to cache collisions and ambiguous prompts.
- **Prefix domain-specific attributes** with the domain (`bio_mechanism_clarity`, `policy_actionability`) to avoid collisions when working across domains.

### Combining attributes

Weights control relative importance in the composite score. Some patterns:

**Balanced multi-objective** (equal weight):
```json
[
  {"id": "clarity", "prompt": "clarity", "weight": 1.0},
  {"id": "technical_depth", "prompt": "technical depth", "weight": 1.0},
  {"id": "insight", "prompt": "insight", "weight": 1.0}
]
```

**Insight-heavy** (prioritize novelty):
```json
[
  {"id": "clarity", "prompt": "clarity", "weight": 0.5},
  {"id": "insight", "prompt": "insight", "weight": 2.0}
]
```

**Domain-filtered** (gate + rank):
Use a gate to enforce topic relevance, then rank survivors by quality:
```json
{
  "attributes": [
    {"id": "insight", "prompt": "insight", "weight": 1.0},
    {"id": "technical_depth", "prompt": "technical depth", "weight": 1.0}
  ],
  "gates": [
    {
      "attribute": {"id": "on_topic", "prompt": "Is this content specifically about [your topic]?", "weight": 1.0},
      "op": "gte",
      "threshold": 0.5
    }
  ]
}
```

### Common mistakes

1. **Overly long prompts.** The LLM reads the prompt for every comparison. Keep it under 200 words. Longer is not better.
2. **Conflating dimensions.** "Is this good?" conflates clarity, depth, insight, and relevance. Separate them into distinct attributes with weights.
3. **Forgetting exclusions.** Without "do not conflate X with Y", the LLM will blend nearby dimensions. Explicit exclusions are the most important part of the prompt.
4. **Too many attributes.** Each attribute multiplies the comparison budget. 2-3 attributes is the sweet spot. 4+ rarely justified.
5. **Generic IDs for custom attributes.** Using `"id": "relevance"` across different rerank calls with different prompts creates cache confusion. Be specific: `"id": "mech_interp_relevance_v2"`.
