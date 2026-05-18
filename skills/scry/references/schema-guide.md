# Scry Schema Guide

Reference guide for the documented `scry.*` surface. Treat
`GET /v1/scry/schema` on the target instance as the only source of truth for
live view/function availability and live column metadata. This guide provides
context and query patterns that the schema endpoint alone cannot convey, but it
may mention repo-defined surfaces that are not yet deployed on every public
instance. When you need repo-side conformance proof instead of usage guidance,
run `cd src/api && SCRY_API_KEY=... cargo run --features cli --bin scry-contract-audit -- --output json`;
it checks that `/v1/scry/context` and `/v1/scry/schema` expose the same
`truth_manifest` as the versioned content manifest and fails on non-pass drift
by default.

## Core Views

### scry.entities

The main public content view. Filter aggressively.
Use `GET /v1/stats` or `GET /v1/scry/context` for live corpus totals.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| kind | entity_kind | `post`, `comment`, `paper`, `tweet`, `twitter_thread`, `text`, `webpage`, `document`, `grant`, `prediction_market`, `book`, `podcast_episode`. Cast with `kind::text` in GROUP BY. |
| uri | TEXT | Canonical URL |
| content_text | TEXT | Canonical human-readable content, truncated to 50K chars |
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
| scraped_at | TEXT | Ingest-side scrape timestamp when present |
| extraction_method | TEXT | Extraction or conversion program identifier when recorded |
| extraction_version | TEXT | Extractor/converter version when recorded |
| processor | TEXT | Entity-level processor / transform program id |

**Common source values**: `hackernews`, `lesswrong`, `eaforum`, `arxiv`, `pubmed`,
`twitter`, `bluesky`, `reddit`, `substack`, `manifold`, `metaculus`, `wikipedia`,
`github_skills`, `astralcodexten`, `offshoreleaks`, `biorxiv`, `sec_edgar`,
`nih_reporter`, `federal_register`, `openalex`, `europepmc`, `inspire_hep`,
`congress`, `nsf`, `nvd`, `ecfr`, `crs`, `nasa_ntrs`, `hal`, `osti`,
`zenodo`, `datacite`, `npm`, `polymarket`, `kalshi`, `mailing_list`,
`musingsandroughdrafts`, `stackexchange`, `wikidata`, `gutenberg`, `kl3m`,
`courtlistener`, `cap`, `sporc`.

### scry.chunk_embeddings

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
| chunking_strategy | chunking_strategy | e.g., `semantic_v2_164_20p` |
| model_name | TEXT | Legacy model label |
| created_at | TIMESTAMPTZ | When written |

**Key patterns:**
- Doc-level search: `WHERE chunk_index = 0`
- Not all entities have embeddings. Filter `embedding_voyage4 IS NOT NULL`.

**Derived helpers:**
- `scry.entity_embeddings` gives you exactly the `chunk_index = 0` rows.
- `scry.entities_with_embeddings` is `scry.entities` pre-joined to `scry.entity_embeddings`.
- `scry.embedding_coverage` is a reporting surface for source/kind public vs staged vs ready coverage and freshness.

### Source-native corpus views

Not all large corpora live canonically in `scry.entities`. Source-native tables
are first-class query surfaces, and `scry.source_records` is the cross-source
union view over those records.

