---
name: scry-datalog
description: >-
  Use when a question is a walk over a graph Scry holds rather than a scan
  of one table: who cites a paper and who cites those citers, whom two
  accounts both follow in the historical Twitter archive, which hosts link
  to a site and link back, the reply tree under a Hacker News story,
  PageRank over a walked citation subgraph. Uses the datalog MCP tool (a
  JSON program or Datalog rules) over the edge catalog: OpenAlex references
  and cited_by, twitter.following and followers, hackernews.children, crawl
  host links.
---

# Datalog and fixpoint programs

A program names relations (typed id sets) built from seeds, catalog edges, filters, intersection and negation, evaluated to a fixpoint or a depth cap; each hop is one metered Scry SQL statement, or a step of the resident citation graph. Rows carry `parent` and `depth`: a walked answer is its own provenance chain.

## When to use

- Citation closures: who cites a work and who cites those citers, references two literatures share.
- Follow graphs in the historical Twitter archive: whom an account follows, who follows it, what two accounts share.
- Link graphs of the captured web: which hosts a site links to, which link back.
- Reply trees: the items under a Hacker News story, and who wrote them.
- Set algebra over walks: `in`, `not`, anti-joins on tuples, PageRank or components over a walked pair relation.

The core `scry` skill (auth, the query door, response fields) is assumed loaded. Plain SQL is better when one keyed statement answers: a single hop, one work's citers from `openalex.cited_by`, one Reddit thread by `link_id`.

## Surfaces

| Surface | What it does | Required arguments or columns | What comes back | Cost or limit the contract states |
|---|---|---|---|---|
| `datalog` tool (`POST https://api.scry.io/mcp`) | named relations of typed ids, one statement per hop | `program`: `{relations, out, depth?, resident?, analyze?}` or a rules string; `max_seconds` (default 300, max 1800), `budget_nanodollars`, `max_chars` | `outcome`, `relations` rows `{id, kind, parent, depth, attrs?}`, `counts`, `meter.per_statement`, `truncations[]`, `coverage` | 16 relations, 50000 rows each, LIMIT <= 50000 per sql atom, 4 edges per bound body, 2 MB body |
| edges `references`, `cited_by` | works a work cites / works citing it | OpenAlex work ids (bare `W…` accepted) | works, kind `openalex.work` | `cited_by` keeps the newest 50 citers per work (`edge_window`) and filters on `publication_year` alone; unfiltered hops stay resident |
| `openalex.cited_by` | one work's citers, newest first | `cited_work_id = 'https://openalex.org/W…'` | `citing_work_id`, `publication_date` | keyed on `cited_work_id` only; count with `uniqExact(citing_work_id)`; a missing date reads 1900-01-01 |
| edges and relations `twitter.following`, `twitter.followers` | who an account follows / who follows it (historical Twitter archive) | account ids (`twitter.users WHERE handle = '<h>' LIMIT 1`); SQL keyed on `follower_id` / `followee_id` | account ids; rows `follower_id, followee_id, first/last_observed_on` | ~200 ms per step; large accounts cut at 50000, lowest ids kept; one edge is several observation rows |
| edges `hackernews.children`, `parent`, `story_items`, `by`, `items_of` over `hackernews.items` | reply trees and authorship | `hn_id` seeds; hydrate `WHERE hn_id IN {rel}` | items, kind `hackernews.item`; handles from `by` | ~20 ms per 150 keys; `story_hn_id` is a declared hole, walk `children` instead |
| edges `crawl.host_outlinks`, `crawl.host_backlinks`; relation `crawl.host_links` | host -> host over the captured web | host names verbatim (`www` kept); SQL keyed on `source_host` | hosts; rows `source_host, target_host, pages` | ~0.3-0.5 s per step; hubs cut at 50000; an unkeyed read is killed on memory |
| `reddit.comments` | no edge: a thread is one keyed statement | `link_id = 't3_<post>'` and a closed `created_utc` window; `parent_id = 't1_<c>'` for one comment's replies | `id`, `parent_id` (`t1_` reply, `t3_` top level), `author`, `body`, `score` | `parent_id` alone has no index; ids recur, count with `uniqExact(id)` |

The follow edges answer only inside the X gate; access is reviewed and requested by writing to hi@scry.io.

## Idioms

