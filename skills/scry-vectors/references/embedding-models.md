# Embedding Models

Reference for models available in Scry's vector pipeline. Covers what each model is, what it costs, and when to choose it.

## Models Available for Corpus Search

These models have pre-computed embeddings stored in `public_embeddings` and exposed canonically through `scry.chunk_embeddings`, `scry.document_embeddings`, and `scry.embedded_entities`.

### voyage-4-lite (canonical)

| Property | Value |
|----------|-------|
| Column | `embedding_voyage4` |
| Dimensions | 2048 (halfvec) |
| Provider | Voyage AI |
| Cost | $0.02 per 1M tokens |
| Coverage | Canonical model for all new embeddings; broadest corpus coverage |
| Index type | vchordrq (approximate cosine) |
| Operator | `<=>` (cosine distance) |

This is the only model you should use for semantic search in Scry. The canonical semantic surfaces expose it as `embedding_voyage4`, and the entire vector algebra toolkit (`debias_vector`, `contrast_axis`, `scale_vector`, etc.) operates on `halfvec(2048)` -- the Voyage-4-lite dimensionality.

Voyage-4-lite is part of the Voyage-4 model family. All Voyage-4 variants (nano, lite, full, large) share the same embedding space. A vector from voyage-4-lite and a vector from voyage-4 are directly comparable via cosine distance. The corpus uses a mix of voyage-4-lite (bulk) and voyage-4-nano (some older embeddings), but they coexist in the same `embedding_voyage4` column.

### fnv-384 (local hash)

| Property | Value |
|----------|-------|
| Column | `embedding_fnv384` |
| Dimensions | 384 (halfvec) |
| Provider | Local (FNV-1a hash) |
| Cost | Zero (no API call) |
| Coverage | Sparse; not computed for most entities |
| Index type | vchordrq (approximate cosine) |
| Operator | `<=>` (cosine distance) |

A deterministic hash-based embedding. Not a learned model -- it uses FNV-1a hashing to map text to a fixed 384-dimensional vector. Characteristics:

- **Zero cost**: No API call, no token budget consumption. Computed locally.
- **Deterministic**: Same text always produces the same vector. No model version drift.
- **Low semantic fidelity**: Hash embeddings capture lexical co-occurrence patterns, not deep semantic similarity. "dog" and "canine" will have different hash vectors. "bank" (financial) and "bank" (river) will have the same hash vector.
- **Sparse coverage**: Most corpus entities do not have `embedding_fnv384` computed. Not suitable as a primary search model.

Use case: Zero-cost similarity for lexically-focused tasks, or as a cheap pre-filter before a more expensive Voyage-4-lite search. In practice, `voyage-4-lite` is almost always the right choice.

**FNV-384 is NOT available through `/v1/scry/embed`.** The embed endpoint only supports `voyage-4-lite`. FNV-384 embeddings exist in the corpus from batch processing but cannot be created interactively.

## Model Available for /v1/scry/embed

Only one model is available for embedding text via the API:

### voyage-4-lite

```json
{
  "name": "my_concept",
  "text": "your concept description here",
  "model": "voyage-4-lite"
}
```

The `model` field defaults to `voyage-4-lite` if omitted. Passing any other value returns an error.

## Token Budget

Each private API key has an embedding token budget (default: 1.5M tokens). Every call to `/v1/scry/embed` with `voyage-4-lite` consumes tokens from this budget.

| Budget detail | Value |
|--------------|-------|
| Default budget | 1,500,000 tokens |
| Cost per 1M tokens | $0.02 (Voyage AI pricing) |
| Budget per key | ~$0.03 worth of embeddings |
| Reset | Regenerating the key resets the budget |
| Remaining tokens | Returned in every embed response as `remaining_tokens` |

**Budget math for typical usage:**
- A 100-word concept description uses ~130-150 tokens.
- 1.5M tokens = ~10,000 embed calls with 150-token descriptions.
- Typical skill workflow uses 2-6 handles = negligible budget impact.

## Choosing a Model

For interactive vector composition workflows (what this skill is about), the decision is simple:

**Use `voyage-4-lite` for everything.** It is the only model available for `/v1/scry/embed`, it has the broadest corpus coverage, and the vector algebra functions are designed for its 2048-dimensional space. The token cost is negligible for concept embedding (a few hundred tokens per handle).

FNV-384 is relevant only when querying pre-computed `embedding_fnv384` columns in the corpus, which is uncommon.

## Embedding Quality Tips

The quality of your search depends on the quality of your embed text. Guidelines:

**Be descriptive, not terse.** "mech interp" embeds poorly. "mechanistic interpretability, reverse-engineering learned circuits and features in neural networks, understanding how specific neurons and attention heads contribute to model behavior" embeds well.

**Include synonyms and related phrases.** The embedding captures the semantic neighborhood of the full text, not just the primary concept. Including related terms widens the catchment area.

**Match the register of what you want to find.** If you want academic papers, embed in academic style. If you want blog posts, embed in casual style. The model encodes tone/register weakly but measurably.

**Iterate.** Embed, search, inspect results, refine the text, re-embed (personal keys can overwrite handles). The first embedding is rarely the best one.

## Stored Vector Schema

Stored vectors live in `scry.stored_vectors` with RLS (row-level security) enforcing user isolation:

| Column | Type | Notes |
|--------|------|-------|
| `user_id` | UUID | Owner |
| `name` | TEXT | Handle name (the `@handle` reference) |
| `embedding_voyage4` | halfvec(2048) | Voyage-4 vector (mutually exclusive with fnv384) |
| `embedding_fnv384` | halfvec(384) | FNV hash vector (mutually exclusive with voyage4) |
| `source_text` | TEXT | Original text that was embedded |
| `token_count` | INT | Tokens consumed |
| `model_name` | TEXT | Model used |
| `created_at` | TIMESTAMPTZ | Creation timestamp |

A stored vector has exactly one of `embedding_voyage4` or `embedding_fnv384` populated (enforced by a CHECK constraint). In practice, all API-created vectors use `embedding_voyage4`.

Personal keys can list vectors via `GET /v1/scry/vectors` and delete via `DELETE /v1/scry/vectors/{name}`.

## Limits

| Constraint | Base account key | Pass-enabled account key |
|-----------|------------------|--------------------------|
| Max rows with vectors in output | 200 | 500 |
| Handle naming | Any valid identifier (overwritable) | Any valid identifier (overwritable) |
| List/delete vectors | Yes | Yes |
| Embed token budget | 1.5M per key | 1.5M per key |
| Max text per embed request | 8,192 tokens | 8,192 tokens |
