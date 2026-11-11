#!/usr/bin/env python3
"""Issue #3779: isolated PG18 one-rule tests; no LF production access."""
import json
import os
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
DB="lf_3779_step40_pg18"
FIX=ROOT/"sandbox/lf_contract_gate_test/rule_scope_v1/step40_pg18_fixture.sql"
BASE=ROOT/"sandbox/lf_contract_gate_test/rule_scope_v1/lf_profile_input_validate_live_9293aa23_fixture.sql"
MIG=ROOT/"supabase/migrations/20261111170000_lf_profile_input_governance_rule_scope_loop_v1.sql"
LIVE_MD5="9293aa23cb29f3bb984a37799b6e5ff3"
CASES=0

def sql(query,db=DB,fail=False):
    env=dict(os.environ)
    env.setdefault("PGHOST","127.0.0.1")
    env.setdefault("PGPORT","5432")
    env.setdefault("PGUSER","postgres")
    env.setdefault("PGPASSWORD","postgres")
    p=subprocess.run(["psql","-X","-q","-A","-t","-v","ON_ERROR_STOP=1","-d",db],
        input=query,text=True,capture_output=True,env=env,timeout=300)
    if fail:
        if not p.returncode: raise AssertionError("FAIL_EXPECTED_SQL_REJECTION")
        return p.stderr.strip()
    if p.returncode: raise AssertionError("FAIL_PG_SQL:"+p.stderr[-2500:])
    return p.stdout.strip()

def check(name,okay,raw=None):
    global CASES
    if not okay: raise AssertionError("FAIL_"+name+" "+str(raw)[:1900])
    CASES+=1
    print("PASS_"+name,flush=True)

def h(scope):
    return {
        "schema_version":"LF_ROUTER_HANDOFF_TEST",
        "profile_code":"PERFIL-PRODUCT-DIRECTOR-LF",
        "fingerprint_sha256":"b"*64,
        "router_authorization_receipt":{"profile_execution_allowed":True},
        "scope":scope,
        "semantic_request":{"router_action_binding":{
            "profile_task_intent":"RULE_ADMINISTRATIVE_REVIEW",
            "input_governance_requirement":"REQUIRED_BY_TASK"}}
    }

def seed(code,scope,screen_selection=None):
    hand=h(scope)
    manifest={"router_profile_handoff":hand,"read_only":True,
        "no_write":True,"no_promotion":True}
    if screen_selection: manifest["screen_selection_result"]=screen_selection
    def quote(s): return s.replace("'","''")
    sql("INSERT INTO public.lf_operation_execution"
        "(execution_id,operation_code,target_type,target_code,status,manifest)"
        "VALUES('"+quote(code)+"','EJECUCION_PERFIL_LF','PERFIL',"
        "'PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS','"+
        quote(json.dumps(manifest))+"'::jsonb);")
    return hand

def invoke(code,hand):
    raw=json.dumps(hand,ensure_ascii=False,sort_keys=True).replace("'","''")
    value=sql("SELECT public.lf_profile_execution_input_validate_v1("
             "'"+code+"','literal request','synthetic://user-test',"
             "'"+raw+"'::jsonb);")
    v=json.loads(value)
    print("RAW_CASE "+json.dumps({"case":code,"result":v},ensure_ascii=False,sort_keys=True),flush=True)
    return v

