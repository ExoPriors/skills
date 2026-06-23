---
name: lessonline-research
description: Research LessOnline people, sessions, venues, authenticated event profile evidence, aliases, public-writing candidates, and public event evidence through Scry's LessOnline tables. Use when exploring hosts, presenters, event/profile evidence, people worth meeting, or public corpus matches for LessOnline.
---

# LessOnline Research

Use this after the base Scry skill. Start with `/v1/scry/context` and
`/v1/scry/schema`; only use relations and functions the live schema exposes.
For LessOnline 2026, use `event_slug = 'lessonline-2026'`.

## What This Means

LessOnline rows are source-linked event evidence. A person row can be
grounded by public schedule/page evidence, authenticated event profile evidence,
or both. It is not a claim that Scry has a complete attendee directory.

Use this skill for:

- finding event people, hosts, sessions, venues, and profile evidence;
- grounding a person in event-record provenance before wider research;
- finding aliases, public-writing candidates, and corpus matches;
- ranking people to meet by schedule evidence, topical fit, corpus depth, and
  unresolved uncertainty.

Do not use it to infer private attendance beyond the cited event/profile
evidence, merge identities without public evidence, or treat a missing match as
absence.

## Main Surfaces

Check schema first, then prefer these when present:

- `scry.search_lessonline(...)`
- `scry.search_lessonline_event_records(...)`
- `scry.search_lessonline_people(...)`
- `scry.search_lessonline_person_corpus_matches(...)`
- `scry.lessonline_event_records`
- `scry.lessonline_people`
- `scry.lessonline_person_evidence`
- `scry.lessonline_person_public_aliases`
- `scry.lessonline_person_corpus_matches`
- `scry.lessonline_person_research_frontier`
- `scry.lessonline_person_cards`
- `scry.lessonline_query_coverage`

Use `review_state` and `confidence_tier` to separate research leads from
reviewed identity-backed matches.

## Query Patterns

Unified first pass:

```sql
SELECT result_scope, display_name, title, corpus_source::text, match_basis,
       confidence_tier, review_state, uri
FROM scry.search_lessonline('Jeff Kaufman', 'lessonline-2026', NULL, 25)
LIMIT 25;
```

Person card:

```sql
SELECT display_name, session_count, evidence_count, alias_count,
       corpus_match_count, corpus_source_counts, schedule_evidence,
       public_writing_candidates, lane_statuses
FROM scry.lessonline_person_cards
WHERE event_slug = 'lessonline-2026'
  AND person_key = 'jeff-kaufman-jefftk'
LIMIT 1;
```

Person lookup with event/profile grounding:

```sql
WITH person AS (
  SELECT person_key, display_name
  FROM scry.search_lessonline_people('Philip', 'lessonline-2026', 10)
)
SELECT p.display_name, e.evidence_role, e.title, e.starts_at, e.venue_name, e.uri
FROM person p
JOIN scry.lessonline_person_evidence e USING (person_key)
WHERE e.event_slug = 'lessonline-2026'
ORDER BY e.starts_at NULLS LAST, e.title
LIMIT 50;
```

Session, host, and venue search:

```sql
SELECT record_type, title, venue_name, starts_at, snippet
FROM scry.search_lessonline_event_records(
  'alignment research', 'lessonline-2026', NULL, 50
)
ORDER BY score DESC NULLS LAST, starts_at NULLS LAST
LIMIT 50;
```

Public writing candidates:

```sql
SELECT lessonline_display_name, corpus_source::text, match_basis,
       confidence_tier, review_state, title, uri, original_author,
       original_timestamp
FROM scry.search_lessonline_person_corpus_matches(
  'Jeff Kaufman', NULL, 'lessonline-2026', NULL, 25
)
ORDER BY original_timestamp DESC NULLS LAST
LIMIT 25;
```

Follow-through frontier:

```sql
SELECT display_name, alias_count, identity_candidate_count, corpus_match_count,
       candidate_corpus_match_count, lane_statuses
FROM scry.lessonline_person_research_frontier
WHERE event_slug = 'lessonline-2026'
ORDER BY corpus_match_count DESC, alias_count DESC, display_name
LIMIT 50;
```

## Research Loop

1. Pick a candidate from `scry.lessonline_people` or `scry.search_lessonline`.
2. Open `scry.lessonline_person_cards` for the person summary.
3. Read `scry.lessonline_person_evidence` before making claims about the person.
4. Inspect aliases and frontier rows for identity leads and open follow-ups.
5. Use corpus-match rows before widening to federated or semantic Scry search.
6. Cite event evidence rows, public URLs, corpus records, shares, or receipts.
