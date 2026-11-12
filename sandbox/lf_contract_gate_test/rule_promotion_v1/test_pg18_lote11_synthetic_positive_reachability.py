#!/usr/bin/env python3
"""L11 trust-preserving reachability check for the UNMODIFIED L7/L8 gate.
No forged official provenance. Any positive requiring a synthetic row marked
as native official is NOT_REACHABLE_WITH_HONEST_SYNTHETIC_PROVENANCE.
PG18 ROLLBACK only; this does NOT prove a happy-path E2E.
"""
import hashlib
import json
from pathlib import Path
import test_pg18_lote10_owner_declared_e2e_attestation_limits as l10
import test_pg18_lote7_exact_citation_capture as l7
import test_pg18_lote5_real_verdict_profile_return as l5

ROOT=Path(__file__).resolve().parents[3]
DATA=ROOT/"sandbox/lf_contract_gate_test/rule_promotion_v1"
DB="lf_3779_l11_positive_reachability_pg18"
LABEL="MECHANICAL_ONLY_SYNTHETIC_PROVENANCE_NOT_E2E"
CASE="K00E813F0"
N=0

def sql(s):return l7.base.sql(s,db=DB)
def lit(s):return l7.lit(s)
def check(name,passed,raw):
    global N
    print("RAW_L11_"+name+" "+json.dumps(raw,ensure_ascii=False,sort_keys=True,default=str),flush=True)
    if not passed: raise AssertionError("L11_FAIL_"+name+" "+str(raw)[:4100])
    N+=1
    print("PASS_L11_"+name,flush=True)
def md5():
    return sql("""SELECT 'MD5|'||jsonb_build_object(
     'apply',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
     'capture_record',md5(pg_get_functiondef('public.lf_rule_promotion_citation_record_v1(text,text,text)'::regprocedure)),
     'citation_verify',md5(pg_get_functiondef('public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure)),
     'l8_guard',md5(pg_get_functiondef('public.lf_rule_promotion_citation_scope_guard_v2()'::regprocedure)))::text;""")["MD5"]

def read_gate_contract():
    return sql("""SELECT 'C|'||jsonb_build_object(
      'record_rejects_test_only_synthetic',
        position('st.evidence_payload->>''test_only_synthetic''=''true''' IN
          pg_get_functiondef('public.lf_rule_promotion_citation_record_v1(text,text,text)'::regprocedure))>0,
      'verify_rejects_test_only_synthetic',
        position('st.evidence_payload->>''test_only_synthetic''=''true''' IN
          pg_get_functiondef('public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure))>0,
      'verify_requires_native_ig_provenance',
        position('x.source_provenance IS DISTINCT FROM ''OFFICIAL_STEP70_VERIFIED_NATIVE_IG''' IN
          pg_get_functiondef('public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure))>0,
      'verify_positive_name_present',
        position('VERIFIED_CAPTURE_BINDING' IN
          pg_get_functiondef('public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure))>0,
      'owner_rejects_same_ig_identity',
        position('owner_map.owner_profile_code=p.ig_semantic_validator_identity' IN
          pg_get_functiondef('public.lf_rule_promotion_profile_owner_verify_v1(text)'::regprocedure))>0,
      'readback_retries_without_vigente',
        position('RULE_READBACK_FAILED_NO_VIGENTE' IN
          pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))>0)::text;""")["C"]

