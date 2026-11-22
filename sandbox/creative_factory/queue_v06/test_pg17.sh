#!/usr/bin/env bash
# PG17 disposable DB only. Does NOT connect to Supabase or use credentials.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${PGHOST:?}" "${PGUSER:?}" "${PGDATABASE:?}"
[[ "$PGDATABASE" == "saly_queue_test" ]] || { echo BLOCK_NON_DISPOSABLE_DB; exit 2; }
[[ "$PGHOST" == "127.0.0.1" || "$PGHOST" == "localhost" ]] || { echo BLOCK_REMOTE_DB; exit 2; }
[[ -z "${PGPASSWORD:-}" && -z "${LF_SUPABASE_DB_PASSWORD:-}" ]] || { echo BLOCK_DB_SECRET_ENV; exit 2; }
psql -XAt -v ON_ERROR_STOP=1 -c "show server_version_num" | grep -qE '^17[0-9]{4}$' || {
  echo BLOCK_PG17_REQUIRED; exit 2;
}
echo 'TEST_LEGACY_BASELINE_ON_DISPOSABLE_PG17'
bash "$ROOT/queue_v02/test_pg17.sh"
echo 'TEST_NATIVE_DELIVERY_GUARD_ON_FRESH_DISPOSABLE_PG17'
psql -X -v ON_ERROR_STOP=1 -q -f "$ROOT/queue_v02/fixture_pg17.sql" >/dev/null
psql -X -v ON_ERROR_STOP=1 -q -f "$ROOT/queue_v06/001_saly_delivery_attestation_guard_candidate.sql" >/dev/null
psql -X -v ON_ERROR_STOP=1 -q -f "$ROOT/queue_v06/test_attestation_pg17.sql"
python3 "$ROOT/queue_v06/test_mutations_pg17.py"
echo 'RESTORE_CANDIDATE_AFTER_MUTANTS'
psql -X -v ON_ERROR_STOP=1 -q -f "$ROOT/queue_v02/fixture_pg17.sql" >/dev/null
psql -X -v ON_ERROR_STOP=1 -q -f "$ROOT/queue_v06/001_saly_delivery_attestation_guard_candidate.sql" >/dev/null
psql -X -v ON_ERROR_STOP=1 -q -f "$ROOT/queue_v06/test_attestation_pg17.sql"
count="$(psql -XAt -v ON_ERROR_STOP=1 -c "select count(*) from saly.creative_queue_native_delivery_evidence_v1")"
[[ "$count" == "0" ]] || { echo BLOCK_TEST_ROLLBACK_LEAK; exit 1; }
echo 'PASS_NATIVE_DELIVERY_PG17_BASELINE_AND_ATTESTATION_ROLLBACK'
