# Identity Schema Reference

Detailed schema for the identity resolution layer exposed through Scry.

Source of truth: `src/db/schema.sql`

---

## Core Tables (Internal)

These tables live in the `identity` and `public` schemas. Scry users access them through read-only views.

### `actors` (public schema)

One row per platform account. The foundation of all author attribution.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | Referenced by `public_entities.author_actor_id` |
| `user_id` | UUID FK -> users | Non-null when actor is a registered ExoPriors user |
| `source` | external_system | Platform enum (twitter, lesswrong, github_repos, etc.) |
| `external_id` | TEXT NOT NULL | Platform-specific user ID (stable) |
| `handle` | TEXT | Username / screen name (may change) |
| `display_name` | TEXT | Human-readable name |
| `profile_url` | TEXT | Link to profile page |
| `is_community_archiver` | BOOLEAN | True for archival bot accounts |
| `metadata` | JSONB | Platform-specific extras |
| `created_at` | TIMESTAMPTZ | Row creation time |

**Unique constraint:** `(source, external_id)` -- one actor per platform identity.

**Key index:** `(source, handle)` for handle lookups.

Scry view: `scry.actors` exposes all columns except `user_id` and `is_community_archiver`.

### `identity.people`

One row per real-world person. System-owned canonical records.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | The canonical person identifier |
| `display_name` | TEXT NOT NULL | Best known name |
| `canonical_slug` | TEXT UNIQUE | URL-safe identifier (e.g., "eliezer-yudkowsky") |
| `wikidata_qid` | TEXT | Wikidata Q-identifier if known (e.g., "Q5577429") |
| `bio` | TEXT | Brief description |
| `tags` | TEXT[] | Categories: researcher, blogger, engineer, etc. |
| `metadata` | JSONB | Flexible storage |
| `created_at` | TIMESTAMPTZ | |
| `updated_at` | TIMESTAMPTZ | |

Scry view: `scry.people` only shows people that have at least one actor link with probability >= 0.9 (non-rejection).

### `identity.actor_links`

Bayesian-scored edges linking actors to people. The core identity resolution table.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `person_id` | UUID FK -> identity.people | Target person |
| `actor_id` | UUID FK -> actors | Linked actor |
| `log_odds` | FLOAT NOT NULL | Bayesian evidence score (log-odds scale) |
| `probability` | FLOAT GENERATED | `1/(1+exp(-log_odds))`, stored for query convenience |
| `method` | identity.link_method | How the link was established |
| `is_primary` | BOOLEAN | True for the "main" identity on a platform |
| `notes` | TEXT | Free-text annotation |
| `evidence` | JSONB | Array of `{method, log_odds, details}` objects |
| `created_at` | TIMESTAMPTZ | |
| `reviewed_at` | TIMESTAMPTZ | When a human last reviewed |
| `reviewed_by` | UUID FK -> users | Who reviewed |

**Unique constraint:** `(person_id, actor_id)` -- one link per actor-person pair.

**Evidence scale (log-odds):**

| log_odds | probability | Interpretation |
|---|---|---|
| 0.0 | 50% | No evidence either way |
| 2.0 | 88% | Moderate evidence for |
| 3.0 | 95% | Strong evidence for |
| 4.0 | 98% | Very strong evidence for |
| 5.0 | 99.3% | Near certain |
| -4.0 | 2% | Strong evidence against |
| -5.0 | 0.7% | Near certain rejection |

Evidence is additive: `log_odds_total = sum(log_odds_i)`.

**Link methods (`identity.link_method` enum):**

| Method | Typical log_odds | Meaning |
|---|---|---|
| `handle_match` | +3.0 | Identical handles across platforms |
| `display_name_match` | +1.5 to +2.5 | Identical display names (weighted by rarity) |
| `manual` | +5.0 or -5.0 | Human verification |
| `self_declared` | +4.5 | User linked their own accounts |
| `profile_link` | +2.0 | One profile links to another |
| `stylometric` | +0.5 to +2.0 | Writing style analysis |
| `network` | +0.5 to +1.5 | Social graph analysis |
| `wikidata` | +3.5 | Matched via Wikidata sameAs |
| `temporal` | +0.5 to +1.5 | Posting pattern correlation |
| `rejection` | -5.0 | Explicit rejection (these are NOT the same person) |

### `identity.change_log`

Audit trail for identity graph mutations.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `person_id` | UUID | Affected person |
| `actor_id` | UUID | Affected actor |
| `action` | TEXT | `create_person`, `link_actor`, `merge_people`, `split_person`, `reject_link` |
| `old_state` | JSONB | State before change |
| `new_state` | JSONB | State after change |
| `reason` | TEXT | Why the change was made |
| `performed_by` | UUID | User who did it (NULL = automated) |
| `created_at` | TIMESTAMPTZ | |