def explicitly_synthetic_step70():
    case=l7.CASES[CASE]
    quote=l10.raw_lines.__globals__["QUOTES"][CASE][1] if "QUOTES" in l10.raw_lines.__globals__ else None
    if quote is None:
        quotes={x.split("|",2)[0]:x.split("|",2)[2] for x in (DATA/"lote9_real_review_pass1_chat_export_model_unattested.txt").read_text(encoding="utf-8").splitlines()}
        quote=quotes[CASE]
    line=CASE+"|ALLOW|"+quote
    return sql(f"""BEGIN;
    {l7.seed(CASE,verdict="ALLOW",quote=quote)}
    UPDATE public.lf_operation_execution_steps
    SET evidence_payload=jsonb_set(evidence_payload,
        '{{test_only_synthetic}}','true'::jsonb,true)
    WHERE execution_id='EXEC-PARENT-TEST-001' AND step_id='semantic_judge';
    SET LOCAL ROLE lf_rule_citation_step70_bridge;
    SELECT 'RECORD|'||public.lf_rule_promotion_citation_record_v1(
       'PROM-L7',{lit(line)},'EXEC-PARENT-TEST-001')::text;
    RESET ROLE;
    SELECT 'VERIFY|'||public.lf_rule_promotion_citation_verify_v1('PROM-L7')::text;
    SELECT 'APPLY|'||public.lf_rule_promotion_apply_v1('PROM-L7')::text;
    SELECT 'TX|'||jsonb_build_object(
      'candidate_state',(SELECT estado FROM lf_ops.reglas
             WHERE codigo={lit(case["base_rule"]["code"])}),
      'capture_rows',(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1))::text;
    ROLLBACK;
    SELECT 'RB|'||jsonb_build_object(
      'capture_rows',(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1),
      'source_rows',(SELECT count(*) FROM public.lf_rule_promotion_citation_source_v1))::text;""")

def owner_equals_ig_guard():
    # This is an isolated predicate/readback probe. OWNER APPROVE cannot be
    # reached for the same real K quote while the L7 native provenance is
    # unverified. Never label it an integrated owner-approval test.
    return sql("""SELECT 'O|'||jsonb_build_object(
       'same_identity_rejected_by_guard',
        ('INPUT_VALIDATOR:EDGE:input-governance-validator-v1:abcdef'
           = 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:abcdef'),
       'forbidden_identity_prefix',
        ('INPUT_VALIDATOR:EDGE:input-governance-validator-v1:abcdef'
           ~ '^(HUMAN:|INPUT_VALIDATOR:|IG:)'),
       'actual_authenticated_owner_approval_for_L11','NOT_PROVEN',
       'cannot_overcome_unverified_L7','NOT_REACHABLE')::text;""")["O"]

