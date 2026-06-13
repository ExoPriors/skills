# Scry Access And Runtime

Use this reference when authentication, anonymous bootstrap, x402 payment,
congestion pricing, receipts, delegated authorization, or runtime behavior
matters. For live truth, prefer `GET /v1/scry/context`,
`GET /v1/scry/pricing`, `GET /v1/scry/account`, and
`GET /v1/scry/schema` over static text.

## Canonical Key Contract

- Canonical environment variable: `SCRY_API_KEY`.
- Request header: `Authorization: Bearer $SCRY_API_KEY`.
- Anonymous bootstrap key format: `scry_anon_*` from
  `POST /v1/scry/anonymous-key`.
- Recommended anonymous client header:
  `X-Scry-Client-Tag: <short-stable-tag>`.

Recommended default for less-technical users: store `SCRY_API_KEY` once in
`~/.scry/.env`. A launch-directory `./.env` can supply project settings, but
`~/.scry/.env` wins for the durable Scry key.

```bash
mkdir -p "$HOME/.scry"
chmod 700 "$HOME/.scry"
umask 077
printf '%s\n' 'SCRY_API_KEY=<your key>' > "$HOME/.scry/.env"
set -a
[ -f ./.env ] && . ./.env
[ -f "$HOME/.scry/.env" ] && . "$HOME/.scry/.env"
[ ! -f "$HOME/.scry/.env" ] && [ -f "$HOME/.scry/env" ] && . "$HOME/.scry/env"
set +a
```

Treat embedded bearer keys as local secrets. Keep them out of repositories,
public prompts, shared transcripts, screenshots, and durable global agent
context.

Use anonymous bootstrap for immediate discovery. Switch to a personal key in
`~/.scry/.env` when the session needs durable vector handles, shares, receipts,
spend controls, or continuity across agent restarts.

## No Key Present: Onboarding

When `SCRY_API_KEY` is missing after the canonical env load, do both:

1. Continue immediately: mint an anonymous bootstrap key and run bounded
   discovery (see Anonymous Public Trial below).
2. Tell the user once, plainly: a free account at https://scry.io/#console
   issues a personal Scry API key. Store it as one line `SCRY_API_KEY=...`
   in `~/.scry/.env`, or paste it into the session and the agent persists it
   there.

Do not block discovery on signup. Repeat the pointer only when work hits an
anonymous limit (degraded rows, `401`/`402`/`429`) or the user asks for
durable artifacts: shares, receipts, durable @handles, spend controls, or
continuity across restarts.

## Durable Bootstrap Paths

1. **Console (human-backed):** the user creates a free account at
   https://scry.io/#console and copies a personal Scry API key (or a setup
   prompt embedding it); the agent persists it to `~/.scry/.env`.
2. **Operator-provisioned:** a signed-in human calls `POST /v1/auth/api-keys`,
   creates a Scry-scoped key, and gives the secret to the agent.
3. **Wallet-native:** an agent with an EVM wallet calls
   `POST /v1/auth/agent/signup`; the response returns a session token plus API
   key.

All paths end with the same bearer-key contract.

## Anonymous Public Trial

Use anonymous bootstrap for immediate public access without signup. It is meant
for fast trial access; sustained usage should use a personal Scry API key.

```bash
CLIENT_TAG="${SCRY_CLIENT_TAG:-dev-laptop}"
ANON_KEY="$(curl -s https://api.scry.io/v1/scry/anonymous-key \
  -X POST \
  -H "X-Scry-Client-Tag: $CLIENT_TAG" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["api_key"])')"

curl -s https://api.scry.io/v1/scry/schema \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "X-Scry-Client-Tag: $CLIENT_TAG"
```

Keep the same `X-Scry-Client-Tag` on the same device while anonymous so access
stays reliable across requests from the same device. After minting an anonymous
key, reuse the same client tag on schema, search, and query requests; your
anonymous session stays reliable even if a later request is missing the key or
uses a new one.
Anonymous keys can also call `POST /v1/scry/embed`,
`GET /v1/scry/vectors`, and `DELETE /v1/scry/vectors/{name}`. Handles stay
bound to the anonymous session rather than a durable account namespace.

## Packaged Skill Freshness

```bash
npx skills add exopriors/skills
npx skills update
```

At session start, call:

```bash
curl -s "https://api.scry.io/v1/scry/context?skill_generation=2026061301" \
  -H "Authorization: Bearer $SCRY_API_KEY"
```

If the response includes `should_update_skill=true`, tell the user to run
`npx skills update`. If `client_skill_generation` is `null` while this packaged
skill is active, or local instructions still point to legacy ExoPriors hostnames
or legacy console routes, stop and update skills before deeper debugging.

## Congestion Pricing

Primary controls:

- Authenticated queries have no daily quota. Use eager or patient mode to choose
  how you respond to congestion pricing; ordinary rate limits also apply.
- `X-Scry-Budget: <nanodollars>` is optional. It sets an eager-bid cap and an
  x402 funding hint; authenticated queries do not need it.
- `X-Scry-Max-Exposure: <nanodollars>` caps runtime exposure for the query.
- `GET /v1/scry/account` is the one-stop billing status check: wallet, mode,
  spend, live base fee, utilization, and auto-topup state.