| View | Notes |
|------|-------|
| `scry.source_records` | Cross-source union of source-native records. Includes `source`, `external_id`, `entity_id`, `kind`, `uri`, `title`, `content_text`, `metadata`, `created_at`, `updated_at`. Some families use prefixed `external_id` values such as `edition:...`, `repository:...`, or `paper_artifact:...`; when a canonical table stores a generic `document` kind, `metadata.logical_kind` carries the typed-search logical kind. |
| `scry.bluesky` / `hackernews` / `wikipedia` / `pubmed` / `repec` / `kalshi` / `nih_reporter` / `govinfo_crec` / `offshoreleaks` / `openalex` | Clean primary aliases for the major source-native corpora. Prefer these names in new agent/user queries. |
| `scry.hackernews_items` | Canonical HN substrate keyed by `hn_id`. Contains posts and comments, thread ancestry (`parent_hn_id`, `story_hn_id`), outbound URL, score, full text, and `anchor_entity_id` for joins to crawled webpage entities. |
| `scry.wikipedia_articles` | Canonical Wikipedia substrate keyed by `page_id`. Contains revisions, categories, article text, and quality metadata. |
| `scry.pubmed_papers` | Canonical PubMed substrate keyed by `pmid`. Contains paper text, DOI/PMC identifiers, journal metadata, and MeSH/keyword metadata. |
| `scry.repec_records` | Canonical RePEc substrate keyed by `handle`. Contains source-specific bibliographic fields, file links, full-text fetch status, and economics metadata. |
| `scry.kalshi_markets` | Canonical Kalshi substrate keyed by `ticker`. Contains event/series tickers, market status/result, pricing snapshots, and market timing fields. |
| `scry.nih_reporter_projects` | Canonical NIH RePORTER substrate keyed by `appl_id`. Contains fiscal year, award amount, project identifiers, PI lists, and organization metadata. |
| `scry.govinfo_crec_granules` | Canonical GovInfo Congressional Record substrate keyed by `granule_id`. Contains package/chamber/class metadata and issue/publication dates. |
| `scry.arxiv` / `scry.arxiv_papers` | Canonical arXiv substrate keyed by `arxiv_id`. Includes payload, DOI, categories, authors, publication metadata, and the source-native arXiv alias. |
| `scry.openalex_works` | Canonical OpenAlex work surface keyed by `work_id`. Joins graph metadata with dedicated abstract payload rows and optional `entity_id` bridge links. |
| `scry.openalex_work_external_ids` | Source-local OpenAlex alias registry keyed by `work_id`. Use it for carried external identifiers such as PubMed PMIDs that belong to the OpenAlex work rather than the shared ext-id bridge. |
| `scry.bluesky_posts` | Canonical Bluesky substrate keyed by AT URI. |
| `scry.twitter_posts` | Canonical Twitter/X substrate keyed by canonical tweet URI. Exposes public provenance tags plus aggregated observation-source tags such as `observation_sources`, `capture_channels`, and `has_extension_observation`. |
| `scry.twitter_threads` | Canonical Twitter thread-root substrate keyed by `thread:{root_tweet_id}`. Includes root payload, author/timestamp, aggregate tweet counts, and total likes/retweets for thread-level retrieval. |
| `scry.twitter_post_observations` | Public-safe provenance rows for the Twitter substrate. Exposes source collection, observation source, capture channel, trust score, verification status, and metrics without uploader PII. |
| `scry.twitter_bucket_snapshots` | Scry Tweets bucket pull audit surface. Exposes snapshot-object progress, expected records, committed line coverage, and quality status for the `scry-tweets` Argus snapshot lane. |
| `scry.twitter_follow_edges` | Public Twitter/X follow-edge substrate keyed by follower and followee IDs. Exposes handles, followee profile counts when present, public provenance tags, `coverage_status`, and `graph_coverage_note`; `partial_not_exhaustive` means observed follower/followee counts are lower bounds and missing edges are not evidence of non-following. |
| `scry.twitter_follow_accounts` / `scry.twitter_followees(...)` / `scry.twitter_followers(...)` / `scry.twitter_mutual_followees(...)` / `scry.twitter_followee_overlap(...)` / `scry.twitter_follow_account_summary(...)` | Ergonomic Twitter/X graph traversal helpers. Use these before hand-writing joins when asking for followees, followers, overlap, mutuals, or observed account graph summaries. All returned counts are observed-only unless `coverage_status` states otherwise. |
| `scry.vc_firms` / `scry.vc_accounts` / `scry.vc_tweets` | Venture-capital Twitter/X lens over source-native Twitter rows. Use `scry.vc_accounts` for account priority, VC evidence scores, firm links, and crawl state; use `scry.vc_tweets` for landed tweets by targeted accounts. |
| `scry.vc_embedding_coverage` / `scry.vc_embedding_gaps` | VC target embedding-contract views. `desired_embedding_model` records the requested Voyage 4 tier; `scry.vc_embedding_gaps` lists landed tweets missing the required chunk-0 embedding model. |
| `scry.mailing_lists` / `scry.mailing_list_messages` | Canonical mailing-list list metadata plus per-message substrate keyed by `list_key` / `message_key`. |
| `scry.forum_sites` / `scry.forum_threads` / `scry.forum_posts` | Canonical forum substrate split into site metadata, thread headers, and post rows. Covers Discourse- and Forem-style archives keyed by `site_key` / `thread_key` / `post_key`; `scry.forum_posts` exposes `content_risk` for dangerous/adversarial forum sources. |
| `scry.discussion_messages` | Normalized union over mailing-list messages and forum posts with shared `source_class`, `collection_key`, `thread_key`, `message_key`, `archive_url`, and `content_risk` columns. |
| `scry.openlibrary_editions` / `scry.openlibrary_works` / `scry.openlibrary_authors` | Canonical Open Library bibliographic substrates. |
| `scry.gdelt_articles` | Canonical GDELT news-article substrate keyed by URL / GKG record pairs. Includes themes, tone, entity extraction, and publication time. |
| `scry.who_iris_publications` | Canonical WHO IRIS publication substrate keyed by `handle`. Includes document type, authors, subjects, languages, publishers, and identifiers. |
| `scry.moltbook` / `scry.moltbook_items` | Canonical Moltbook substrate keyed by `item_key`. Includes explicit `content_risk` plus mixed post/comment/document grain. |
| `scry.huggingface` / `scry.huggingface_repositories` | Canonical Hugging Face repository substrate keyed by `repo_id` (`owner/name`). Includes repo type (`model`/`dataset`/`space`), owner handle, card metadata, tags, likes/downloads, and synthesized repo payload text. |
| `scry.huggingface_models` / `scry.huggingface_datasets` / `scry.huggingface_spaces` | Repo-type filtered Hugging Face aliases for common traversal without repeating `WHERE repo_type = ...`. |
| `scry.huggingface_accounts` / `scry.huggingface_organizations` | Canonical Hugging Face account substrate keyed by handle. Includes user/org typing, bio, follower counts, plan/pro flags, and profile metadata. |
| `scry.huggingface_account_socials` / `scry.huggingface_organization_memberships` | Account graph edges. Social handles keyed by `(handle, platform)` plus org→member memberships keyed by `(organization_handle, member_handle)`. |
| `scry.huggingface_account_hardware` | Public profile hardware declarations from HF Local Apps and Hardware. One row per declared hardware item with handle, account display fields, hardware kind, vendor, SKU path/name, memory GB, quantity, and raw metadata. |
| `scry.huggingface_repo_text_artifacts` | Selected high-signal repo text files keyed by `artifact_key`. Includes README/model-card text, Space `app.py`, config files, citations, licenses, and requirements. |
| `scry.huggingface_papers` | Hugging Face Paper Pages keyed by paper id (typically arXiv id). Includes summary, AI summary, authors, upvotes, and discussion id. |
| `scry.huggingface_collections` / `scry.huggingface_collection_items` | Hugging Face collections and their ordered items (models, datasets, spaces, papers, nested collections). |
| `scry.huggingface_discussions` / `scry.huggingface_discussion_events` | Repo discussions / PR threads and their event streams. Discussions are keyed by `repo_type:repo_id#num`; events preserve comment and commit payloads. |
| `scry.huggingface_repo_links` | Explicit repository link graph keyed by repo and target identity. Use it to traverse repos to papers, datasets, collections, mirrored repos, and external references. |
| `scry.huggingface_paper_artifacts` | Derived paper-to-repo link surface over `huggingface_repo_links` joined to repos and hydrated paper pages. |
| `scry.stackexchange` | Canonical StackExchange substrate. Questions and answers from Stack Overflow and 170+ Stack Exchange sites, keyed by `{site}:{post_id}`. Windowed by time period. |
| `scry.stackexchange_site_status` | Site-level StackExchange closure/accounting surface. Use it to inspect per-site import/reconciliation status before assuming a site is complete. |
| `scry.caselaw` | US legal opinions from CourtListener and Caselaw Access Project. Keyed by `cl:{opinion_id}` or `cap:{case_id}`. Includes court, jurisdiction, citations, opinion text. Windowed by decade. |
| `scry.gutenberg_books` | Project Gutenberg full-text public domain books. Keyed by `gutenberg:{ebook_number}`. Includes subject, bookshelf, language, download count. |
| `scry.wikidata_items` | Wikidata structured knowledge graph items and properties. Keyed by QID (e.g., `Q42`). Includes labels, descriptions, aliases, instance_of, subclass_of. |
| `scry.wikidata_claims` | Wikidata structured claims (property-value assertions). Subject QID → property → value. Join to `scry.wikidata_items` on `subject_qid`. |
| `scry.kl3m` | KL3M federal corpus from PleIAs. Government documents, regulations, and .gov web pages. Partitioned by collection family (govinfo, dotgov, courtlistener). Windowed for lexical search. |
| `scry.epstein_artifacts` / `scry.epstein_units` | Serving Epstein document artifacts plus retrieval units. Artifacts expose release/provenance metadata; units expose page/anchor-level text slices and grounding metadata for search. |
| `scry.europepmc` / `scry.europepmc_articles` | Europe PMC source-native article surface keyed by `epmc_id`. Includes PMID/PMCID/DOI identifiers, journal, publication year/date, citation/open-access flags, terms, and article payload text. |
| `scry.sec_edgar` / `scry.sec_edgar_filings` | SEC EDGAR filing surface keyed by accession number. Includes CIK/company/form metadata, filing/report dates, accession URL, and filing text payload. |
| `scry.sec_edgar_denominator_targets` / `scry.sec_edgar_company_coverage` / `scry.sec_edgar_year_form_coverage` / `scry.sec_edgar_ingest_overview` | SEC EDGAR denominator/accounting views for company/form/year coverage and current metadata-stage queue totals. Use these before claiming SEC coverage completeness. |
| `scry.sec_edgar_fulltext_queue` / `scry.sec_edgar_xbrl_queue` / `scry.sec_edgar_queue_summary` | SEC EDGAR work-queue/readiness views for full-text and XBRL followthrough. |
| `scry.sec_edgar_material_filings` | SEC EDGAR material subset for periodic reports, current reports, registration/prospectus filings, governance/ownership filings, and insider-ownership forms, with `material_class` for triage. |
| `scry.google_patents_publications` | Google Patents BigQuery publication surface keyed by `publication_number`. Includes titles, abstracts, claims, descriptions, inventors, assignees, classifications, citations, patent-family links, and canonical patents.google.com URIs. Check row counts for current coverage before treating it as exhaustive prior-art. |
| `scry.sec_quarterly_numbers` / `scry.sec_quarterly_submission` / `scry.sec_quarterly_presentation` / `scry.sec_quarterly_quick_summary` | SEC quarterly financial statement BigQuery tables. Use these for structured public-company facts, filing metadata, statement presentation context, and CIK/company/date joins. |
| `scry.sec_quarterly_calculation` / `scry.sec_quarterly_dimension` / `scry.sec_quarterly_measure_tag` / `scry.sec_quarterly_rendering` / `scry.sec_quarterly_txt` / `scry.sec_quarterly_sic_codes` | SEC quarterly companion tables for XBRL calculation arcs, segment dimensions, tag definitions, rendering metadata, text facts, and SIC labels. |
| `scry.fec_bigquery_candidates` / `scry.fec_bigquery_committees` / `scry.fec_bigquery_candidate_committee_links` / `scry.fec_bigquery_transactions` / `scry.fec_bigquery_operating_expenditures` | FEC BigQuery campaign-finance substrate. Use candidate/committee tables for identity and relationship joins, and transaction/expenditure tables for contribution and spending analysis. |
| `scry.google_trends_daily_terms` / `scry.google_trends_hourly_terms` | Google Trends public term-rank time series. Includes domestic/international daily terms plus hourly top/rising terms for attention and geography/time joins. |
| `scry.irs_990_bigquery_returns` / `scry.irs_990_bigquery_ein_index` | IRS 990 BigQuery nonprofit returns and EIN index. Includes EIN, tax year/period, organization metadata, revenue, expenses, assets, liabilities, and preserved raw payloads for form-family fields. |
| `scry.fcc_political_ad_stations` / `scry.fcc_political_ad_content_info` / `scry.fcc_political_ad_file_history` / `scry.fcc_political_ad_file_records` | FCC political-ad public-file metadata: stations, advertisers/candidates/spend, file history, raw public-file links, OCR flags, hashes, and years. |
| `scry.openaq_air_quality_measurements` | OpenAQ BigQuery air-quality measurement surface with country/city/location, pollutant, measured value, timestamp, units, coordinates, and source name. |
| `scry.noaa_gsod_weather_observations` | NOAA GSOD BigQuery weather observations. Covers a bounded historical window; inspect `observed_on` for the available date range before using it for recent weather. |
| `scry.polymarket_profiles` / `scry.polymarket_markets_embeddings` | Polymarket profile and embedding-support surfaces for prediction-market discovery. |

