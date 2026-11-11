#!/usr/bin/env python3
"""LF #3779 L4: structural semantic gate tests. Reviewer replies are SYNTHETIC,
never native GPT invocations or evidence of independent semantic quality.
All DB writes in disposable PG18 and all candidate promotions ROLLBACK.
"""
import json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
HERE=ROOT/"sandbox/lf_contract_gate_test/rule_promotion_v1"
DB="lf_3779_l4_semantic_gate_pg18"
M3=ROOT/"supabase/migrations/20261111182000_lf_rule_promotion_deterministic_judge_governed_v1.sql"
M4=ROOT/"supabase/migrations/20261111191000_lf_rule_promotion_native_semantic_review_gate_v1.sql"
N=0
def sql(src,db=DB):
    env=dict(os.environ)
    for k,v in dict(PGHOST="127.0.0.1",PGPORT="5432",PGUSER="postgres",PGPASSWORD="postgres").items():env.setdefault(k,v)
    x=subprocess.run(["psql","-X","-q","-A","-t","-v","ON_ERROR_STOP=1","-d",db],
        input=src,text=True,capture_output=True,env=env,timeout=240)
    if x.returncode:raise AssertionError("RAW_PG18_ERROR "+x.stderr[-3500:])
    out={}
    for line in x.stdout.splitlines():
        if "|" not in line:continue
        key,v=line.split("|",1)
        try:out[key]=json.loads(v)
        except ValueError:out[key]=v
    return out
def check(name,ok,raw):
    global N
    print("RAW_"+name+" "+json.dumps(raw,ensure_ascii=False,sort_keys=True,default=str),flush=True)
    if not ok:raise AssertionError("FAIL_"+name+" "+str(raw)[:1500])
    N+=1;print("PASS_"+name,flush=True)
def request():
    return """SELECT 'REQUEST|'||public.lf_rule_promotion_request_v1(
 'EXEC-PARENT-TEST-001','RULE-TEST-001','L4 structural semantic gate')::text;
"""
def decide():
    return """SELECT 'DECISION|'||public.lf_rule_promotion_governed_decide_v1(
 'PROM-TEST','LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1')::text;
"""
def apply():
    return """SELECT 'APPLY|'||public.lf_rule_promotion_apply_v1('PROM-TEST')::text;
"""
def reviewer(verdict="PASS",mode="SEPARATE_NATIVE_CONTEXT",synthetic_mark=False):
    # This SQL deliberately manufactures ONLY A FIXTURE; never pass as real.
    return """
INSERT INTO public.lf_operation_execution(
 execution_id,operation_code,target_code,target_type,status,manifest)
VALUES('EXEC-L4-REVIEWER-FIXTURE-001','EJECUCION_PERFIL_LF',
 'PERFIL-L4-SEMANTIC-REVIEWER-TEST','PERFIL','COMPLETED',
 jsonb_build_object('semantic_review',jsonb_build_object(
 'subject_promotion_id','PROM-TEST','review_mode','"""+mode+"""')));
INSERT INTO public.lf_operation_execution_steps(
 execution_id,step_id,status,evidence_ref,created_by_execution_id,evidence_payload)
SELECT 'EXEC-L4-REVIEWER-FIXTURE-001','semantic_judge',
 'STEP_PASS_WITH_EVIDENCE','fixture://not-an-official-receipt',
 'EXEC-L4-SYNTHETIC-RECORDER',
 jsonb_build_object(
  'test_fixture_generated',true,
  'test_only_synthetic',"""+("true" if synthetic_mark else "false")+""",
  'semantic_judge_result',jsonb_build_object(
    'status','PASS','validator_status','PASS',
    'result',jsonb_build_object(
      'unsupported_claims','[]'::jsonb,'blocking_codes','[]'::jsonb,
      'promotion_semantic_review',jsonb_build_object(
       'schema_version','LF_RULE_PROMOTION_NATIVE_SEMANTIC_REVIEW_V1',
       'promotion_id','PROM-TEST',
       'request_execution_id','EXEC-PARENT-TEST-001',
       'reviewer_execution_id','EXEC-L4-REVIEWER-FIXTURE-001',
       'review_mode','"""+mode+"""',
       'verdict','"""+verdict+"""',
       'packet_sha256',pack.info->>'packet_sha256',
       'candidate_source_sha256',pack.info#>>'{packet,candidate_source_sha256}',
       'security_policy_sha256',pack.info#>>'{packet,security_policy_sha256}',
       'dependency_sha256',pack.info#>>'{packet,dependency_sha256}',
       'cited_evidence',jsonb_build_array(jsonb_build_object(
         'source_code','RULE-TEST-001',
         'source_sha256',pack.info#>>'{packet,candidate_source_sha256}',
         'exact_excerpt','Test baseline',
         'implication','Synthetic structural control only',
         'claim_type','TEST_FIXTURE_NOT_NATIVE_REVIEW')),
       'unsupported_claims','[]'::jsonb))))
FROM (SELECT public.lf_rule_promotion_semantic_packet_v1(
'PROM-TEST') AS info) pack;
"""
def run(name,setup="",mid="",post="",want=None):
    script="BEGIN;\n"+setup+request()+mid+decide()+apply()+post+"""
SELECT 'PROM|'||to_jsonb(p)::text FROM public.lf_rule_promotion_v1 p
 WHERE p.promotion_id='PROM-TEST';
ROLLBACK;
SELECT 'ROLLBACK|'||jsonb_build_object(
 'candidate_state',(SELECT estado FROM lf_ops.reglas WHERE codigo='RULE-TEST-001'),
 'promotions',(SELECT COUNT(*) FROM public.lf_rule_promotion_v1))::text;
"""
    out=sql(script)
    if out.get("ROLLBACK")!={"candidate_state":"CANDIDATO","promotions":0}:
        raise AssertionError("NO_ROLLBACK "+name+" "+str(out.get("ROLLBACK")))
    if want and not want(out):raise AssertionError("GATE_UNEXPECTED "+name+" "+str(out)[:2000])
    print("RAW_CASE_"+name+" "+json.dumps(out,ensure_ascii=False,sort_keys=True),flush=True)
    check(name,True,{"decision":out.get("DECISION"),"apply":out.get("APPLY"),"rollback":out.get("ROLLBACK")})
    return out
