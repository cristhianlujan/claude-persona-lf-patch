#!/usr/bin/env python3
"""LF #3779 L4B: runtime contract for promotion -> EXISTING IG semantic Validator.
Disposable PG18 only. Stub exposes the exact #3682 public API shape; it is NOT a
semantic model and never counts as semantic quality evidence.
"""
import json, os, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
HERE=ROOT/"sandbox/lf_contract_gate_test/rule_promotion_v1"
DB="lf_3779_l4b_validator_reuse_pg18"
M3=ROOT/"supabase/migrations/20261111182000_lf_rule_promotion_deterministic_judge_governed_v1.sql"
M4=ROOT/"supabase/migrations/20261111191000_lf_rule_promotion_native_semantic_review_gate_v1.sql"
N=0

def sql(src,db=DB):
    env=dict(os.environ)
    for k,v in dict(PGHOST="127.0.0.1",PGPORT="5432",PGUSER="postgres",PGPASSWORD="postgres").items():
        env.setdefault(k,v)
    p=subprocess.run(["psql","-X","-q","-A","-t","-v","ON_ERROR_STOP=1","-d",db],
        input=src,text=True,capture_output=True,env=env,timeout=240)
    if p.returncode:
        raise AssertionError("RAW_PG18_ERROR "+p.stderr[-5000:])
    out={}
    for line in p.stdout.splitlines():
        if "|" not in line: continue
        k,v=line.split("|",1)
        try: out[k]=json.loads(v)
        except ValueError: out[k]=v
    return out

def check(name,cond,raw):
    global N
    print("RAW_"+name+" "+json.dumps(raw,sort_keys=True,ensure_ascii=False,default=str),flush=True)
    if not cond: raise AssertionError("FAIL_"+name+" "+str(raw)[:2000])
    N+=1
    print("PASS_"+name,flush=True)

def bootstrap():
    sql("CREATE DATABASE "+DB+";",db="postgres")
    sql((HERE/"promotion_pg18_sandbox_fixture.sql").read_text())
    sql((HERE/"live_promotion_baseline_fixture.sql").read_text())
    sql("""CREATE TRIGGER trg_lf_rule_promotion_guard_v1
      BEFORE UPDATE OF estado ON lf_ops.reglas
      FOR EACH ROW EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();""")
    sql(M3.read_text())
    sql("""
CREATE TABLE public.l4b_ig_stub_state(
 id boolean primary key default true,
 receipt_status text not null,
 audit_verdict text,
 candidate_sha256 text
);
INSERT INTO public.l4b_ig_stub_state(id,receipt_status,audit_verdict,candidate_sha256)
VALUES(true,'SEMANTIC_CANDIDATE_VERIFICATION_REQUIRED',NULL,repeat('a',64));

CREATE OR REPLACE FUNCTION public.fn_input_governance_semantic_packet_v1(
 p_run_id bigint,p_validator_identity text,p_receipt_id bigint,p_ticket uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object(
  'schema_version','IG_SEMANTIC_MODEL_PACKET_V1',
  'status','READY_FOR_MODEL_CANDIDATE',
  'run_id',p_run_id,
  'handoff_receipt_id',p_receipt_id,
  'selected_families',jsonb_build_array('RATE_LIMIT','SESSION'),
  'family_evidence_count',47,
  'source_integrity_verified',true,
  'semantic_pass_authorized',false,
  'promotion_authorized',false,
  'db_packet_sha256',repeat('b',64))
$$;

CREATE OR REPLACE FUNCTION public.fn_input_governance_semantic_external_receipt_readback_v1(
 p_run_id bigint,p_validator_identity text,p_handoff_receipt_id bigint,
 p_ticket uuid,p_candidate_sha256 text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT CASE
  WHEN s.receipt_status='SEMANTIC_CANDIDATE_VERIFICATION_REQUIRED' THEN
   jsonb_build_object('status',s.receipt_status,'run_id',p_run_id,
    'model_candidate_verified',false,'auditor_verified',false,
    'promotion_authorized',false,'production_authorized',false)
  WHEN s.receipt_status='INDEPENDENT_SEMANTIC_VERDICT_REQUIRED' THEN
   jsonb_build_object('status',s.receipt_status,'run_id',p_run_id,
    'candidate_sha256',s.candidate_sha256,'candidate_evidence_receipt_id',101,
    'model_candidate_verified',true,'auditor_verified',false,
    'promotion_authorized',false,'production_authorized',false)
  ELSE
   jsonb_build_object('status','SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE',
    'run_id',p_run_id,'candidate_sha256',s.candidate_sha256,
    'candidate_evidence_receipt_id',101,'candidate_evidence_receipt_sha256',repeat('c',64),
    'independent_audit_receipt_id',202,'independent_audit_receipt_sha256',repeat('d',64),
    'audit_verdict',s.audit_verdict,'model_candidate_verified',true,'auditor_verified',true,
    'semantic_independence_credited',false,'official_write_authorized',false,
    'promotion_authorized',false,'production_authorized',false)
 END
 FROM public.l4b_ig_stub_state s WHERE s.id=true
$$;
""")
    sql(M4.read_text())

