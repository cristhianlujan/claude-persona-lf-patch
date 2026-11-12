#!/usr/bin/env python3
"""L7 exact-citation capture — PG18 disposable-only, ROLLBACK.

Quotes are constructed by THIS TEST from lote4c_fresh_blind_v1.json.
They are NOT excerpts retained from the auditor's five chats, NOT official
Step70 attestations and NOT true #3682 external receipts.
"""
import hashlib
import json
import os
import subprocess
from pathlib import Path
import test_pg18_lote5_real_verdict_profile_return as l5
import test_pg18_lote4b_validator_reuse as base

ROOT=Path(__file__).resolve().parents[3]
BLIND=ROOT/"sandbox/lf_contract_gate_test/rule_promotion_v1/lote4c_fresh_blind_v1.json"
M7=ROOT/"supabase/migrations/20261111235500_lf_rule_promotion_exact_citation_capture_v1.sql"
DB="lf_3779_l7_exact_citation_pg18"
BLIND_SHA=hashlib.sha256(BLIND.read_bytes()).hexdigest()
CASES={c["id"]:c for c in json.loads(BLIND.read_text(encoding="utf-8"))["cases"]}
N=0

def sql(s):return base.sql(s,db=DB)
def check(name,ok,raw):
    global N
    print("RAW_L7_"+name+" "+json.dumps(raw,sort_keys=True,ensure_ascii=False,default=str),flush=True)
    if not ok:raise AssertionError("L7_FAIL_"+name+" "+json.dumps(raw,sort_keys=True,default=str)[:3700])
    N+=1
    print("PASS_L7_"+name,flush=True)

def jlit(v):return base.lit(json.dumps(v,ensure_ascii=False,sort_keys=True))
def lit(v):return base.lit(v)

def seed(case_id,promo="PROM-L7",verdict="ALLOW",quote=None,with_step70=True):
    c=CASES[case_id]
    rule=c["base_rule"]["code"]
    if quote is None:quote=c["base_rule"]["description"]
    line=case_id+"|"+verdict+"|"+quote
    src=jlit(c["base_rule"])
    prop=jlit(c["proposal"])
    rid=lit(rule)
    return f"""
    INSERT INTO lf_ops.reglas(id,codigo,descripcion,estado,owner_name,origen,created_by,valor_config)
    SELECT coalesce((SELECT max(id) FROM lf_ops.reglas),0)+1,
       {rid},{lit(c["base_rule"]["description"])},'CANDIDATO',
       'LF_GOVERNANCE','DEC-GOV-TEST','PG18_L7_FIXTURE',
       (SELECT valor_config FROM lf_ops.reglas WHERE codigo='RULE-TEST-001')
    WHERE NOT EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo={rid});
    INSERT INTO public.lf_rule_promotion_v1(
      promotion_id,rule_code,request_execution_id,requested_by_profile,
      request_snapshot_sha256,status,ig_semantic_run_id,
      ig_semantic_packet_sha256,ig_semantic_candidate_sha256,ig_semantic_binding_sha256,
      ig_semantic_external_receipt,ig_semantic_external_receipt_sha256)
    SELECT {lit(promo)},{rid},'EXEC-PARENT-TEST-001','PERFIL-PRODUCT-DIRECTOR-LF',
      public.lf_asset_snapshot_sha_v1('REGLA',{rid}),'PENDING',
      {9001 if promo=="PROM-L7" else 9002},repeat('b',64),repeat('a',64),repeat('c',64),
      jsonb_build_object('l5_blind_case_verdict',jsonb_build_object(
        'id',{lit(case_id)},'verdict',{lit(verdict)},
        'exact_excerpt',{lit(quote)},'source_code',{rid},
        'source_sha256',public.lf_asset_snapshot_sha_v1('REGLA',{rid}),
        'rule_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',{rid}),
        'packet_sha256',repeat('b',64),'candidate_sha256',repeat('a',64),
        'quote_provenance','UNVERIFIED_NOT_FROM_REAL_REVIEW')),
      repeat('0',64);
    UPDATE public.lf_rule_promotion_v1
    SET ig_semantic_external_receipt_sha256=encode(extensions.digest(
      convert_to(ig_semantic_external_receipt::text,'UTF8'),'sha256'),'hex')
    WHERE promotion_id={lit(promo)};
    SET LOCAL ROLE lf_rule_citation_source_custodian;
    SELECT 'SOURCE_{promo}|'||public.lf_rule_promotion_citation_source_publish_v1(
       {lit(promo)},{lit(case_id)},{src}::jsonb,{prop}::jsonb,
       {lit(BLIND_SHA)},'github:cc4d/lote4c_fresh_blind_v1.json')::text;
    RESET ROLE;
    """+ (f"""
    UPDATE public.lf_operation_execution_steps st
    SET evidence_ref='PG18_STEP70_CONSTRUCTED_NOT_REVIEW',
      created_by_execution_id='EXEC-PARENT-TEST-001',
      evidence_payload=st.evidence_payload || jsonb_build_object(
         'test_only_synthetic',false,
         'semantic_judge_result',jsonb_build_object('status','PASS','validator_status','PASS'),
         'sandbox_fixture_provenance','PG18_CONSTRUCTED_NOT_REVIEW',
         'rule_promotion_citation_line',{lit(line)},
         'rule_promotion_citation_case_id',{lit(case_id)},
         'rule_promotion_citation_source_sha256',s.frozen_case_sha256,
         'rule_promotion_citation_ig_receipt_sha256',p.ig_semantic_external_receipt_sha256,
         'rule_promotion_citation_provenance','UNVERIFIED_NOT_FROM_REAL_REVIEW')
    FROM public.lf_rule_promotion_citation_source_v1 s
    JOIN public.lf_rule_promotion_v1 p ON p.promotion_id=s.promotion_id
    WHERE st.execution_id='EXEC-PARENT-TEST-001' AND st.step_id='semantic_judge'
      AND s.promotion_id={lit(promo)};
    """ if with_step70 else "")

