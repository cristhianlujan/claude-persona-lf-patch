#!/usr/bin/env bash
# PG17 only, disposable local DB. NO Supabase/production credentials or writes.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${PGHOST:?}" "${PGUSER:?}" "${PGDATABASE:?}"
if [[ "${PGDATABASE}" != 'saly_queue_test' || ( "${PGHOST}" != '127.0.0.1' && "${PGHOST}" != 'localhost' ) ]]; then
  echo 'BLOCK_NON_DISPOSABLE_POSTGRES'; exit 2
fi
if [[ -n "${PGPASSWORD:-}" || -n "${LF_SUPABASE_DB_PASSWORD:-}" ]]; then
  echo 'BLOCK_TEST_DB_CREDENTIAL_ENV'; exit 2
fi
psql -X -v ON_ERROR_STOP=1 -qAt -c "SELECT current_setting('server_version_num')" | grep -qE '^17[0-9]{4}$' || {
  echo 'BLOCK_PG17_REQUIRED'; exit 2;
}
echo 'PG17 disposable fixture: begin'
(
 cd "$ROOT/queue_v02"
 psql -X -v ON_ERROR_STOP=1 -q -f fixture_pg17.sql >/dev/null
)
(
 cd "$ROOT/queue_v05"
 psql -X -v ON_ERROR_STOP=1 -q -f 001_saly_native_render_wire_candidate.sql >/dev/null
 psql -X -v ON_ERROR_STOP=1 -q -f test_pg17_candidate.sql
)
echo 'PASS_SALY_NATIVE_RENDER_WIRE_PG17_DISPOSABLE_ROLLBACK'
