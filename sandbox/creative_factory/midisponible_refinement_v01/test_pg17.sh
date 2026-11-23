#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:?}" "${PGDATABASE:?}" "${PGUSER:?}"
if [[ "${PGHOST}" != "127.0.0.1" || "${PGDATABASE}" != "saly_midisponible_refinement_test" ]]; then
 echo 'SALY_REFINEMENT_DISPOSABLE_PG17_ONLY'; exit 2
fi
version="$(psql -XAt -v ON_ERROR_STOP=1 -c 'SHOW server_version_num')"
if [[ "${version:0:2}" != 17 ]]; then echo "SALY_REFINEMENT_PG17_REQUIRED ${version}"; exit 2; fi

# L2A actual trigger bodies + historical tables/identity from approved PR #4648.
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/order_sequence_v02/fixture_pg17_live_l2a.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123061613_lf_saly_creative_single_screen_sequence_v2.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 <<'SQL'
ALTER TABLE saly.creative_order_items ADD COLUMN required boolean NOT NULL DEFAULT true;
-- Repair preflight checks exact RPC presence, without any Native execution.
CREATE FUNCTION saly.creative_chat_begin_pending_v1(text,text[],text,text,jsonb)
RETURNS jsonb LANGUAGE sql AS 'SELECT ''{}''::jsonb';
SQL
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123170239_lf_saly_creative_intake_literal_semantic_repair_v1.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123191500_lf_saly_home_midisponible_refinement_draft_v1.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/midisponible_refinement_v01/validate_pg17.sql
echo 'SALY_MIDISPONIBLE_REFINEMENT_DRAFT_PG17_PASS'
