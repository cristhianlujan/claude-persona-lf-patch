#!/usr/bin/env python3
"""L4D PG18.6 disposable profiles: mocked #3682 transport and owner Step70.
All mutations inside transaction ROLLBACK. Not independent/production authority.
"""
import json
from pathlib import Path
import test_pg18_lote4b_validator_reuse as base

ROOT=Path(__file__).resolve().parents[3]
M4D=ROOT/"supabase/migrations/20261111212500_lf_rule_promotion_profile_owner_authority_v1.sql"
DB="lf_3779_l4d_owner_profile_pg18"
N=0

def sql(q): return base.sql(q,db=DB)
def check(name,passed,raw):
    global N
    print("RAW_L4D_"+name+" "+json.dumps(raw,ensure_ascii=False,sort_keys=True,default=str),flush=True)
    if not passed: raise AssertionError("L4D_FAIL_"+name+" "+json.dumps(raw,sort_keys=True)[:3000])
    N+=1
    print("PASS_L4D_"+name,flush=True)

def bootstrap():
    base.bootstrap(db=DB)
    # Production schema has official Step70 evidence_ref/created_by_execution_id;
    # legacy PG18 L3 fixture did not model them.
    sql("""ALTER TABLE public.lf_operation_execution_steps
       ADD COLUMN evidence_ref text, ADD COLUMN created_by_execution_id text;
    """)
    sql(M4D.read_text(encoding="utf-8"))
    sql("""INSERT INTO public.lf_profile_write_authority_v1 VALUES
      ('PERFIL-OWNER-RULE-LF','PROMOCION_REGLA_LF','ACTIVE');""")

