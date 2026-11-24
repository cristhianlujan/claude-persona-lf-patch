#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:?}" "${PGDATABASE:?}" "${PGUSER:?}"
if [[ "$PGHOST" != "127.0.0.1" || "$PGDATABASE" != "saly_k_task_v2_test" ]]; then
  echo 'DISPOSABLE_PG17_ONLY'; exit 2
fi
if [[ "$(psql -XAt -v ON_ERROR_STOP=1 -c 'SHOW server_version_num' | cut -c 1-2)" != "17" ]]; then
  echo 'POSTGRES17_REQUIRED'; exit 2
fi
echo 'INPUT_F0|Live K01-K06 doc bytes+evidence and knowledge_select_review_v1, original creative_run_expire_v1'
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/k_task_v2/fixture_live_knowledge_pg17.sql >/dev/null
echo 'OUTPUT_F0|EXACT_SOURCE_FIXTURE_LOADED'
echo 'INPUT_MIGRATION|candidate migration on disposable PostgreSQL 17, no SALY real'
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123233000_lf_saly_creative_k_task_orchestration_v2.sql >/dev/null
echo 'OUTPUT_MIGRATION|CANDIDATE_FUNCTIONS_COMPILED'
echo 'INPUT_SQL|BEGIN; A B C D F G H expiry; ROLLBACK'
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/k_task_v2/test_rollback_pg17.sql 2>&1 | tee /tmp/saly_k_v2_sql.log
grep -F 'PG17_SQL_TESTS_PASS' /tmp/saly_k_v2_sql.log >/dev/null
grep -F '"selection_rows": 0' /tmp/saly_k_v2_sql.log >/dev/null
grep -F '"result_rows": 0' /tmp/saly_k_v2_sql.log >/dev/null
grep -F '"preqa_rows": 0' /tmp/saly_k_v2_sql.log >/dev/null
echo 'INPUT_WAIT|simulated ready at 20,100,never and expirer NOT_EXPIRED'
PYTHONPATH=sandbox/creative_factory/k_task_v2 python3 -u -m unittest -v sandbox/creative_factory/k_task_v2/test_wait_after_dispatch_v2.py 2>&1 | tee /tmp/saly_k_v2_wait.log
echo 'INPUT_ABC_FIXTURE|copy real order8 item11, order9 item13, historical 5..10, 55 tokens'
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/k_task_v2/abc_live_pending_fixture_pg17.sql >/dev/null
echo 'OUTPUT_ABC_FIXTURE|COPY_READY_IN_ISOLATED_PG17'
sed -e '/^BEGIN;$/d' -e '/^COMMIT;$/d' supabase/migrations/20261123234000_lf_saly_creative_owner_state_and_medium_v1.sql > /tmp/saly_abc_candidate_no_boundary.sql
echo 'INPUT_ABC_ROLLBACK|BEGIN -> candidate functions and applies_to metadata -> item11 QA / delivery / TERMINADO / owner approve -> item11/13 medium -> ROLLBACK'
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/k_task_v2/abc_timer_palette_medium_rollback_pg17.sql 2>&1 | tee /tmp/saly_abc_v2.log
grep -F 'PASS_ABC_TIMER_PALETTE_MEDIUM_REAL_PENDING_ROLLBACK' /tmp/saly_abc_v2.log >/dev/null
grep -F '"item11": "PENDIENTE"' /tmp/saly_abc_v2.log >/dev/null
grep -F '"context100_exists": 0' /tmp/saly_abc_v2.log >/dev/null
grep -F '"detection_table_exists": false' /tmp/saly_abc_v2.log >/dev/null
grep -F '"owner_medium_confirmation_table_exists": false' /tmp/saly_abc_v2.log >/dev/null
echo 'INPUT_A_FORMAT|decode actual PNG bytes and compare aspect ratio of IPHONE16PRO (3% relative tolerance)'
PYTHONPATH=sandbox/creative_factory/k_task_v2 python3 -u -m unittest -v sandbox/creative_factory/k_task_v2/test_image_format_similarity_v1.py 2>&1 | tee /tmp/saly_image_ratio.log
echo 'PASS_PG17_SALY_TIMER_PALETTE_MEDIUM_ROLLBACK_AND_IMAGE_RATIO'
echo 'PASS_PG17_K_TASK_ROLLBACK_AND_WAIT_TESTS'
