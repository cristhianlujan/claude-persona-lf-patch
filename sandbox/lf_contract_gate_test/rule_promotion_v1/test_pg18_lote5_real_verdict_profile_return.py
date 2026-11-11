#!/usr/bin/env python3
"""L5 PG18 structural checks. Existing #3682 API MOCK ONLY, not real case verdicts.
A real case transcript is NOT supplied: never claim real reviewer execution.
Every scenario rolls back the disposable PG18 transaction.
"""
import json,os,subprocess
from pathlib import Path
import test_pg18_lote4d_profile_owner_approval as l4d
import test_pg18_lote4b_validator_reuse as base

ROOT=Path(__file__).resolve().parents[3]
M5=ROOT/"supabase/migrations/20261111224500_lf_rule_promotion_real_verdict_profile_return_v1.sql"
DB="lf_3779_l5_profile_return_pg18"
N=0

def sql(s):return base.sql(s,db=DB)
def check(name,ok,raw):
    global N
    print("RAW_L5_"+name+" "+json.dumps(raw,sort_keys=True,ensure_ascii=False,default=str),flush=True)
    if not ok:raise AssertionError("L5_FAIL_"+name+" "+json.dumps(raw,sort_keys=True)[:4000])
    N+=1
    print("PASS_L5_"+name,flush=True)

def bootstrap():
    l4d.DB=DB
    l4d.bootstrap()
    sql("""UPDATE public.lf_decisiones_gov
      SET raw_payload=jsonb_set(raw_payload,'{owner_profile_code}',
       to_jsonb('PERFIL-OWNER-RULE-LF'::text),true)
      WHERE decision_number=101;
      ALTER TABLE public.l4b_ig_stub_state
        ADD COLUMN l5_case_verdict text DEFAULT 'ALLOW',
        ADD COLUMN l5_case_quote text DEFAULT 'Test baseline',
        ADD COLUMN l5_case_id text DEFAULT 'K0000ABCD';
      ALTER FUNCTION public.fn_input_governance_semantic_external_receipt_readback_v1(
         bigint,text,bigint,uuid,text)
       RENAME TO fn_input_governance_semantic_external_receipt_readback_l5_mock_original;

      -- This function is a PG18 disposable mock. Case ID/verdict/quote here
      -- are SYNTHETIC inputs, NOT a transcript from any user's five real passes.
      CREATE FUNCTION public.fn_input_governance_semantic_external_receipt_readback_v1(
       p_run_id bigint,p_identity text,p_handoff bigint,p_ticket uuid,
       p_candidate text DEFAULT NULL)
      RETURNS jsonb LANGUAGE sql VOLATILE AS $mock$
      SELECT public.fn_input_governance_semantic_external_receipt_readback_l5_mock_original(
          p_run_id,p_identity,p_handoff,p_ticket,p_candidate)
      || CASE WHEN s.l5_case_verdict IS NULL THEN '{}'::jsonb
       ELSE jsonb_build_object('l5_blind_case_verdict',jsonb_build_object(
         'id',s.l5_case_id,
         'verdict',s.l5_case_verdict,
         'exact_excerpt',s.l5_case_quote,
         'source_code','RULE-TEST-001',
         'source_sha256',public.lf_asset_snapshot_sha_v1('REGLA','RULE-TEST-001'),
         'rule_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA','RULE-TEST-001'),
         'packet_sha256',repeat('b',64),
         'candidate_sha256',s.candidate_sha256,
         'fixture_provenance','PG18_MOCK_NOT_USER_REVIEW'
       )) END
      FROM public.l4b_ig_stub_state s WHERE s.id=true
      $mock$;
    """)
    sql(M5.read_text(encoding="utf-8"))

def run_case(case_verdict="ALLOW",quote="Test baseline",pin=True,fail_readback=False,
             tamper_case=False,owner_profile="PERFIL-OWNER-RULE-LF",missing_case=False):
    before=("UPDATE public.l4b_ig_stub_state SET l5_case_verdict=NULL;" if missing_case else
        "UPDATE public.l4b_ig_stub_state SET l5_case_verdict="+base.lit(case_verdict)+
        ",l5_case_quote="+base.lit(quote)+";")
    pin_query="SELECT 'CASEPIN|'||public.lf_rule_promotion_blind_verdict_pin_v1('PROM-TEST')::text;" if pin else ""
    tamper=("UPDATE public.lf_rule_promotion_v1 SET l5_blind_case_binding_sha256=repeat('f',64) "
            "WHERE promotion_id='PROM-TEST';") if tamper_case else ""
    rb_fail="" if not fail_readback else """CREATE OR REPLACE FUNCTION public.lf_rule_promotion_rule_readback_v1(p_rule_code text)
       RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
       SET search_path TO 'pg_catalog','public','extensions' AS $mockrb$
       SELECT jsonb_build_object('estado','CANDIDATO','rule_code',p_rule_code,
        'snapshot_sha256',repeat('0',64))
       $mockrb$;"""
    return l4d.run_case(
       owner_profile=owner_profile,
       extra_before_bind=before,
       extra_after_bind=pin_query,
       extra_before_apply=tamper+rb_fail,
       extra_after_apply="SELECT 'PROFILE_RETURN|'||public.lf_rule_promotion_profile_return_readback_v1("
           "'PROM-TEST','EXEC-OWNER-L4D-001')::text;")

