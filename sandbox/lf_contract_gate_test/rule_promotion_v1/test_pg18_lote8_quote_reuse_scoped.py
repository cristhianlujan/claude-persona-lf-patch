#!/usr/bin/env python3
"""LF L8: scoped quote reuse, disposable PG18, every scenario ROLLBACK.
Real blind K IDs are used as test data; all quotes are CONSTRUCTED HERE, not
the user's five reviewer quotations. No #3682 native receipt or owner approval.
"""
import copy
import json
from pathlib import Path
import test_pg18_lote7_exact_citation_capture as l7
from test_pg18_lote7_exact_citation_capture import lit

DB="lf_3779_l8_quote_scope_pg18"
N=0

def sql(q): return l7.base.sql(q,db=DB)
def check(code,condition,raw):
    global N
    print("RAW_L8_"+code+" "+json.dumps(raw,sort_keys=True,ensure_ascii=False,default=str),flush=True)
    if not condition:
        raise AssertionError("L8_FAIL_"+code+" "+json.dumps(raw,sort_keys=True,default=str)[:3500])
    N+=1
    print("PASS_L8_"+code,flush=True)

def distinct_parent_sql():
    return """INSERT INTO public.lf_operation_execution(
       execution_id,operation_code,target_code,status,manifest)
       SELECT 'EXEC-PARENT-TEST-002',operation_code,target_code,status,manifest
       FROM public.lf_operation_execution
       WHERE execution_id='EXEC-PARENT-TEST-001';
       INSERT INTO public.lf_operation_execution_steps(
         execution_id,step_id,status,evidence_payload,evidence_ref,created_by_execution_id)
       SELECT 'EXEC-PARENT-TEST-002',step_id,status,evidence_payload,evidence_ref,
         CASE WHEN created_by_execution_id IS NULL THEN NULL ELSE 'EXEC-PARENT-TEST-002' END
       FROM public.lf_operation_execution_steps
       WHERE execution_id='EXEC-PARENT-TEST-001';"""

def two_base_quotes(different_rule=False):
    first="K00E813F0"
    second="K00A10207" if different_rule else "K00A5FECB"
    original=copy.deepcopy(l7.CASES[second])
    quote=l7.CASES[first]["base_rule"]["description"]
    if different_rule:
        # Adversarial synthetic collision: the original different rule DOES
        # NOT contain this text. Mutate only the disposable fixture to prove
        # that even two individually literal base citations cannot cross rules.
        clone=copy.deepcopy(original)
        clone["base_rule"]["description"]=quote
        l7.CASES[second]=clone
    try:
        line1=first+"|ALLOW|"+quote
        line2=second+"|BLOCK|"+quote
        statement=f"""BEGIN;
          {l7.seed(first,"PROM-L7","ALLOW",quote)}
          SET LOCAL ROLE lf_rule_citation_step70_bridge;
          SELECT 'FIRST|'||public.lf_rule_promotion_citation_record_v1(
            'PROM-L7',{lit(line1)},'EXEC-PARENT-TEST-001')::text;
          RESET ROLE;
          {distinct_parent_sql()}
          {l7.seed(second,"PROM-L7-SECOND","BLOCK",quote,capture_run="EXEC-PARENT-TEST-002")}
          SELECT 'SECOND_LINE|'||public.lf_rule_promotion_citation_line_check_v1(
            'PROM-L7-SECOND',{lit(line2)})::text;
          SET LOCAL ROLE lf_rule_citation_step70_bridge;
          SELECT 'SECOND|'||public.lf_rule_promotion_citation_record_v1(
            'PROM-L7-SECOND',{lit(line2)},'EXEC-PARENT-TEST-002')::text;
          RESET ROLE;
          SELECT 'READBACK|'||jsonb_build_object(
            'captures',(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1),
            'same_quote',(SELECT count(DISTINCT quote_sha256) FROM public.lf_rule_promotion_citation_capture_v1),
            'same_rule',(SELECT count(DISTINCT s.rule_code)
              FROM public.lf_rule_promotion_citation_capture_v1 c
              JOIN public.lf_rule_promotion_citation_source_v1 s
              USING(promotion_id,case_id)),
            'first_origin',(SELECT literal_origin FROM public.lf_rule_promotion_citation_capture_v1 WHERE promotion_id='PROM-L7'),
            'second_origin',(SELECT literal_origin FROM public.lf_rule_promotion_citation_capture_v1 WHERE promotion_id='PROM-L7-SECOND'))::text;
          SELECT 'FIRST_GATE|'||public.lf_rule_promotion_citation_verify_v1('PROM-L7')::text;
          SELECT 'SECOND_GATE|'||public.lf_rule_promotion_citation_verify_v1('PROM-L7-SECOND')::text;
          ROLLBACK;
          SELECT 'ROLLBACK|'||jsonb_build_object(
            'captures',(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1),
            'sources',(SELECT count(*) FROM public.lf_rule_promotion_citation_source_v1))::text;"""
        return sql(statement)
    finally:
        l7.CASES[second]=original

