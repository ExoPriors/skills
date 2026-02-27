# Scry Schema Guide

Authoritative reference for the `scry.*` schema. Always call `GET /v1/scry/schema`
for live column metadata -- this document provides context and guidance that the
schema endpoint alone cannot convey.

## Core Views

### scry.entities

The main content view. 229M+ rows. Filter aggressively.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| kind | entity_kind | `post`, `comment`, `paper`, `tweet`, `twitter_thread`, `text`, `webpage`, `document`, `grant`, `prediction_market`, `book`, `podcast_episode`. Cast with `kind::text` in GROUP BY. |
| uri | TEXT | Canonical URL |
| payload | TEXT | Full text content, truncated to 50K chars |
| title | TEXT | Title when available. NULL for many comments, tweets, some sources. |
| upvotes | INT | Raw upvote/score value from source (sparse) |
| score | INT | COALESCE of upvotes/baseScore/score/likes. Still sparse for sources without votes. For fast sorting prefer `upvotes` directly. |
| comment_count | INT | Coalesced comment count (when available) |
| vote_count | INT | LW/EA voteCount |
| word_count | INT | LW/EA wordCount |
| is_af | BOOL | Alignment Forum flag (LW/EA) |
| original_author | TEXT | Author name or handle. May be NULL for tweets, deleted accounts. |
| original_timestamp | TIMESTAMPTZ | Publication time |
| source | external_system | Origin platform. Cast with `source::text`. |
| content_risk | TEXT | `'dangerous'` for adversarial content (Moltbook, etc.). NULL is safe. |
| metadata | JSONB | Source-specific fields (see Metadata section below) |
| created_at | TIMESTAMPTZ | When ingested into ExoPriors |
| author_actor_id | UUID | FK to scry.actors for structured author lookups |
| parent_entity_id | UUID | Direct parent (for replies/comments) |
| anchor_entity_id | UUID | Root entity in a thread |

**Common source values**: `hackernews`, `lesswrong`, `eaforum`, `arxiv`, `pubmed`,
`twitter`, `bluesky`, `reddit`, `substack`, `manifold`, `metaculus`, `wikipedia`,
`github_skills`, `astralcodexten`, `offshoreleaks`, `biorxiv`, `sec_edgar`,
`nih_reporter`, `federal_register`, `openalex`, `europepmc`, `inspire_hep`,
`congress`, `nsf_awards`, `nvd`, `ecfr`, `crs`, `nasa_ntrs`, `hal`, `osti`,
`zenodo`, `datacite`, `npm`, `polymarket`, `kalshi`, `mailing_list`.

### scry.embeddings

Chunked semantic vectors for entities.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| entity_id | UUID | FK to scry.entities.id |
| chunk_index | INT | 0 = document-level summary chunk |
| chunk_start | INT | Byte offset (UTF-8) |
| chunk_end | INT | Byte offset (UTF-8) |
| token_count | INT | Tokens in this chunk |
| embedding_voyage4 | halfvec(2048) | Voyage 4 family vector. Coverage still ramping. |
| embedding_fnv384 | halfvec(384) | Local FNV-1a hash embedding (experimental) |
| chunking_strategy | chunking_strategy | e.g., `semantic_v2_164_20p` |
| model_name | TEXT | Legacy model label |
| created_at | TIMESTAMPTZ | When written |

**Key patterns:**
- Doc-level search: `WHERE chunk_index = 0`
- Not all entities have embeddings. Filter `embedding_voyage4 IS NOT NULL`.
- For full-document FNV search, aggregate across chunks:
  `SELECT entity_id, MIN(embedding_fnv384 <=> @handle) AS dist ... GROUP BY entity_id`

### scry.actors

Author/account records across all sources.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| source | external_system | Platform |
| external_id | TEXT | Platform-specific ID |
| handle | TEXT | Username/handle |
| display_name | TEXT | Display name |
| profile_url | TEXT | Profile link |
| metadata | JSONB | Source-specific fields |
| created_at | TIMESTAMPTZ | When ingested |

### scry.reddit