def run(case_id="K00E813F0",quote=None,verdict="ALLOW",mode="valid"):
    c=CASES[case_id]
    if quote is None:quote=c["base_rule"]["description"]
    line=case_id+"|"+verdict+"|"+quote
    source_sql=seed(case_id,verdict=verdict,quote=quote)
    sql_after=""
    if mode=="drift":
        sql_after=f"UPDATE lf_ops.reglas SET descripcion=descripcion||' CHANGED_AFTER_CAPTURE' WHERE codigo={lit(c['base_rule']['code'])};"
    if mode=="hash":
        sql_after="UPDATE public.lf_rule_promotion_v1 SET ig_semantic_external_receipt_sha256=repeat('f',64) WHERE promotion_id='PROM-L7';"
    script=f"""BEGIN;
      {source_sql}
      SELECT 'LINE|'||public.lf_rule_promotion_citation_line_check_v1(
         'PROM-L7',{lit(line)})::text;
      SET LOCAL ROLE lf_rule_citation_step70_bridge;
      SELECT 'CAPTURE|'||public.lf_rule_promotion_citation_record_v1(
        'PROM-L7',{lit(line)},'EXEC-PARENT-TEST-001')::text;
      RESET ROLE;
      SELECT 'GATE_BEFORE|'||public.lf_rule_promotion_citation_verify_v1('PROM-L7')::text;
      {sql_after}
      SELECT 'GATE_AFTER|'||public.lf_rule_promotion_citation_verify_v1('PROM-L7')::text;
      SELECT 'APPLY|'||public.lf_rule_promotion_apply_v1('PROM-L7')::text;
      SELECT 'WITHIN_TX|'||jsonb_build_object(
        'rule_state',(SELECT estado FROM lf_ops.reglas WHERE codigo={lit(c["base_rule"]["code"])}),
        'capture_rows',(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1),
        'promotion_status',(SELECT status FROM public.lf_rule_promotion_v1 WHERE promotion_id='PROM-L7')
      )::text;
      ROLLBACK;
      SELECT 'ROLLBACK|'||jsonb_build_object(
        'case_source_rows',(SELECT count(*) FROM public.lf_rule_promotion_citation_source_v1),
        'capture_rows',(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1),
        'case_rule_rows',(SELECT count(*) FROM lf_ops.reglas WHERE codigo={lit(c["base_rule"]["code"])}))::text;
    """
    return sql(script)

def reuse_quote():
    a,b=CASES["K00E813F0"],CASES["K00A5FECB"]
    assert a["base_rule"]["code"]==b["base_rule"]["code"]
    quote=a["base_rule"]["description"]
    line1="K00E813F0|ALLOW|"+quote
    line2="K00A5FECB|BLOCK|"+quote
    script=f"""BEGIN;
      {seed("K00E813F0","PROM-L7","ALLOW",quote)}
      SET LOCAL ROLE lf_rule_citation_step70_bridge;
      SELECT 'FIRST|'||public.lf_rule_promotion_citation_record_v1(
        'PROM-L7',{lit(line1)},'EXEC-PARENT-TEST-001')::text;
      RESET ROLE;
      {seed("K00A5FECB","PROM-L7-SECOND","BLOCK",quote)}
      SET LOCAL ROLE lf_rule_citation_step70_bridge;
      SELECT 'SECOND|'||public.lf_rule_promotion_citation_record_v1(
        'PROM-L7-SECOND',{lit(line2)},'EXEC-PARENT-TEST-001')::text;
      RESET ROLE;
      SELECT 'WITHIN|'||jsonb_build_object('captures',
       (SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1))::text;
      ROLLBACK;
      SELECT 'ROLLBACK|'||jsonb_build_object('captures',
       (SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1))::text;
    """
    return sql(script)