def main():
    bootstrap()
    md5=sql("""SELECT 'MD5|'||jsonb_build_object(
      'real_case_pin',md5(pg_get_functiondef('public.lf_rule_promotion_blind_verdict_pin_v1(text)'::regprocedure)),
      'real_case_verify',md5(pg_get_functiondef('public.lf_rule_promotion_blind_verdict_verify_v1(text)'::regprocedure)),
      'owner_verify',md5(pg_get_functiondef('public.lf_rule_promotion_profile_owner_verify_v1(text)'::regprocedure)),
      'profile_approve',md5(pg_get_functiondef('public.lf_rule_promotion_profile_approve_v1(text,text)'::regprocedure)),
      'governed_decide',md5(pg_get_functiondef('public.lf_rule_promotion_governed_decide_v1(text,text)'::regprocedure)),
      'apply',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
      'return_readback',md5(pg_get_functiondef('public.lf_rule_promotion_profile_return_readback_v1(text,text)'::regprocedure))
    )::text;""")["MD5"]
    print("RAW_L5_FUNCTION_MD5 "+json.dumps(md5,sort_keys=True),flush=True)

    perms=sql("""SELECT 'REGISTRY_PRIVILEGES|'||jsonb_build_object(
       'service_select',has_table_privilege('service_role','public.lf_rule_promotion_profile_owner_v1','SELECT'),
       'service_insert',has_table_privilege('service_role','public.lf_rule_promotion_profile_owner_v1','INSERT'),
       'service_update',has_table_privilege('service_role','public.lf_rule_promotion_profile_owner_v1','UPDATE'),
       'service_delete',has_table_privilege('service_role','public.lf_rule_promotion_profile_owner_v1','DELETE'),
       'anon_insert',has_table_privilege('anon','public.lf_rule_promotion_profile_owner_v1','INSERT'),
       'authenticated_update',has_table_privilege('authenticated','public.lf_rule_promotion_profile_owner_v1','UPDATE'))::text;""")["REGISTRY_PRIVILEGES"]
    check("IG_AND_PROFILE_CANNOT_WRITE_OWNER_REGISTRY",
       perms=={"service_select":True,"service_insert":False,"service_update":False,"service_delete":False,
               "anon_insert":False,"authenticated_update":False},perms)

    # Stronger runtime check: even service_role cannot self-assign owner via SQL.
    import os
    env=dict(os.environ)
    for k,v in dict(PGHOST="127.0.0.1",PGPORT="5432",PGUSER="postgres",PGPASSWORD="postgres").items():
        env.setdefault(k,v)
    cmd="""BEGIN;
      SET LOCAL ROLE service_role;
      UPDATE public.lf_rule_promotion_profile_owner_v1
       SET owner_profile_code='INPUT_VALIDATOR:MOCK' WHERE rule_code='RULE-TEST-001';
      ROLLBACK;"""
    attempt=subprocess.run(["psql","-X","-q","-v","ON_ERROR_STOP=1","-d",DB],
                           input=cmd,text=True,capture_output=True,env=env,timeout=120)
    check("IG_SERVICE_ROLE_CANNOT_MUTATE_OWNER_MAPPING",
      attempt.returncode!=0 and "permission denied" in attempt.stderr.lower(),
      {"exit_code":attempt.returncode,"stderr_tail":attempt.stderr[-500:]})

    r=run_case()
    check("MOCK_ALLOW_CASE_APPLY_AND_PROFILE_READBACK",
      r["CASEPIN"]["status"]=="REAL_VERDICT_ALLOW_VERIFIED"
      and r["OWNER_APPROVAL"]["status"]=="APPROVED"
      and r["APPLY"]["status"]=="APPLIED"
      and r["PROFILE_RETURN"]["status"]=="READY"
      and r["PROFILE_RETURN"]["readback_verified"] is True
      and r["ROLLBACK"]=={"candidate_state":"CANDIDATO","promotions":0,"owner_runs":0},r)

    r=run_case(fail_readback=True)
    check("READBACK_FAILURE_NO_VIGENTE_AND_RETRYABLE",
      r["OWNER_APPROVAL"]["status"]=="APPROVED"
      and r["APPLY"]["status"]=="RETRY_REQUIRED"
      and r["WITHIN_TX"]["candidate_state"]=="CANDIDATO"
      and r["WITHIN_TX"]["promotion_state"]=="APPROVED"
      and r["PROFILE_RETURN"]["status"]=="RETRY_REQUIRED",r)

    r=run_case(case_verdict="BLOCK")
    check("BLOCK_CASE_ESCALATES_NO_APPLY",
      r["CASEPIN"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["PRE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=run_case(case_verdict="INCONCLUSIVE")
    check("INCONCLUSIVE_CASE_ESCALATES_NO_APPLY",
      r["CASEPIN"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["PRE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=run_case(quote="FORGED_NO_SUCH_LITERAL")
    check("CITATION_NOT_EXACT_ESCALATES_NO_APPLY",
      r["CASEPIN"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["PRE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=run_case(tamper_case=True)
    check("POST_OWNER_CASE_BINDING_DRIFT_BLOCKED_BY_APPLY",
      r["OWNER_APPROVAL"]["status"]=="APPROVED"
      and r["APPLY"]["status"]=="BLOCKED"
      and r["WITHIN_TX"]["candidate_state"]=="CANDIDATO",r)

    r=run_case(missing_case=True)
    check("NO_REAL_CASE_RECEIPT_NO_PROMOTION",
      r["CASEPIN"]["blocking_code"]=="L5_REAL_BLIND_CASE_RECEIPT_NOT_PROVIDED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    print("LF_L5_STRUCTURAL_PG18_PASS checks="+str(N),flush=True)
    print("REAL_FIVE_PASS_CASE_RECEIPT=UNVERIFIED PG18_CASE_FIXTURE=SYNTHETIC NATIVE_MODEL_CALLS=0",flush=True)

if __name__=="__main__":
    main()
