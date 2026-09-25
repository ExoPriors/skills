---
name: scry-github
description: >-
  Use when a question is about GitHub repositories and their READMEs, docs or
  source files; a login's public repo portfolio, including repos since deleted
  or renamed; parsed agent SKILL.md files across public repos; software
  packages across npm, PyPI, crates, Go, NuGet, Packagist and other registries;
  Hugging Face models, datasets and spaces with likes, downloads, bytes on the
  hub and daily counter history; or Chrome Web Store extensions by permission,
  developer, install figure or manifest text. Relations: github.*,
  agents.skills, packages.catalog, huggingface.*, extensions.*.
---

# GitHub, packages, and models

The GitHub repository universe and its documents, parsed agent skills, the merged package catalog, Hugging Face hub repositories with content details and daily counters, and the Chrome Web Store catalog with dated snapshots. Rows are observations: the clock is the observation date and most questions dedupe before they count.

## When to use

- Which repos, READMEs, or source files mention a phrase, ranked by stars.
- A login's public repos, including ones since deleted, renamed, or made private.
- Which agent skills exist for a task, and in which repos.
- Which ecosystems hold a package; its latest version, license, or repository.
- Hugging Face models, datasets, spaces: likes, downloads, bytes, config, a counter's trajectory.
- Chrome Web Store extensions by permission, developer, install figure, or manifest text.

The core `scry` skill (auth, the query door, response fields) is assumed loaded.

## Doors

Tier and lag are the `schema?mode=index` line as read 2026-09-25; the served index is the authority. No relation here is reviewed-access.

| relation | what one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `github.repos` | one github.com origin as the archive last visited it | `owner_lc`, `name_lc` | `last_full_visit_at` (archive clock) | `name_lc` exact or 3-gram `LIKE` | primary, frozen, lag 112d. `owner_lc` is the access path; no stars or language |
| `github.documents` | one file of one repo at its newest observation, plus one `<owner>/<repo>:repository` summary row | `external_id` = `<owner>/<repo>:<path>` | `observed_on`; `pushed_at` in `metadata.repo` | `content_text`, `lower(content_text)`, `title` (tokens); 3-gram lane in Traps | depth, frozen, lag 1m. `metadata.repo` holds stars, language, license, topics |
| `agents.skills` | one parsed SKILL.md with git provenance | `source`, `repo`, `path` | `observed_on` (day) | `body`, `name` (tokens); 3-grams on `lower(concat(name, ' ', body))` | primary, frozen, lag 2m. `tier` is the skill tree's top directory; `curation = 'curated'` marks hand-picked sets |
| `packages.catalog` | one merged package across registries | `package_key` = `<ecosystem>/<name>` | `observed_on` (batch date); `latest_release_at` | `name` (tokens); `lower(name)` 3-grams | primary, frozen, lag 9d. One batch fold; `ecosystem` values are the roster |
| `huggingface.repositories` | one observation of a model, dataset, or space | `repo_type`, `repo_id` | `observed_on`; `last_modified_at` (hub clock) | none; `payload` is scanned text | depth, hourly, lag 2m. Several rows per repo; dedupe (Idioms) |
| `huggingface.repo_details` | one repo's content record: bytes on the hub, files, `downloads_all_time`, model config | `repo_type`, `repo_id` | `observed_on` | none | depth, hourly, lag 1m. `http_status = 200` rows carry numbers; filled by priority, so absence here is not absence on the hub |
| `huggingface.snapshots_daily` | one (repo, day) row: downloads, likes, trending_score | `repo_type`, `repo_id`, `day` | `day` | none | depth, daily, lag 11h. `downloads` is the hub's trailing-30-day figure |
| `extensions.chrome_web_store` | one listed item at its newest snapshot, manifest parsed into permission arrays | `id` | `published_at`, `updated_at` (store clocks) | `search_text_lc` (name, descriptions, developer, manifest) | depth, periodic, lag 1d. Other predicates scan; cheap under a LIMIT |
| `extensions.chrome_web_store_snapshots` | one listing on one fetch day; a delisted id keeps its rows | `id`, `observed_on` | `observed_on` | `search_text_lc` | depth, periodic, lag 1d. The wide sibling; read by `id`; census is `count() BY observed_on, item_type` |

## Idioms