def other_rule_quote():
    a=CASES["K00E813F0"]
    b=CASES["K00A10207"]
    line="K00E813F0|ALLOW|"+b["base_rule"]["description"]
    script=f"""BEGIN;
      {seed("K00E813F0",with_step70=False)}
      SELECT 'CROSS|'||public.lf_rule_promotion_citation_line_check_v1(
        'PROM-L7',{lit(line)})::text;
      SET LOCAL ROLE lf_rule_citation_source_custodian;
      SELECT 'WRONG_CASE|'||public.lf_rule_promotion_citation_source_publish_v1(
       'PROM-L7','K00A10207',{jlit(b['base_rule'])}::jsonb,
       {jlit(b['proposal'])}::jsonb,
       {lit(BLIND_SHA)},'github:cc4d/lote4c_fresh_blind_v1.json')::text;
      RESET ROLE;
      ROLLBACK;"""
    return sql(script)

def injected_quote():
    c=CASES["K00FE8562"]
    quote=c["proposal"]["description"]
    line="K00FE8562|BLOCK|"+quote
    script=f"""BEGIN;
    {seed("K00FE8562",verdict="BLOCK",quote=quote,with_step70=False)}
    SELECT 'INJECT|'||public.lf_rule_promotion_citation_line_check_v1(
      'PROM-L7',{lit(line)})::text;
    ROLLBACK;"""
    return sql(script)

