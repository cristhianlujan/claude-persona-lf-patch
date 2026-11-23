#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:?required}" "${PGDATABASE:?required}" "${PGUSER:?required}"
if [[ "${PGHOST}" != "127.0.0.1" || "${PGDATABASE}" != "saly_creative_chain_test" ]]; then
 echo 'CREATIVE_PG17_TEST_TARGET_FORBIDDEN'; exit 2
fi
v="$(psql -X -v ON_ERROR_STOP=1 -Atqc 'SHOW server_version_num')"
if [[ "${v:0:2}" != "17" ]]; then
 echo "CREATIVE_PG17_VERSION_REQUIRED got=${v}"; exit 2
fi
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/order_sequence_v01/fixture_pg17.sql
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123104500_lf_saly_creative_single_screen_sequence_v1.sql
psql -X -v ON_ERROR_STOP=1 <<'SQL'
DO $check$
DECLARE home bigint; next_id bigint;
BEGIN
 SELECT id INTO STRICT home FROM saly.creative_orders
  WHERE code='SALY_HOME_V015_SINGLE_20261123';
 SELECT id INTO STRICT next_id FROM saly.creative_orders
  WHERE code='SALY_ADELANTO_V015_SINGLE_20261123';
 IF (SELECT count(*) FROM saly.creative_orders WHERE request_kind='APP_SCREEN_SINGLE') <> 2
 OR (SELECT count(*) FROM saly.creative_order_items WHERE order_id IN(home,next_id))<>2
 OR (SELECT count(*) FROM saly.creative_order_items WHERE order_id=1)<>2
 OR NOT EXISTS(SELECT 1 FROM saly.creative_order_sequence_v1
   WHERE order_id=next_id AND depends_on_order_id=home)
 OR NOT saly.creative_order_sequence_dependency_met_v1(home)
 OR saly.creative_order_sequence_dependency_met_v1(next_id)
 OR (SELECT count(*) FROM saly.creative_runs)<>0
 THEN RAISE EXCEPTION 'CREATIVE_PG17_READBACK_FAILED'; END IF;
END $check$;
SQL
echo 'CREATIVE_PG17_SINGLE_SCREEN_CHAIN_PASS'
