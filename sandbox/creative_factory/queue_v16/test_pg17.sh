#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:?}" "${PGDATABASE:?}" "${PGUSER:?}"
if [[ "${PGHOST}" != "127.0.0.1" || "${PGDATABASE}" != "saly_chat_gate_v16_test" ]]; then
 echo 'CREATIVE_V16_NON_DISPOSABLE_DB_FORBIDDEN'; exit 2
fi
if [[ "$(psql -XAt -v ON_ERROR_STOP=1 -c 'SHOW server_version_num' | cut -c 1-2)" != 17 ]]; then
 echo 'CREATIVE_V16_PG17_REQUIRED'; exit 2
fi
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v16/fixture_pg17.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123064000_lf_saly_creative_serial_queue_infrastructure_v1.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v16/wire_dependencies_pg17.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123064300_lf_saly_creative_native_render_wire_infrastructure_v1.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v16/live_terminal_guards_pg17.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123084800_lf_saly_creative_chat_entry_qa_gate_v1.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v16/test_single_screen_sequence_pg17.sql
psql -XAt -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM saly.creative_orders o WHERE o.code IN ('SALY_HOME_V015_SINGLE_20261123','SALY_ADELANTO_V015_SINGLE_20261123') AND o.status='TERMINADO'" | grep -qx 2 || {
 echo 'CREATIVE_V16_SINGLE_TERMINAL_READBACK_FAIL'; exit 1; }
echo 'PASS_V16_PG17_SINGLE_SCREEN_SERIAL_AND_INDEPENDENT_QA_TERMINAL'
