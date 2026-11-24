#!/usr/bin/env bash
set -euo pipefail
if [[ "${PGHOST:-}" != '127.0.0.1' || "${PGDATABASE:-}" != 'saly_pr2_owner_pg17' ]]; then echo 'FAIL_DISPOSABLE_PG17_ONLY'; exit 2; fi
[[ "$(psql -XAt -c 'SHOW server_version_num' | cut -c1-2)" == '17' ]] || { echo 'FAIL_POSTGRES17_REQUIRED'; exit 2; }
echo 'PR2_INPUT|fixture exact K01-K06 + production guard function copies on PG17 only'
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/k_task_v2/fixture_live_knowledge_pg17.sql >/dev/null
echo 'PR2_PR1_DEPENDENCY_INPUT|apply PR1 233000 only in disposable PG17'
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/k_task_v2/abc_pr1_dependency_snapshot_233000.sql >/dev/null
psql -XAt -v ON_ERROR_STOP=1 -c "SELECT 'PR2_DEPENDENCY_OUTPUT|'||jsonb_build_object('pr1_k_selection',to_regclass('saly.creative_task_selection_v2') IS NOT NULL,'pr1_ready',to_regprocedure('saly.creative_run_image_readback_v2(bigint,bigint)') IS NOT NULL)::text"
echo 'PR2_FIXTURE_INPUT|clone real pending 11/13 and 55 identity version rows'
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/k_task_v2/abc_live_pending_fixture_pg17.sql >/dev/null
psql -XAt -v ON_ERROR_STOP=1 -c "SELECT 'PR2_FIXTURE_READBACK|'||jsonb_build_object('item11',(SELECT status FROM saly.creative_order_items WHERE id=11),'item13',(SELECT status FROM saly.creative_order_items WHERE id=13),'tokens',(SELECT count(*) FROM saly.identity_versions))::text"
sed -e '/^BEGIN;$/d' -e '/^COMMIT;$/d' supabase/migrations/20261123234000_lf_saly_creative_owner_state_and_medium_v1.sql > /tmp/saly_abc_candidate_no_boundary.sql
echo 'PR2_SCHEMA_ROLLBACK_INPUT|BEGIN; exact PR2 candidate; ROLLBACK'
{ printf 'BEGIN;\n'; cat /tmp/saly_abc_candidate_no_boundary.sql; printf '\nROLLBACK;\n'; } > /tmp/pr2_schema_rollback.sql
psql -X -v ON_ERROR_STOP=1 -f /tmp/pr2_schema_rollback.sql > /dev/null
psql -XAt -v ON_ERROR_STOP=1 -c "SELECT 'PR2_SCHEMA_ROLLBACK_OUTPUT|'||jsonb_build_object('new_detection',to_regclass('saly.creative_run_detection_v1') IS NOT NULL,'new_token_confirm',to_regclass('saly.creative_token_medium_confirmations_v1') IS NOT NULL,'pr1_k_exists',to_regclass('saly.creative_task_selection_v2') IS NOT NULL)::text" | tee /tmp/pr2_schema_readback.txt
grep -F '"new_detection": false' /tmp/pr2_schema_readback.txt >/dev/null
grep -F '"new_token_confirm": false' /tmp/pr2_schema_readback.txt >/dev/null
grep -F '"pr1_k_exists": true' /tmp/pr2_schema_readback.txt >/dev/null
echo 'PR2_FUNCTIONAL_ROLLBACK_INPUT|PG17 copied item11, order8 and item13, 55 tokens, timer detection, owner approval, protected mediums and full ROLLBACK'
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/k_task_v2/abc_timer_palette_medium_rollback_pg17.sql 2>&1 | tee /tmp/pr2_functional.txt
grep -F 'PASS_ABC_TIMER_PALETTE_MEDIUM_REAL_PENDING_ROLLBACK' /tmp/pr2_functional.txt >/dev/null
grep -F '"item11": "PENDIENTE"' /tmp/pr2_functional.txt >/dev/null
grep -F '"item13": "PENDIENTE"' /tmp/pr2_functional.txt >/dev/null
grep -F '"detection_table_exists": false' /tmp/pr2_functional.txt >/dev/null
echo 'PR2_FORMAT_QA_INPUT|decode image bytes, compare aspect ratio, distinguish NO_EVALUADO'
PYTHONPATH=sandbox/creative_factory/k_task_v2 python3 -u -m unittest -v sandbox/creative_factory/k_task_v2/test_image_format_similarity_v1.py 2>&1 | tee /tmp/pr2_image_format.txt
echo 'PR2_OVER_PR1_PG17_ROLLBACK_PASS'
