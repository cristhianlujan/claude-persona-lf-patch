#!/usr/bin/env python3
"""LF #3779 Lote3: one target rule; isolated PG18; SQL functions REAL, fixtures synthetic."""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "sandbox/lf_contract_gate_test/rule_promotion_v1"
DB = "lf_3779_one_rule_prom_pg18"
MIG = ROOT / "supabase/migrations/20261111182000_lf_rule_promotion_deterministic_judge_governed_v1.sql"
N = 0
SOURCE_MD5 = {
 "lf_rule_promotion_request_v1": ("text,text,text","2fcac9f18b1581985af93639e475cd1a"),
 "lf_rule_promotion_decide_v1": ("text,text,text,text","16e45f40dad5cecc215a2f978be47728"),
 "lf_rule_promotion_apply_v1": ("text","d7fe763c999db6f6259b6b1e2bd69644"),
 "lf_rule_promotion_guard_v1": ("","ee782e4bd0128c80ee13881899c0d74e"),
}

def sql(src, db=DB):
    env = dict(os.environ)
    for k,v in {"PGHOST":"127.0.0.1","PGPORT":"5432","PGUSER":"postgres","PGPASSWORD":"postgres"}.items():
        env.setdefault(k,v)
    p = subprocess.run(["psql","-X","-q","-A","-t","-v","ON_ERROR_STOP=1","-d",db],
        input=src,env=env,text=True,capture_output=True,timeout=240)
    if p.returncode:
        raise AssertionError("PG18_RAW_ERROR "+p.stderr[-3000:])
    return p.stdout.strip()

def check(name, passed, raw=None):
    global N
    if not passed:
        raise AssertionError("FAIL_"+name+" "+json.dumps(raw,ensure_ascii=False,default=str)[:2000])
    N += 1
    print("PASS_"+name,flush=True)

def md5(name,args):
    return sql("SELECT md5(pg_get_functiondef('public."+name+"("+args+")'::regprocedure));")

def parse_lines(out):
    rows={}
    for line in out.splitlines():
        if "|" not in line: continue
        key,raw=line.split("|",1)
        try: val=json.loads(raw)
        except (ValueError,TypeError): val=raw
        rows[key]=val
    return rows

def run_case(name, setup="", before_judge="", after_decision="", after_apply="", decide_actor="LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1", apply=True):
    statement = """
BEGIN;
""" + setup + """
SELECT 'REQUEST|'||public.lf_rule_promotion_request_v1(
 'EXEC-PARENT-TEST-001','RULE-TEST-001','Governed candidate quality decision')::text;
""" + before_judge + """
SELECT 'DECISION|'||public.lf_rule_promotion_governed_decide_v1(
 'PROM-TEST','""" + decide_actor + """')::text;
""" + after_decision + ("""
SELECT 'APPLY|'||public.lf_rule_promotion_apply_v1('PROM-TEST')::text;
""" if apply else "") + after_apply + """
SELECT 'PROMOTION|'||to_jsonb(p)::text FROM public.lf_rule_promotion_v1 p WHERE promotion_id='PROM-TEST';
SELECT 'RULE_STATE|'||to_jsonb(r)::text FROM lf_ops.reglas r WHERE codigo='RULE-TEST-001';
ROLLBACK;
SELECT 'AFTER_ROLLBACK|'||jsonb_build_object(
 'candidate_state',(SELECT estado FROM lf_ops.reglas WHERE codigo='RULE-TEST-001'),
 'promotion_rows',(SELECT count(*) FROM public.lf_rule_promotion_v1))::text;
"""
    raw=sql(statement)
    data=parse_lines(raw)
    # Raw evidence is printed in source order, including the actual function outputs.
    print("RAW_"+name+" "+json.dumps(data,sort_keys=True,ensure_ascii=False),flush=True)
    check(name+"_ROLLBACK",
        data.get("AFTER_ROLLBACK")=={"candidate_state":"CANDIDATO","promotion_rows":0},
        data.get("AFTER_ROLLBACK"))
    return data

def update_step40_sha():
    return """
UPDATE public.lf_operation_execution_steps SET evidence_payload =
 jsonb_set(evidence_payload,'{input_governance,rule_source_sha256}',
  to_jsonb(public.lf_asset_snapshot_sha_v1('REGLA','RULE-TEST-001')),true)
WHERE execution_id='EXEC-PARENT-TEST-001' AND step_id='input_validate';
"""