- `GET /v1/scry/preferences` returns `pricing_mode` and
  `max_bid_multiplier`.
- `PATCH /v1/scry/preferences` changes `pricing_mode` and bid multiplier.
- `pricing_mode: "eager"` bids into admission during congestion.
- `pricing_mode: "patient"` waits FIFO at base price.
- `GET /v1/scry/price` returns current `base_fee`, `utilization`,
  `load_pressure`, `recommended_max_fee`, and epoch metadata.
- `GET /v1/scry/price/history` compares the current epoch to recent history.
- `GET /v1/scry/pricing` is the live billing and market authority.
- `POST /v1/scry/estimate` returns estimate, reserve, authorized exposure,
  exposure timeout, and cost breakdown.

In eager mode, Scry uses uniform clearing: winners pay the epoch clearing price,
not every winner's submitted maximum. `max_bid_multiplier` clamps the effective
eager bid before admission.

If a congestion-priced query runs into its spend envelope, the API returns
`402` with `query_exposure_exhausted`. Narrow the query, switch to patient
mode, or use eager mode only when the broader query is worth the congestion
price; do not retry the same request unchanged.

## Receipts

Use receipts when the user needs durable provenance for execution cost, SQL
fingerprint, runtime, billing, or security details.

- `POST /v1/scry/query?receipt=summary` returns stable id, SQL fingerprint,
  and main cost/runtime facts inline.
- `POST /v1/scry/query?receipt=full` returns estimate, billing, execution, and
  structured security details inline.
- `GET /v1/scry/query-receipts` lists recent receipts for the authenticated
  caller.
- `GET /v1/scry/query-receipts/{id}` rehydrates a durable query receipt.
- Add `?include_sql=true` only when the owner explicitly needs the original SQL
  back.

Useful query response headers:

- `x-scry-cost`
- `x-scry-receipt-id`
- `x-scry-authorized-exposure`
- `x-scry-reserved`
- `x-scry-exposure-timeout-ms`
- `x-scry-eager-multiplier-accepted`
- `x-scry-eager-multiplier-charged`
- `x-scry-admission`
- `x-scry-admission-wait-ms`
- `X-Scry-Base-Fee`
- `X-Scry-Priority-Fee`
- `X-Scry-Compute-Units`
- `X-Scry-Utilization`
- `X-Scry-Epoch`

## Funding Rails

Live funding rails:

- x402 direct query payment;
- browser Stripe checkout;
- delegated Stripe saved-method funding;
- crypto topup.

These identifiers are not yet live funding rails: `stripe_acp`, `ap2`,
`visa_tap`, and `mastercard_agent_pay`.

Common card surfaces:

- `POST /v1/billing/checkout/custom`: safe default browser checkout URL.
- `POST /v1/billing/setup-payment-method`: one operator browser visit to save a
  card.
- `POST /v1/billing/agent-topup`: charges a saved payment instrument and
  requires `X-Scry-Subject-Agent` plus an active capped `agent_topup` mandate.
- `GET /v1/billing/auto-topup` and `PATCH /v1/billing/auto-topup`: Stripe-backed
  replenishment into paid balance.
- `GET /v1/billing/auto-topup/eligibility`: reports whether recurring
  saved-method funding is available, and what is needed if not.
- `GET /v1/billing/payment-instruments`: lists saved payment methods.
- `GET /v1/billing/payment-mandates`: lists delegated funding/query mandates.
- `GET /v1/billing/pricing`: returns available credit pricing tiers.

Check `GET /v1/scry/account` and its `funding.card_funding` block to see which
card paths are available.

## Delegated Agent Policy

`X-Scry-Subject-Agent: <agent-id>` activates delegated query policy. If the
authenticated account has a matching active `query_access` mandate, Scry applies
that mandate's `max_query_exposure` cap and returns a
`delegated_authorization` object. Without a matching mandate, `/v1/scry/query`
fails with `delegated_authorization_required`.

The same header selects delegated stored-card topup authority on
`POST /v1/billing/agent-topup`.

## x402 Query-Only Access

`POST /v1/scry/query` supports standard x402 as an explicit paid path. Use it
when the caller already has an x402-capable client or wallet and only wants
direct paid query execution.

If x402 is enabled and the request has no `Authorization` header, the first
unsigned query returns `402 Payment Required` with machine-readable payment
requirements. When the caller also sends `X-Scry-Budget`, Scry treats it as an
x402 funding hint subject to the configured base quantum. After settlement, the
paid amount converts into paid balance. Scry queries spend Scry credits first
and paid balance second; provider-backed work requires paid balance.

Minimal client shape:

```js
import { wrapFetchWithPayment } from 'x402-fetch';

const paidFetch = wrapFetchWithPayment(fetch, walletClient);
const resp = await paidFetch('https://api.scry.io/v1/scry/query', {
  method: 'POST',
  headers: { 'content-type': 'text/plain' },
  body: 'SELECT 1 LIMIT 1',
});
```

For schema/context, shares, judgements, feedback, or repeated multi-endpoint
usage, prefer a personal Scry API key.