def case(receipt_status,audit_verdict=None,mutate_after_bind=False,security_bypass=False):
    candidate="a"*64
    mut=""
    if security_bypass:
        mut="""UPDATE lf_ops.reglas SET valor_config=jsonb_set(valor_config,'{auth_bypass}','true'::jsonb,true)
        WHERE codigo='RULE-TEST-001';
        UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(
          evidence_payload,'{input_governance,rule_source_sha256}',
          to_jsonb(public.lf_asset_snapshot_sha_v1('REGLA','RULE-TEST-001')),true)
        WHERE execution_id='EXEC-PARENT-TEST-001' AND step_id='input_validate';"""
    drift=""
    if mutate_after_bind:
        drift="UPDATE lf_ops.reglas SET descripcion=descripcion||' drift' WHERE codigo='RULE-TEST-001';"
    script=f"""BEGIN;
UPDATE public.l4b_ig_stub_state SET receipt_status={json.dumps(receipt_status)},
 audit_verdict={('NULL' if audit_verdict is None else json.dumps(audit_verdict))};
{mut}
SELECT 'REQUEST|'||public.lf_rule_promotion_request_v1(
 'EXEC-PARENT-TEST-001','RULE-TEST-001','L4B existing validator reuse')::text;
SELECT 'BIND|'||public.lf_rule_promotion_bind_ig_semantic_v1(
 'PROM-TEST',9001,'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:abcdef',
 7001,'00000000-0000-0000-0000-000000000001'::uuid,{json.dumps(candidate)})::text;
{drift}
SELECT 'VERIFY|'||public.lf_rule_promotion_ig_semantic_verify_v1('PROM-TEST')::text;
SELECT 'DECISION|'||public.lf_rule_promotion_governed_decide_v1(
 'PROM-TEST','LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1')::text;
SELECT 'APPLY|'||public.lf_rule_promotion_apply_v1('PROM-TEST')::text;
ROLLBACK;
SELECT 'ROLLBACK|'||jsonb_build_object(
 'candidate_state',(SELECT estado FROM lf_ops.reglas WHERE codigo='RULE-TEST-001'),
 'promotions',(SELECT count(*) FROM public.lf_rule_promotion_v1))::text;"""
    return sql(script)

def main():
    bootstrap()
    md5=sql("""SELECT 'MD5|'||jsonb_build_object(
      'bind',md5(pg_get_functiondef('public.lf_rule_promotion_bind_ig_semantic_v1(text,bigint,text,bigint,uuid,text)'::regprocedure)),
      'verify',md5(pg_get_functiondef('public.lf_rule_promotion_ig_semantic_verify_v1(text)'::regprocedure)),
      'decide',md5(pg_get_functiondef('public.lf_rule_promotion_governed_decide_v1(text,text)'::regprocedure)),
      'apply',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure)))::text;""")["MD5"]
    print("RAW_L4B_MD5 "+json.dumps(md5,sort_keys=True),flush=True)

    r=case('SEMANTIC_CANDIDATE_VERIFICATION_REQUIRED')
    check("EXISTING_IG_MISSING_EVIDENCE_RETRY",
      r["BIND"]["status"]=="BOUND_EXISTING_IG_SEMANTIC_EVIDENCE"
      and r["VERIFY"]["status"]=="RETRY_REQUIRED"
      and r["DECISION"]["status"]=="RETRY_REQUIRED"
      and r["APPLY"]["status"]=="BLOCKED"
      and r["ROLLBACK"]=={"candidate_state":"CANDIDATO","promotions":0},r)

    r=case('INDEPENDENT_SEMANTIC_VERDICT_REQUIRED')
    check("EXISTING_IG_AUDITOR_REQUIRED_RETRY",
      r["VERIFY"]["status"]=="RETRY_REQUIRED"
      and r["DECISION"]["status"]=="RETRY_REQUIRED",r)

    r=case('SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE','PASS')
    check("EXISTING_IG_AUDIT_PASS_STILL_NOT_PROMOTABLE",
      r["VERIFY"]["blocking_code"]=="RETRY_SEMANTIC_QUALITY_GATE_NOT_AUTHORIZED"
      and r["DECISION"]["status"]=="RETRY_REQUIRED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=case('SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE','FAIL')
    check("EXISTING_IG_AUDIT_FAIL_BLOCKS",
      r["VERIFY"]["blocking_code"]=="BLOCK_EXISTING_IG_SEMANTIC_AUDIT"
      and r["DECISION"]["status"]=="BLOCKED",r)

    r=case('SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE','PASS',mutate_after_bind=True)
    check("RULE_SNAPSHOT_DRIFT_BLOCKS",
      r["VERIFY"]["blocking_code"]=="BLOCK_IG_SEMANTIC_RULE_SNAPSHOT_DRIFT"
      and r["DECISION"]["status"]=="BLOCKED",r)

    r=case('SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE','PASS',security_bypass=True)
    check("DETERMINISTIC_BLOCK_CANNOT_BE_OVERRIDDEN",
      r["BIND"]["blocking_code"]=="DETERMINISTIC_FIRST_FILTER_NOT_AUTO_APPROVABLE"
      and r["DECISION"]["status"]=="BLOCKED",r)

    print("LF_L4B_EXISTING_IG_VALIDATOR_REUSE_PG18_PASS checks="+str(N),flush=True)
    print("NATIVE_MODEL_CALLS=0 STRUCTURAL_RUNTIME_ONLY=true",flush=True)

if __name__=="__main__":
    main()