def main():
    sql("CREATE DATABASE "+DB+";",db="postgres")
    sql((BASE/"promotion_pg18_sandbox_fixture.sql").read_text())
    sql((BASE/"live_promotion_baseline_fixture.sql").read_text())
    sql("""CREATE TRIGGER trg_lf_rule_promotion_guard_v1
      BEFORE UPDATE OF estado ON lf_ops.reglas FOR EACH ROW
      EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();""")
    sql((BASE/"live_currentness_authority_fixture.sql").read_text())
    for name,(args,expected) in SOURCE_MD5.items():
        obs=md5(name,args)
        print("RAW_MD5_BEFORE_"+name+" "+obs,flush=True)
        check("BASELINE_MD5_"+name,obs==expected,{"expected":expected,"actual":obs})
    current_live=sql("SELECT md5(pg_get_functiondef('programacion.fn_input_run_source_currentness_v1(bigint)'::regprocedure));")
    print("RAW_MD5_CURRENTNESS_REAL "+current_live,flush=True)
    check("CURRENTNESS_LIVE_FUNCTION_FROZEN",current_live=="ba43b8cc06220a2ae079d5d7d6c7710c")
    sql(MIG.read_text())
    for name,(args,original) in SOURCE_MD5.items():
        after=md5(name,args)
        print("RAW_MD5_AFTER_"+name+" "+after,flush=True)
        check("MD5_"+name+("_CHANGED" if name!="lf_rule_promotion_guard_v1" else "_UNCHANGED"),
            (after!=original if name!="lf_rule_promotion_guard_v1" else after==original))
    judge_md5=sql("SELECT md5(pg_get_functiondef('public.lf_rule_promotion_quality_judge_v1(text)'::regprocedure));")
    governed_md5=sql("SELECT md5(pg_get_functiondef('public.lf_rule_promotion_governed_decide_v1(text,text)'::regprocedure));")
    print("RAW_MD5_NEW_JUDGE "+judge_md5,flush=True)
    print("RAW_MD5_NEW_DECIDER "+governed_md5,flush=True)
    check("NEW_JUDGE_AND_DECIDER_SOURCE_HASHED",len(judge_md5)==len(governed_md5)==32)

    positive=run_case("ONE_RULE_POSITIVE",after_decision="""
SELECT 'SAME_HASH_PRE_APPLY|'||((
 SELECT request_snapshot_sha256 FROM public.lf_rule_promotion_v1
 WHERE promotion_id='PROM-TEST')
 =public.lf_asset_snapshot_sha_v1('REGLA','RULE-TEST-001'))::text;
SELECT 'REPLAY_SAME_HASH_DECIDE|'||
 public.lf_rule_promotion_governed_decide_v1('PROM-TEST',
  'LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1')::text;
SELECT 'REPLAY_SAME_HASH_REQUEST|'||
 public.lf_rule_promotion_request_v1('EXEC-PARENT-TEST-001',
  'RULE-TEST-001','same parent and unchanged snapshot')::text;
""",after_apply="""
SELECT 'CURRENTNESS_POST_APPLY|'||programacion.fn_input_run_source_currentness_v1(1101)::text;
INSERT INTO programacion.input_readiness_runs(
 id,version_id,pantalla_id,status,contract_version,contract_revision,
 contract_snapshot_sha256,source_manifest,source_snapshot_sha256,scope,supersedes_run_id)
SELECT 1102,version_id,pantalla_id,'COMPLETED',contract_version,contract_revision,
 contract_snapshot_sha256,programacion.fn_input_build_source_manifest(1102),
 programacion.fn_v09_sha256_jsonb(programacion.fn_input_build_source_manifest(1102)),
 '{}'::jsonb,1101
FROM programacion.input_readiness_runs WHERE id=1101;
SELECT 'CURRENTNESS_SUCCESSOR|'||programacion.fn_input_run_source_currentness_v1(1102)::text;
SELECT 'REPLAY_DECIDE|'||public.lf_rule_promotion_governed_decide_v1(
 'PROM-TEST','LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1')::text;
SELECT 'REPLAY_APPLY|'||public.lf_rule_promotion_apply_v1('PROM-TEST')::text;
SELECT 'REPLAY_REQUEST|'||public.lf_rule_promotion_request_v1(
 'EXEC-PARENT-TEST-001','RULE-TEST-001','exact same RUN and same request')::text;
""")
    check("ONE_RULE_GOOD_CANDIDATE_PROMOTED",
      positive["REQUEST"]["status"]=="PENDING_GOVERNED_DECISION"
      and positive["DECISION"]["status"]=="APPROVED"
      and positive["APPLY"]["status"]=="APPLIED"
      and positive["RULE_STATE"]["estado"]=="VIGENTE",positive)
    check("JUDGE_RECEIPT_SHA256_PERSISTED",
      len(positive["PROMOTION"]["judge_receipt_sha256"])==64
      and positive["PROMOTION"]["judge_receipt"]["classification"]=="AUTO_APPROVABLE"
      and positive["PROMOTION"]["judge_receipt"]["independent_semantic_judge_attested"] is False,
      positive["PROMOTION"])
    check("REAL_CURRENTNESS_AFTER_CHANGE_IS_STALE",
      positive["CURRENTNESS_POST_APPLY"]["source_current"] is False,
      positive["CURRENTNESS_POST_APPLY"])
    check("REAL_CURRENTNESS_AFTER_FIXTURE_SUCCESSOR_CURRENT",
      positive["CURRENTNESS_SUCCESSOR"]["source_current"] is True,
      positive["CURRENTNESS_SUCCESSOR"])
    check("SAME_RUN_SAME_HASH_REPLAY_BLOCKED",
      positive["SAME_HASH_PRE_APPLY"] is True
      and positive["REPLAY_SAME_HASH_DECIDE"]["blocking_code"]=="PROMOTION_NOT_PENDING"
      and positive["REPLAY_SAME_HASH_REQUEST"]["blocking_code"]=="PROMOTION_ALREADY_OPEN"
      and positive["REPLAY_DECIDE"]["blocking_code"]=="PROMOTION_NOT_PENDING"
      and positive["REPLAY_APPLY"]["blocking_code"]=="PROMOTION_NOT_APPROVED"
      and positive["REPLAY_REQUEST"]["blocking_code"]=="RULE_NOT_CANDIDATE",
      positive)
    dep=run_case("NEG_DEPENDENCY_CANDIDATE",
      setup="UPDATE lf_ops.reglas SET estado='CANDIDATO' WHERE codigo='RULE-DEPENDENCY-001';")
    check("DEPENDENCY_CANDIDATE_BLOCKED",
      "RULE_DEPENDENCY_NOT_VIGENTE" in dep["DECISION"]["blocking_codes"]
      and dep["APPLY"]["status"]=="BLOCKED",dep)
    inverse=run_case("NEG_VIGENTE_DEPENDS_ON_CANDIDATO",
      setup="""UPDATE lf_ops.reglas SET valor_config=
        '{"depends_on_rules":["RULE-TEST-001"],"source_decision_number":99}'::jsonb
      WHERE codigo='RULE-DEPENDENCY-001';""")
    check("VIGENTE_TO_CANDIDATO_DEPENDENCY_BLOCKED",
      "VIGENTE_DEPENDS_ON_CANDIDATO" in inverse["DECISION"]["blocking_codes"]
      and inverse["APPLY"]["status"]=="BLOCKED",inverse)
    security=run_case("NEG_SECURITY_POLICY_CONFLICT",
      setup="""UPDATE lf_ops.reglas SET valor_config=
      jsonb_set(valor_config,'{deny_by_default}','false'::jsonb,true)
      WHERE codigo='RULE-TEST-001';"""+update_step40_sha())
    check("SECURITY_POLICY_CONTRADICTION_BLOCKED",
      "VIGENTE_SECURITY_POLICY_CONFLICT" in security["DECISION"]["blocking_codes"]
      and security["APPLY"]["status"]=="BLOCKED",security)
    bypass=run_case("NEG_OBVIOUS_SECURITY_BYPASS",
      setup="""UPDATE lf_ops.reglas SET valor_config=
        jsonb_set(valor_config,'{auth_bypass}','true'::jsonb,true)
      WHERE codigo='RULE-TEST-001';"""+update_step40_sha())
    check("OBVIOUS_BYPASS_BLOCKED",
      "OBVIOUS_SECURITY_BYPASS" in bypass["DECISION"]["blocking_codes"]
      and bypass["APPLY"]["status"]=="BLOCKED",bypass)
    owner=run_case("NEG_OWNER_MISSING",
      setup="UPDATE lf_ops.reglas SET owner_name=NULL WHERE codigo='RULE-TEST-001';"+update_step40_sha())
    check("OWNER_ABSENT_BLOCKED",
      "FUNCTIONAL_OWNER_MISSING_OR_WRONG" in owner["DECISION"]["blocking_codes"]
      and owner["APPLY"]["status"]=="BLOCKED",owner)
    source=run_case("NEG_CANONICAL_PROVENANCE_NOT_APPROVED",
      setup="""UPDATE lf_ops.reglas SET valor_config=
       jsonb_set(valor_config,'{source_decision_number}','999'::jsonb,true)
       WHERE codigo='RULE-TEST-001';"""+update_step40_sha())
    check("CANONICAL_PROVENANCE_MISSING_BLOCKED",
      "CANONICAL_DECISION_SOURCE_NOT_APPROVED" in source["DECISION"]["blocking_codes"]
      and source["APPLY"]["status"]=="BLOCKED",source)
    unbound=run_case("NEG_CANONICAL_DECISION_UNBOUND_TO_RULE",
      setup="""UPDATE public.lf_decisiones_gov SET raw_payload=jsonb_set(
        raw_payload,'{rule_code}','"UNRELATED-RULE-001"'::jsonb,true)
       WHERE decision_number=101;""")
    check("CANONICAL_DECISION_MUST_BIND_TO_EXACT_RULE",
      "CANONICAL_DECISION_RULE_BINDING_MISSING" in unbound["DECISION"]["blocking_codes"]
      and unbound["APPLY"]["status"]=="BLOCKED",unbound)
    source_drift=run_case("NEG_CANONICAL_SOURCE_CHANGED_AFTER_JUDGE",
      after_decision="""UPDATE public.lf_decisiones_gov SET raw_payload=
       jsonb_set(raw_payload,'{source}','"CHANGED_AFTER_DECISION"'::jsonb,true)
       WHERE decision_number=101;""")
    check("SOURCE_CHANGE_AFTER_JUDGE_INVALIDATES_RECEIPT",
      source_drift["DECISION"]["status"]=="APPROVED"
      and source_drift["APPLY"]["blocking_code"]=="PROMOTION_JUDGE_RECEIPT_NOT_CURRENT",source_drift)
    stale=run_case("NEG_HASH_TAMPER",
      before_judge="UPDATE lf_ops.reglas SET descripcion='TAMPERED' WHERE codigo='RULE-TEST-001';")
    check("HASH_TAMPER_BLOCKED",
      "RULE_SNAPSHOT_CHANGED" in stale["DECISION"]["blocking_codes"],stale)
    self_decider=run_case("NEG_DECIDER_IS_REQUESTER",
      decide_actor="PERFIL-PRODUCT-DIRECTOR-LF")
    check("SAME_ACTOR_FOR_REQUEST_AND_DECIDE_BLOCKED",
      self_decider["DECISION"]["blocking_code"]=="DECIDER_NOT_SEPARATE_FROM_REQUESTER"
      and self_decider["APPLY"]["status"]=="BLOCKED",self_decider)
    human=run_case("NEG_HUMAN_AUTHORITY_UNVERIFIED",
      setup="""UPDATE public.lf_decisiones_gov SET raw_payload=jsonb_set(
       raw_payload,'{authority_class}','"HUMAN_ONLY"'::jsonb,true)
       WHERE decision_number=101;""",
      after_apply="""SELECT 'HUMAN_TEXT_DECIDE|'||
       public.lf_rule_promotion_decide_v1('PROM-TEST','APPROVE',
       'HUMAN:CLAIM_ONLY','unverified')::text;""")
    check("HUMAN_ONLY_REAL_AUTHORITY_NOT_TEXT",
      human["DECISION"]["status"]=="HUMAN_DECISION_REQUIRED"
      and human["HUMAN_TEXT_DECIDE"]["blocking_code"]=="AUTHENTICATED_HUMAN_RECEIPT_REQUIRED",
      human)
    print("LF_RULE_PROMOTION_PG18_PASS",N,flush=True)

if __name__=="__main__":
    main()