def main():
    sql("CREATE DATABASE "+DB+";",db="postgres")
    sql((HERE/"promotion_pg18_sandbox_fixture.sql").read_text())
    sql((HERE/"live_promotion_baseline_fixture.sql").read_text())
    sql("""CREATE TRIGGER trg_lf_rule_promotion_guard_v1
     BEFORE UPDATE OF estado ON lf_ops.reglas
     FOR EACH ROW EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();""")
    sql(M3.read_text())
    sql("""ALTER TABLE public.lf_operation_execution_steps
        ADD COLUMN evidence_ref text, ADD COLUMN created_by_execution_id text;
    CREATE TABLE public.lf_error_knowledge(codigo text primary key,estado text);
    INSERT INTO public.lf_error_knowledge VALUES(
    'PROFILE-EXECUTION-SEMANTIC-JUDGE-NOT-ENFORCED-001','ACTIVE_REMEDIATION');""")
    sql(M4.read_text())
    print("RAW_SEMANTIC_GATE_MD5 "+
       str(sql("""SELECT 'CHECK|'||jsonb_build_object(
       'decide',md5(pg_get_functiondef('public.lf_rule_promotion_governed_decide_v1(text,text)'::regprocedure)),
       'apply',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
       'record',md5(pg_get_functiondef('public.lf_rule_promotion_semantic_record_v1(text,text)'::regprocedure)),
       'verify',md5(pg_get_functiondef('public.lf_rule_promotion_semantic_verify_v1(text)'::regprocedure)))::text;""").get("CHECK")),flush=True)
    run("MISSING_SEMANTIC_REVIEW_RETRY",want=lambda o:
        o["DECISION"]["blocking_code"]=="RETRY_SEMANTIC_REVIEW_REQUIRED"
        and o["APPLY"]["blocking_code"]=="PROMOTION_NOT_APPROVED")
    run("DETERMINISTIC_BLOCK_CANNOT_BE_OVERRIDDEN",
        setup="""UPDATE lf_ops.reglas SET valor_config=jsonb_set(
        valor_config,'{auth_bypass}','true'::jsonb,true)
        WHERE codigo='RULE-TEST-001';
        UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(
        evidence_payload,'{input_governance,rule_source_sha256}',
        to_jsonb(public.lf_asset_snapshot_sha_v1('REGLA','RULE-TEST-001')),true)
        WHERE step_id='input_validate';""",
        want=lambda o:o["DECISION"]["status"]=="BLOCKED"
             and "OBVIOUS_SECURITY_BYPASS" in o["DECISION"]["blocking_codes"])
    run("SAME_PARENT_REVIEWER_BLOCKED",
        mid="""SELECT 'RECORD|'||public.lf_rule_promotion_semantic_record_v1(
        'PROM-TEST','EXEC-PARENT-TEST-001')::text;""",
        want=lambda o:o["RECORD"]["blocking_code"]=="REVIEWER_MUST_BE_DISTINCT_RUN")
    run("NONEXISTENT_REVIEWER_BLOCKED",
        mid="""SELECT 'RECORD|'||public.lf_rule_promotion_semantic_record_v1(
        'PROM-TEST','EXEC-MISSING')::text;""",
        want=lambda o:o["RECORD"]["blocking_code"]=="REVIEWER_GOVERNED_RUN_NOT_FOUND")
    run("CURRENT_CONTEXT_NOT_SEPARATE",
        mid=reviewer(mode="CURRENT_CONTEXT_REVIEW")+"""
        SELECT 'RECORD|'||public.lf_rule_promotion_semantic_record_v1(
          'PROM-TEST','EXEC-L4-REVIEWER-FIXTURE-001')::text;""",
        want=lambda o:o["RECORD"]["blocking_code"]=="REVIEWER_ROLE_OR_SCOPE_NOT_ATTESTED")
    run("SYNTHETIC_MARKED_STEP70_REJECTED",
        mid=reviewer(synthetic_mark=True)+"""
        SELECT 'RECORD|'||public.lf_rule_promotion_semantic_record_v1(
          'PROM-TEST','EXEC-L4-REVIEWER-FIXTURE-001')::text;""",
        want=lambda o:o["RECORD"]["blocking_code"]=="REVIEWER_STEP70_RECEIPT_NOT_ATTESTED")
    run("EKB_ACTIVE_BLOCKS_AUTOMATIC_APPROVAL",
        mid=reviewer()+"""
        SELECT 'RECORD|'||public.lf_rule_promotion_semantic_record_v1(
          'PROM-TEST','EXEC-L4-REVIEWER-FIXTURE-001')::text;""",
        want=lambda o:o["RECORD"]["status"]=="RECORDED"
            and o["DECISION"]["semantic_gate"]["blocking_code"]==
                 "BLOCK_SEMANTIC_JUDGE_ENFORCEMENT_NOT_RESOLVED"
            and o["APPLY"]["status"]=="BLOCKED")
    ekb="UPDATE public.lf_error_knowledge SET estado='RESOLVED' WHERE codigo='PROFILE-EXECUTION-SEMANTIC-JUDGE-NOT-ENFORCED-001';"
    r=run("SYNTHETIC_REVIEW_SCHEMA_POSITIVE_NOT_NATIVE",
        setup=ekb,
        mid=reviewer()+"""
        SELECT 'RECORD|'||public.lf_rule_promotion_semantic_record_v1(
          'PROM-TEST','EXEC-L4-REVIEWER-FIXTURE-001')::text;""",
        want=lambda o:o["RECORD"]["status"]=="RECORDED"
          and o["DECISION"]["status"]=="APPROVED"
          and o["APPLY"]["status"]=="APPLIED"
          and o["PROM"]["semantic_receipt"] is not None
          and o["PROM"]["semantic_receipt_sha256"] is not None)
    print("RAW_CRITICAL_LIMIT synthetic reviewer fixture successful only because EKB was changed in a transaction; not native review; independence remains false",flush=True)
    run("SYNTHETIC_SEMANTIC_BLOCK_CANNOT_APPROVE",
        setup=ekb,
        mid=reviewer(verdict="BLOCK")+"""
        SELECT 'RECORD|'||public.lf_rule_promotion_semantic_record_v1(
          'PROM-TEST','EXEC-L4-REVIEWER-FIXTURE-001')::text;""",
        want=lambda o:o["DECISION"]["semantic_gate"]["blocking_code"]==
                    "BLOCK_SEMANTIC_CONTRADICTION" and o["APPLY"]["status"]=="BLOCKED")
    run("SYNTHETIC_SEMANTIC_INCONCLUSIVE_RETRY",
        setup=ekb,
        mid=reviewer(verdict="INCONCLUSIVE")+"""
        SELECT 'RECORD|'||public.lf_rule_promotion_semantic_record_v1(
          'PROM-TEST','EXEC-L4-REVIEWER-FIXTURE-001')::text;""",
        want=lambda o:o["DECISION"]["semantic_gate"]["blocking_code"]==
                    "RETRY_SEMANTIC_INCONCLUSIVE" and o["APPLY"]["status"]=="BLOCKED")
    run("SEMANTIC_RECEIPT_POLICY_DRIFT_BLOCKED",
        setup=ekb,
        mid=reviewer()+"""
        SELECT 'RECORD|'||public.lf_rule_promotion_semantic_record_v1(
          'PROM-TEST','EXEC-L4-REVIEWER-FIXTURE-001')::text;
        UPDATE lf_ops.politicas_seguridad SET policy_config=jsonb_set(
        policy_config,'{server_side_enforcement}','false'::jsonb,true)
        WHERE policy_code='SEC-AUTH';
        SELECT 'SEMANTIC_READBACK|'||public.lf_rule_promotion_semantic_verify_v1('PROM-TEST')::text;""",
        want=lambda o:o["SEMANTIC_READBACK"]["blocking_code"]==
                    "BLOCK_SEMANTIC_SOURCE_OR_RECEIPT_DRIFT")
    print("LF_L4_SEMANTIC_GATE_STRUCTURAL_PG18_PASS",N,flush=True)
    print("NATIVE_MODEL_CALLS=0 INDEPENDENT_JUDGE_RECEIPTS=0",flush=True)
if __name__=="__main__":main()
