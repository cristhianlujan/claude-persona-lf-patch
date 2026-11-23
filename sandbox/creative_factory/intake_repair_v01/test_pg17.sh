#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:?}" "${PGDATABASE:?}" "${PGUSER:?}"
if [[ "$PGHOST" != "127.0.0.1" || "$PGDATABASE" != "saly_intake_repair_test" ]]; then
 echo 'BLOCK_NON_DISPOSABLE_PG17'; exit 2
fi
ver="$(psql -XAt -v ON_ERROR_STOP=1 -c 'SHOW server_version_num')"
if [[ "${ver:0:2}" != 17 ]]; then
 echo 'BLOCK_NOT_PG17'; exit 2
fi
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/intake_repair_v01/fixture_pg17.sql >/dev/null
# Real compiler grants are irrelevant; this exact PG17 fixture checks
# schema/source correction, the DB trigger and negative gate codes.
psql -X -v ON_ERROR_STOP=1 -c "CREATE FUNCTION saly.creative_chat_begin_pending_v1(text,text[],text,text,jsonb) RETURNS jsonb LANGUAGE sql AS 'SELECT jsonb_build_object(''status'',''FIXTURE_ONLY'')';" >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123105500_lf_saly_creative_intake_literal_semantic_repair_v1.sql
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/intake_repair_v01/test_pg17.sql
psql -XAt -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM saly.creative_orders WHERE request_kind='APP_SCREEN_SINGLE' AND NOT (scope_json ? 'literal_request') AND scope_json->>'intake_source_status'='MISSING_VERIFIED_USER_VISUAL_REQUEST'" | grep -qx '2'
psql -XAt -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM saly.creative_orders WHERE request_kind='APP_SCREEN_BATCH' AND code='LEGACY_BATCH_QUEUE_TEST' AND status='PLANIFICADO'" | grep -qx '1'
psql -XAt -v ON_ERROR_STOP=1 -c 'SELECT count(*) FROM saly.creative_runs' | grep -qx '0'
echo 'PASS_SALY_INTAKE_V1_PG17_SEMANTIC_SOURCE_REPAIR_AND_NEGATIVE_TESTS'
