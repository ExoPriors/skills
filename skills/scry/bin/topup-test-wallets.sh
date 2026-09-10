#!/bin/bash
# Test-wallet top-up rail: restores each pricing-lane TEST account below to exactly $20
# (operator-sized 2026-09-09) with the same wallet_events + wallet_entries grant pair the
# signup path writes, under the wallet's advisory lock. Never above $20, never a customer.
# Doctrine and the operator's words: skills/scry/SKILL.md § Test wallets.
set -eu
TARGET=${TARGET:-20000000000}   # $20, her sizing for the two test accounts — the ceiling for this rail
declare -a USERS=(
  "55fbd76f-4113-4a67-aebd-c4cc082f1127 acct1 SCRY_TEST_API_KEY"
  "2b643878-5136-45d7-bb88-4a1f6b74578f acct2 SCRY_TEST2_API_KEY"
)
stamp=$(python3 -c 'import time;print(time.strftime("%Y%m%d%H%M%S",time.gmtime()))')
for entry in "${USERS[@]}"; do
  set -- $entry; uid=$1; name=$2
  sql="BEGIN;
SELECT pg_advisory_xact_lock(credit_lock_key('$uid'));
WITH bal AS (
  SELECT COALESCE((SELECT balance_nanodollars FROM wallet_balances WHERE user_id='$uid' AND bucket='scry_credit'), 0) AS b
), ev AS (
  INSERT INTO wallet_events (user_id, api_key_id, kind, idempotency_key, source, related_object, notes)
  SELECT '$uid', NULL, 'grant', 'test_topup_${stamp}', 'test_wallet_topup', 'pricing-lane drills',
         'Test-wallet top-up to \$20 (operator-sized 2026-09-09; agent rail; test account, not a customer)'
  FROM bal WHERE b < $TARGET
  RETURNING id
)
INSERT INTO wallet_entries (event_id, user_id, bucket, delta_nanodollars)
SELECT ev.id, '$uid', 'scry_credit', $TARGET - bal.b FROM ev, bal;
COMMIT;
SELECT '$name spendable_scry_nanodollars=' || balance_nanodollars FROM wallet_balances WHERE user_id='$uid' AND bucket='scry_credit';"
  ssh colo2 "sudo -n -u postgres psql -p 25432 -h /var/run/postgresql -At -q -v ON_ERROR_STOP=1 -d keep_db" <<< "$sql"
done