def main():
    l5.DB=DB
    l5.l4d.DB=DB
    l5.bootstrap()
    sql(M7.read_text(encoding="utf-8"))
    md5=sql("""SELECT 'MD5|'||jsonb_build_object(
      'l5_blind_before','5dcdf7d9ebe4fc53cb80c80514f5c44f',
      'l7_blind_after',md5(pg_get_functiondef('public.lf_rule_promotion_blind_verdict_verify_v1(text)'::regprocedure)),
      'apply_before','bc5d3b6b39e755915d61a99a9cb4926d',
      'apply_after',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
      'source_publish',md5(pg_get_functiondef('public.lf_rule_promotion_citation_source_publish_v1(text,text,jsonb,jsonb,text,text)'::regprocedure)),
      'line_check',md5(pg_get_functiondef('public.lf_rule_promotion_citation_line_check_v1(text,text)'::regprocedure)),
      'step70_record',md5(pg_get_functiondef('public.lf_rule_promotion_citation_record_v1(text,text,text)'::regprocedure)),
      'citation_verify',md5(pg_get_functiondef('public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure)))::text;""")["MD5"]
    print("RAW_L7_MD5 "+json.dumps(md5,sort_keys=True),flush=True)
    acl=sql("""SELECT 'ACL|'||jsonb_build_object(
      'service_src_dml',has_table_privilege('service_role','public.lf_rule_promotion_citation_source_v1','INSERT'),
      'service_capture_dml',has_table_privilege('service_role','public.lf_rule_promotion_citation_capture_v1','INSERT'),
      'service_capture_rpc',has_function_privilege('service_role','public.lf_rule_promotion_citation_record_v1(text,text,text)','EXECUTE'),
      'anon_capture_rpc',has_function_privilege('anon','public.lf_rule_promotion_citation_record_v1(text,text,text)','EXECUTE'),
      'bridge_capture_rpc',has_function_privilege('lf_rule_citation_step70_bridge','public.lf_rule_promotion_citation_record_v1(text,text,text)','EXECUTE'),
      'bridge_capture_dml',has_table_privilege('lf_rule_citation_step70_bridge','public.lf_rule_promotion_citation_capture_v1','INSERT'),
      'bridge_login',(SELECT rolcanlogin FROM pg_roles WHERE rolname='lf_rule_citation_step70_bridge'))::text;""")["ACL"]
    check("NO_IG_SERVICE_ROLE_DML_OR_CAPTURE_RPC",
       acl=={"service_src_dml":False,"service_capture_dml":False,
             "service_capture_rpc":False,"anon_capture_rpc":False,
             "bridge_capture_rpc":True,"bridge_capture_dml":False,
             "bridge_login":False},acl)
    x=run()
    check("LITERAL_BASE_RULE_VALID_REVIEW_ONLY",
       x["SOURCE_PROM-L7"]["status"]=="SOURCE_FROZEN"
       and x["LINE"]["status"]=="LITERAL_STRUCTURE_VERIFIED_FOR_CAPTURE"
       and x["LINE"]["literal_origin"]=="BASE_RULE"
       and x["CAPTURE"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
       and x["GATE_BEFORE"]["status"]=="PROFILE_OWNER_REVIEW_ONLY"
       and x["GATE_BEFORE"]["next_actor"]=="PROFILE_OWNER"
       and x["APPLY"]["status"]=="BLOCKED"
       and x["ROLLBACK"]["case_source_rows"]==0 and x["ROLLBACK"]["capture_rows"]==0,x)
    for name,quote in [("FABRICATED","Esta supuesta cita fabricada no aparece en el texto original de la regla ni en su propuesta y debe rechazarse."),("EMPTY",""),("TRIVIAL","a")]:
        r=run(quote=quote)
        check(name+"_QUOTE_REJECTED",
          (name!="FABRICATED" or r["LINE"]["blocking_code"]=="L7_QUOTE_NOT_LITERAL_IN_FROZEN_TEXT")
          and r["LINE"]["status"]=="HUMAN_DECISION_REQUIRED"
          and r["CAPTURE"]["status"]=="HUMAN_DECISION_REQUIRED"
          and r["GATE_BEFORE"]["status"]=="HUMAN_DECISION_REQUIRED"
          and r["APPLY"]["status"]=="BLOCKED"
          and r["WITHIN_TX"]["rule_state"]=="CANDIDATO",r)
    cross=other_rule_quote()
    check("OTHER_RULE_QUOTE_AND_SOURCE_REJECTED",
       cross["CROSS"]["status"]=="HUMAN_DECISION_REQUIRED"
       and cross["WRONG_CASE"]["blocking_code"]=="L7_SOURCE_OR_RULE_MISMATCH",cross)
    reused=reuse_quote()
    check("QUOTE_REUSE_DIFFERENT_CASE_REJECTED",
       reused["FIRST"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
       and reused["SECOND"]["blocking_code"]=="L7_QUOTE_OR_CASE_REUSED"
       and reused["WITHIN"]["captures"]==1
       and reused["ROLLBACK"]["captures"]==0,reused)
    drift=run(mode="drift")
    check("RULE_MUTATION_AFTER_CAPTURE_BLOCKS_APPLY",
      drift["GATE_BEFORE"]["status"]=="PROFILE_OWNER_REVIEW_ONLY"
      and drift["GATE_AFTER"]["status"]=="HUMAN_DECISION_REQUIRED"
      and drift["APPLY"]["blocking_code"]=="L7_EXACT_CITATION_NOT_CURRENT"
      and drift["WITHIN_TX"]["rule_state"]=="CANDIDATO",drift)
    hash_drift=run(mode="hash")
    check("IG_RECEIPT_HASH_DRIFT_BLOCKS_APPLY",
       hash_drift["GATE_AFTER"]["status"]=="HUMAN_DECISION_REQUIRED"
       and hash_drift["APPLY"]["status"]=="BLOCKED"
       and hash_drift["APPLY"]["blocking_code"]=="L7_EXACT_CITATION_NOT_CURRENT",hash_drift)
    block=run(case_id="K00A10207",verdict="BLOCK")
    check("BLOCK_WITH_VALID_LITERAL_ESCALATES_HUMAN_NEVER_PROMOTES",
       block["LINE"]["status"]=="LITERAL_STRUCTURE_VERIFIED_FOR_CAPTURE"
       and block["CAPTURE"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
       and block["GATE_BEFORE"]["status"]=="HUMAN_DECISION_REQUIRED"
       and block["APPLY"]["status"]=="BLOCKED"
       and block["WITHIN_TX"]["rule_state"]=="CANDIDATO",block)
    injected=injected_quote()
    check("QUOTED_PROMPT_INJECTION_IS_DATA_VERDICT_UNCHANGED",
       injected["INJECT"]["status"]=="LITERAL_STRUCTURE_VERIFIED_FOR_CAPTURE"
       and injected["INJECT"]["verdict"]=="BLOCK"
       and injected["INJECT"]["literal_origin"]=="PROPOSAL",injected)
    print("LF_L7_EXACT_CITATION_PG18_PASS checks="+str(N),flush=True)
    print("L7_TEST_QUOTES=UNVERIFIED_NOT_FROM_REAL_REVIEW NATIVE_IG_RECEIPT=false PROFILE_OWNER_APPROVAL_ATTESTED=false",flush=True)
    print("ROLLBACK_ALL=true ACTUAL_USER_5PASS_CITATIONS=NOT_CAPTURED AUTO_PROMOTIONS=0",flush=True)
if __name__=="__main__":
    main()
