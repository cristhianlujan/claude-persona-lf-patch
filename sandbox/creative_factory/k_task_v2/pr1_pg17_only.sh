#!/usr/bin/env bash
set -euo pipefail
if [[ "${PGHOST:-}" != '127.0.0.1' || "${PGDATABASE:-}" != 'saly_pr1_k_pg17' ]]; then echo 'FAIL_LOCAL_PG17_ONLY'; exit 2; fi
[[ "$(psql -XAt -c 'SHOW server_version_num' | cut -c1-2)" == '17' ]] || { echo 'FAIL_POSTGRES17_REQUIRED'; exit 2; }
echo 'PR1_INPUT|isolated fixture exact K01-K06, 10 evidence rows, original functions'
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/k_task_v2/fixture_live_knowledge_pg17.sql >/dev/null
echo 'PR1_FIXTURE_OUTPUT|LOADED'
sed -e '/^BEGIN;$/d' -e '/^COMMIT;$/d' supabase/migrations/20261123233000_lf_saly_creative_k_task_orchestration_v2.sql >/tmp/pr1_body.sql
{ printf 'BEGIN;\n'; cat /tmp/pr1_body.sql; printf '\nROLLBACK;\n'; } >/tmp/pr1_migration_rollback.sql
echo 'PR1_MIGRATION_INPUT|BEGIN; exact PR1 migration body; ROLLBACK;'
psql -X -v ON_ERROR_STOP=1 -f /tmp/pr1_migration_rollback.sql >/dev/null
psql -XAt -v ON_ERROR_STOP=1 -c "SELECT 'PR1_MIGRATION_ROLLBACK_OUTPUT|'||jsonb_build_object('selection_table',to_regclass('saly.creative_task_selection_v2') IS NOT NULL,'readback_fn',to_regprocedure('saly.creative_run_image_readback_v2(bigint,bigint)') IS NOT NULL)::text" | tee /tmp/pr1_schema_rb.txt
grep -F '"selection_table": false' /tmp/pr1_schema_rb.txt >/dev/null
grep -F '"readback_fn": false' /tmp/pr1_schema_rb.txt >/dev/null
echo 'PR1_FUNCTIONAL_INPUT|isolated apply then BEGIN/ROLLBACK positive and negative queries'
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123233000_lf_saly_creative_k_task_orchestration_v2.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/k_task_v2/test_rollback_pg17.sql 2>&1 | tee /tmp/pr1_functional.txt
grep -F 'PG17_SQL_TESTS_PASS' /tmp/pr1_functional.txt >/dev/null
grep -F '"result_rows": 0' /tmp/pr1_functional.txt >/dev/null
grep -F '"preqa_rows": 0' /tmp/pr1_functional.txt >/dev/null
echo 'PR1_WAIT_INPUT|READY at20/100, TIMEOUT180, invalid evidence and SQL binding'
PYTHONPATH=sandbox/creative_factory/k_task_v2 python3 -u -m unittest -v sandbox/creative_factory/k_task_v2/test_wait_after_dispatch_v2.py 2>&1 | tee /tmp/pr1_wait.txt
echo 'PR1_PG17_ROLLBACK_PASS'