---

## Scry Views

These are the read-only views available to Scry users. All filter to high-confidence links only.

### `scry.actors`

Direct passthrough of `public.actors`:

| Column | Type |
|---|---|
| `id` | UUID |
| `source` | external_system |
| `external_id` | TEXT |
| `handle` | TEXT |
| `display_name` | TEXT |
| `profile_url` | TEXT |
| `metadata` | JSONB |
| `created_at` | TIMESTAMPTZ |

### `scry.people`

Filtered view of `identity.people` -- only people with at least one non-rejection actor link at probability >= 0.9.

| Column | Type |
|---|---|
| `id` | UUID |
| `display_name` | TEXT |
| `canonical_slug` | TEXT |
| `wikidata_qid` | TEXT |
| `bio` | TEXT |
| `tags` | TEXT[] |
| `metadata` | JSONB |
| `created_at` | TIMESTAMPTZ |
| `updated_at` | TIMESTAMPTZ |

### `scry.person_aliases`

Flattened join of `identity.actor_links` and `actors`. One row per (person, actor, name variant) combination. Only includes links with probability >= 0.9 and method != 'rejection'.

Two rows may exist per actor link: one from `handle`, one from `display_name` (when both are non-null and produce distinct normalized names).

| Column | Type | Notes |
|---|---|---|
| `person_id` | UUID | FK to `scry.people.id` |
| `actor_id` | UUID | FK to `scry.actors.id` |
| `source` | external_system | Platform |
| `author_name` | TEXT | Raw name (handle or display_name) |
| `author_norm` | TEXT | `normalize_author_name(author_name)` |
| `author_key` | TEXT | `source::text || ':' || author_norm` (for joins to `mv_author_profiles`) |
| `handle` | TEXT | Actor's handle |
| `display_name` | TEXT | Actor's display name |
| `profile_url` | TEXT | Actor's profile URL |
| `external_id` | TEXT | Platform-specific ID |
| `link_method` | TEXT | How the link was established (cast from enum) |
| `confidence` | FLOAT | Probability of the link being correct (>= 0.9) |

**Join pattern to mv_author_profiles:** `ON ap.source = pa.source AND ap.author_norm = pa.author_norm`

### `scry.github_people`

Actor-centric summary of GitHub repository ingestion. One row per GitHub actor with aggregated repo/comment counts and star metrics.

| Column | Type | Notes |
|---|---|---|
| `actor_id` | UUID | FK to `scry.actors.id` |
| `github_login` | TEXT | `actors.external_id` for GitHub |
| `handle` | TEXT | |
| `display_name` | TEXT | |
| `profile_url` | TEXT | |
| `repo_document_count` | BIGINT | Non-comment entities from GitHub repos |
| `repo_issue_comment_count` | BIGINT | Issue/PR comments |
| `unique_repo_count` | BIGINT | Distinct repos |
| `sum_distinct_repo_stars` | BIGINT | Sum of stars across distinct repos |
| `max_repo_stars` | BIGINT | Stars on their most popular repo |
| `sum_distinct_repo_watchers` | BIGINT | |
| `max_repo_watchers` | BIGINT | |
| `first_seen_at` | TIMESTAMPTZ | Earliest GitHub activity |
| `last_seen_at` | TIMESTAMPTZ | Latest GitHub activity |
| `latest_repo_activity` | TIMESTAMPTZ | Latest repo-level activity |
| `actor_metadata` | JSONB | Actor metadata blob |
| `actor_created_at` | TIMESTAMPTZ | |

### `scry.github_person_repos`

One row per actor-repo edge. Per-repo breakdown of stars, watchers, language.

| Column | Type | Notes |
|---|---|---|
| `actor_id` | UUID | FK to `scry.actors.id` |
| `github_login` | TEXT | |
| `handle` | TEXT | |
| `display_name` | TEXT | |
| `repo_id` | BIGINT | GitHub repo ID |
| `repo_full_name` | TEXT | e.g., "torvalds/linux" |
| `repo_language` | TEXT | Primary language |
| `repo_stars` | BIGINT | |
| `repo_watchers` | BIGINT | |
| `first_seen_at` | TIMESTAMPTZ | |
| `last_seen_at` | TIMESTAMPTZ | |

**Join to `github_people`:** `ON gp.actor_id = gpr.actor_id`

### `scry.mv_author_profiles`

Materialized view. Per-source author rollups with optional person_id from identity graph.

