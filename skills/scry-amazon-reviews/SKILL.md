---
name: scry-amazon-reviews
description: >-
  Use when a question needs Amazon product reviews or the products they review:
  which reviews say a phrase, how the low-star, verified-purchase or review-volume
  share moves by year in a category, which products draw the most reviews on a
  topic, which reviewers or stores dominate a category, one product's review
  history by ASIN, or product metadata (title, store, price, rating count,
  category path, attribute JSON). Covers the
  McAuley Lab Amazon Reviews 2023 release as a frozen snapshot: reviews from 1996
  to 2023-09 (amazon.reviews) and the item catalog (amazon.items), joined on
  parent_asin.
---

# Amazon reviews and items

The family is one frozen snapshot of the McAuley Lab Amazon Reviews 2023 release: product reviews with rating, headline, text, helpful votes and the verified-purchase flag, and the product catalog they review, keyed by product family (`parent_asin`) within an upstream category slug.

## When to use

- Which reviews say a phrase, in which category, earliest or latest first.
- How the low-star share, the verified-purchase share or the review volume moves by year in a category, with the denominator.
- Which products draw the most reviews on a topic, with their catalog titles.
- Which reviewers or which stores dominate a category over a window.
- One product's review history by `parent_asin`, or one reviewer's rows across categories.
- Product metadata: title, store, price, rating count, category path, brand and the other upstream attributes.

The core `scry` skill (authentication, the query door, response fields) is assumed loaded.

## Doors

| relation | what one row is | key | time column | text column(s) | notes |
| --- | --- | --- | --- | --- | --- |
| `amazon.reviews` | one review of a product variant (`asin`) under its family (`parent_asin`) by a reviewer (`user_id`): `rating`, `title`, `text`, `images`, `helpful_vote`, `verified_purchase`, `category` | (`parent_asin`, `user_id`, `ts`) | `ts` (authored, UTC) | `text` (word-token index, case-sensitive `hasToken`); `title` plain | depth, lag 7d, periodic; fast predicates in order `parent_asin`, then `user_id` under it, then a `ts` range; `user_id` and `asin` alone are indexed; `category = '<slug>'` reads that category only |
| `amazon.items` | one product family (`parent_asin`) within a `category`: `title`, `store`, `average_rating`, `rating_number`, `features`, `description`, `price`, `images`, `categories` path, `details` JSON | (`category`, `parent_asin`) | none (entity snapshot) | `title` (word-token index, case-sensitive); `has(categories, '<leaf>')` has its own index | depth, lag 7d, periodic; the cheap sibling: find products here, then reach reviews by `parent_asin`; a bare `parent_asin` reads across categories |

## Idioms

- Scope by `category` first. It is the upstream slug (`Electronics`, `Musical_Instruments`, `Kindle_Store`); the roster is `SELECT category, count() AS items FROM amazon.items GROUP BY category ORDER BY items DESC LIMIT 40`. `main_category` on items is a display name, empty on a share of rows, and not the filter.
- Token search is case-sensitive on `text` and `title`: `hasToken(text, 'Kindle')`; either case via `hasAnyTokens(text, ['Kindle', 'kindle'])`; a phrase is `hasAllTokens(text, ['Raspberry', 'Pi'])` then `position(text, 'Raspberry Pi') > 0`. A substring test alone has no index, and `positionCaseInsensitive(text, 'raspberry pi')` also matches "raspberry pie", so the tokens go first.
- Items first, reviews by key: pick products with `hasToken(title, '<Token>')` in a category, `ORDER BY rating_number DESC`, then read reviews with `parent_asin = '<asin>'` (the fastest path), `asin = '<asin>'` for one variant, `user_id = '<id>'` for one reviewer across categories.
- Time is `ts` alone, authored, UTC: window with `ts >= '2020-01-01' AND ts < '2023-01-01'` beside a category or a key; a `ts` range on its own scans. Items carry no time; the reviews contract's `extent` ends where the release ends.
- Dedup: `LIMIT 1 BY parent_asin, user_id, ts` on reviews (a key can briefly appear as more than one row). Items are one row per (`category`, `parent_asin`); bind `category` on both sides of a join.
- Denominators: `count()` beside `countIf(rating <= 2)`, `countIf(verified_purchase)` or `countIf(hasToken(text, '<Token>'))` per group; `rating` runs 1 to 5; `helpful_vote` ranks one product's reviews.
- Item fields: `price` is a string (`toFloat64OrNull(price)`, empty on most rows); `details` is the upstream attribute JSON (`JSONExtractString(details, 'Brand')`, keys spelled as upstream does, `'ISBN 13'` included); `description` and `features` are arrays (`arrayStringConcat(description, ' ')`); on Books, `store` carries the byline and `author`, where present, a JSON record (`JSONExtractString(author, 'name')`).
- Helpers bind `text` explicitly: `scry_recipe('<slug>', text)`, `scry_recipe_density('<slug>', text)`, `scry_lex('"battery life" NEAR/60 died', text)`.
- Citation: the product page is `concat('https://www.amazon.com/dp/', asin)` (or `parent_asin` for the family); a review has no id on the wire, so cite it as (`parent_asin`, `user_id`, `ts`) with the product page.

## Worked queries

**Earliest Electronics reviews that say "Raspberry Pi"?**

```sql
SELECT ts, rating, parent_asin, asin, title
FROM amazon.reviews
WHERE category = 'Electronics'
  AND hasAllTokens(text, ['Raspberry', 'Pi'])
  AND position(text, 'Raspberry Pi') > 0
ORDER BY ts ASC
LIMIT 1 BY parent_asin, user_id, ts
LIMIT 10
```

