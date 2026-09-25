# ExoPriors Agent Skills

Agent skill package for [Scry](https://scry.io) — authenticated, metered, read-only SQL over registered public corpora: papers, forums, social archives, prediction markets, mailing lists, and more.

Works with Claude Code, Cursor, Codex, Gemini CLI, and [40+ other agents](https://github.com/vercel-labs/skills).

## Install

```bash
# every skill
npx skills add exopriors/skills

# one skill
npx skills add exopriors/skills --skill scry
```

## Skills

`scry` is the core: authentication, the query door, response fields, discovery, and research conduct. Every other skill is a specialization — one family of sources or one method — installed beside it.

<!-- skills:begin -->
| Skill | Use when |
|-------|----------|
| **scry** | Use Scry's read-only SQL research surface (/v1/scry/schema, /v1/scry/query) for bounded SQL over the public internet, provenance, and vector helpers. Also use when a research ask wants diverse, orthogonal sources, angles, hypotheses, or probe phrasings — includes the enumeration discipline and the /v1/creativity/outsized fan-out. |
<!-- skills:end -->

## Quick Start

Get a Scry API key at [scry.io](https://scry.io/#console), then:

```bash
export SCRY_API_KEY=scry_...

curl -s https://api.scry.io/v1/scry/query \
  -H "Authorization: Bearer $SCRY_API_KEY" \
  -H "Content-Type: text/plain" \
  --data "SELECT hn_id, title, original_author, original_timestamp, uri FROM hackernews.items WHERE title != '' ORDER BY original_timestamp DESC LIMIT 20"
```

Or just ask your agent: *"Search Scry for recent papers on mechanistic interpretability"* — the skill handles the rest.

## What's in the corpus?

The live schema is the coverage authority: `GET /v1/scry/schema` (with your API key) lists every enabled relation with its columns, counts, and freshness, and a relation omitted there is unavailable. Registered families include Hacker News, full-retention Reddit, a multi-community forum corpus (LessWrong, EA Forum, and more), Bluesky, Mastodon, OpenAlex works and authors, full-text academic papers, books, the historical Twitter archive, prediction markets, mailing lists, SEC filings, GitHub, and archived web pages.

## Capabilities

- **SQL queries** via `POST /v1/scry/query` — one bounded statement, `Content-Type: text/plain`
- **Typed discovery** via `POST /v1/scry/search`
- **Semantic search** — mint a named vector with `POST /v1/scry/embed`, then use `@name` inside `scry_vector_topk_distance`
- **Vector algebra** — `scry_debias_vector()` for "X but not Y" queries
- **Query permalinks** — parameterized shares with live controls at `scry.io/scry/share/{slug}`
- **Coverage blocks** on every query response — measured extent, known holes, freshness lag
- **Structured judgements** — persistent, queryable agent observations

## Contributing

This repository is a publish target: the `skills/` tree and the skills table above are projected from ExoPriors' internal canonical repository, and direct edits here are overwritten on the next sync. Found a defect or a stale claim? Open an issue — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