| Column | Type | Notes |
|---|---|---|
| `source` | external_system | |
| `author_name` | TEXT | `MIN(original_author)` within group |
| `author_norm` | TEXT | `normalize_author_name(author_name)` |
| `author_key` | TEXT | `source::text || ':' || author_norm` (unique index) |
| `person_id` | UUID | From identity graph (NULL if not linked) |
| `author_actor_id` | UUID | `MIN(author_actor_id)` within group |
| `entity_count` | BIGINT | Total entities |
| `post_count` | BIGINT | Entities with kind='post' |
| `comment_count` | BIGINT | Entities with kind='comment' |
| `total_post_score` | BIGINT | Sum of upvotes/baseScore for posts |
| `avg_post_score` | NUMERIC | Average post score |
| `max_score` | INTEGER | Highest single-entity score |
| `first_activity` | TIMESTAMPTZ | |
| `last_activity` | TIMESTAMPTZ | |
| `af_count` | BIGINT | Alignment Forum posts |
| `sample_entity_id` | UUID | One entity ID for quick inspection |

**Threshold:** Only authors with >= 3 entities appear.

**Indexes:** `author_key` (unique), `author_norm`, `source`, `entity_count DESC`, `last_activity DESC`, `person_id`, `author_actor_id`.

### `scry.mv_author_stats`

Simpler materialized view. Cross-source stats by `original_author` string (no source partitioning).

| Column | Type | Notes |
|---|---|---|
| `original_author` | TEXT | Unique index |
| `post_count` | BIGINT | |
| `comment_count` | BIGINT | |
| `total_post_score` | BIGINT | |
| `avg_post_score` | NUMERIC | |
| `max_score` | INTEGER | |
| `first_activity` | TIMESTAMPTZ | |
| `last_activity` | TIMESTAMPTZ | |
| `af_count` | BIGINT | Alignment Forum posts |

**Threshold:** Only authors with >= 3 entities appear.

---

## Helper Functions

### `normalize_author_name(text) -> text`

Lowercases, trims, and collapses internal whitespace. Returns NULL on NULL or empty input.

Usage: stable join key across author name variants. Used internally by `mv_author_profiles` and `scry.person_aliases`.

```sql
SELECT normalize_author_name('  Eliezer  Yudkowsky ');
-- returns: 'eliezer yudkowsky'
```

---

## Entity-Author Relationship

`public_entities.author_actor_id` (UUID, FK -> `actors.id`) is the primary link from content to author. Not all entities have an `author_actor_id` -- some only have `original_author` (a free-text string).

The hierarchy for resolving "who wrote this?":

1. `e.author_actor_id` -> `actors` (structured, linkable to identity graph)
2. `e.original_author` (free text, best-effort)
3. `e.metadata->>'userId'` / `e.metadata->>'username'` (source-specific, used by LW/EA Forum)

For cross-platform resolution, `author_actor_id` is required. Entities without it can only be grouped by `original_author` string matching.

---

## Internal Scry (Per-User People Layer)

Separate from the system identity graph, `internal_scry` provides per-user private people records with RLS isolation. Used by the People Finder UI.

### `internal_scry.people`

Per-user person records (RLS: owner sees only their own).

| Column | Type |
|---|---|
| `id` | UUID PK |
| `owner_user_id` | UUID FK -> users |
| `display_name` | TEXT |
| `canonical_slug` | TEXT |
| `short_label` | TEXT |
| `primary_location` | TEXT |
| `primary_domain` | TEXT |
| `tags` | TEXT[] |
| `metadata` | JSONB |
| `created_at` | TIMESTAMPTZ |
| `updated_at` | TIMESTAMPTZ |

### `internal_scry.person_identities`

Links internal_scry people to actors (RLS-isolated via person ownership).

| Column | Type |
|---|---|
| `id` | UUID PK |
| `person_id` | UUID FK -> internal_scry.people |
| `actor_id` | UUID FK -> actors |
| `is_primary` | BOOLEAN |
| `note` | TEXT |
| `metadata` | JSONB |
| `created_at` | TIMESTAMPTZ |

### `internal_scry.annotations`

Unified notes, entity links, and person relations (RLS-isolated).

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `owner_user_id` | UUID | |
| `annotation_type` | internal_scry_annotation_type | `note`, `entity_link`, or `person_relation` |
| `person_id` | UUID | Source person |
| `target_entity_id` | UUID | For entity_link type |
| `target_person_id` | UUID | For person_relation type |
| `relation_type` | VARCHAR(64) | Required for entity_link and person_relation |
| `title` | TEXT | |
| `body` | TEXT | Required for note type |
| `weight` | REAL | |
| `importance` | INTEGER | |
| `metadata` | JSONB | |
| `created_at` | TIMESTAMPTZ | |
| `updated_at` | TIMESTAMPTZ | |

These tables are NOT directly queryable through Scry SQL. They are accessed through the internal Scry API endpoints.
