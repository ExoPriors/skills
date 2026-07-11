# Error reference

| Status | First move |
| --- | --- |
| `400` | Re-read `/v1/scry/schema`; fix ClickHouse syntax, relation, columns, or missing `LIMIT`. |
| `401` | Reload `SCRY_API_KEY` and remove whitespace. |
| `402` | Inspect account, pricing, estimate, and funding state. |
| `403` | Use a key with Scry scope; do not probe engine catalogs. |
| `429` | Respect `Retry-After`. |
| `503` | Tighten the query or retry later. |

If a relation or helper is absent from `/v1/scry/schema`, it is unavailable.
Choose another registered surface or report the coverage gap. Never route the
query to a fallback database.

For slow queries: reduce selected columns, add a selective predicate, lower the
limit, and inspect a recent time window when the schema exposes one. Use
`POST /v1/scry/estimate` before a broader retry.