- Shape: a body is one source (`ids`, `sql`, `ann`, `rel`), edges in walking order, then `filter` / `in` / `not`; a `rel` naming its own relation recurses; `depth` caps hops, else `max_seconds`, budget and the row cap bound the walk; `"analyze": true` sizes it unmetered, then `out: []` for counts, then a narrow `out`.
- Seed keyed: an account by `twitter.users WHERE handle = … LIMIT 1`; a work by id or `doi_norm`; a story by `hn_id`; a host as a literal `ids` atom.
- Prune inside the walk: `filter` on a destination column changes what is expanded and billed; `in` bounds a recursion; `not` subtracts a finished set and keeps excluded nodes from being expanded.
- Hydrate last, keyed, small: after a `rel`, a `sql` atom reads `WHERE <key> IN {rel}` and returns its columns under `attrs`, `parent` and `depth` intact, rows by depth then id (ORDER BY only picks the LIMIT window); versioned tables hydrate through `GROUP BY id` with aliases that are no column name.
- Splice: `{name}` inside a sql atom is a query-scoped table (ids with `_depth`, `_parent`; a pair relation's columns), so a per-root aggregate is `SELECT S AS id, uniqExact(H) AS n FROM {pairs} GROUP BY id`; a sql atom after its own `rel` returning `src` beside `id` is a sql edge over a table the catalog lacks.
- Tuples: `"vars": ["S", "W"]` makes a pair relation; a bound body is a driving `{"rel": {"name", "vars"}}` plus up to four `{"edge": {"name", "vars"}}` joins, `not` anti-joins and `filter` on a var; `cited_by` goes last.
- Rules form: `program` may be a Datalog rules string over predicates such as `openalex.cites`, `hackernews.reply`, `hackernews.authored`, `twitter.follows`, a `?-` query and `.depth N`, `.out A, B`, `.analyze`; the query's rows return as relation `answer`.
- Rank the walked set, never intersect it with a global ANN top-k: `rank {handle, k}` orders a finished relation by exact distance, `beam {handle, k}` steers a recursion, `rerank {query, column, top}` scores hydrated text; `pagerank`, `components`, `scc` run in process over a finished pair relation.
- Cite from the envelope: `parent` and `depth` are the witness chain (`emit: "paths"` adds the full path); cite a row by its key with `truncations` and `coverage` beside it.

## Worked calls

```bash
H=(-H "Authorization: Bearer $SCRY_API_KEY" -H "content-type: application/json" -H "accept: application/json" -H "mcp-protocol-version: 2025-06-18" -H "mcp-method: tools/call" -H "mcp-name: datalog")
```

**Who cites ResNet, and who cites those citers, inside its own era, top by citations**

```bash
curl -s https://api.scry.io/mcp "${H[@]}" --data @- <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"datalog","arguments":{"max_seconds":120,"program":{"relations":{
"seed":{"bodies":[[{"ids":["W2194775991"]}]]},
"citers":{"bodies":[[{"rel":"seed"}],[{"rel":"citers"},{"edge":"cited_by"},{"filter":{"col":"publication_year","op":"<=","val":2017}}]]},
"best":{"bodies":[[{"rel":"citers"},{"not":"seed"},{"sql":"SELECT id, left(title, 60) AS title, publication_year AS year, cited_by_count AS cited FROM openalex.works WHERE id IN {citers} ORDER BY cited_by_count DESC LIMIT 5"}]]}},
"out":["best"],"depth":2}}}}
EOF
```

`counts.citers.by_depth` reads 50 at depth 1 (the `edge_window` cut) and their citers at depth 2; `best` rows carry `parent` and `attrs.title/year/cited`; the seed took one LIMIT slot before `not` dropped it, so four rows return. (verified 2026-09-25)

**Whom two accounts both follow, hydrated from twitter.users**

```bash
curl -s https://api.scry.io/mcp "${H[@]}" --data @- <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"datalog","arguments":{"program":{"relations":{
"a":{"bodies":[[{"sql":"SELECT author_id AS id FROM twitter.users WHERE handle = 'karpathy' LIMIT 1"}]]},
"b":{"bodies":[[{"sql":"SELECT author_id AS id FROM twitter.users WHERE handle = 'ylecun' LIMIT 1"}]]},
"fa":{"bodies":[[{"rel":"a"},{"edge":"twitter.following"}]]},
"fb":{"bodies":[[{"rel":"b"},{"edge":"twitter.following"}]]},
"both":{"bodies":[[{"rel":"fa"},{"in":"fb"}]]},
"who":{"bodies":[[{"rel":"both"},{"sql":"SELECT author_id AS id, any(handle) AS handle, max(followers) AS seen FROM twitter.users WHERE author_id IN {both} GROUP BY id ORDER BY seen DESC LIMIT 10"}]]}},
"out":["who"]}}}}
EOF
```

`who` rows are account ids with `attrs.handle` and `attrs.seen`; `counts.fa`, `counts.fb` are the observed following lists, `counts.both` their intersection. (verified 2026-09-25)

**Which hosts gwern.net links to that link back, with linking-page counts**

```bash
curl -s https://api.scry.io/mcp "${H[@]}" --data @- <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"datalog","arguments":{"program":{"relations":{
"seed":{"bodies":[[{"ids":["gwern.net"]}]]},
"out":{"bodies":[[{"rel":"seed"},{"edge":"crawl.host_outlinks"}]]},
"mutual":{"bodies":[[{"rel":"seed"},{"edge":"crawl.host_backlinks"},{"in":"out"}]]},
"pages":{"bodies":[[{"rel":"mutual"},{"sql":"SELECT source_host AS id, sum(pages) AS pages_to_seed FROM crawl.host_links WHERE source_host IN {mutual} AND target_host = 'gwern.net' GROUP BY id ORDER BY pages_to_seed DESC LIMIT 10"}]]}},
"out":["pages"]}}}}
EOF
```

`pages` rows are hosts in id order with `attrs.pages_to_seed` (sort on the client); `counts.out` is the outlink set, `counts.mutual` its intersection with the backlinks. (verified 2026-09-25)

**Who commented under a Hacker News story, as Datalog rules**

```bash
curl -s https://api.scry.io/mcp "${H[@]}" --data @- <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"datalog","arguments":{"program":"Below(root, item) :- hackernews.reply(root, item).\nBelow(root, item) :- Below(root, parent), hackernews.reply(parent, item).\nVoice(root, user) :- Below(root, item), hackernews.authored(user, item).\n?- Voice(44281727, user)."}}}
EOF
```

`relations.answer` holds one tuple `{user}` per distinct commenter, `parent {id: "44281727"}`; `counts.Below.by_depth` is the tree's generations. (verified 2026-09-25)

## Traps

- `max_seconds`, `budget_nanodollars` and `max_chars` sit beside `program`, never inside it; a relation's value is an object with `bodies`, never a SQL string; an undeclared key or atom is refused by name before anything runs.
- `not_in` is the older spelling of `not`; `references` and `cited_by` are unprefixed, other edges name their corpus; Reddit has no edge; an unknown edge name returns the catalog, unmetered.
- Read `outcome` and `truncations[]` before an absence claim: `edge_window` makes a `cited_by` count a lower bound; `rows` at the cap makes downstream aggregates floors and a `not` leaky; a halt names the relations left unevaluated and `retry_after_seconds`.
- Looks like absence: `counts.<seed>.rows = 0` leaves the hops silent; a foreign id seeded into an edge (a Hacker News handle is not a GitHub login) is an empty hop, not a refusal; a hydrate's LIMIT counts rows a later `not` removes; a follow edge is several observation rows (`count()` overcounts, `uniqExact` counts); a `following` list is sparse for large accounts, so census it in SQL first; an unkeyed read of `crawl.host_links` is killed on memory, so key `source_host`.
- Cost: an unkeyed sql seed over `twitter.tweets`, `hackernews.items` or `openalex.works` reads the table; `twitter.by` reads granules per id, so feed it hundreds of ids, never a 40k relation; a filter, a `vars` body or `resident: off` moves a citation hop onto a paid statement.

## Composes with

- `scry` (core) supplies auth, the query door, `coverage`, and `schema` (`relation=<name>`) for a hydrate's columns.
- `scry-academic`, `scry-twitter-archive`, `scry-hackernews`, `scry-reddit` and `scry-web-crawl` supply the seeds (work ids, account ids, `hn_id`, hosts) and take the walked ids back.
- `embed` mints the handles `ann`, `rank` and `beam` consume; `semantic_join` is the tabular counterpart when the join key is meaning rather than an edge.
