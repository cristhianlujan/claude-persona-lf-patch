#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T12|FAIL unsafe'; exit 2; }
psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
BEGIN;
DO $$
DECLARE p text:='CI LF F1 sealed prompt';h text;review jsonb;cl jsonb;pkt jsonb;vis jsonb;snap jsonb;adm jsonb;wire jsonb;res jsonb;tok uuid;rid bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM saly.creative_orders o JOIN saly.proyecto p ON p.id=o.project_id WHERE o.id=25 AND p.codigo='LF' AND o.id<>23)
 THEN RAISE EXCEPTION 'T12_ALTERNATE_LF_ORDER_MISSING'; END IF;
 h:=encode(extensions.digest(convert_to(p,'UTF8'),'sha256'),'hex');
 review:=jsonb_build_object('prompt_sha256',h,'verdict','PASS','checks',jsonb_build_array(
  jsonb_build_object('code','PROMPT_LITERAL_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_IDENTITY_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_CONTEXT_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_HASH_MATCH','verdict','PASS','evidence','CI')));
 PERFORM saly.creative_lf_prompt_seal_v1(2501,p,'GPT_NATIVE','CLAUDE_NATIVE',review);
 cl:=saly.creative_queue_claim_by_id_v1(25,'T12_WORKER',86400);tok:=(cl->>'claim_token')::uuid;
 pkt:=saly.creative_item_work_packet_l2c(2501);vis:=saly.creative_item_visual_contract_l3b(2501);
 snap:=(pkt->'input_snapshot')||jsonb_build_object('visual_contract',vis->'contract','visual_contract_sha256',vis->>'contract_sha256');
 adm:=saly.creative_queue_admit_run_v1(tok,1,'T12-RUN-1',snap);rid:=(adm->>'run_id')::bigint;
 PERFORM saly.creative_queue_advance_run_v1(tok,rid,'EJECUTANDO');
 wire:=saly.creative_native_render_wire_v1(tok,rid,'CLAUDE_NATIVE');
 res:=saly.creative_queue_native_reserve_dispatch_v1(tok,rid,'CLAUDE_NATIVE',wire->>'wire_sha256',wire->>'wire_sha256','T12-REQ-1');
 IF res->>'status'<>'RESERVED_NOT_DISPATCHED' OR wire->>'business_code'<>'LF' OR wire->>'order_id'<>'25'
 THEN RAISE EXCEPTION 'T12_NOT_FULL_PASS'; END IF;
END $$;
ROLLBACK;
SQL
echo 'T12|PASS'
