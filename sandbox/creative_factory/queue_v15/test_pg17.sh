#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:?}" "${PGDATABASE:?}" "${PGUSER:?}"
if [[ "${PGHOST}" != '127.0.0.1' || "${PGDATABASE}" != 'saly_native_wire_v15_test' ]]; then
 echo 'BLOCK_WIRE_NON_DISPOSABLE_DB'; exit 2
fi
if [[ "$(psql -X -At -v ON_ERROR_STOP=1 -c 'SHOW server_version_num' | cut -c 1-2)" != "17" ]]; then
 echo 'BLOCK_WIRE_NON_PG17'; exit 2
fi
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v02/fixture_pg17.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v06/001_saly_delivery_attestation_guard_candidate.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v15/fixture_preprod_pg17.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123064300_lf_saly_creative_native_render_wire_infrastructure_v1.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v15/test_wire_pg17.sql
x="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM saly.creative_runs")"
[[ "$x" = "0" ]] || { echo 'CREATIVE_WIRE_FAKE_RUN'; exit 1; }
echo 'PASS_SALY_WIRE_V15_ISOLATED_PG17_GPT_CLAUDE_SIX_NEGATIVES_ROLLBACK'