Reddit-specific view with native Reddit fields.

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT | Reddit full ID (`t1_` or `t3_`) |
| reddit_id | TEXT | Base36 ID without prefix |
| kind | entity_kind | `post` or `comment` |
| subreddit | TEXT | Subreddit name |
| uri | TEXT | Permalink |
| payload | TEXT | Body/selftext (50K truncated) |
| title | TEXT | Post title (NULL for comments) |
| upvotes | INT | Score (can be negative) |
| score | INT | Coalesced |
| comment_count | INT | Post comment count |
| original_author | TEXT | Handle (NULL if deleted) |
| original_timestamp | TIMESTAMPTZ | Creation time |
| link_full_id | TEXT | Parent post for comments |
| parent_full_id | TEXT | Parent comment or post |
| over_18 | BOOL | NSFW flag |
| is_self | BOOL | Self post flag |
| domain | TEXT | Link domain |
| source_set | TEXT | `full` or `subreddits24` |
| source_file | TEXT | Source filename |
| metadata | JSONB | Moderation flags, flair, etc. |
| created_at | TIMESTAMPTZ | Ingest time |

### scry.entity_edges

Relationship edges between entities (currently OffshoreLeaks).

| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| edge_kind | entity_edge_kind | Only `relation` exposed |
| from_entity_id | UUID | Source node |
| to_entity_id | UUID | Target node |
| edge_type | TEXT | Relationship type |
| ingest_source | TEXT | Origin (`offshoreleaks`) |
| observed_at | TIMESTAMPTZ | Optional observation time |
| metadata | JSONB | Source-specific edge data |
| created_at | TIMESTAMPTZ | Creation time |

---

## People / Identity Views

| View | Description |
|------|-------------|
| `scry.actors` | Per-source account records |
| `scry.people` | Cross-platform merged identities (high confidence) |
| `scry.person_aliases` | Links people to source-specific author keys |
| `scry.mv_author_profiles` | Author stats aggregated per source |
| `scry.mv_author_stats` | Author post counts and score aggregates |
| `scry.github_people` | GitHub-specific maintainer aggregates |
| `scry.github_person_repos` | GitHub person-to-repo mapping |

---

## Agent Views

| View | Description |
|------|-------------|
| `scry.agent_judgements` | Structured agent observations (queryable) |
| `scry.agent_emitters` | Registered agent emitter identities |
| `scry.keepalive_funding_status` | Funding status observations |

---

## Materialized Views (Pre-filtered Subsets)

These are the primary performance tool. Use them instead of scanning `scry.entities`.

### Forum / Blog Posts

| View | Description | Has embedding_voyage4? |
|------|-------------|----------------------|
| `scry.mv_lesswrong_posts` | LessWrong posts with scores, AF flag | Yes |
| `scry.mv_eaforum_posts` | EA Forum posts with scores | Yes |
| `scry.mv_unjournal_posts` | Unjournal evaluations | Yes |
| `scry.mv_hackernews_posts` | HN posts with scores | Yes |
| `scry.mv_substack_posts` | Substack articles | Yes |
| `scry.mv_blogosphere_posts` | Independent blogs (astralcodexten, etc.) | Yes |
| `scry.mv_forum_posts` | Multi-forum aggregate (LW, EA, DSL, MR) | Yes |
| `scry.mv_datasecretslox_posts` | Data Secrets Lox posts | Yes |
| `scry.mv_marginalrevolution_posts` | Marginal Revolution posts | Yes |
| `scry.mv_ethereum_posts` | Ethereum ecosystem posts | Yes |

### Cross-Source Aggregates

| View | Description | Has embedding_voyage4? |
|------|-------------|----------------------|
| `scry.mv_posts` | All post-kind entities across sources | Yes |
| `scry.mv_high_score_posts` | Posts with score >= threshold | Yes |
| `scry.mv_papers` | Papers from arxiv, pubmed, biorxiv, openalex, etc. | Yes |
| `scry.mv_af_posts` | Alignment Forum posts only | Yes |

### Comments