Source-local lexical helpers exist for many of these views:

| Function | Notes |
|----------|-------|
| `scry.search_bluesky_posts(query_text, mode, limit_n)` | BM25 over Bluesky `payload` plus DID / handle / display-name fields. |
| `scry.search_twitter_posts(query_text, mode, limit_n)` | BM25 over source-native Twitter/X tweet rows. Use for individual tweet identity, canonical URI, author fields, timestamps, and public observation provenance arrays. |
| `scry.search_hackernews_items(query_text, mode, kinds, limit_n)` | BM25 over HN `title`, `payload`, and `original_author`. |
| `scry.search_wikipedia_articles(query_text, mode, limit_n)` | BM25 over Wikipedia `title`, `payload`, and `original_author`. |
| `scry.search_pubmed_papers(query_text, mode, limit_n)` | BM25 over PubMed `title`, `payload`, `original_author`, and `journal`. |
| `scry.search_repec_records(query_text, mode, external_types, limit_n)` | BM25 over RePEc `title`, `payload`, `original_author`, `journal`, `series`, and `institution`. |
| `scry.search_openlibrary_editions(query_text, mode, limit_n)` | BM25 over Open Library edition `title`, `payload`, `original_author`, and `publish_date`. |
| `scry.search_openlibrary_works(query_text, mode, limit_n)` | BM25 over Open Library work `title`, `payload`, and `original_author`. |
| `scry.search_openlibrary_authors(query_text, mode, limit_n)` | BM25 over Open Library author `name`, `payload`, `original_author`, and life-date fields. |
| `scry.search_federated(query_text, sources, kinds, limit_n, per_source_cap)` | Cross-source lexical shortlist helper across shared and source-native corpora. It normalizes provenance-bearing results for first-pass discovery. |
| `scry.search_huggingface(query_text, mode, scopes, repo_types, limit_n)` | Unified Hugging Face discovery helper across repos, artifacts, collections, papers, discussions, accounts, and paper-artifact hops. Use this when you do not yet know which HF surface is the right starting point. |
| `scry.search_huggingface_accounts(query_text, mode, account_types, limit_n)` | BM25 over HF account handles, display names, bios, and plan labels. |
| `scry.huggingface_account_repositories(owner_handle, repo_types, limit_n)` | Traverses a HF handle into its owned repositories with popularity/freshness ordering. |
| `scry.search_huggingface_repositories(query_text, mode, repo_types, owner_handles, limit_n)` | BM25 over Hugging Face repo payloads, titles, descriptions, repo ids, and owner handles. |
| `scry.search_huggingface_repo_text_artifacts(query_text, mode, repo_types, artifact_kinds, limit_n)` | BM25 over README/model-card/code/config text captured from high-signal Hub files. |
| `scry.search_huggingface_collections(query_text, mode, owner_handles, limit_n)` | BM25 over collection titles, descriptions, owner handles, and item summaries. |
| `scry.search_huggingface_papers(query_text, mode, year_from, limit_n)` | BM25 over Hugging Face Paper Page summaries, AI summaries, titles, and author names. |
| `scry.search_huggingface_discussions(query_text, mode, repo_types, statuses, limit_n)` | BM25 over discussion titles, concatenated thread payloads, repo ids, author display names, and status. |
| `scry.huggingface_find_paper_artifacts(query_text, year_from, limit_n)` | Traverses paper hits back into linked Hub repos using `huggingface_repo_links`; it prefers direct arXiv/DOI and OpenAlex resolution before falling back to HF paper pages, so paper-to-artifact recovery does not depend on starting inside Hugging Face first. |
| `scry.openalex_find_works(query, min_year, limit)` | Source-native OpenAlex work lookup over titles and DOIs with dedicated abstract payload link-through. |
| `scry.search_mailing_list_messages(query_text, mode, list_keys, limit_n)` | BM25 over mailing-list message rows. |
| `scry.search_forum_posts(query_text, mode, site_keys, limit_n)` | BM25 over canonical forum posts keyed by site-specific `post_key`. Skips `content_risk='dangerous'` rows by default; use site keys such as `ethresearch`, `datasecretslox`, or `solana_forum`. |
| `scry.search_discussions(query_text, mode, limit_n)` | Merges mailing-list and forum lexical hits into a normalized discussion result surface with shared collection/thread/message keys. |
| `scry.search_packages(query_text, registries, limit_n)` | Cross-registry package search over npm, PyPI, crates.io, Go modules, NuGet, Maven Central, Hex.pm, Packagist, pub.dev, CocoaPods, conda-forge, JSR, and Homebrew. |
| `scry.social_search(query_text, mode, limit_n)` | Convenience union over the major social/post surfaces when you want a fast social-only lexical pass. |
| `scry.search_stackexchange_questions(query_text, mode, sites, tags, limit_n, window_key)` | BM25 over StackExchange question windows. Default window: `recent`. Use `window_key='all'` to search all periods. |
| `scry.search_stackexchange_answers(query_text, mode, sites, limit_n, window_key)` | BM25 over StackExchange answer windows. |
| `scry.search_caselaw(query_text, mode, courts, jurisdictions, limit_n, window_key)` | BM25 over US caselaw by decade. Default window: `2020s`. Windows: `2020s`, `2010s`, `2000s`, `1990s`, `1980s`, `pre1980`, `all`. |
| `scry.search_gutenberg(query_text, mode, languages, subjects, limit_n)` | BM25 over Project Gutenberg full-text books. Filter by language (`en`, `fr`, etc.) and/or subject. |
| `scry.search_wikidata(query_text, mode, entity_types, limit_n)` | BM25 over Wikidata items. `entity_types` defaults to `['item', 'property']`. |
| `scry.search_kl3m(query_text, mode, collections, agencies, limit_n, window_key)` | BM25 over KL3M federal corpus. `agencies` filters by regulatory body. `collections` filters by collection name (e.g., `govinfo-fr`, `dotgov-*`). Windows: `govinfo_recent`, `govinfo_2010s`, `govinfo_2000s`, `govinfo_pre2000`, `dotgov_recent`, `dotgov_2010s`, `dotgov_pre2010`, `govinfo_all`, `dotgov_all`, `all`. |
| `scry.search_epstein_units(query_text, release_families, artifact_kinds, unit_kinds, date_from, date_to, limit_n)` | BM25 over serving Epstein units with filters for release family, artifact kind, unit kind, and retrieved-at date. |
| `scry.search_europepmc_articles(query_text, mode, limit_n)` | BM25 over Europe PMC article titles, abstracts/payloads, authors, journal, DOI/PMID/PMCID, and terms. |
| `scry.search_sec_edgar_filings(query_text, forms, ciks, limit_n)` | BM25 over SEC EDGAR filing payloads with optional form and CIK filters. |
| `scry.sec_edgar_company_filings(cik_or_ticker, forms, limit_n)` | Bounded SEC filing lookup by ticker or CIK, newest first, returning queue/content-stage fields for one company. |

