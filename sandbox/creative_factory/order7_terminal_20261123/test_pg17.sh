#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:?}" "${PGDATABASE:?}" "${PGUSER:?}"
if [[ "${PGHOST}" != "127.0.0.1" || "${PGDATABASE}" != "saly_chat_terminal7_test" ]]; then
  echo 'NON_DISPOSABLE_DATABASE_FORBIDDEN'; exit 2
fi
if [[ "$(psql -XAt -v ON_ERROR_STOP=1 -c "SHOW server_version_num" | cut -c 1-2)" != 17 ]]; then
  echo 'PG17_REQUIRED'; exit 2
fi
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v16/fixture_pg17.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v16/live_terminal_guards_pg17.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/order7_terminal_20261123/prestate_negative_pg17.sql
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123230000_lf_saly_creative_chat_terminal_home7_item10_v1.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/order7_terminal_20261123/poststate_negative_pg17.sql
if psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123230000_lf_saly_creative_chat_terminal_home7_item10_v1.sql >/dev/null 2>&1; then
  echo 'REPLAY_UNEXPECTEDLY_ACCEPTED'; exit 1
fi
echo 'PASS_PG17_GOVERNED_HISTORICAL_HOME7_ITEM10_TERMINAL_NEGATIVES_AND_READBACK'