| View | Description | Has embedding_voyage4? |
|------|-------------|----------------------|
| `scry.mv_lesswrong_comments` | LW comments | Yes |
| `scry.mv_eaforum_comments` | EA Forum comments | Yes |
| `scry.mv_high_karma_comments` | High-karma comments across forums | Yes |
| `scry.mv_substack_comments` | Substack comments | Yes |

### Social Media

| View | Description | Has embedding_voyage4? |
|------|-------------|----------------------|
| `scry.mv_twitter_threads` | Twitter threads | Yes |
| `scry.mv_bluesky_posts` | Bluesky posts | No (ramping) |

### Academic Papers

| View | Description | Has embedding_voyage4? |
|------|-------------|----------------------|
| `scry.mv_arxiv_papers` | arXiv preprints | Yes |
| `scry.mv_pubmed_papers` | PubMed articles | Partial |
| `scry.mv_biorxiv_papers` | bioRxiv/medRxiv preprints | Partial |
| `scry.mv_openalex_papers` | OpenAlex works | Partial |
| `scry.mv_philpapers` | PhilPapers entries | Partial |

### Reference / Government / Markets

| View | Description |
|------|-------------|
| `scry.mv_wikipedia_articles` | Wikipedia articles |
| `scry.mv_prediction_markets` | Manifold, Metaculus, Polymarket, Kalshi |
| `scry.mv_manifold_markets` | Manifold markets specifically |
| `scry.mv_metaculus_questions` | Metaculus questions |
| `scry.mv_github_documents` | GitHub-sourced documents |
| `scry.mv_mailing_list_messages` | Mailing list messages |

### Embedding-Specific Views

| View | Description |
|------|-------------|
| `scry.mv_posts_doc_embeddings` | Post entity_ids with doc-level embeddings |
| `scry.mv_substantive_doc_embeddings` | Higher-quality doc embeddings (filtered) |
| `scry.mv_twitter_doc_embeddings` | Twitter thread doc embeddings |

### Reddit Windowed Views

Reddit is sharded by time period for performance:

| View | Period |
|------|--------|
| `scry.mv_reddit_posts_recent` | Recent |
| `scry.mv_reddit_posts_2022_2023` | 2022-2023 |
| `scry.mv_reddit_posts_2020_2021` | 2020-2021 |
| `scry.mv_reddit_posts_2018_2019` | 2018-2019 |
| `scry.mv_reddit_posts_2014_2017` | 2014-2017 |
| `scry.mv_reddit_posts_2010_2013` | 2010-2013 |
| `scry.mv_reddit_posts_2005_2009` | 2005-2009 |

Comment equivalents follow the same naming: `scry.mv_reddit_comments_*`.

### Substack Auxiliary

| View | Description |
|------|-------------|
| `scry.mv_substack_publications` | Publication-level metadata |

### OpenAlex Views

| View | Description |
|------|-------------|
| `scry.openalex_works` | OpenAlex work records |
| `scry.openalex_authors` | OpenAlex author records |
| `scry.openalex_institutions` | Institutions |
| `scry.openalex_concepts` | Concepts/topics |
| `scry.openalex_work_authorships` | Work-to-author links |
| `scry.openalex_work_institutions` | Work-to-institution links |
| `scry.openalex_work_references` | Citation references |
| `scry.openalex_work_concepts` | Work-to-concept links |

### Patent Views

| View | Description |
|------|-------------|
| `scry.patent_families` | Patent family records |
| `scry.patent_publications` | Individual patent publications |
| `scry.patent_embeddings` | Patent embedding vectors |
| `scry.patent_family_citations` | Patent citation relationships |

### Specialty Views

| View | Description |
|------|-------------|
| `scry.books` | Book entities |
| `scry.github_repo_audit` | GitHub repository audit data |
| `scry.npm_package_audit` | npm package audit data |
| `scry.offshoreleaks_nodes` | OffshoreLeaks nodes (flattened) |
| `scry.offshoreleaks_edges` | OffshoreLeaks edges (flattened) |
| `scry.sporc_episodes` | Podcast episodes |
| `scry.sporc_turns` | Podcast transcript turns |
| `scry.entities_private` | Private entities (authenticated only) |
| `scry.embeddings_private` | Private embeddings (authenticated only) |
| `scry.entities_all` | Union of public + private (authenticated only) |