It is normal to combine multiple source-native helpers in one statement:

```sql
WITH hn AS (
  SELECT 'hackernews'::text AS source, hn_id::text AS external_id, score
  FROM scry.search_hackernews_items('alignment tax', kinds => ARRAY['post'], limit_n => 20)
),
wiki AS (
  SELECT 'wikipedia'::text AS source, page_id::text AS external_id, score
  FROM scry.search_wikipedia_articles('alignment tax', limit_n => 20)
),
hits AS (
  SELECT * FROM hn
  UNION ALL
  SELECT * FROM wiki
)
SELECT h.source, r.uri, r.title, h.score
FROM hits h
JOIN scry.source_records r
  ON r.source = h.source
 AND r.external_id = h.external_id
ORDER BY h.score DESC
LIMIT 20;
```

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

### scry.reddit_posts / scry.reddit_comments

Repo-defined union views over all 7 time-window shards. On the public instance
these direct retrieval surfaces are currently **degraded**: they appear in the
live schema, but performance is not reliable enough to treat them as the normal
happy path.

Use these only when a query is already tightly bounded by subreddit and time.
For default Reddit lexical work, use `scry.search_reddit(...)`; its `auto`
window uses the fast frontier accelerator when applicable and a bounded
recent-window lane otherwise. Use `scry.reddit_search_contract`,
`scry.reddit_search_window_status`, `scry.reddit_subreddit_stats`,
`scry.reddit_subreddit_stats_monthly`, `scry.reddit_clusters()`, and
`scry.reddit_embeddings` for discovery and coverage checks.

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT | Reddit full ID (`t1_` or `t3_`) |
| reddit_id | TEXT | Base36 ID without prefix |
| kind | entity_kind | `post` or `comment` |
| subreddit | TEXT | Subreddit name (indexed) |
| uri | TEXT | Permalink |
| payload | TEXT | Body/selftext (50K truncated) |
| title | TEXT | Post title (NULL for comments) |
| upvotes | INT | Score (can be negative, indexed) |
| score | INT | Coalesced |
| comment_count | INT | Post comment count |
| original_author | TEXT | Handle (NULL if deleted, indexed) |
| original_timestamp | TIMESTAMPTZ | Creation time (indexed with subreddit) |
| link_full_id | TEXT | Parent post for comments |
| parent_full_id | TEXT | Parent comment or post |
| over_18 | BOOL | NSFW flag |
| is_self | BOOL | Self post flag |
| domain | TEXT | Link domain (indexed) |
| source_set | TEXT | `full` or `subreddits24` |
| source_file | TEXT | Source filename |
| metadata | JSONB | Moderation flags, flair, etc. |
| created_at | TIMESTAMPTZ | Ingest time |

### scry.reddit

Union of `scry.reddit_posts` and `scry.reddit_comments`. Same columns. **Always
filter by subreddit** — unfiltered queries scan billions of rows.

### scry.reddit_subreddits(pattern, min_total, limit_n)

Discover available subreddits. `pattern` uses SQL ILIKE (`%` = wildcard). Returns
subreddit, post_count, comment_count, total_count, earliest, latest, active_authors.

### scry.reddit_subreddit_stats / scry.reddit_subreddit_stats_monthly

Aggregated subreddit activity counts and monthly time series.
`reddit_subreddit_stats` is one row per subreddit across all shard windows.
`reddit_subreddit_stats_monthly` is one row per `(subreddit, month)`.

### scry.reddit_author_stats

Aggregated per-author activity across all time windows.

### scry.reddit_domain_stats

Top domains shared on Reddit (materialized view).

### Accelerator policy

`GET /v1/scry/context` exposes `offerings.accelerator_families` and
`offerings.relation_accelerator_policies`. Treat relations advertised as
`default` as canonical surfaces. Treat relations advertised as `fast_path` or
`conditional` as optional helpers only after `/v1/scry/index-view-status`
confirms their required tracked objects are healthy.

### Thematic Cluster Views

Pre-filtered views for common research topics. Each covers 3-22 curated subreddits:

| View | Cluster | Example subreddits |
|------|---------|--------------------|
| `scry.reddit_ai` | AI/ML | MachineLearning, LocalLLaMA, ChatGPT, OpenAI, singularity |
| `scry.reddit_science` | Science | science, askscience, Physics, biology, space |
| `scry.reddit_rationality` | Rationality/EA | slatestarcodex, EffectiveAltruism, LessWrong, Futurology |
| `scry.reddit_economics` | Economics/Finance | economics, wallstreetbets, investing, CryptoCurrency |
| `scry.reddit_law` | Law/Policy | law, scotus, geopolitics, PoliticalDiscussion |
| `scry.reddit_tech` | Tech/Programming | programming, rust, Python, netsec, ExperiencedDevs |
| `scry.reddit_health` | Health/Medicine | medicine, Nootropics, longevity, publichealth |
| `scry.reddit_history` | History | history, AskHistorians, badhistory |
| `scry.reddit_climate` | Climate/Energy | climate, energy, nuclear, collapse, sustainability |
| `scry.reddit_philosophy` | Philosophy/CogSci | philosophy, psychology, cogsci, linguistics |
| `scry.reddit_culture` | Culture/Ideas | books, TrueFilm, TrueReddit, DepthHub |
| `scry.reddit_education` | Education/Academia | Teachers, AskAcademia, Professors, GradSchool |
| `scry.reddit_politics` | Political Analysis | worldnews, moderatepolitics, anime_titties |
| `scry.reddit_business` | Business/Startups | Entrepreneur, smallbusiness, venturecapital |
| `scry.reddit_math` | Mathematics/Stats | math, statistics, dataisbeautiful, datasets |
| `scry.reddit_defense` | Defense/OSINT | CredibleDefense, WarCollege, Military, OSINT |
| `scry.reddit_gaming` | Game Dev/Discussion | Games, pcgaming, gamedev, truegaming |
| `scry.reddit_urban` | Urban Planning | urbanplanning, fuckcars, transit |
| `scry.reddit_food` | Food/Nutrition | Cooking, nutrition, AskCulinary, farming |

Discover all clusters and their members: `SELECT * FROM scry.reddit_clusters()`.

### scry.reddit_thread(post_id, max_depth, limit_n)

Returns the full comment tree for a Reddit post as a flat table with depth column.
Uses recursive CTE on `parent_full_id` chains. Requires `link_full_id` index.

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT | Comment ID |
| depth | INT | 0 = top-level reply, 1+ = nested |
| parent_id | TEXT | Direct parent (post ID or comment ID) |
| author | TEXT | Username |
| score | INT | Upvotes |
| posted | TIMESTAMPTZ | Comment timestamp |
| body | TEXT | Comment text (capped at 4000 chars) |

### scry.reddit_embeddings

