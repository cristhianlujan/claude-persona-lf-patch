#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T11|FAIL unsafe'; exit 2; }
psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
BEGIN;
INSERT INTO saly.creative_orders(id,project_id,code,request_key,title,request_kind,design_mode,requested_by,scope_json,identity_snapshot,status,context_set_id)
OVERRIDING SYSTEM VALUE VALUES
(9211,3,'LF_F1_T11_ORDER','lf-f1-t11','T11 pending semantic QA','APP_SCREEN_SINGLE','EXPLORE','CI_F1',
 jsonb_build_object('queue_mode','SERIAL_V1','review_only',false,'render_authorized',true,'rendering_authority',true,
   'literal_request','CI LF F1 synthetic request','original_literal_request','CI LF F1 synthetic request'),
 '{}'::jsonb,'PLANIFICADO',9001);
INSERT INTO saly.creative_order_items(id,order_id,code,ordinal,kind,title,required,acceptance_json,context_json,status)
OVERRIDING SYSTEM VALUE
SELECT 92111,9211,'LF_F1_T11_SCREEN',1,'SCREEN','T11',true,
       jsonb_set(acceptance_json,'{semantic_qa}','{"status":"PENDING"}'::jsonb,true),context_json,'PENDIENTE'
FROM saly.creative_order_items WHERE id=2501;
DO $$
DECLARE cl jsonb;tok uuid;
BEGIN
 cl:=saly.creative_queue_claim_by_id_v1(9211,'T11_WORKER',86400);tok:=(cl->>'claim_token')::uuid;
 IF cl->>'status'<>'CLAIMED' THEN RAISE EXCEPTION 'T11_CLAIM:%',cl; END IF;
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
