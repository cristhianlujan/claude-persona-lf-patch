#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T07|FAIL unsafe'; exit 2; }
calc() {
  local db="$1"
  PGDATABASE="$db" psql -XAt -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
CREATE TEMP TABLE t07_result(v text);
DO $$
DECLARE l2a jsonb;l2c jsonb;l3b jsonb;snap jsonb;cl jsonb;adm jsonb;wire jsonb;rj jsonb;tok uuid;rid bigint;
BEGIN
 l2a:=saly.creative_item_context_l2a(9101);
 l2c:=saly.creative_item_work_packet_l2c(9101);
 l3b:=saly.creative_item_visual_contract_l3b(9101);
 IF l2c->>'readiness_code'<>'READY_FOR_NATIVE_HANDOFF' OR l3b#>>'{contract,production_manifest,dispatch_readiness}'<>'READY_FOR_NATIVE_HANDOFF'
 THEN RAISE EXCEPTION 'T07_SALY_FIXTURE_NOT_READY'; END IF;
 snap:=(l2c->'input_snapshot')||jsonb_build_object('visual_contract',l3b->'contract','visual_contract_sha256',l3b->>'contract_sha256');
 cl:=saly.creative_queue_claim_by_id_v1(9100,'T07_WORKER',600);tok:=(cl->>'claim_token')::uuid;
 IF cl->>'status'<>'CLAIMED' THEN RAISE EXCEPTION 'T07_CLAIM:%',cl; END IF;
 adm:=saly.creative_queue_admit_run_v1(tok,1,'T07-RUN-1',snap);rid:=(adm->>'run_id')::bigint;
 PERFORM saly.creative_queue_advance_run_v1(tok,rid,'EJECUTANDO');
 wire:=saly.creative_native_render_wire_v1(tok,rid,'GPT_NATIVE');
 SELECT to_jsonb(r)-'created_at'-'updated_at'-'deadline_at'-'started_at'-'finished_at' INTO rj FROM saly.creative_runs r WHERE r.id=rid;
 INSERT INTO t07_result VALUES(encode(extensions.digest(convert_to(jsonb_build_object(
   'l2a',l2a,'l2c',l2c,'l3b',l3b,'run',rj,'wire',wire)::text,'UTF8'),'sha256'),'hex'));
END $$;
SELECT v FROM t07_result;
ROLLBACK;
SQL
}
base="$(calc lf_creative_f1_baseline | head -n1)"
cand="$(calc lf_creative_f1_candidate | head -n1)"
[[ "$base" =~ ^[0-9a-f]{64}$ && "$cand" == "$base" ]] || { echo "T07|FAIL base=$base candidate=$cand"; exit 1; }
echo 'T07|PASS'