- Token first, phrase second: `hasAllTokens(lower(content_text), [...])` on documents, `hasAnyTokens(body, ['Term', 'term'])` on skills, `hasToken(search_text_lc, ...)` on the store; name the rarest token, confirm with `positionCaseInsensitive`. `hasToken` is case-sensitive; `search_text_lc` and `lower(content_text)` are the lowercase lanes.
- Dedupe before counting: `ORDER BY observed_on DESC LIMIT 1 BY <key>` on the hub three, on documents (`external_id`), on skills (`repo, path`; same-day revisions tie, read `blob_sha`); count entities with `uniqExact(<key>)`.
- Keyed reads: `owner_lc = '<login>'`; `startsWith(external_id, '<owner>/<repo>:')`; `repo_type = ... AND repo_id = '<owner/name>'`, and `repo_id LIKE '<owner>/%'` for an owner's hub repos (`owner_handle` scans); `package_key = '<ecosystem>/<name>'`; `id = '<store id>'`.
- Clocks: `github.repos` times are archive visits, so a stale `last_full_visit_at` means unknown, never dead; the forge, hub and store clocks are the Doors time columns. A trajectory is a keyed read on `snapshots_daily` with `day >= today() - 30`; a likes ranking there adds `likes >= <floor>` so the index is read.
- Cheap sibling first: `kind = 'repository'` rows of `github.documents` are one summary row per repo (stars, language, `pushed_at`), so rank repos there before reading files. The store catalog before its snapshots; `huggingface.repositories` before `repo_details` unless bytes or config are the question.
- Source URL from a row: `origin` (repos), `uri` (documents and skills, a blob URL at the observed commit; hub repositories, the hub page), `source_url` (store), `repository_url` and `homepage_url` (packages).
- Ids: `<owner>/<repo>` is the spine shared by `github.repos` (`owner`, `name`), the `external_id` prefix of documents, `agents.skills.repo`, and package `repository_url`. A hub `repo_id` is a hub id, not a GitHub one.
- JSON: `metadata` (documents, hub repositories) reads with `JSONExtractInt(metadata, 'repo', 'stargazers_count')` and kin; hub `tags`, `siblings`, `card_data` are JSON strings; `payload` is rendered text, not JSON.

## Worked queries

**Which READMEs mention "speculative decoding", by stars?**

```sql
SELECT external_id, JSONExtractInt(metadata, 'repo', 'stargazers_count') AS stars, uri
FROM github.documents
WHERE hasAllTokens(lower(content_text), ['speculative', 'decoding'])
  AND positionCaseInsensitive(content_text, 'speculative decoding') > 0
  AND endsWith(external_id, ':README.md')
  AND NOT JSONExtractBool(metadata, 'deleted')
ORDER BY stars DESC
LIMIT 1 BY external_id
LIMIT 10
```

One row per README, most-starred first; `uri` is the blob at the observed commit. (verified 2026-09-25)

**What is one login's public repo portfolio, including what the forge no longer serves?**

```sql
SELECT name, origin, latest_status, n_full_visits, last_full_visit_at
FROM github.repos
WHERE owner_lc = 'karpathy'
ORDER BY last_full_visit_at DESC
LIMIT 20
```

`latest_status = 'not_found'` rows are repos since deleted, renamed, or made private; a renamed repo appears under both paths. (verified 2026-09-25)

**Of extensions published each month of 2025, what share asks for `<all_urls>`?**

```sql
SELECT toStartOfMonth(published_at) AS month, count() AS listed,
       countIf(has(host_permissions, '<all_urls>')) AS all_urls,
       round(all_urls / listed, 3) AS share
FROM extensions.chrome_web_store
WHERE item_type = 'extension'
  AND published_at >= '2025-01-01' AND published_at < '2026-01-01'
GROUP BY month
ORDER BY month
LIMIT 12
```

One row per month with the denominator (`listed`) beside the numerator; the window is the store's publish clock, not the observation date. (verified 2026-09-25)

**Which datasets hold the most bytes on the hub, and how liked are they?**

