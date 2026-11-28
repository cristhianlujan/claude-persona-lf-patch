#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T11|FAIL unsafe'; exit 2; }
psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
BEGIN;
UPDATE saly.creative_order_items SET acceptance_json=jsonb_set(acceptance_json,'{semantic_qa}','{"status":"PENDING"}'::jsonb,true) WHERE id=2501;
DO $$
DECLARE cl jsonb;tok uuid;
BEGIN
 cl:=saly.creative_queue_claim_by_id_v1(25,'T11_WORKER',86400);tok:=(cl->>'claim_token')::uuid;
 BEGIN
  PERFORM saly.creative_queue_admit_run_v1(tok,1,'T11-RUN-1','{}'::jsonb);
  RAISE EXCEPTION 'T11_DID_NOT_BLOCK';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'LF_SEMANTIC_QA_KEYS_INVALID' THEN RAISE EXCEPTION 'T11_WRONG_ERROR:%',SQLERRM; END IF;
 END;
END $$;
ROLLBACK;
SQL
echo 'T11|PASS'