Semantic vectors for the embedding-covered Reddit subset (partial corpus coverage by design).

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT | Reddit full ID (`t1_`/`t3_`) |
| source_window | TEXT | Source shard table used for retrieval |
| kind | entity_kind | `post` or `comment` |
| subreddit | TEXT | Subreddit name |
| original_timestamp | TIMESTAMPTZ | Source timestamp |
| upvotes | INT | Source score |
| payload_chars | INT | Text length used for prioritization |
| priority_score | DOUBLE PRECISION | Queue priority used for coverage rollout |
| chunk_index | INT | 0 = document-level |
| chunk_start | INT | Byte offset start |
| chunk_end | INT | Byte offset end |
| token_count | INT | Tokens in chunk |
| chunking_strategy | chunking_strategy | Strategy label |
| embedding_voyage4 | halfvec(2048) | Voyage 4 space embedding |
| model_name | TEXT | Usually `voyage-4-nano` for local runs |
| created_at | TIMESTAMPTZ | Write time |

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

Three layers of author resolution, bottom to top:

1. **`scry.actors`** -- one row per platform account (`source` + `external_id` is unique). Content links here via `author_actor_id`.
2. **`scry.person_accounts`** -- conservative public actor-to-person edges. One row per linked public account with confidence, link method, and activity counts.
3. **`scry.people`** -- one row per real-world person (only those with >= 1 verified public actor link), including `actor_count` and `entity_count`.
4. **`scry.person_aliases`** -- alias helper derived from verified public links (`handle` + `display_name` normalized forms). Useful for loose text lookup, not the primary canonical join path.

| View | Description |
|------|-------------|
| `scry.actors` | Per-source account records |
| `scry.people` | Cross-platform merged identities from verified public links, with public counts |
| `scry.person_accounts` | Canonical public person-account edges (columns: `person_id`, `actor_id`, `source`, `external_id`, `handle`, `display_name`, `profile_url`, `link_method`, `confidence`, `entity_count`, `post_count`, `comment_count`, `first_activity`, `last_activity`) |
| `scry.person_aliases` | Alias forms derived from verified public person-account links |
| `scry.mv_author_profiles` | Per-source author stats aggregated from entity rows (threshold: >= 3 entities) |
| `scry.mv_author_stats` | Author post counts and score aggregates |
| `scry.github_people` | GitHub-specific maintainer aggregates (stars, repos, comments) |
| `scry.github_person_repos` | GitHub person-to-repo mapping |

**Identity confidence interpretation:**

| Probability | Meaning |
|-------------|---------|
| >= 0.98 | Manual verification or self-declared link |
| 0.90 - 0.98 | Verified public evidence such as canonical-id or profile-link confirmation |
| < 0.90 | Below Scry threshold -- not surfaced in views |

Public identity views contain the conservative verified-public link layer used for cross-source author lookup.

Common names produce false merges. When `display_name` is generic (e.g., "John Smith"), verify with secondary evidence (same bio, cross-linked profiles, overlapping topics).

**Primary query path:** find the person in `scry.people`, inspect linked public accounts in `scry.person_accounts`, then query `scry.entities` by `author_person_id`.

**Helper function:** `normalize_author_name(text)` -- lowercases, trims, collapses whitespace. Used for alias helpers, not as the canonical merge authority.

---

## Agent Views

| View | Description |
|------|-------------|
| `scry.agent_judgements` | Structured agent observations (queryable with an authenticated personal-key Scry SQL context) |
| `scry.agent_emitters` | Aggregated agent emitter stats visible through the authenticated judgement surface |

---

## Materialized Views (Pre-filtered Subsets)

These are the primary performance tool. Use them instead of scanning `scry.entities`.

### Forum / Blog Posts

| View | Description | Has embedding_voyage4? |
|------|-------------|----------------------|
| `scry.mv_lesswrong_posts` | LessWrong posts with scores, AF flag. Source-native (forum_posts). Columns include `post_key` — join `scry.forum_posts` on `post_key` for full content. | Yes |
| `scry.mv_eaforum_posts` | EA Forum posts with scores. Source-native (forum_posts). Columns include `post_key`. | Yes |
| `scry.mv_unjournal_posts` | Unjournal evaluations | Yes |
| `scry.mv_hackernews_posts` | HN posts with scores | Yes |
| `scry.mv_substack_posts` | Substack articles | Yes |
| `scry.mv_blogosphere_posts` | Independent blogs (astralcodexten, etc.) | Yes |
| `scry.mv_forum_posts` | Multi-forum aggregate (LW, EA, DSL, MR) | Yes |
| `scry.mv_datasecretslox_posts` | Data Secrets Lox posts | Yes |
| `scry.mv_marginalrevolution_posts` | Marginal Revolution posts | Yes |
| `scry.mv_ethereum_posts` | Ethereum ecosystem posts | Yes |
| `scry.mv_crypto_posts` | Crypto-focused posts | Yes |

### Canonical Semantic Surfaces

| View | Description | Has embedding_voyage4? |
|------|-------------|----------------------|
| `scry.chunk_embeddings` | Canonical chunk-level embedding substrate keyed by `entity_id` + `chunk_index` | Yes |
| `scry.entity_embeddings` | Canonical entity-level embedding helper (`chunk_index = 0`) for embedded public entities | Yes |
| `scry.entities_with_embeddings` | Public entity rows joined to `scry.entity_embeddings`; filter `kind` and `source` as needed | Yes |
| `scry.embedding_coverage` | Source/kind public vs staged vs ready embedding coverage reporting surface | N/A |
| `scry.arxiv_papers_embeddings` / `scry.twitter_posts_embeddings` / `scry.forum_posts_embeddings` / `scry.moltbook_items_embeddings` / `scry.hackernews_items_embeddings` / `scry.wikipedia_articles_embeddings` / `scry.pubmed_papers_embeddings` / `scry.repec_records_embeddings` / `scry.kalshi_markets_embeddings` / `scry.nih_reporter_projects_embeddings` / `scry.govinfo_crec_granules_embeddings` / `scry.offshoreleaks_nodes_embeddings` | Source-local chunk embeddings keyed by the canonical table's natural identifier plus `entity_id`; use when you need the exact semantic owner table instead of the cross-source union | Yes |

### Cross-Source Aggregates

| View | Description | Has embedding_voyage4? |
|------|-------------|----------------------|
| `scry.mv_posts` | Legacy post-only convenience aggregate; prefer `scry.entities_with_embeddings` or `scry.entity_embeddings`, and check live schema before depending on it | Yes / schema-dependent |
| `scry.mv_high_score_posts` | Posts with score >= threshold | Yes |
| `scry.mv_papers` | Papers from arxiv, pubmed, biorxiv, openalex, etc. | Yes |
| `scry.mv_af_posts` | Alignment Forum posts only | Yes |

### Comments

| View | Description | Has embedding_voyage4? |
|------|-------------|----------------------|
| `scry.mv_lesswrong_comments` | LW comments. Source-native (forum_posts). Columns include `post_key`. | Yes |
| `scry.mv_eaforum_comments` | EA Forum comments. Source-native (forum_posts). Columns include `post_key`. | Yes |
| `scry.mv_high_karma_comments` | High-karma comments across forums | Yes |
| `scry.mv_substack_comments` | Substack comments | Yes |

### Social Media

| View | Description | Has embedding_voyage4? |
|------|-------------|----------------------|
| `scry.mv_twitter_threads` | Twitter/X thread aggregate fast path; prefer `scry.twitter_posts` / `scry.search_twitter_posts` when the question needs individual tweet identity or observation provenance. | Yes |
| `scry.mv_bluesky_posts` | Bluesky posts | No (ramping) |

### Academic Papers

