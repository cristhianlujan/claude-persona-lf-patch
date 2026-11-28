#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T06|FAIL unsafe'; exit 2; }
psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
BEGIN;
DO $$
DECLARE p text:='CI LF F1 sealed prompt';h text;review jsonb;cl jsonb;pkt jsonb;vis jsonb;snap jsonb;adm jsonb;wire jsonb;r1 jsonb;r2 jsonb;tok uuid;rid bigint;
BEGIN
 h:=encode(extensions.digest(convert_to(p,'UTF8'),'sha256'),'hex');
 review:=jsonb_build_object('prompt_sha256',h,'verdict','PASS','checks',jsonb_build_array(
  jsonb_build_object('code','PROMPT_LITERAL_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_IDENTITY_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_CONTEXT_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_HASH_MATCH','verdict','PASS','evidence','CI')));
 PERFORM saly.creative_lf_prompt_seal_v1(2501,p,'GPT_NATIVE','CLAUDE_NATIVE',review);
 cl:=saly.creative_queue_claim_by_id_v1(25,'T06_WORKER',86400);tok:=(cl->>'claim_token')::uuid;
 pkt:=saly.creative_item_work_packet_l2c(2501);vis:=saly.creative_item_visual_contract_l3b(2501);
 snap:=(pkt->'input_snapshot')||jsonb_build_object('visual_contract',vis->'contract','visual_contract_sha256',vis->>'contract_sha256');
 adm:=saly.creative_queue_admit_run_v1(tok,1,'T06-RUN-1',snap);rid:=(adm->>'run_id')::bigint;
 PERFORM saly.creative_queue_advance_run_v1(tok,rid,'EJECUTANDO');
 wire:=saly.creative_native_render_wire_v1(tok,rid,'GPT_NATIVE');
 r1:=saly.creative_queue_native_reserve_dispatch_v1(tok,rid,'GPT_NATIVE',wire->>'wire_sha256',wire->>'wire_sha256','T06-REQ-1');
 r2:=saly.creative_queue_native_reserve_dispatch_v1(tok,rid,'GPT_NATIVE',wire->>'wire_sha256',wire->>'wire_sha256','T06-REQ-1');
 IF r1->>'status'<>'RESERVED_NOT_DISPATCHED' OR r2->>'status'<>'ALREADY_RESERVED_NOT_DISPATCHED' THEN RAISE EXCEPTION 'T06_IDEMPOTENCY_STATUS'; END IF;
 BEGIN
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(tok,rid,'GPT_NATIVE',wire->>'wire_sha256',wire->>'wire_sha256','T06-REQ-2');
  RAISE EXCEPTION 'T06_REPLAY_DID_NOT_BLOCK';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_DISPATCH_RESERVATION_REPLAY_CONFLICT' THEN RAISE EXCEPTION 'T06_REPLAY_WRONG:%',SQLERRM; END IF;
 END;
 BEGIN
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(tok,rid,'GPT_NATIVE',repeat('0',64),wire->>'wire_sha256','T06-REQ-1');
  RAISE EXCEPTION 'T06_DRIFT_DID_NOT_BLOCK';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_DISPATCH_WIRE_DRIFT' THEN RAISE EXCEPTION 'T06_DRIFT_WRONG:%',SQLERRM; END IF;
 END;
END $$;
ROLLBACK;
SQL
echo 'T06|PASS'
