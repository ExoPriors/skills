# Registered vector helpers

Vector SQL uses ClickHouse helpers advertised by `GET /v1/scry/schema`:

- `scry_cosine_similarity(a, b)`
- `scry_vector_norm(v)`
- `scry_unit_vector(v)`
- `scry_scale_vector(v, scalar)`
- `scry_debias_vector(a, target)`
- `scry_contrast_axis(positive, negative)`

The registered retrieval relation is `scry.scry_vector_topk`. Confirm its live
signature and columns before use; its result columns are `canonical_uri` and
`distance`. Do not use database-specific vector operators or assume that an
unregistered embedding table is queryable.

Vectors are ranking hypotheses. Check nearest rows against lexical evidence,
provenance, source coverage, and the intended concept before reporting a
semantic conclusion.