def same_case_twice():
    case="K00E813F0"
    quote=l7.CASES[case]["base_rule"]["description"]
    line=case+"|ALLOW|"+quote
    return sql(f"""BEGIN;
      {l7.seed(case)}
      SET LOCAL ROLE lf_rule_citation_step70_bridge;
      SELECT 'FIRST|'||public.lf_rule_promotion_citation_record_v1(
        'PROM-L7',{lit(line)},'EXEC-PARENT-TEST-001')::text;
      SELECT 'SECOND|'||public.lf_rule_promotion_citation_record_v1(
        'PROM-L7',{lit(line)},'EXEC-PARENT-TEST-001')::text;
      RESET ROLE;
      SELECT 'READBACK|'||jsonb_build_object(
        'captures',(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1))::text;
      ROLLBACK;
      SELECT 'ROLLBACK|'||(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1)::text;""")

def main():
    l7.DB=DB
    l7.l5.DB=DB
    l7.l5.l4d.DB=DB
    l7.l5.bootstrap()
    sql(l7.M7.read_text(encoding="utf-8"))
    q="""SELECT 'MD5|'||jsonb_build_object(
      'capture_record',md5(pg_get_functiondef(
       'public.lf_rule_promotion_citation_record_v1(text,text,text)'::regprocedure)),
      'apply',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
      'citation_verify',md5(pg_get_functiondef('public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure)),
      'existing_ig',md5(pg_get_functiondef(
       'public.lf_rule_promotion_ig_citation_verify_v1(text,jsonb,bigint,text,text,text,text,text)'::regprocedure)))::text;"""
    before=sql(q)["MD5"]
    sql(l7.M8.read_text(encoding="utf-8"))
    after=sql(q)["MD5"]
    guard_sha=sql("""SELECT 'NEW|'||jsonb_build_object(
       'scope_guard_md5',md5(pg_get_functiondef(
        'public.lf_rule_promotion_citation_scope_guard_v2()'::regprocedure)),
       'table_pk',(SELECT string_agg(att.attname,',' ORDER BY key.ord)
        FROM pg_constraint c
        JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS key(attnum,ord) ON TRUE
        JOIN pg_attribute att ON att.attrelid=c.conrelid AND att.attnum=key.attnum
        WHERE c.conrelid='public.lf_rule_promotion_citation_capture_v1'::regclass
          AND c.contype='p'),
       'old_global_quote_unique',(SELECT count(*) FROM pg_constraint c
        WHERE c.conrelid='public.lf_rule_promotion_citation_capture_v1'::regclass
         AND c.conname='lf_rule_promotion_citation_capture_v1_quote_sha256_key'),
       'proposal_partial_unique',(SELECT count(*) FROM pg_indexes
        WHERE schemaname='public'
         AND tablename='lf_rule_promotion_citation_capture_v1'
         AND indexname='lf_rule_promotion_proposal_quote_one_case_v2'
         AND indexdef ILIKE '%UNIQUE INDEX%'
         AND indexdef ILIKE '%WHERE (literal_origin = ''PROPOSAL''%')
    )::text;""")["NEW"]
    check("SCOPED_UNIQUE_AND_ALL_L7_MD5_UNCHANGED",
      before==after
      and before["capture_record"]=="89cbfac4162dbc9f8ecca59f2c3ab4c3"
      and before["apply"]=="86b0494984edf95cf0f9c0a0df67000b"
      and guard_sha["table_pk"]=="promotion_id,case_id"
      and guard_sha["old_global_quote_unique"]==0
      and guard_sha["proposal_partial_unique"]==1,
      {"before":before,"after":after,"structural":guard_sha})
    same=two_base_quotes()
    check("BASE_RULE_SAME_RULE_SAME_EXCERPT_BOTH_PASS",
      same["FIRST"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
      and same["SECOND_LINE"]["status"]=="LITERAL_STRUCTURE_VERIFIED_FOR_CAPTURE"
      and same["SECOND_LINE"]["literal_origin"]=="BASE_RULE"
      and same["SECOND"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
      and same["READBACK"]=={"captures":2,"same_quote":1,"same_rule":1,
                            "first_origin":"BASE_RULE","second_origin":"BASE_RULE"}
      and same["FIRST_GATE"]["status"]=="PROFILE_OWNER_REVIEW_ONLY"
      and same["SECOND_GATE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and same["SECOND_GATE"]["blocking_code"]=="L7_BLOCK_QUOTE_VERIFIED_NO_PROMOTION"
      and same["ROLLBACK"]=={"captures":0,"sources":0},same)
    proposal=l7.reuse_quote()
    check("PROPOSAL_SAME_TEXT_OTHER_CASE_REJECTED",
      proposal["FIRST"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
      and proposal["SECOND"]["blocking_code"]=="L7_QUOTE_OR_CASE_REUSED"
      and proposal["WITHIN"]["captures"]==1 and proposal["ROLLBACK"]["captures"]==0,
      proposal)
    cross=l7.other_rule_quote()
    check("OTHER_RULE_NOT_LITERAL_SOURCE_REJECTED",
      cross["CROSS"]["blocking_code"]=="L7_QUOTE_NOT_LITERAL_IN_FROZEN_TEXT"
      and cross["WRONG_CASE"]["blocking_code"]=="L7_SOURCE_OR_RULE_MISMATCH",cross)
    synthetic_cross=two_base_quotes(different_rule=True)
    check("CROSS_RULE_IDENTICAL_BASE_QUOTE_SYNTHETIC_COLLISION_REJECTED",
      synthetic_cross["FIRST"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
      and synthetic_cross["SECOND_LINE"]["status"]=="LITERAL_STRUCTURE_VERIFIED_FOR_CAPTURE"
      and synthetic_cross["SECOND"]["blocking_code"]=="L7_QUOTE_OR_CASE_REUSED"
      and synthetic_cross["READBACK"]["captures"]==1
      and synthetic_cross["ROLLBACK"]["captures"]==0,
      {"case_data_provenance":"PG18_ADVERSARIAL_TEXT_COLLISION_NOT_IN_REAL_BLIND","raw":synthetic_cross})
    twice=same_case_twice()
    check("SAME_CASE_SECOND_CAPTURE_REJECTED",
      twice["FIRST"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
      and twice["SECOND"]["blocking_code"]=="L7_QUOTE_OR_CASE_REUSED"
      and twice["READBACK"]["captures"]==1
      and twice["ROLLBACK"]==0,twice)
    print("LF_L8_SCOPED_CITATION_REUSE_PG18_PASS checks="+str(N),flush=True)
    print("L7_REGRESSION_SUITE_RUNS_SEPARATELY_ON_L8_SCHEMA=true QUOTES_CONSTRUCTED=UNVERIFIED_NOT_FROM_REAL_REVIEW",flush=True)
    print("PG18_ROLLBACK=true L8_NO_LIVE_APPLY=true NO_NATIVE_IG_RECEIPT=true",flush=True)
if __name__=="__main__":
    main()