```sql
SELECT d.repo_id, round(d.used_storage_bytes / 1e12, 2) AS tb, d.file_count, r.likes, r.downloads
FROM (
  SELECT repo_id, used_storage_bytes, file_count FROM huggingface.repo_details
  WHERE repo_type = 'dataset' AND http_status = 200
  ORDER BY observed_on DESC LIMIT 1 BY repo_id
) AS d
INNER JOIN (
  SELECT repo_id, likes, downloads FROM huggingface.repositories
  WHERE repo_type = 'dataset'
  ORDER BY observed_on DESC LIMIT 1 BY repo_id
) AS r USING (repo_id)
ORDER BY d.used_storage_bytes DESC
LIMIT 10
```

Both sides deduped to the newest observation before the join; without the inner `LIMIT 1 BY`, a repo repeats. (verified 2026-09-25)

**Which ecosystems hold packages named with "mcp", and which supply downloads?**

```sql
SELECT ecosystem, count() AS packages, countIf(downloads_total > 0) AS with_downloads, max(downloads_total) AS top_downloads
FROM packages.catalog
WHERE hasToken(name, 'mcp')
GROUP BY ecosystem
ORDER BY packages DESC
LIMIT 10
```

One row per ecosystem; `with_downloads` is the denominator for any downloads ranking, since a zero means no source supplied the field. (verified 2026-09-25)

**Which repos publish the most skills that discuss prompt injection?**

```sql
SELECT repo, uniqExact(path) AS skills
FROM agents.skills
WHERE scry_lex('"prompt injection"')
GROUP BY repo
ORDER BY skills DESC
LIMIT 10
```

`scry_lex` expands the phrase against the relation's own text lanes; `uniqExact(path)` counts skills, not observation rows. (verified 2026-09-25)

## Traps

- `packages.catalog`: `downloads_total = 0`, empty strings and empty arrays mean no source supplied the field; check `countIf(downloads_total > 0)` per ecosystem before ranking by downloads. `first_published_at` is the contract's authored axis, but its floor is per source (libraries_io rows floor at 2015-01, npm- and pypi-native rows reach 2012 and 2006, crates and maven stop at 2020-01): an upper bound on first publish, never a clean axis.
- A substring `LIKE` over `lower(content_text)` is refused; the 3-gram lane is the verbatim `lower(concat(ifNull(title, ''), ' ', content_text)) LIKE '%needle%'`, and a long phrase there reads most of the relation. Anchor on a rare token instead.
- `github.repos`: zero rows is not proof a repo does not exist. `owner = '<Owner>'`, `latest_status`, `last_full_visit_at` and `latest_full_snapshot` equality (mirror detection) each scan on their own. One repo can sit under several origins (`.git` suffix, trailing slash, case).
- `github.documents`: `kind` is `document`, `repository`, or `pdf_markdown`; a README is `endsWith(external_id, ':README.md')`. Tombstones have `JSONExtractBool(metadata, 'deleted')` true and empty text. Capture is budgeted, so absence here is not absence on GitHub.
- Hugging Face: `owner_handle`, tag and description predicates scan; `JSONExtract` on `payload` reads nothing. `snapshots_daily.downloads` overlaps day to day, so differences and sums mean nothing; the total is `repo_details.downloads_all_time`. Model-only `repo_details` columns are empty for datasets.
- Chrome Web Store: `users` is the store's rounded figure; `sum(users) AS users` collides with the column, alias it `installs`; an unparsed manifest leaves the permission arrays empty with `mv = 0`. A delisted id has no catalog row: read the snapshots.
- `agents.skills`: `category`, `version`, `author`, `license` and `tags` are mostly empty; filter on `repo`, `tier`, `curation`. `hasToken(body, 'playwright')` misses `Playwright`: use `hasAnyTokens` over both spellings or the 3-gram lane.

## Cross-family joins

- `judgements.scores_current.entity_id = concat('agent_skills:', repo, ':', path)` scores a skill row.
- `agents.skills.repo`, or `concat(owner, '/', name)` from `github.repos`, prefixes `github.documents.external_id` as `concat(repo, ':')`: the repo's files and its `:repository` row.
- Hub `tags` carries `arxiv:<id>` and `base_model:<repo_id>` entries: `extractAll(tags, 'arxiv:([0-9.]+)')` joins `academic.catalog.arxiv_id`; `base_model:` links models to their parents.
- Package `repository_url` names the GitHub repo: take owner and name from it, lowercase, and look up `github.repos` by `owner_lc`, `name_lc` in a second statement.