| View | Description | Has embedding_voyage4? |
|------|-------------|----------------------|
| `scry.mv_arxiv_papers` | Legacy arXiv convenience view; prefer `scry.arxiv` / `scry.arxiv_papers`. | Yes |
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
| `scry.polymarket` / `scry.polymarket_markets` | Polymarket markets (source-native table) |
| `scry.polymarket_events` | Polymarket event groups |
| `scry.polymarket_market_outcomes` | Outcome rows and CLOB token IDs for each Polymarket market |
| `scry.polymarket_comments` | Polymarket comments linked to markets and events |
| `scry.polymarket_trades` | Polymarket trades |
| `scry.polymarket_activity` | Public on-chain activity for Polymarket wallets |
| `scry.polymarket_market_holders` / `scry.polymarket_market_positions` | Holder and position data for each market |
| `scry.polymarket_orderbooks` | Polymarket orderbook snapshot summaries |
| `scry.polymarket_price_snapshots` / `scry.polymarket_price_history` | Polymarket token price snapshots and history |
| `scry.polymarket_tags` / `scry.polymarket_series` / `scry.polymarket_rewards` / `scry.polymarket_sports` | Polymarket tags, series, rewards, and sports catalogs |
| `scry.mv_github_documents` | GitHub-sourced documents |
| `scry.mv_mailing_list_messages` | Mailing list messages |
| `scry.mv_freshness` | Materialized-view freshness and approximate row counts; use it to verify whether a convenience view is populated before relying on it |
### Cross-Source Semantic Search Substrate

`scry.chunk_embeddings` is now backed by the materialized `mv_chunk_embeddings` table with
vchordrq ANN indexes. This means `ORDER BY embedding_voyage4 <=> @vec` queries against
`scry.chunk_embeddings` and `scry.entity_embeddings` use real ANN instead of sequential
scanning 20+ source-native embedding tables.

### Reddit Windowed Views

Reddit is sharded by time period for performance. These `mv_` names are legacy
and currently backed by plain views, not materialized views. On the public
instance they are also currently **degraded**, so treat them as diagnostic /
repo-defined surfaces unless live schema status says otherwise.

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

Scholarly works mirrored from the OpenAlex graph. Five node types connected by junction tables:
Authors --[authorships]--> Works --[references]--> Works, with Institutions and Concepts linked via junction tables.

| View | Description |
|------|-------------|
| `scry.openalex_works` | All works with payload, entity linkage |
| `scry.openalex_authors` | Author records with ORCID |
| `scry.openalex_institutions` | Institutions with country, type, ROR |
| `scry.openalex_concepts` | Concept taxonomy with hierarchy level |
| `scry.openalex_work_authorships` | Work-author links with position, affiliation |
| `scry.openalex_work_institutions` | Work-institution links |
| `scry.openalex_work_references` | Citation edges (work cites work) |
| `scry.openalex_work_concepts` | Work-concept tags with relevance scores |

**OpenAlex ID formats:**

| Entity | Prefix | Example | Lookup |
|--------|--------|---------|--------|
| Author | `A` | `A5000005023` | `https://openalex.org/A5000005023` |
| Work | `W` | `W2741809807` | `https://openalex.org/W2741809807` |
| Institution | `I` | `I13416579` | `https://openalex.org/I13416579` |
| Concept | `C` | `C199360897` | `https://openalex.org/C199360897` |

**Well-known institution IDs:** MIT `I13416579`, Harvard `I136199984`, Stanford `I27837315`, Oxford `I205783295`, Google `I40120149`.

**Well-known concept IDs:** Machine Learning `C199360897`, AI `C41008148`, Deep Learning `C154945302`, Computer Science `C119857082`, Biology `C86803240`, Mathematics `C33923547`.

### StackExchange Views

StackExchange corpus: questions and answers from Stack Overflow and 170+ Stack Exchange
sites. Windowed by time period, mirroring the Reddit pattern.

| View | Description |
|------|-------------|
| `scry.stackexchange` | Base view over all StackExchange posts |
| `scry.stackexchange_site_status` | Site-level denominator/freshness/accounting status (`post_count`, question/answer splits, verification/execution state, skip counters) |
| `scry.mv_stackexchange_questions_recent` | Recent questions |
| `scry.mv_stackexchange_questions_2022_2023` | 2022-2023 questions |
| `scry.mv_stackexchange_questions_2020_2021` | 2020-2021 questions |
| `scry.mv_stackexchange_questions_2018_2019` | 2018-2019 questions |
| `scry.mv_stackexchange_questions_2014_2017` | 2014-2017 questions |
| `scry.mv_stackexchange_questions_2010_2013` | 2010-2013 questions |
| `scry.mv_stackexchange_questions_2008_2009` | 2008-2009 questions |
| `scry.mv_stackexchange_answers_*` | Matching answer windows (`recent`, `2022_2023`, `2020_2021`, `2018_2019`, `2014_2017`, `2010_2013`, `2008_2009`) |

Key columns: `id` (`{site}:{post_id}`), `site`, `site_group`, `post_type`
(`question`/`answer`), `parent_id`, `title` (questions only), `payload`, `tags`
(questions only, `TEXT[]`), `original_author`, `score`, `view_count`,
`answer_count`, `comment_count`, `accepted_answer_id`, `is_accepted`,
`original_timestamp`, `uri`.

Filter by `site` (e.g., `stackoverflow`, `serverfault`, `math.stackexchange`) and
`tags` (e.g., `'rust' = ANY(tags)`).
Use `scry.stackexchange_site_status` for cheap coverage/freshness checks before
running broad StackExchange lexical scans.

### Caselaw Views

US legal opinions from CourtListener and Caselaw Access Project, windowed by decade.

| View | Period |
|------|--------|
| `scry.caselaw` | All opinions (base view) |
| `scry.mv_caselaw_opinions_2020s` | 2020s |
| `scry.mv_caselaw_opinions_2010s` | 2010s |
| `scry.mv_caselaw_opinions_2000s` | 2000s |
| `scry.mv_caselaw_opinions_1990s` | 1990s |
| `scry.mv_caselaw_opinions_1980s` | 1980s |
| `scry.mv_caselaw_opinions_pre1980` | Pre-1980 |

Key columns: `id` (`cl:{opinion_id}` or `cap:{case_id}`), `source`
(`courtlistener`/`cap`), `court` (slug: `scotus`, `ca9`, `nysd`, ...),
`court_full_name`, `jurisdiction` (`federal`/`state:{state}`/`territorial`),
`jurisdiction_level` (supreme/appellate/district), `case_name`, `case_name_short`,
`docket_number`, `citation`, `citations` (`TEXT[]`), `opinion_type`, `title`,
`payload` (opinion text), `author_name` (judge), `original_timestamp`,
`date_filed`, `uri`, `word_count`.

Filter by `court`, `jurisdiction`, or `citations` (GIN-indexed `TEXT[]` for
cross-reference lookups).

### Gutenberg Views

Project Gutenberg public domain full-text books.

| View | Description |
|------|-------------|
| `scry.gutenberg_books` | All Gutenberg books |

Key columns: `id`, `ebook_number`, `title`, `original_author`,
`author_birth_year`, `author_death_year`, `language` (ISO code, indexed),
`subject` (`TEXT[]`), `bookshelf` (`TEXT[]`), `rights`, `payload` (full text,
50K truncated), `word_count`, `download_count` (indexed DESC), `media_type`,
`uri`, `original_timestamp`.

Filter by `language` (e.g., `'en'`) and `subject` arrays. Sort by
`download_count DESC` for popular works.

### Wikidata Views

Wikidata structured knowledge graph: items, properties, and claims.

| View | Description |
|------|-------------|
| `scry.wikidata_items` | Items and properties keyed by QID |
| `scry.wikidata_claims` | Structured property-value assertions |

**wikidata_items** columns: `qid` (e.g., `Q42`), `entity_type`
(`item`/`property`), `label_en`, `description_en`, `aliases_en` (`TEXT[]`),
`label_json` (JSONB, multilingual), `description_json` (JSONB), `instance_of`
(`TEXT[]`, GIN-indexed), `subclass_of` (`TEXT[]`), `sitelinks_count`,
`claims_count`, `wikipedia_title_en`, `payload`, `uri`, `last_modified`.

