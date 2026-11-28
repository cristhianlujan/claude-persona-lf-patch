#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T01|FAIL unsafe'; exit 2; }
psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
BEGIN;
DO $$
DECLARE p text:='CI LF F1 sealed prompt'; h text; review jsonb; seal jsonb; l2a jsonb; l2c jsonb; l3b jsonb;
BEGIN
 h:=encode(extensions.digest(convert_to(p,'UTF8'),'sha256'),'hex');
 review:=jsonb_build_object('prompt_sha256',h,'verdict','PASS','checks',jsonb_build_array(
  jsonb_build_object('code','PROMPT_LITERAL_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_IDENTITY_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_CONTEXT_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_HASH_MATCH','verdict','PASS','evidence','CI')));
 seal:=saly.creative_lf_prompt_seal_v1(2501,p,'GPT_NATIVE','CLAUDE_NATIVE',review);
 l2a:=saly.creative_item_context_l2a(2501);
 l2c:=saly.creative_item_work_packet_l2c(2501);
 l3b:=saly.creative_item_visual_contract_l3b(2501);
 IF l2a->>'schema_version'<>'LF_CREATIVE_CONTEXT_L2A_V1' OR l2a->>'business_code'<>'LF'
 OR l2c->>'readiness_code'<>'READY_FOR_NATIVE_HANDOFF'
 OR l3b#>>'{contract,schema_version}'<>'LF_VISUAL_CONTRACT_L3B_V1'
 OR l3b#>>'{contract,production_manifest,dispatch_readiness}'<>'READY_FOR_NATIVE_HANDOFF'
 OR l3b#>>'{contract,production_manifest,prompt_sha256}' IS DISTINCT FROM h
 THEN RAISE EXCEPTION 'T01_LF_PIPELINE_NOT_CANONICAL'; END IF;
END $$;
ROLLBACK;
SQL
echo 'T01|PASS'
