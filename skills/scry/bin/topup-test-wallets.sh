#!/bin/bash
# Test-wallet top-up rail: restores each pricing-lane TEST account below to exactly $20 of
# scry_credit (operator-sized 2026-09-09) and $10 of promo_credit (operator 2026-09-10: "fund our
# test accounts so we can test things" — provider inference arms from promo_credit + cash only,
# provider_keys.rs spendable_provider_nanodollars, so scry_credit alone never exercises the MCP
# chat / creativity doors) with the same wallet_events + wallet_entries grant pair the signup path
# writes, under the wallet's advisory lock. Never above the targets, never a customer.
# Doctrine and the operator's words: skills/scry/SKILL.md § Test wallets.
set -eu
SCRY_TARGET=${SCRY_TARGET:-20000000000}    # $20 scry_credit — her sizing for the two test accounts
PROMO_TARGET=${PROMO_TARGET:-10000000000}  # $10 promo_credit — the promo default; real provider exposure, bounded here
declare -a USERS=(
  "55fbd76f-4113-4a67-aebd-c4cc082f1127 acct1 SCRY_TEST_API_KEY"
  "2b643878-5136-45d7-bb88-4a1f6b74578f acct2 SCRY_TEST2_API_KEY"
)
stamp=$(python3 -c 'import time;print(time.strftime("%Y%m%d%H%M%S",time.gmtime()))')
for entry in "${USERS[@]}"; do
  set -- $entry; uid=$1; name=$2
  sql="BEGIN;
SELECT pg_advisory_xact_lock(credit_lock_key('$uid'));"
  for pair in "scry_credit $SCRY_TARGET" "promo_credit $PROMO_TARGET"; do
    set -- $pair; bucket=$1; target=$2
    sql="$sql
WITH bal AS (
  SELECT COALESCE((SELECT balance_nanodollars FROM wallet_balances WHERE user_id='$uid' AND bucket='$bucket'), 0) AS b
), ev AS (
  INSERT INTO wallet_events (user_id, api_key_id, kind, idempotency_key, source, related_object, notes)
  SELECT '$uid', NULL, 'grant', 'test_topup_${bucket}_${stamp}', 'test_wallet_topup', 'pricing-lane drills',
         'Test-wallet top-up of $bucket (agent rail; test account, not a customer)'
  FROM bal WHERE b < $target
  RETURNING id
)
INSERT INTO wallet_entries (event_id, user_id, bucket, delta_nanodollars)
SELECT ev.id, '$uid', '$bucket', $target - bal.b FROM ev, bal;"
  done
  sql="$sql
COMMIT;
SELECT '$name ' || string_agg(bucket || '=' || balance_nanodollars, ' ' ORDER BY bucket) FROM wallet_balances WHERE user_id='$uid' AND bucket IN ('scry_credit','promo_credit');"
  ssh colo2 "sudo -n -u postgres psql -p 25432 -h /var/run/postgresql -At -q -v ON_ERROR_STOP=1 -d keep_db" <<< "$sql"
done