**wikidata_claims** columns: `id` (`{qid}:{property}:{hash}`), `subject_qid`
(FK to items), `property` (e.g., `P31`), `property_label`, `value_type`
(`wikibase-item`/`string`/`time`/...), `value_qid`, `value_string`,
`value_time`, `rank` (`preferred`/`normal`/`deprecated`).

Common patterns:
- Find items: `scry.search_wikidata('Douglas Adams', limit_n => 5)`
- Instance-of lookup: `WHERE 'Q5' = ANY(instance_of)` (humans)
- Traverse claims: join `scry.wikidata_claims` to `scry.wikidata_items` on
  `subject_qid = qid`
- Cross-reference Wikipedia: match `wikipedia_title_en` to
  `scry.wikipedia_articles` title

### KL3M Federal Corpus Views

KL3M corpus from PleIAs: federal government documents, regulations, and .gov web pages.
Partitioned by collection family, with windowed tables for lexical search.

| View | Description |
|------|-------------|
| `scry.kl3m` | Base view over all KL3M documents |
| `scry.mv_kl3m_govinfo_recent` | Recent govinfo documents |
| `scry.mv_kl3m_govinfo_2010s` | 2010s govinfo |
| `scry.mv_kl3m_govinfo_2000s` | 2000s govinfo |
| `scry.mv_kl3m_govinfo_pre2000` | Pre-2000 govinfo |
| `scry.mv_kl3m_dotgov_recent` | Recent .gov web pages |
| `scry.mv_kl3m_dotgov_2010s` | 2010s .gov pages |
| `scry.mv_kl3m_dotgov_pre2010` | Pre-2010 .gov pages |

Key columns: `id` (`{collection}:{doc_hash}`), `collection` (e.g.,
`govinfo-fr`, `govinfo-cfr`, `govinfo-crec`, `govinfo-bills`, `dotgov-*`),
`collection_group` (`govinfo`/`dotgov`/`courtlistener`/`other`), `doc_type`
(regulation, bill, hearing, report, webpage, ...), `title`, `payload`,
`original_author`, `agency`, `original_timestamp`, `uri`, `word_count`.

Filter by `collection_group` for broad categories, `collection` for specific
document families, or `agency` for regulatory body.

### Government/Academic Sources in scry.entities

These sources live in `scry.entities` (not in dedicated tables). Query with
`source = '<source_name>'::external_system`. Key metadata fields vary by source:

| Source | Kind | Typical metadata fields |
|--------|------|------------------------|
| `sec_edgar` | `post` | `form_type`, `cik`, `ticker`, `company_name`, `accession_number`, `report_date`, `sic_code`, `sic_description` |
| `nih_reporter` | `grant` | `nih.project_num`, `nih.fiscal_year`, `nih.award_amount`, `nih.organization`, `nih.activity_code`, `nih.principal_investigators` |
| `federal_register` | `regulation` | `document_number`, `type`, `subtype`, `agency_names`, `agency_ids`, `citation`, `start_page`, `end_page`, `pdf_url` |
| `congress` | `document` | `congress`, `bill_type`, `bill_number`, `sponsor_name`, `sponsor_party`, `sponsor_state`, `policy_area`, `latest_action`, `has_summary` |
| `nsf` | `grant` | `award_id`, `pi_name`, `institution`, `estimated_total_amt`, `program`, `directorate`, `division`, `start_date`, `exp_date` |
| `nvd` | `report` | `cve_id`, `cvss_v31_score`, `cvss_v31_severity`, `cvss_v31_vector`, `cvss_v2_score`, `weaknesses`, `vuln_status` |
| `ecfr` | `regulation` | `cfr_title_number`, `cfr_title_name`, `part_number`, `citation`, `amendment_citation` |
| `crs` | `report` | `topics`, `active`, `crs_type`, `crs_id`, `sourceLink` |
| `nasa_ntrs` | `report` | `ntrs_id`, `sti_type`, `center_code`, `center_name`, `subject_categories`, `keywords`, `doi`, `conference_name` |
| `inspire_hep` | `paper` | `inspire_id`, `arxiv_id`, `doi`, `journal`, `arxiv_categories`, `inspire_categories`, `document_type`, `author_count` |
| `europepmc` | `paper` | `pmid`, `doi`, `journal`, `epmc_source`, `pub_year`, `is_open_access`, `cited_by_count`, `keywords`, `mesh_terms` |
| `hal` | `paper` | `hal_id`, `doc_type`, `language`, `doi`, `journal`, `conference`, `domains`, `keywords` |
| `osti` | `paper` | `osti_id`, `document_type`, `doi`, `sponsor_org`, `research_org`, `subject_categories`, `keywords`, `language` |
| `zenodo` | `paper`/`post` | `doi`, `resource_type` (object: `type`, `subtype`), `access_right`, `communities`, `keywords`, `license`, `creator_orcids` |
| `datacite` | `paper`/`document` | `doi`, `resource_type`, `resource_type_general`, `publisher`, `publication_year`, `subjects`, `citation_count` |

These are queryable through `scry.search_federated(...)`, source-native helpers
where available, or direct `scry.entities` queries with `source` filters.

### Patent Views

`src/db/corpus.sql` defines these patent views, but they are **not guaranteed**
to exist on every public instance. Before using them, confirm they appear in
`GET /v1/scry/schema`. If the schema endpoint does not list them, or SQL returns
`relation "scry.patent_*" does not exist`, treat the public patent surface as
unavailable on that instance rather than inferring zero matching patents from an
empty query.

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
| `scry.nyt_archive_articles` | NYT Archive API article corpus |
| `scry.nyt_article_search_articles` | NYT Article Search API corpus |
| `scry.nyt_books_items` | NYT Books API items and list entries |
| `scry.nyt_rss_items` | NYT RSS feed items |
| `scry.nyt_times_wire_items` | NYT Times Wire items |
| `scry.nyt_top_stories_items` | NYT Top Stories items |
| `scry.nyt_most_popular_items` | NYT Most Popular items |
| `scry.offshoreleaks_nodes` | OffshoreLeaks nodes (flattened) |
| `scry.offshoreleaks_edges` | OffshoreLeaks edges (flattened) |
| `scry.sporc_episodes` | Podcast episodes |
| `scry.sporc_turns` | Podcast transcript turns |
| `scry.entities_private` | Private entities (authenticated only) |
| `scry.private_twitter_bookmarks` | Private Twitter bookmark rows (authenticated only) |
| `scry.private_twitter_bookmark_authors` | Private bookmark rows resolved to linked authors when a public Twitter actor match exists (authenticated only) |
| `scry.chunk_embeddings_private` | Private chunk embeddings (authenticated only) |
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
- **Twitter**: `score`/`upvotes` often NULL. `title` frequently NULL (use `content_text`).
  `original_author` may be NULL; prefer `metadata->>'username'`.
- **arXiv**: `title` often in metadata. `score` is always NULL.
- **Bluesky**: embeddings still ramping. No score field.
- **Reddit**: `upvotes` can be negative. Prefer `scry.search_reddit(...)` for
  lexical retrieval and `scry.search_reddit_semantic(...)` for semantic
  retrieval over the embedding-covered subset.

---

## Lexical Search Functions

If the task is fast result discovery rather than broader SQL composition, use
`scry.search_federated(...)` or a source-local `scry.search_*` helper first,
then widen into richer SQL once you know the right corpus and filters.

