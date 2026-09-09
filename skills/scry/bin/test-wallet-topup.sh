#!/bin/bash
# Test-wallet top-up rail (operator 2026-09-09: "I shouldn't be having to think about test
# wallets. That is an automated thing"). Restores each Scry TEST account to exactly the
# $10 onboarding default — the same wallet_events + wallet_entries pair the signup grant
# writes (kind grant, bucket scry_credit; wallet_balances is trigger-maintained), under
# the wallet's advisory lock. Never more than the $10 default per grant, never a
# customer: the user ids below are the two pricing-lane test accounts
# (vault secret/scry/test-account-pricing-lanes and …-2). Run before every storm drill.
set -eu
TARGET=${TARGET:-10000000000}   # $10, the onboarding default — the ceiling for an agent grant
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
         'Test-wallet top-up to the \$10 onboarding default (agent rail; test account, not a customer)'
  FROM bal WHERE b < $TARGET
  RETURNING id
)
INSERT INTO wallet_entries (event_id, user_id, bucket, delta_nanodollars)
SELECT ev.id, '$uid', 'scry_credit', $TARGET - bal.b FROM ev, bal;
COMMIT;
SELECT '$name spendable_scry_nanodollars=' || balance_nanodollars FROM wallet_balances WHERE user_id='$uid' AND bucket='scry_credit';"
  ssh colo2 "sudo -n -u postgres psql -p 25432 -h /var/run/postgresql -At -q -v ON_ERROR_STOP=1 -d keep_db" <<< "$sql"
done