def run_case(verdict="PERMITIR",owner_profile="PERFIL-OWNER-RULE-LF",
             grant=True,bad_quote=False,policy_drift=False,
             tamper_owner_hash=False,synthetic_owner=False,
             synthetic_parent=False,missing_owner_run=False,
             same_execution=False,auth_only=False):
    quote="UNTRUSTED_FABRICATED_QUOTE_XYZ" if bad_quote else "Test baseline"
    owner_run="EXEC-PARENT-TEST-001" if same_execution else "EXEC-OWNER-L4D-001"
    actor_rows=""
    if owner_profile=="PERFIL-PRODUCT-DIRECTOR-LF":
        actor_rows=""
    if not grant:
        actor_rows+="DELETE FROM public.lf_profile_write_authority_v1 WHERE profile_code='PERFIL-OWNER-RULE-LF';"
    setup_owner="" if missing_owner_run or same_execution else f"""
    INSERT INTO public.lf_operation_execution(
      execution_id,operation_code,target_code,status,manifest)
      VALUES('{owner_run}','EJECUCION_PERFIL_LF',{base.lit(owner_profile)},
       'COMPLETED','{{"profile_decision_mode":"RULE_PROMOTION_OWNER_APPROVAL"}}'::jsonb);
    INSERT INTO public.lf_operation_execution_steps(
      execution_id,step_id,status,evidence_payload,evidence_ref,created_by_execution_id)
      SELECT '{owner_run}','semantic_judge','STEP_PASS_WITH_EVIDENCE',
       jsonb_build_object(
         'test_only_synthetic',{str(synthetic_owner).lower()},
         'sandbox_fixture_provenance','PG18_MOCK_NOT_LIVE_RECEIPT',
         'semantic_judge_result',jsonb_build_object('status','PASS','validator_status','PASS'),
         'rule_promotion_owner_approval',jsonb_build_object(
           'schema_version','LF_RULE_PROMOTION_OWNER_APPROVAL_V1',
           'decision','APPROVE','promotion_id',p.promotion_id,
           'owner_profile_code',{base.lit(owner_profile)},
           'owner_execution_id','{owner_run}',
           'proposer_profile_code',p.requested_by_profile,
           'ig_proposer_identity',p.ig_semantic_validator_identity,
           'ig_run_id',p.ig_semantic_run_id,
           'rule_code',p.rule_code,
           'rule_snapshot_sha256',p.request_snapshot_sha256,
           'packet_sha256',p.ig_semantic_packet_sha256,
           'candidate_sha256',p.ig_semantic_candidate_sha256,
           'ig_external_receipt_sha256',p.ig_semantic_external_receipt_sha256,
           'ig_review_sha256',p.ig_semantic_review_sha256,
           'ig_binding_sha256',p.ig_semantic_binding_sha256,
           'policy_sha256',p.ig_semantic_policy_set_sha256,
           'dependency_sha256',p.ig_semantic_dependency_sha256,
           'source_decision_sha256',j->>'source_decision_sha256')),
       'PG18-STUB-OWNER-STEP70','{owner_run}'
      FROM public.lf_rule_promotion_v1 p
      CROSS JOIN LATERAL (SELECT public.lf_rule_promotion_quality_judge_v1('PROM-TEST') AS j) d
      WHERE p.promotion_id='PROM-TEST';"""
    drift=(
       "UPDATE lf_ops.politicas_seguridad SET policy_config="
       "jsonb_set(policy_config,'{server_side_enforcement}','false'::jsonb,true) "
       "WHERE policy_code='SEC-AUTH';"
    ) if policy_drift else ""
    tamper=(
       "UPDATE public.lf_rule_promotion_v1 SET owner_approval_receipt_sha256="
       "repeat('f',64) WHERE promotion_id='PROM-TEST';"
    ) if tamper_owner_hash else ""
    clean="" if synthetic_parent else """UPDATE public.lf_operation_execution_steps
      SET evidence_payload=jsonb_set(evidence_payload,'{test_only_synthetic}','false'::jsonb,true)
      WHERE execution_id='EXEC-PARENT-TEST-001' AND step_id='semantic_judge';"""
    script=f"""BEGIN;
    UPDATE public.l4b_ig_stub_state
       SET receipt_status='SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE',
           audit_verdict='PASS', semantic_verdict={base.lit(verdict)},
           evidence_quote={base.lit(quote)};
    {clean}
    {actor_rows}
    SELECT 'REQUEST|'||public.lf_rule_promotion_request_v1(
       'EXEC-PARENT-TEST-001','RULE-TEST-001','PG18 L4D owner profile')::text;
    SELECT 'BIND|'||public.lf_rule_promotion_bind_ig_semantic_v1(
       'PROM-TEST',9001,'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:abcdef',
       7001,'00000000-0000-0000-0000-000000000001'::uuid,repeat('a',64))::text;
    INSERT INTO public.lf_rule_promotion_profile_owner_v1(
      rule_code,owner_profile_code,source_decision_sha256,status)
      VALUES('RULE-TEST-001',{base.lit(owner_profile)},
       public.lf_rule_promotion_quality_judge_v1('PROM-TEST')->>'source_decision_sha256','ACTIVE');
    {drift}
    SELECT 'PRE|'||public.lf_rule_promotion_governed_decide_v1(
       'PROM-TEST','LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1')::text;
    {setup_owner}
    SELECT 'OWNER_APPROVAL|'||public.lf_rule_promotion_profile_approve_v1(
      'PROM-TEST',{base.lit(owner_run)})::text;
    {tamper}
    SELECT 'APPLY|'||public.lf_rule_promotion_apply_v1('PROM-TEST')::text;
    SELECT 'WITHIN_TX|'||jsonb_build_object(
       'candidate_state',(SELECT estado FROM lf_ops.reglas WHERE codigo='RULE-TEST-001'),
       'promotion_state',(SELECT status FROM public.lf_rule_promotion_v1 WHERE promotion_id='PROM-TEST'),
       'decision_route',(SELECT decision_route FROM public.lf_rule_promotion_v1 WHERE promotion_id='PROM-TEST'))::text;
    ROLLBACK;
    SELECT 'ROLLBACK|'||jsonb_build_object(
       'candidate_state',(SELECT estado FROM lf_ops.reglas WHERE codigo='RULE-TEST-001'),
       'promotions',(SELECT count(*) FROM public.lf_rule_promotion_v1),
       'owner_runs',(SELECT count(*) FROM public.lf_operation_execution
          WHERE execution_id='EXEC-OWNER-L4D-001'))::text;
    """
    return sql(script)