| Function | Description | Max limit |
|----------|-------------|-----------|
| `scry.search_federated(query_text, sources, kinds, limit_n, per_source_cap)` | Canonical source-aware lexical shortlist helper across shared and source-native corpora | 200 |
| `scry.search(query_text, mode, kinds, limit_n)` | Shared BM25 diagnostic helper over `content_text`; prefer `scry.search_federated(...)` | 100 |
| `scry.search_ids(query, mode, kinds, limit_n)` | Shared BM25 diagnostic id helper over `content_text`; prefer `scry.search_federated(...)` | 2000 |
| `scry.search_reddit(query_text, mode, subreddits, kinds, limit_n, window_key)` | Ergonomic Reddit lexical search across posts/comments | 100 |
| `scry.search_reddit_posts(query, subreddits, limit_n, window_key)` | Reddit post search | 50 per window |
| `scry.search_reddit_comments(query, subreddits, limit_n, window_key)` | Reddit comment search | 50 per window |
| `scry.search_reddit_semantic(query_embedding, subreddits, kinds, limit_n, min_upvotes, min_timestamp)` | Ergonomic Reddit semantic search across the embedding-covered post/comment subset | 200 |
| `scry.search_reddit_posts_semantic(query_embedding, subreddits, limit_n, min_upvotes, min_timestamp)` | Reddit semantic search over embedding-covered subset | 200 |
| `scry.search_reddit_comments_semantic(query_embedding, subreddits, limit_n, min_upvotes, min_timestamp)` | Reddit comment semantic search over embedding-covered subset | 200 |
| `scry.search_exhaustive(query_text, mode, kinds, limit_n, offset_n)` | Higher-cap paginated search | 1000 |
| `scry.hybrid_search(query, query_vector, kinds, limit_n)` | Lexical + semantic rerank | 100 |
| `scry.author_topics(author_pattern, topics)` | Per-author topic hit counts | -- |
| `scry.preview_text(input, max_chars)` | Safe content-text prefix helper | -- |
| `scry.preview_text_safe(input, max_chars)` | Exception-safe content-text prefix helper | -- |
| `scry.search_private_twitter_bookmarks(query_text, mode, limit_n)` | Private Twitter bookmark lexical search (authenticated only) | 200 |
| `scry.private_bookmarked_author_affinity(limit_n)` | Person-level affinity rollup from private Twitter bookmarks through accepted internal identity links (authenticated only) | 200 |

Default kinds for omitted `kinds`: `post`, `paper`, `document`, `webpage`, `twitter_thread`, `grant`.

Use `scry.search_reddit(...)` as the normal lexical path and
`scry.search_reddit_semantic(...)` as the normal semantic path for Reddit.
`scry.search()` broadens once to `comment` if that default returns 0 rows.
If a `scry.search*` call fails, switch to `scry.search_federated(...)` or a
source-native helper. `/v1/scry/index-view-status` and the `status` fields in
`/v1/scry/schema` show live object health.

### Package Registry Search Functions

Unified cross-registry package search across 14 registries. Use
`scry.search_packages()` for cross-registry discovery, or individual
registry functions for targeted lookups.

| Function | Description |
|----------|-------------|
| `scry.search_packages(query_text, registries, limit_n)` | Unified cross-registry search. `registries` is a text array filter (e.g., `ARRAY['npm','pypi']`); NULL searches all. Returns `registry`, `package_name`, `description`, `original_author`, `latest_version`, `downloads_total`, `license`, `repository_url`, `score`. |
| `scry.search_npm_packages(query_text, mode, limit_n)` | npm packages |
| `scry.search_pypi_packages(query_text, mode, limit_n)` | PyPI packages |
| `scry.search_crates_io_packages(query_text, mode, limit_n)` | crates.io (Rust) |
| `scry.search_rubygems_packages(query_text, mode, limit_n)` | RubyGems |
| `scry.search_go_module_packages(query_text, mode, limit_n)` | Go modules |
| `scry.search_nuget_packages(query_text, mode, limit_n)` | NuGet (.NET) |
| `scry.search_maven_central_packages(query_text, mode, limit_n)` | Maven Central (Java) |
| `scry.search_hex_pm_packages(query_text, mode, limit_n)` | Hex.pm (Elixir/Erlang) |
| `scry.search_packagist_packages(query_text, mode, limit_n)` | Packagist (PHP) |
| `scry.search_pub_dev_packages(query_text, mode, limit_n)` | pub.dev (Dart/Flutter) |
| `scry.search_cocoapods_packages(query_text, mode, limit_n)` | CocoaPods (iOS/macOS) |
| `scry.search_conda_forge_packages(query_text, mode, limit_n)` | conda-forge |
| `scry.search_jsr_packages(query_text, mode, limit_n)` | JSR (Deno/Node) |
| `scry.search_homebrew_formulae(query_text, mode, limit_n)` | Homebrew formulae |

### Social and Twitter Search Functions

| Function | Description |
|----------|-------------|
| `scry.social_search(query_text, mode, limit_n)` | Cross-platform social search (Twitter/X, Reddit, StackExchange, mailing lists). Returns unified rows with `source`, `platform`, `uri`, `snippet`, `score`; use source-native helpers when source-specific provenance matters. |
| `scry.search_twitter_posts(query_text, mode, limit_n)` | BM25 over individual source-native Twitter/X tweet rows. Returns `tweet_id`, `canonical_uri`, author/timestamp fields, and observation provenance arrays. |
| `scry.search_twitter_threads(query_text, mode, limit_n)` | BM25 over Twitter/X thread root tweets. Returns thread-level aggregates (`tweet_count`, `total_likes`, `total_retweets`); do not use as the canonical tweet identity surface. |

For VC-targeted Twitter/X work, start with `scry.vc_accounts` for the account
queue, `scry.vc_tweets` for landed tweets, and
`scry.vc_embedding_coverage` / `scry.vc_embedding_gaps` for Voyage 4 repair
work.

### Diagnostic Views

| View | Notes |
|------|-------|
| `scry.mv_freshness` | Materialized view health: populated status, approx row counts, last analyze timestamp. Useful for diagnosing stale search results. |

### OpenAlex Helper Functions

| Function | Description |
|----------|-------------|
| `scry.openalex_find_authors(query, limit)` | Fuzzy author search |
| `scry.openalex_find_works(query, min_year, limit)` | Work title/DOI search |
| `scry.openalex_find_works_fast(query, min_year, limit)` | Metadata-only work search |
| `scry.openalex_author_works(author_id, min_year, limit)` | Works authored by a specific OpenAlex author |
| `scry.openalex_author_profile(author_id)` | Single author profile |
| `scry.openalex_institution_authors(inst_id, min_year, limit)` | Authors at institution |
| `scry.openalex_concept_authors(concept_id, min_year, limit)` | Authors by concept |
| `scry.openalex_author_coauthors(author_id, min_year, limit)` | Coauthor network |
| `scry.openalex_author_citation_neighbors(author_id, min_year, limit)` | Citation neighbors |

### Inspection And Long-Text Helpers

| Function | Description |
|----------|-------------|
| `scry.table_sample(surface_name, sample_n)` | Returns JSON row samples for quick shape inspection before writing more complex queries. |
| `scry.entity_content_text_slice(entity_id, start, max_chars)` | Retrieves deeper public `content_text` slices beyond the 50K preview cap. Use `start` and `max_chars` to page through long entities. |
| `scry.sporc_transcript_slice(entity_id, start, max_chars)` | Same as `entity_content_text_slice`, but isolates the transcript portion of SPORC pages before slicing. |

### Vector Algebra Functions

| Function | Description |
|----------|-------------|
| `debias_vector(axis, topic)` | Remove axis projection from topic ("X but not Y") |
| `debias_removed_fraction(axis, topic)` | Quick overlap check before debiasing; treat as a diagnostic, not a strict energy fraction |
| `debias_diagnostics(axis, topic)` | Norm/cosine/projection sanity checks |
| `contrast_axis(@pos, @neg)` | Build axis from two opposing embeddings |
| `unit_vector(vec)` | Normalize vector to unit length |