def main():
    l10.DB=DB
    l7.DB=DB
    l7.l5.DB=DB
    l7.l5.l4d.DB=DB
    l5.DB=DB
    l5.l4d.DB=DB
    l5.bootstrap()
    sql(l7.M7.read_text(encoding="utf-8"))
    sql(l7.M8.read_text(encoding="utf-8"))
    before=md5()
    expected={"apply":"86b0494984edf95cf0f9c0a0df67000b",
     "capture_record":"89cbfac4162dbc9f8ecca59f2c3ab4c3",
     "citation_verify":"773a62783baa5edbe967200cac66b8c3",
     "l8_guard":"522d12f0843be1da3c785cef3c0bf3fc"}
    check("GATE_MD5_FROZEN",before==expected,{"before":before,"expected":expected})
    contract=read_gate_contract()
    check("POSITIVE_CONTRACT_PRESENT_BUT_OFFICIAL_ATTESTATION_REQUIRED",
      all(contract.values()),contract)
    quotes={x.split("|",2)[0]:(x.split("|",2)[1],x.split("|",2)[2])
            for x in (DATA/"lote9_real_review_pass1_chat_export_model_unattested.txt").read_text(encoding="utf-8").splitlines()}
    real=quotes[CASE]
    check("K_REAL_ALLOW_QUOTE_SOURCE",
      real[0]=="ALLOW"
      and real[1] in l7.CASES[CASE]["proposal"]["description"],
      {"case":CASE,"verdict":real[0],"quote":real[1],
       "quote_source":"PASS1_REAL_CHAT_EXPORT_NOT_NATIVE_RECEIPT",
       "provenance":LABEL})
    # L10 already tests this exact K quote with an explicitly simulated owner.
    synthetic=l10.route(CASE,*real,variant="ALLOW")
    check("EXPLICITLY_NON_OFFICIAL_CITATION_CANNOT_PROMOTE",
      synthetic["CAPTURE"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
      and synthetic["CITATION_GATE_PRE"]["status"]=="PROFILE_OWNER_REVIEW_ONLY"
      and synthetic["APPLY"]["blocking_code"]=="L7_EXACT_CITATION_NOT_CURRENT"
      and synthetic["CLOSE_READBACK"]["rule_state"]=="CANDIDATO"
      and synthetic["ROLLBACK"]["capture_rows"]==0,
      {"label":LABEL,"case":CASE,"citation_gate":synthetic["CITATION_GATE_PRE"],
       "apply":synthetic["APPLY"],"tx":synthetic["CLOSE_READBACK"],
       "rollback":synthetic["ROLLBACK"],"owner_simulated":True})
    honest=explicitly_synthetic_step70()
    check("TEST_ONLY_SYNTHETIC_TRUE_CANNOT_CAPTURE_OFFICIAL",
      honest["RECORD"]["blocking_code"]=="L7_STEP70_VERBATIM_CAPTURE_NOT_ATTESTED"
      and honest["VERIFY"]["blocking_code"]=="L7_CITATION_MISSING_NO_AUTO_PROMOTION"
      and honest["APPLY"]["status"]=="BLOCKED"
      and honest["TX"]["candidate_state"]=="CANDIDATO"
      and honest["RB"]=={"capture_rows":0,"source_rows":0},honest)
    # Pair 1: altering a single character in the same real K quote.
    changed=real[1][:-1]+("X" if not real[1].endswith("X") else "Y")
    tamper=l7.run(case_id=CASE,verdict="ALLOW",quote=changed)
    check("PAIR1_QUOTE_ONE_CHAR_CHANGED_DENIED",
      tamper["LINE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and tamper["CAPTURE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and tamper["APPLY"]["status"]=="BLOCKED"
      and tamper["WITHIN_TX"]["rule_state"]=="CANDIDATO",
      {"line":tamper["LINE"],"capture":tamper["CAPTURE"],"apply":tamper["APPLY"]})
    # Pair 2: post-capture snapshot drift.
    drift=l10.route(CASE,*real,variant="DRIFT")
    check("PAIR2_RULE_DRIFT_AFTER_CAPTURE_DENIED_IN_APPLY",
      drift["CAPTURE"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
      and drift["CITATION_GATE_POST"]["status"]=="HUMAN_DECISION_REQUIRED"
      and drift["APPLY"]["blocking_code"]=="L7_EXACT_CITATION_NOT_CURRENT"
      and drift["READBACK"]["estado"]=="CANDIDATO",
      {"capture":drift["CAPTURE"],"verify_after":drift["CITATION_GATE_POST"],
       "apply":drift["APPLY"],"readback":drift["READBACK"]})
    # Pair 3: structural owner/IG identity predicate; integration NOT_PROVEN.
    owner=owner_equals_ig_guard()
    check("PAIR3_OWNER_EQUALS_IG_IS_FORBIDDEN_BUT_BRANCH_UNREACHED",
      owner["same_identity_rejected_by_guard"] is True
      and owner["forbidden_identity_prefix"] is True
      and owner["actual_authenticated_owner_approval_for_L11"]=="NOT_PROVEN",owner)
    # Pair 4: readback failure cannot be reached with honest L7 provenance.
    # L5 regression separately tests the rollback/retry subtransaction, but
    # this exact K fixture cannot enter it. Do not fabricate an APPROVED owner.
    rb={"scenario":"PAIR4_READBACK_FAILURE",
       "L5_readback_retry_branch_exists":contract["readback_retries_without_vigente"],
       "same_case_after_approved_with_native_receipt":"NOT_REACHABLE",
       "reason":"No authentic Step70/IG/owner. Apply must reject before performing VIGENTE write/readback.",
       "promotion_status":"PENDING","rule_state":"CANDIDATO",
       "unverified":"NO_NATIVE_READBACK_FAILURE_EXERCISED_IN_L11"}
    check("PAIR4_RETRY_BRANCH_NOT_REACHABLE_IN_HONEST_K_FIXTURE",
      rb["L5_readback_retry_branch_exists"] is True
      and rb["same_case_after_approved_with_native_receipt"]=="NOT_REACHABLE",rb)
    after=md5()
    check("MD5_BEFORE_AFTER_UNCHANGED",before==after,{"before":before,"after":after})
    stages=["Router","Perfil","RUN","IG","Curator","Validator","Retorno perfil",
            "Ejecucion","Promocion","VIGENTE","Readback","Cierre"]
    board=[{"stage":x,"status":"SANDBOX_VERIFIED" if x in ("Validator","Readback") else "NOT_PROVEN",
            "note":("Literal check and CANDIDATO negative readback proven, NOT a positive VIGENTE readback"
              if x in ("Validator","Readback") else "No authenticated native source or end-to-end execution")}
           for x in stages]
    check("12_STAGE_BOARD_UNCHANGED_GLOBAL_NOT_PROVEN",
      len(board)==12 and sum(x["status"]=="NOT_PROVEN" for x in board)==10,
      {"stages":board,"global":"NOT_PROVEN","mechanical_positive":"NOT_REACHABLE_WITH_HONEST_SYNTHETIC_PROVENANCE"})
    report={"schema_version":"LF_L11_PG18_POSITIVE_REACHABILITY_DIAG_V1",
      "label":LABEL,"global":"NOT_PROVEN",
      "mechanical_positive":"NOT_REACHABLE_WITH_HONEST_SYNTHETIC_PROVENANCE",
      "native_IG_attested":False,"official_step70_attested":False,
      "reviewer_model":"ChatGPT","reviewer_model_source":"OWNER_DECLARED_NOT_SYSTEM_ATTESTED",
      "gate_sql_contract":contract,"gate_md5_before":before,"gate_md5_after":after,
      "real_case":CASE,"real_quote":real[1],
      "controls":{
        "non_official_capture":{"capture":synthetic["CAPTURE"],"gate":synthetic["CITATION_GATE_PRE"],"apply":synthetic["APPLY"]},
        "explicit_test_only_true":{"capture":honest["RECORD"],"gate":honest["VERIFY"]},
        "quote_tamper":{"line":tamper["LINE"],"apply":tamper["APPLY"]},
        "rule_drift":{"gate":drift["CITATION_GATE_POST"],"apply":drift["APPLY"]},
        "owner_equals_IG":owner,
        "readback_failure":rb},
      "stages":board,
      "unverified":["official #3682 native receipt", "authentic Step70",
          "positive VERIFIED_CAPTURE_BINDING", "authenticated owner approval",
          "APPLIED/VIGENTE/READY via real K", "profile return and terminal closure"]}
    out=DATA/"lote11_honest_synthetic_reachability_runtime.json"
    out.write_text(json.dumps(report,ensure_ascii=False,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print("RAW_L11_BOARD "+json.dumps(board,ensure_ascii=False,sort_keys=True),flush=True)
    print("RAW_L11_REPORT "+json.dumps({"file":out.name,
      "sha256":hashlib.sha256(out.read_bytes()).hexdigest()},sort_keys=True),flush=True)
    print("LF_L11_POSITIVE_REACHABILITY_PG18_PASS checks="+str(N),flush=True)
    print("MECHANICAL_POSITIVE=NOT_REACHABLE_WITH_HONEST_SYNTHETIC_PROVENANCE GLOBAL_E2E=NOT_PROVEN",flush=True)
if __name__=="__main__":main()
