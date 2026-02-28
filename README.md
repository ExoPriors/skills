# ExoPriors Agent Skills

Agent skills for [Scry](https://exopriors.com/scry) — read-only SQL + semantic search over 229M+ entities (papers, posts, code, legal docs, predictions, and more).

Works with Claude Code, Cursor, Codex, Gemini CLI, and [40+ other agents](https://github.com/vercel-labs/skills).

## Install

```bash
# All skills
npx skills add exopriors/skills

# Just the core
npx skills add exopriors/skills --skill scry
```

## Skills

| Skill | Type | What it does |
|-------|------|-------------|
| **scry** | Auto | Core querying — schema discovery, lexical search, materialized views, shares, judgements |
| **vector-composition** | Auto | Semantic search with `@handle` vectors, debiasing, vector algebra |
| **rerank** | Auto | LLM pairwise reranking with canonical attributes (clarity, technical_depth, insight) |
| **people-graph** | Auto | Cross-platform author identity resolution (Twitter, GitHub, LW, arXiv, etc.) |
| **openalex** | Auto | Academic corpus navigation — 230M+ works, citation graphs, coauthor networks |
| **research-workflow** | `/research` | End-to-end orchestrator: find → embed → rerank → share → judge |
| **tutorial** | `/tutorial` | 7-step guided onboarding for your first Scry session |
| **scry-people-finder** | `/find-people` | Discover relevant people across the corpus by topic |

## Quick Start

Get a Scry API key at [exopriors.com/scry](https://exopriors.com/scry), then:

```bash
export EXOPRIORS_API_KEY=exopriors_...

# Your agent can now query 229M+ entities
curl -s https://api.exopriors.com/v1/scry/query \
  -H "Authorization: Bearer $EXOPRIORS_API_KEY" \
  -H "Content-Type: text/plain" \
  --data "SELECT title, uri, source FROM scry.entities WHERE kind = 'paper' ORDER BY original_timestamp DESC LIMIT 5"
```

Or just ask your agent: *"Search Scry for recent papers on mechanistic interpretability"* — the skills handle the rest.

## What's in the corpus?

229M+ entities across 80+ sources including arXiv, PubMed, LessWrong, EA Forum, HackerNews, Twitter, Bluesky, GitHub, Reddit, StackExchange, Wikipedia, Manifold, OpenAlex, SEC EDGAR, Congressional Record, and more.

## Capabilities

- **SQL queries** over the full corpus via `POST /v1/scry/query`
- **Lexical search** (BM25) via `scry.search()`
- **Semantic search** with voyage-4-lite embeddings and named `@handle` vectors
- **Vector algebra** — `debias_vector()` for "X but not Y" queries
- **LLM reranking** with configurable attributes and model tiers
- **Cross-platform identity** resolution across 10+ platforms
- **Academic graph** traversal (citations, coauthors, institutions)
- **Shareable artifacts** with permanent URLs
- **Structured judgements** — persistent, queryable agent observations

## Contributing

The source of truth for these skills is the `skills/` directory in [exopriors-core](https://github.com/ExoPriors/exopriors-core). Changes should be made there and synced here via `tools/sync-skills.sh --push`. Direct edits to this repo will be overwritten on next sync.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full sync workflow, source-of-truth file map, and content guidelines.

## License

MIT
