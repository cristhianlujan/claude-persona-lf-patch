#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:?PGHOST required}" "${PGDATABASE:?PGDATABASE required}" "${PGUSER:?PGUSER required}"
if [[ "${PGHOST}" != "127.0.0.1" || "${PGDATABASE}" != "saly_queue_staging_test" ]]; then
  echo 'CREATIVE_QUEUE_TEST_NON_DISPOSABLE_DB'; exit 2
fi
if [[ "$(psql -X -At -v ON_ERROR_STOP=1 -c 'show server_version_num' | cut -c 1-2)" != "17" ]]; then
  echo 'CREATIVE_QUEUE_TEST_PG17_REQUIRED'; exit 2
fi
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v14/fixture_pg17.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123064000_lf_saly_creative_serial_queue_infrastructure_v1.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v14/test_queue_pg17.sql
psql -X -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO saly.creative_orders(code,status,scope_json,request_kind,created_at)
VALUES
('SYNTHETIC_JOB_A','PLANIFICADO',
 '{"queue_mode":"SERIAL_V1","review_only":false,"render_authorized":true,"rendering_authority":true}',
 'APP_SCREEN_SINGLE','2026-11-24T01:00:00Z'),
('SYNTHETIC_JOB_B','PLANIFICADO',
 '{"queue_mode":"SERIAL_V1","review_only":false,"render_authorized":true,"rendering_authority":true}',
 'APP_SCREEN_SINGLE','2026-11-24T02:00:00Z');
INSERT INTO saly.creative_order_items(order_id,code,ordinal,status)
SELECT id,'SCREEN',1,'LISTO' FROM saly.creative_orders
WHERE code IN ('SYNTHETIC_JOB_A','SYNTHETIC_JOB_B');
SQL
a="$(mktemp)"; b="$(mktemp)"; trap 'rm -f "$a" "$b"' EXIT
psql -X -At -v ON_ERROR_STOP=1 -c "SELECT saly.creative_queue_claim_next_v1('PHYSICAL_WORKER_A',NULL)->>'status'" > "$a" & p1=$!
psql -X -At -v ON_ERROR_STOP=1 -c "SELECT saly.creative_queue_claim_next_v1('PHYSICAL_WORKER_B',NULL)->>'status'" > "$b" & p2=$!
wait "$p1"; wait "$p2"
actual="$(cat "$a" "$b" | sort | tr '\n' ' ')"
if [[ "$actual" != "BUSY CLAIMED " ]]; then
  echo "CREATIVE_QUEUE_CONCURRENCY_FAIL:$actual"; exit 1
fi
readback="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM saly.creative_queue_claims_v1 WHERE state='ACTIVE'")"
[[ "$readback" == "1" ]] || { echo 'CREATIVE_QUEUE_DOUBLE_CLAIM'; exit 1; }
echo 'PASS_CREATIVE_QUEUE_STAGING_PG17_LIVE_DEPENDENCY_ACL_AND_2_WORKERS'