def main():
    orig=BASE.read_text(encoding="utf-8").split("\n",1)[1].strip().removesuffix(";")
    migr=MIG.read_text(encoding="utf-8")
    before="""    IF v_direct_profile_ig THEN
      IF upper(coalesce(p_handoff#>>'{scope,target_type}',''))<>'PANTALLA' THEN"""
    after="""    IF v_direct_profile_ig AND upper(coalesce(p_handoff#>>'{scope,target_type}',''))='REGLA' THEN
      v_ig:=public.lf_profile_rule_screen_loop_preflight_v1(p_execution_id,p_handoff);
    ELSIF v_direct_profile_ig THEN
      IF upper(coalesce(p_handoff#>>'{scope,target_type}',''))<>'PANTALLA' THEN"""
    newsrc=orig.replace(before,after)
    assert before in orig and orig.count(before)==1
    # Exact source-level comparison proves no mutation of original PANTALLA path.
    embedded=migr[migr.index("CREATE OR REPLACE FUNCTION public.lf_profile_execution_input_validate_v1"):
      migr.index("\nREVOKE ALL ON FUNCTION public.lf_profile_execution_input_validate_v1")]
    check("PANTALLA_SOURCE_IDENTICAL_EXCEPT_RULE_DISPATCH",
          embedded.strip().removesuffix(";")==newsrc)
    sql("CREATE DATABASE "+DB+";",db="postgres")
    sql(FIX.read_text(encoding="utf-8"))
    sql(BASE.read_text(encoding="utf-8"))
    md5_before=sql("SELECT md5(pg_get_functiondef("
      "'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure));")
    print("RAW_MD5_BEFORE "+md5_before,flush=True)
    check("STEP40_LIVE_MD5_BASELINE",md5_before==LIVE_MD5)
    sql(MIG.read_text(encoding="utf-8"))
    md5_after=sql("SELECT md5(pg_get_functiondef("
      "'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure));")
    print("RAW_MD5_AFTER "+md5_after,flush=True)
    check("STEP40_MD5_CHANGED",md5_after!=md5_before and len(md5_after)==32)
    # One rule, one active screen, CURRENTNESS_AUTHORITY confirms source CURRENT.
    active=seed("EXEC-ACTIVE",{"target_type":"REGLA",
        "resolution_status":"RESOLVED","target_hint":"RULE-ACTIVE-001"})
    r=invoke("EXEC-ACTIVE",active)
    check("ONE_RULE_ACTIVE_CURRENT_POSITIVE",
          r["status"]=="READY" and r["input_governance"]["screen_count"]==1
          and r["input_governance"]["screen_results"][0]["source_current"] is True
          and r["input_governance"]["mutation_authorized"] is False,r)
    # One rule with NO screen: canonical RULE source, never fabricated screen IG.
    unlinked=seed("EXEC-UNLINKED",{"target_type":"REGLA",
        "resolution_status":"RESOLVED","target_hint":"RULE-UNLINKED-001"})
    r=invoke("EXEC-UNLINKED",unlinked)
    check("ONE_RULE_NO_SCREEN_CANONICAL_POSITIVE",
          r["status"]=="READY" and r["input_governance"]["screen_count"]==0
          and r["input_governance"]["no_screen_rule_count"]==1
          and r["input_governance"]["canonical_rule_exceptions"][0]["screen_ig_ready"] is False,r)
    # Inactive-only: MUST block even though a real relation exists.
    inactive=seed("EXEC-INACTIVE",{"target_type":"REGLA",
        "resolution_status":"RESOLVED","target_hint":"RULE-INACTIVE-001"})
    r=invoke("EXEC-INACTIVE",inactive)
    check("ONLY_INACTIVE_WITHOUT_SCOPE_DECISION_BLOCKS",
          r["blocking_code"]=="BLOCK_PROFILE_RULE_IG_INACTIVE_SCREEN_SCOPE_UNATTESTED",r)
    missing=seed("EXEC-NOT-FOUND",{"target_type":"REGLA",
        "resolution_status":"RESOLVED","target_hint":"RULE-MISSING-001"})
    r=invoke("EXEC-NOT-FOUND",missing)
    check("NONEXISTENT_RULE_BLOCKS",r["blocking_code"]=="BLOCK_PROFILE_RULE_IG_RULE_NOT_FOUND",r)
    bad_hash=seed("EXEC-HASH-DRIFT",{"target_type":"REGLA",
        "resolution_status":"RESOLVED","target_hint":"RULE-ACTIVE-001",
        "expected_rule_sha256":"0"*64})
    r=invoke("EXEC-HASH-DRIFT",bad_hash)
    check("ALTERED_RULE_SHA_BLOCKS",r["blocking_code"]=="BLOCK_PROFILE_RULE_IG_SOURCE_HASH_CHANGED",r)
    altered=dict(active)
    altered["scope"]=dict(active["scope"],target_hint="RULE-UNLINKED-001")
    r=invoke("EXEC-ACTIVE",altered)
    check("TAMPERED_PARENT_SCOPE_BLOCKS",
          r["blocking_code"]=="BLOCK_PROFILE_RULE_IG_HANDOFF_SCOPE_CHANGED",r)
    sql("UPDATE programacion.fake_ig_state SET source_current=false WHERE pantalla_id=101;")
    r=invoke("EXEC-ACTIVE",active)
    check("SCREEN_IG_NOT_CURRENT_BLOCKS",
          r["blocking_code"]=="BLOCK_PROFILE_RULE_IG_SCREEN_NOT_CURRENT",r)
    sql("UPDATE programacion.fake_ig_state SET source_current=true WHERE pantalla_id=101;")
    sel={"decision":"SELECTED","selected_screen_code":"SCREEN-A",
         "semantic_receipt_sha256":"c"*64}
    screen=seed("EXEC-PANTALLA",{"target_type":"PANTALLA",
        "resolution_status":"RESOLVED","target_hint":"SCREEN-A"},sel)
    r=invoke("EXEC-PANTALLA",screen)
    check("PANTALLA_REAL_RUNTIME_REGRESSION",
          r["status"]=="READY" and
          r["input_governance"]["binding_mode"]=="DIRECT_PROFILE",r)
    # Step40 is a STABLE read-only attestation: a second READ does not replay WRITE.
    a=invoke("EXEC-ACTIVE",active)
    b=invoke("EXEC-ACTIVE",active)
    check("REPEATED_STEP40_READ_ONLY_NO_EFFECT",
          a["status"]=="READY" and b["status"]=="READY"
          and sql("SELECT count(*) FROM public.lf_operation_execution")=="6"
          and sql("SELECT descripcion FROM lf_ops.reglas WHERE id=1")=="material active baseline")
    # Mutations inside a transaction roll back. No caller can grant source_current.
    sql("BEGIN; UPDATE lf_ops.reglas SET descripcion='ROLLBACK TEST' WHERE id=1; ROLLBACK;")
    check("TRANSACTION_ROLLBACK_PRESERVES_SOURCE",
          sql("SELECT descripcion FROM lf_ops.reglas WHERE id=1")=="material active baseline")
    print("LF_STEP40_RULE_SCOPE_PG18_PASS",CASES,flush=True)

if __name__=="__main__":
    main()
