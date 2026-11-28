#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T05|FAIL unsafe'; exit 2; }
psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
BEGIN;
DO $$
DECLARE p text:='CI LF F1 sealed prompt';h text;review jsonb;cl jsonb;pkt jsonb;vis jsonb;snap jsonb;adm jsonb;wire jsonb;res jsonb;tok uuid;rid bigint;
BEGIN
 h:=encode(extensions.digest(convert_to(p,'UTF8'),'sha256'),'hex');
 review:=jsonb_build_object('prompt_sha256',h,'verdict','PASS','checks',jsonb_build_array(
  jsonb_build_object('code','PROMPT_LITERAL_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_IDENTITY_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_CONTEXT_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_HASH_MATCH','verdict','PASS','evidence','CI')));
 PERFORM saly.creative_lf_prompt_seal_v1(2501,p,'GPT_NATIVE','CLAUDE_NATIVE',review);
 cl:=saly.creative_queue_claim_by_id_v1(25,'T05_WORKER',86400);tok:=(cl->>'claim_token')::uuid;
 IF cl->>'status'<>'CLAIMED' THEN RAISE EXCEPTION 'T05_CLAIM:%',cl; END IF;
 pkt:=saly.creative_item_work_packet_l2c(2501);vis:=saly.creative_item_visual_contract_l3b(2501);
 snap:=(pkt->'input_snapshot')||jsonb_build_object('visual_contract',vis->'contract','visual_contract_sha256',vis->>'contract_sha256');
 adm:=saly.creative_queue_admit_run_v1(tok,1,'T05-RUN-1',snap);rid:=(adm->>'run_id')::bigint;
 PERFORM saly.creative_queue_advance_run_v1(tok,rid,'EJECUTANDO');
 wire:=saly.creative_native_render_wire_v1(tok,rid,'GPT_NATIVE');
 res:=saly.creative_queue_native_reserve_dispatch_v1(tok,rid,'GPT_NATIVE',wire->>'wire_sha256',wire->>'wire_sha256','T05-REQ-1');
 IF wire->>'status'<>'RENDER_WIRE_FROZEN_AUTHORIZED' OR wire->>'native_transmitted'<>'false'
 OR res->>'status'<>'RESERVED_NOT_DISPATCHED' OR res->>'native_transmitted'<>'false'
 OR res->>'dispatch_authorized'<>'false'
 OR (SELECT state FROM saly.creative_runs WHERE id=rid)<>'EJECUTANDO'
 THEN RAISE EXCEPTION 'T05_PIPELINE_INVALID wire=% reserve=%',wire,res; END IF;
END $$;
ROLLBACK;
SQL
echo 'T05|PASS'