One row per review key, earliest first, with the variant reviewed (`asin`) and its family; `title` is the review's own headline. (verified 2026-09-25)

**Among verified Software purchases, what share rated two stars or lower each year?**

```sql
SELECT toYear(ts) AS year,
       count() AS reviews,
       countIf(rating <= 2) AS low,
       round(low / reviews, 3) AS low_share
FROM amazon.reviews
WHERE category = 'Software' AND verified_purchase = 1
  AND ts >= '2015-01-01' AND ts < '2023-01-01'
GROUP BY year
ORDER BY year
LIMIT 20
```

One row per year with the review count as denominator, the low-star count and the share; the window is bounded on both ends and a GROUP BY needs its LIMIT. (verified 2026-09-25)

**Which Software products draw the most reviews mentioning "subscription", and what are they?**

```sql
SELECT h.parent_asin, i.title, h.n, h.avg_rating
FROM (
  SELECT parent_asin, count() AS n, round(avg(rating), 2) AS avg_rating
  FROM amazon.reviews
  WHERE category = 'Software' AND hasToken(text, 'subscription')
  GROUP BY parent_asin
  ORDER BY n DESC
  LIMIT 10
) AS h
LEFT JOIN (
  SELECT parent_asin, title FROM amazon.items WHERE category = 'Software'
) AS i ON i.parent_asin = h.parent_asin
ORDER BY h.n DESC
LIMIT 10
```

The review side aggregates first and only its top ten reach the join; the items side is scoped to the same category. An empty `title` means the family is absent from the catalog. (verified 2026-09-25)

**The most prolific Musical Instruments reviewers since 2020, with their mean rating?**

```sql
SELECT user_id, count() AS reviews, uniqExact(parent_asin) AS products, round(avg(rating), 2) AS avg_rating
FROM amazon.reviews
WHERE category = 'Musical_Instruments' AND ts >= '2020-01-01'
GROUP BY user_id
ORDER BY reviews DESC
LIMIT 10
```

One row per reviewer id: review count, distinct product families and mean rating; `products` below `reviews` marks repeat reviews of one family. (verified 2026-09-25)

**The most-rated Kindle in the Electronics catalog: its reviews, verified count and mean rating by year?**

```sql
SELECT toYear(ts) AS year, count() AS reviews, countIf(verified_purchase) AS verified, round(avg(rating), 2) AS avg_rating
FROM amazon.reviews
WHERE parent_asin = (
  SELECT parent_asin FROM amazon.items
  WHERE category = 'Electronics' AND hasToken(title, 'Kindle')
  ORDER BY rating_number DESC LIMIT 1
)
GROUP BY year
ORDER BY year
LIMIT 20
```

The items subquery resolves the `parent_asin`, so the review read is the indexed point lookup; `verified` beside `reviews` is the per-year denominator pair. (verified 2026-09-25)

**Do low-star Software reviews hedge more than five-star ones?**

```sql
SELECT rating, count() AS reviews,
       countIf(scry_recipe('hedging', text)) AS hedged,
       round(hedged / reviews, 3) AS hedged_share
FROM amazon.reviews
WHERE category = 'Software' AND ts >= '2020-01-01'
GROUP BY rating
ORDER BY rating
LIMIT 5
```

One row per rating with the membership count of the shared `hedging` recipe over `text` and its share; read the recipe's `measurements` before treating membership as a classifier. (verified 2026-09-25)

## Traps

- Case: `hasToken` on `text` and `title` is exact-case; either spelling alone misses a share of mentions (measured 2026-09-25 on `Raspberry` in Electronics), so pass both through `hasAnyTokens`. `lower(text)` has no index here.
- Time: `ts` is the only clock on reviews and items have none; a window past the release's end is empty by construction, not absence.
- Unscoped scans: a `ts` range, a title prefix or a substring test without `category` or a key reads the relation; `main_category` in place of `category`; a bare `parent_asin` on items reads across categories (unambiguous today, measured 2026-09-25, but slower than the keyed read).
- Look-alike columns: `asin` is the variant reviewed and `parent_asin` the family that joins items; `category` (slug) is not `categories` (the item's path array) nor `main_category`; `average_rating` and `rating_number` are the upstream counters at snapshot time, not aggregates of the reviews held, so `avg(rating)` over reviews differs from them.
- No withdrawn state: the release is frozen, a review deleted upstream before it was never in it, and there is no review id; identity is (`parent_asin`, `user_id`, `ts`).
- Duplicates: a review key can briefly appear twice (`LIMIT 1 BY` the key); one book or product exists as several `parent_asin` rows (editions, bundles), so a title is not an identity.
- Encoding: `text` carries `<br />` tags and HTML entities on a share of rows (`replaceAll(text, '<br />', ' ')` before display); `images`, `price`, `videos`, `subtitle` and `author` are empty on most rows and `bought_together` throughout (the contract's `mostly_empty_columns`).

## Cross-family joins

- `amazon.reviews.parent_asin` joins `amazon.items.parent_asin`; bind `category` on both sides for the keyed read.
- Books items join `books.catalog` on `has(isbn13, replaceAll(JSONExtractString(details, 'ISBN 13'), '-', ''))`; a print edition's `parent_asin` is often its ISBN-10.
- `user_id` is an opaque reviewer id that joins no other relation; `persons.links` does not cover it.
