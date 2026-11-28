#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T04|FAIL unsafe'; exit 2; }
psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
BEGIN;
DO $$
DECLARE p text:='CI LF F1 sealed prompt';h text;review jsonb;pkt jsonb;vis jsonb;snap jsonb;
BEGIN
 h:=encode(extensions.digest(convert_to(p,'UTF8'),'sha256'),'hex');
 review:=jsonb_build_object('prompt_sha256',h,'verdict','PASS','checks',jsonb_build_array(
  jsonb_build_object('code','PROMPT_LITERAL_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_IDENTITY_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_CONTEXT_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_HASH_MATCH','verdict','PASS','evidence','CI')));
 PERFORM saly.creative_lf_prompt_seal_v1(2501,p,'GPT_NATIVE','CLAUDE_NATIVE',review);
 pkt:=saly.creative_item_work_packet_l2c(2501);vis:=saly.creative_item_visual_contract_l3b(2501);
 snap:=(pkt->'input_snapshot')||jsonb_build_object('visual_contract',vis->'contract','visual_contract_sha256',vis->>'contract_sha256');
 snap:=jsonb_set(snap,'{screen_spec,screen}',to_jsonb('TAMPERED'::text),true);
 BEGIN
  PERFORM saly.creative_assert_run_snapshot_v1(2501,snap);
  RAISE EXCEPTION 'T04_DID_NOT_BLOCK';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_RUN_SNAPSHOT_NOT_CANONICAL' THEN RAISE EXCEPTION 'T04_WRONG_ERROR:%',SQLERRM; END IF;
 END;
END $$;
ROLLBACK;
SQL
echo 'T04|PASS'
