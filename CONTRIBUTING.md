# Contributing & Maintaining Skills

## When to Update Skills

These skills must stay in sync with the Scry API. Update skills when:

- **API endpoints change** — new routes, removed routes, changed request/response shapes
- **Schema changes** — new views, renamed columns, new materialized views, new SQL functions
- **Limits change** — row caps, vector caps, timeout policies, token budgets
- **New features** — new rerank attributes, new search functions, new share kinds
- **Model changes** — rerank model tiers, embedding models

## Source of Truth

The canonical source files that skills must match:

| What | File |
|------|------|
| SQL schema, views, functions | `src/db/schema.sql` |
| Scry API routes | `src/api/src/routes/scry.rs` |
| Shares API | `src/api/src/routes/scry_shares.rs` |
| Judgements API | `src/api/src/routes/scry_judgements.rs` |
| Embeddings API | `src/api/src/routes/embeddings.rs` |
| Rerank engine | `src/api/src/rerank/mod.rs` |
| SQL validation | `src/api/src/sql_validation.rs` |
| Request/response models | `src/api/src/models/` |
| Scry docs | `docs/scry.md` |
| Constants (limits, caps) | `src/api/src/routes/scry.rs` (top ~100 lines) |

## Key Constants to Watch

```
PUBLIC_MAX_QUERY_ROWS = 2000
MAX_QUERY_ROWS = 10000
PUBLIC_MAX_QUERY_ROWS_WITH_VECTORS = 200
MAX_QUERY_ROWS_WITH_VECTORS = 500
MAX_SCRY_RERANK_ENTITIES = 500
DEFAULT_SCRY_RERANK_MAX_ENTITIES = 200
DEFAULT_SCRY_RERANK_TEXT_MAX_CHARS = 4000
SCRY_TOKEN_BUDGET = 1_500_000
MIN_QUERY_TIMEOUT_SECS = 20
DAILY_BANDWIDTH_LIMIT_BYTES_PUBLIC = 200 MiB
```

## Sync Workflow

1. Make changes in the exopriors-core repo (`skills/` directory)
2. Verify against source code — especially constants and function signatures
3. Copy to exopriors-skills repo
4. Commit and push both repos

## Skill Structure

Each skill follows the [Anthropic Agent Skills Spec](https://github.com/anthropics/skills/blob/main/spec/agent-skills-spec.md):

```
skills/<name>/
  SKILL.md          # Required. Under 500 lines. YAML frontmatter + markdown.
  references/       # Optional. Detailed docs for agent context.
  scripts/          # Optional. Automation scripts.
```

Valid YAML frontmatter keys: `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`, `disable-model-invocation`, `user-invocable`.

## Content Guidelines

- **20% mental model** — why things work the way they do
- **70% recipes** — copy-paste patterns with goal → calls → payload → fallback
- **10% guardrails** — error handling, quota management, degradation
- All SQL examples must be verified against `src/db/schema.sql`
- All API calls must be verified against `src/api/src/routes/`
- Reference shared guardrails (`skills/references/guardrails.md`) instead of repeating safety rules