---

## Metadata Fields by Source

Metadata is JSONB. Access with `metadata->>'field_name'`.

**LessWrong / EA Forum**: `baseScore`, `voteCount`, `wordCount`, `af`,
`postExternalId`, `parentCommentExternalId`

**HackerNews**: `hnId`, `hnType`, `score`, `descendants`, `parentId`,
`parentCommentId`

**Reddit**: `permalink`, `outbound_url`, `distinguished`, `edited`,
`is_submitter`, `stickied`, `subreddit_type`, `link_flair_text`, `upvote_ratio`

**arXiv**: `primary_category`, `categories`, `authors`

**Twitter**: `username`, `displayName`, `replyToUsername`

**Manifold**: `contractId`, `contractSlug`, `contractQuestion`, `commentId`,
`commentType`, `betAmount`, `betOutcome`, `likes`

**OffshoreLeaks**: `node_type`, `node_id`, `sourceID`, `countries`,
`country_codes`, `jurisdiction`, `status`

---

## Column Reliability Notes

- **LW/EA posts**: `score` reliable, `title` usually populated.
- **LW/EA comments**: `title` often NULL, `score` from baseScore.
- **HN posts/comments**: `score` from metadata, `title` may be NULL on comments.
- **Twitter**: `score`/`upvotes` often NULL. `title` frequently NULL (use `payload`).
  `original_author` may be NULL; prefer `metadata->>'username'`.
- **arXiv**: `title` often in metadata. `score` is always NULL.
- **Bluesky**: embeddings still ramping. No score field.
- **Reddit**: `upvotes` can be negative. Use windowed views for performance.

---

## Lexical Search Functions

| Function | Description | Max limit |
|----------|-------------|-----------|
| `scry.search(query, kinds, limit_n)` | BM25 lexical search with result details | 100 |
| `scry.search_ids(query, mode, kinds, limit_n)` | IDs-only lexical search (cheaper) | 2000 |
| `scry.search_reddit_posts(query, subreddits, limit_n, window_key)` | Reddit post search | 50 per window |
| `scry.search_reddit_comments(query, subreddits, limit_n, window_key)` | Reddit comment search | 50 per window |
| `scry.search_exhaustive(query, kinds, limit_n, offset_n)` | Higher-cap paginated search | 500 |
| `scry.hybrid_search(query, query_vector, kinds, limit_n)` | Lexical + semantic rerank | 100 |
| `scry.author_topics(author_pattern, topics)` | Per-author topic hit counts | -- |

### OpenAlex Helper Functions

| Function | Description |
|----------|-------------|
| `scry.openalex_find_authors(query, limit)` | Fuzzy author search |
| `scry.openalex_find_works(query, min_year, limit)` | Work title/DOI search |
| `scry.openalex_find_works_fast(query, min_year, limit)` | Metadata-only work search |
| `scry.openalex_author_profile(author_id)` | Single author profile |
| `scry.openalex_institution_authors(inst_id, min_year, limit)` | Authors at institution |
| `scry.openalex_concept_authors(concept_id, min_year, limit)` | Authors by concept |
| `scry.openalex_author_coauthors(author_id, min_year, limit)` | Coauthor network |
| `scry.openalex_author_citation_neighbors(author_id, min_year, limit)` | Citation neighbors |

### Vector Algebra Functions

| Function | Description |
|----------|-------------|
| `debias_vector(axis, topic)` | Remove axis projection from topic ("X but not Y") |
| `debias_removed_fraction(axis, topic)` | Quick check if debias would be a no-op |
| `debias_diagnostics(axis, topic)` | Norm/cosine/projection sanity checks |
| `contrast_axis(@pos, @neg)` | Build axis from two opposing embeddings |
| `contrast_axis_balanced(@pos, @neg)` | Balanced contrast axis |
| `unit_vector(vec)` | Normalize vector to unit length |
