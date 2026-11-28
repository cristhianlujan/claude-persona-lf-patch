#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T10|FAIL unsafe'; exit 2; }
psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
BEGIN;
UPDATE saly.creative_order_items SET acceptance_json=acceptance_json-'semantic_qa' WHERE id=2501;
DO $$
DECLARE cl jsonb;tok uuid;
BEGIN
 cl:=saly.creative_queue_claim_by_id_v1(25,'T10_WORKER',86400);tok:=(cl->>'claim_token')::uuid;
 BEGIN
  PERFORM saly.creative_queue_admit_run_v1(tok,1,'T10-RUN-1','{}'::jsonb);
  RAISE EXCEPTION 'T10_DID_NOT_BLOCK';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'LF_RUN_SEMANTIC_QA_REQUIRED' THEN RAISE EXCEPTION 'T10_WRONG_ERROR:%',SQLERRM; END IF;
 END;
END $$;
ROLLBACK;
SQL
echo 'T10|PASS'
