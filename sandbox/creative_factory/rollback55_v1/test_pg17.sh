#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:?}" "${PGDATABASE:?}" "${PGUSER:?}"
if [[ "$PGHOST" != "127.0.0.1" || "$PGDATABASE" != "saly_rollback55_test" ]]; then
  echo 'NON_DISPOSABLE_DATABASE_FORBIDDEN'; exit 2
fi
if [[ "$(psql -XAt -v ON_ERROR_STOP=1 -c 'SHOW server_version_num' | cut -c 1-2)" != "17" ]]; then
  echo 'POSTGRES17_REQUIRED'; exit 2
fi
echo 'INPUT_00: exact live SELECT snapshot fixture, 55 versions + 3 orders + 3 items'
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/rollback55_v1/fixture_pg17.sql >/dev/null
echo 'OUTPUT_00: fixture loaded'
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/rollback55_v1/test_transaction_rollback_pg17.sql | tee /tmp/saly55_rollback_trace.log
grep -F 'STEP08_OUTPUT_AFTER_ROLLBACK|' /tmp/saly55_rollback_trace.log >/dev/null || exit 1
grep -F '"simulated_context_rows": 0' /tmp/saly55_rollback_trace.log >/dev/null || exit 1
grep -F '"order9_context_set_id": 3' /tmp/saly55_rollback_trace.log >/dev/null || exit 1
grep -F '"handoff_temp_table_exists": false' /tmp/saly55_rollback_trace.log >/dev/null || exit 1
echo 'PASS_SALY_55_TOKEN_SINGLE_TRANSACTION_ROLLBACK_NO_PERSISTENCE'