def main():
    bootstrap()
    md5=sql("""SELECT 'MD5|'||jsonb_build_object(
      'ig_bind',md5(pg_get_functiondef('public.lf_rule_promotion_bind_ig_semantic_v1(text,bigint,text,bigint,uuid,text)'::regprocedure)),
      'ig_verify',md5(pg_get_functiondef('public.lf_rule_promotion_ig_semantic_verify_v1(text)'::regprocedure)),
      'owner_verify',md5(pg_get_functiondef('public.lf_rule_promotion_profile_owner_verify_v1(text)'::regprocedure)),
      'owner_approve',md5(pg_get_functiondef('public.lf_rule_promotion_profile_approve_v1(text,text)'::regprocedure)),
      'governed_decide',md5(pg_get_functiondef('public.lf_rule_promotion_governed_decide_v1(text,text)'::regprocedure)),
      'apply',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))
    )::text;""")["MD5"]
    print("RAW_L4D_PG18_MD5 "+json.dumps(md5,sort_keys=True),flush=True)
    r=run_case()
    check("OWNER_PROFILE_VALID_APPROVES_AND_APPLIES_IN_ROLLBACK",
      r["PRE"]["status"]=="PROFILE_APPROVAL_REQUIRED"
      and r["OWNER_APPROVAL"]["status"]=="APPROVED"
      and r["OWNER_APPROVAL"]["decided_by"]=="PROFILE:PERFIL-OWNER-RULE-LF"
      and r["APPLY"]["status"]=="APPLIED"
      and r["WITHIN_TX"]["candidate_state"]=="VIGENTE"
      and r["ROLLBACK"]=={"candidate_state":"CANDIDATO","promotions":0,"owner_runs":0},r)

    r=run_case(owner_profile="PERFIL-PRODUCT-DIRECTOR-LF")
    check("PROPOSER_PROFILE_CANNOT_SELF_APPROVE",
      r["PRE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["OWNER_APPROVAL"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=run_case(grant=False)
    check("PROFILE_NO_WRITE_AUTHORITY_ESCALATES_HUMAN",
      r["PRE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["OWNER_APPROVAL"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=run_case(tamper_owner_hash=True)
    check("OWNER_RECEIPT_HASH_TAMPER_APPLY_BLOCKED",
      r["OWNER_APPROVAL"]["status"]=="APPROVED"
      and r["APPLY"]["blocking_code"]=="PROMOTION_OWNER_APPROVAL_RECEIPT_NOT_CURRENT"
      and r["WITHIN_TX"]["candidate_state"]=="CANDIDATO",r)

    r=run_case(synthetic_parent=True)
    check("PARENT_STEP70_SYNTHETIC_REJECTED",
      r["BIND"]["blocking_code"]=="BLOCK_SYNTHETIC_PARENT_STEP70_EVIDENCE"
      and r["OWNER_APPROVAL"]["status"]!="APPROVED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=run_case(synthetic_owner=True)
    check("OWNER_STEP70_SYNTHETIC_REJECTED",
      r["OWNER_APPROVAL"]["blocking_code"]=="PROFILE_OWNER_STEP70_NOT_ATTESTED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=run_case(bad_quote=True)
    check("FABRICATED_EXACT_QUOTE_ESCALATES_HUMAN",
      r["BIND"]["blocking_code"]=="BLOCK_IG_SEMANTIC_CITATION_NOT_IN_CURRENT_SOURCE"
      and r["PRE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=run_case(policy_drift=True)
    check("POLICY_DRIFT_ESCALATES_HUMAN",
      r["PRE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=run_case(verdict="BLOQUEAR")
    check("NATIVE_BLOCK_ESCALATES_BUT_NEVER_PROMOTES",
      r["PRE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["OWNER_APPROVAL"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=run_case(verdict="INCONCLUSO")
    check("NATIVE_INCONCLUSIVE_ESCALATES_BUT_NEVER_PROMOTES",
      r["PRE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["OWNER_APPROVAL"]["status"]=="HUMAN_DECISION_REQUIRED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=run_case(missing_owner_run=True)
    check("OWNER_NONEXISTENT_RUN_NOT_ACCEPTED",
      r["OWNER_APPROVAL"]["blocking_code"]=="PROFILE_OWNER_EXECUTION_NOT_ATTESTED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    r=run_case(same_execution=True)
    check("OWNER_CANNOT_USE_PARENT_RUN",
      r["OWNER_APPROVAL"]["blocking_code"]=="PROFILE_OWNER_EXECUTION_NOT_ATTESTED"
      and r["APPLY"]["status"]=="BLOCKED",r)

    print("LF_L4D_PROFILE_OWNER_AUTHORITY_PG18_PASS checks="+str(N),flush=True)
    print("SIMULATED_OWNER_RUNS_ONLY=true NATIVE_MODEL_CALLS=0 IG_PROFILE_INDEPENDENCE=false",flush=True)

if __name__=="__main__":
    main()
