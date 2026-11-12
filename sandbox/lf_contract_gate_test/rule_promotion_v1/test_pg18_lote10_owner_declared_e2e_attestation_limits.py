#!/usr/bin/env python3
"""L10 PG18 actual pass1 quotations, existing L7/L8 unchanged. Four ROLLBACK paths.

Trust boundary: real quote text is USER-SUPPLIED, model identity is OWNER-DECLARED.
No real #3682 receipt, OIDC, official Router, profile RUN or Step70 can be
manufactured. The fixture of IG and Step70 is expressly sandbox synthetic;
the simulated owner has test_only_synthetic=true. This is NOT a full E2E PASS.
"""
import hashlib
import json
from pathlib import Path
import test_pg18_lote7_exact_citation_capture as l7
from test_pg18_lote7_exact_citation_capture import lit
import test_pg18_lote5_real_verdict_profile_return as l5
import test_pg18_lote4b_validator_reuse as base

ROOT=Path(__file__).resolve().parents[3]
DATA=ROOT/"sandbox/lf_contract_gate_test/rule_promotion_v1"
EXPORT=DATA/"lote9_real_review_pass1_chat_export_model_unattested.txt"
L9META=DATA/"lote9_real_review_pass1_chat_export_model_unattested.json"
L6META=DATA/"lote6_claude_blind_5pass_verdicts_not_native_ig_receipt_v1.json"
DB="lf_3779_l10_e2e_owner_declaration_pg18"
N=0

STAGES=("Router","Perfil","RUN","IG","Curator","Validator",
       "Retorno perfil","Ejecucion","Promocion","VIGENTE","Readback","Cierre")

def sql(s):return base.sql(s,db=DB)
def check(code,ok,raw):
    global N
    print("RAW_L10_"+code+" "+json.dumps(raw,sort_keys=True,ensure_ascii=False,default=str),flush=True)
    if not ok:
        raise AssertionError("L10_FAIL_"+code+" "+json.dumps(raw,sort_keys=True,ensure_ascii=False,default=str)[:5000])
    N+=1
    print("PASS_L10_"+code,flush=True)

def raw_lines():
    raw=EXPORT.read_bytes()
    sha=hashlib.sha256(raw).hexdigest()
    rows={}
    for line in raw.decode("utf-8").splitlines():
        parts=line.split("|",2)
        if len(parts)!=3 or parts[1] not in ("ALLOW","BLOCK"):
            raise AssertionError("UNEXPECTED_EXPORT_LINE")
        rows[parts[0]]=(parts[1],parts[2])
    meta=json.loads(L9META.read_text(encoding="utf-8"))
    five=json.loads(L6META.read_text(encoding="utf-8"))
    expected_verdicts={x["id"]:x["verdict"] for x in five["entries"]}
    check("REAL_QUOTE_HASH_AND_OWNER_DECLARATION",
      sha==meta["expected_sha256"]==
        "d319670079ece0e0285e37a3194a1e1c9e784e9b7b6f5e7d35ed4882200bf4bc"
      and raw.endswith(b"\n") and len(rows)==154
      and len(five["entries"])==154
      and all(expected_verdicts.get(i)==v for i,(v,q) in rows.items())
      and meta["reviewer_model"]=="ChatGPT"
      and five["reviewer_model"]=="ChatGPT"
      and meta["reviewer_model_source"]=="OWNER_DECLARED_NOT_SYSTEM_ATTESTED"
      and five["reviewer_model_source"]=="OWNER_DECLARED_NOT_SYSTEM_ATTESTED"
      and not meta["reviewer_model_system_attestation"]
      and not five["reviewer_model_system_attestation"]
      and meta["native_ig_receipt"] is False,
      {"export_sha256":sha,"cases":len(rows),"model":"ChatGPT",
       "model_source":"OWNER_DECLARED_NOT_SYSTEM_ATTESTED",
       "model_system_attested":False,
       "same_model_ig_owner_reviewer":True,
       "independence_attested":False,"native_receipt":False,
       "real_excerpt_K00E813F0":rows["K00E813F0"][1]})
    return rows

def md5_readback():
    q="""SELECT 'M|'||jsonb_build_object(
      'apply',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
      'capture_record',md5(pg_get_functiondef('public.lf_rule_promotion_citation_record_v1(text,text,text)'::regprocedure)),
      'citation_verify',md5(pg_get_functiondef('public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure)),
      'l8_guard',md5(pg_get_functiondef('public.lf_rule_promotion_citation_scope_guard_v2()'::regprocedure)),
      'l7_line',md5(pg_get_functiondef('public.lf_rule_promotion_citation_line_check_v1(text,text)'::regprocedure)),
      'l7_blind',md5(pg_get_functiondef('public.lf_rule_promotion_blind_verdict_verify_v1(text)'::regprocedure)))::text;"""
    return sql(q)["M"]

def route(case_id,verdict,quote,variant):
    # Each request uses a real source/quote. l7.seed creates a completely
    # disposable SYNTHETIC promotion + IG/Step70 stub; NOT an authentic receipt.
    c=l7.CASES[case_id]
    line=case_id+"|"+verdict+"|"+quote
    source_sql=l7.seed(case_id,verdict=verdict,quote=quote)
    drift="" if variant!="DRIFT" else (
        "UPDATE lf_ops.reglas SET descripcion=descripcion||' DRIFT_POST_CAPTURE' "
        "WHERE codigo="+lit(c["base_rule"]["code"])+";")
    # Owner is intentionally simulated, visibly tagged, and not granted
    # production authority. Must never be used to impersonate a true owner.
    simulated_owner="" if variant!="ALLOW" else """
       INSERT INTO public.lf_operation_execution(
          execution_id,operation_code,target_code,status,manifest)
       VALUES('EXEC-OWNER-L10-SIM','EJECUCION_PERFIL_LF',
          'PERFIL-OWNER-RULE-LF','COMPLETED',
          '{"profile_decision_mode":"RULE_PROMOTION_OWNER_APPROVAL",
             "test_only_synthetic":true,"owner_authority":"SIMULATED"}'::jsonb);
       INSERT INTO public.lf_operation_execution_steps(
          execution_id,step_id,status,evidence_payload,evidence_ref,created_by_execution_id)
       VALUES('EXEC-OWNER-L10-SIM','semantic_judge','STEP_PASS_WITH_EVIDENCE',
          '{"test_only_synthetic":true,"sandbox_fixture_provenance":"PG18_MOCK_NOT_OFFICIAL",
             "semantic_judge_result":{"status":"PASS","validator_status":"PASS"},
             "rule_promotion_owner_approval":{"decision":"APPROVE","owner_mode":"SIMULATED_NOT_ATTESTED"}}'::jsonb,
          'PG18-SIM-STEP70','EXEC-OWNER-L10-SIM');
       SELECT 'OWNER|'||public.lf_rule_promotion_profile_approve_v1(
          'PROM-L7','EXEC-OWNER-L10-SIM')::text;
    """
    # The route intentionally exposes every actual gate result; do NOT
    # overwrite mock source_provenance to OFFICIAL to force a happy path.
    query=f"""BEGIN;
      {source_sql}
      SELECT 'SOURCE|'||jsonb_build_object(
        'promotion_exists',(SELECT count(*) FROM public.lf_rule_promotion_v1
            WHERE promotion_id='PROM-L7'),
        'rule',(SELECT codigo FROM lf_ops.reglas WHERE codigo={lit(c["base_rule"]["code"])}),
        'source_provenance','PG18_MOCK_IG_STEP70_NOT_NATIVE_RECEIPT')::text;
      SELECT 'LINE|'||public.lf_rule_promotion_citation_line_check_v1(
          'PROM-L7',{lit(line)})::text;
      SET LOCAL ROLE lf_rule_citation_step70_bridge;
      SELECT 'CAPTURE|'||public.lf_rule_promotion_citation_record_v1(
          'PROM-L7',{lit(line)},'EXEC-PARENT-TEST-001')::text;
      RESET ROLE;
      SELECT 'CITATION_GATE_PRE|'||public.lf_rule_promotion_citation_verify_v1('PROM-L7')::text;
      SELECT 'EXTERNAL_GATE|'||public.lf_rule_promotion_ig_semantic_verify_v1('PROM-L7')::text;
      {drift}
      SELECT 'CITATION_GATE_POST|'||public.lf_rule_promotion_citation_verify_v1('PROM-L7')::text;
      {simulated_owner}
      SELECT 'APPLY|'||public.lf_rule_promotion_apply_v1('PROM-L7')::text;
      SELECT 'READBACK|'||public.lf_rule_promotion_rule_readback_v1(
           {lit(c["base_rule"]["code"])})::text;
      SELECT 'RETURN|'||public.lf_rule_promotion_profile_return_readback_v1(
         'PROM-L7','EXEC-OWNER-L10-SIM')::text;
      SELECT 'CLOSE_READBACK|'||jsonb_build_object(
          'run_status',(SELECT status FROM public.lf_operation_execution
                WHERE execution_id='EXEC-PARENT-TEST-001'),
          'owner_profile_run_status',(SELECT status FROM public.lf_operation_execution
                WHERE execution_id='EXEC-OWNER-L10-SIM'),
          'promotion_status',(SELECT status FROM public.lf_rule_promotion_v1
                WHERE promotion_id='PROM-L7'),
          'rule_state',(SELECT estado FROM lf_ops.reglas
                WHERE codigo={lit(c["base_rule"]["code"])}))::text;
      ROLLBACK;
      SELECT 'ROLLBACK|'||jsonb_build_object(
           'promotion_rows',(SELECT count(*) FROM public.lf_rule_promotion_v1
                 WHERE promotion_id='PROM-L7'),
           'capture_rows',(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1),
           'source_rows',(SELECT count(*) FROM public.lf_rule_promotion_citation_source_v1),
           'rule_rows',(SELECT count(*) FROM lf_ops.reglas
                  WHERE codigo={lit(c["base_rule"]["code"])}),
           'sim_owner_rows',(SELECT count(*) FROM public.lf_operation_execution
                WHERE execution_id='EXEC-OWNER-L10-SIM'))::text;
    """
    return sql(query)

def board(a):
    # These statuses refer to REAL EXECUTION of steps, not confidence.
    # Readback stage is verified only for the negative CANDIDATO readback.
    entries=[]
    for stage in STAGES:
        if stage=="Validator":
            status="SANDBOX_VERIFIED"
            evidence="Exact frozen-source quote passes L7/L8 structural check; this is not semantic approval."
        elif stage=="Readback":
            status="SANDBOX_VERIFIED"
            evidence="Rollback and persisted CANDIDATO negative readback verified; VIGENTE readback is NOT_PROVEN."
        elif stage=="Router":status,evidence="NOT_PROVEN","No official ACT-0001 invocation or OIDC receipt."
        elif stage=="Perfil":status,evidence="NOT_PROVEN","No authentic proprietor profile; sandbox owner marked SIMULATED."
        elif stage=="RUN":status,evidence="NOT_PROVEN","Only disposable PG18 RUN fixture, not official RUN."
        elif stage=="IG":status,evidence="NOT_PROVEN","No native #3682 IG receipt; fixture is explicitly synthetic."
        elif stage=="Curator":status,evidence="NOT_PROVEN","No authenticated Curator receipt/execution."
        elif stage=="Retorno perfil":status,evidence="NOT_PROVEN","Profile return/readback is not READY; no real transport."
        elif stage=="Ejecucion":status,evidence="NOT_PROVEN","No complete real profile execution / 11 steps / judge."
        elif stage=="Promocion":status,evidence="NOT_PROVEN","Apply blocked by missing real citation/owner attestation."
        elif stage=="VIGENTE":status,evidence="NOT_PROVEN","Rule remains CANDIDATO, no VIGENTE update."
        elif stage=="Cierre":status,evidence="NOT_PROVEN","No RUN COMPLETED, 11/11, terminal READY receipt."
        else:raise AssertionError(stage)
        entries.append({"stage":stage,"status":status,"evidence":evidence})
    return entries

def main():
    lines=raw_lines()
    l7.DB=DB
    l7.l5.DB=DB
    l7.l5.l4d.DB=DB
    l5.DB=DB
    l5.l4d.DB=DB
    l5.bootstrap()
    sql(l7.M7.read_text(encoding="utf-8"))
    sql(l7.M8.read_text(encoding="utf-8"))
    before=md5_readback()
    expected={"apply":"86b0494984edf95cf0f9c0a0df67000b",
      "capture_record":"89cbfac4162dbc9f8ecca59f2c3ab4c3",
      "citation_verify":"773a62783baa5edbe967200cac66b8c3",
      "l8_guard":"522d12f0843be1da3c785cef3c0bf3fc",
      "l7_line":"f7bc0cf0564696a5ac6088fe85b0e957",
      "l7_blind":"f0aa0ae6130929d258266269def45bf9"}
    check("GATE_MD5_EXISTING_UNMODIFIED",before==expected,
      {"before":before,"expected":expected,"migration_L10":False})
    a=route("K00E813F0",*lines["K00E813F0"],variant="ALLOW")
    check("ALLOW_ACTUAL_QUOTE_CAPTURE_SIM_OWNER_NO_NATIVE_IG_NO_VIGENTE",
      a["SOURCE"]["promotion_exists"]==1
      and a["LINE"]["status"]=="LITERAL_STRUCTURE_VERIFIED_FOR_CAPTURE"
      and a["LINE"]["literal_origin"]=="PROPOSAL"
      and a["CAPTURE"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
      and a["CITATION_GATE_PRE"]["status"]=="PROFILE_OWNER_REVIEW_ONLY"
      and a["CITATION_GATE_PRE"]["promotable"] is False
      and a["OWNER"]["status"]!="APPROVED"
      and a["APPLY"]["status"]=="BLOCKED"
      and a["READBACK"]["estado"]=="CANDIDATO"
      and a["RETURN"]["status"]!="READY"
      and a["CLOSE_READBACK"]["rule_state"]=="CANDIDATO"
      and a["ROLLBACK"]=={"promotion_rows":0,"capture_rows":0,"source_rows":0,
                          "rule_rows":0,"sim_owner_rows":0},
      {"case_id":"K00E813F0","quote_source":"REAL_PASS1_CHAT_EXPORT",
       "ig_step70":"PG18_MOCK_NOT_NATIVE_IG",
       "owner":"SIMULATED_NO_AUTHORITY","raw":a})
    b=route("K00A10207",*lines["K00A10207"],variant="BLOCK")
    check("BLOCK_REAL_CASE_GOES_HUMAN_NO_PROMOTION",
       b["LINE"]["status"]=="LITERAL_STRUCTURE_VERIFIED_FOR_CAPTURE"
       and b["CAPTURE"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
       and b["CITATION_GATE_PRE"]["status"]=="HUMAN_DECISION_REQUIRED"
       and b["CITATION_GATE_PRE"]["blocking_code"]=="L7_BLOCK_QUOTE_VERIFIED_NO_PROMOTION"
       and b["APPLY"]["status"]=="BLOCKED"
       and b["READBACK"]["estado"]=="CANDIDATO"
       and b["ROLLBACK"]["capture_rows"]==0,
       {"case_id":"K00A10207","raw":b})
    c=route("K00C8E827",*lines["K00C8E827"],variant="SHORT")
    check("SHORT_REAL_ALLOW_TO_HUMAN_NO_PROMOTION",
       c["LINE"]["blocking_code"]=="L7_QUOTE_EMPTY_OR_TRIVIAL"
       and c["CAPTURE"]["status"]=="HUMAN_DECISION_REQUIRED"
       and c["CITATION_GATE_PRE"]["status"]=="HUMAN_DECISION_REQUIRED"
       and c["APPLY"]["status"]=="BLOCKED"
       and c["READBACK"]["estado"]=="CANDIDATO"
       and c["ROLLBACK"]["capture_rows"]==0,
       {"case_id":"K00C8E827","quote_characters":len(lines["K00C8E827"][1]),"raw":c})
    d=route("K00E813F0",*lines["K00E813F0"],variant="DRIFT")
    check("QUOTE_CAPTURED_THEN_RULE_DRIFT_APPLY_REJECTS",
       d["CAPTURE"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
       and d["CITATION_GATE_PRE"]["status"]=="PROFILE_OWNER_REVIEW_ONLY"
       and d["CITATION_GATE_POST"]["status"]=="HUMAN_DECISION_REQUIRED"
       and d["APPLY"]["status"]=="BLOCKED"
       and d["APPLY"]["blocking_code"]=="L7_EXACT_CITATION_NOT_CURRENT"
       and d["READBACK"]["estado"]=="CANDIDATO"
       and d["CLOSE_READBACK"]["rule_state"]=="CANDIDATO"
       and d["ROLLBACK"]["rule_rows"]==0,
       {"case_id":"K00E813F0","raw":d})
    stages=board(a)
    check("12_STAGE_E2E_HONEST_NOT_PROVEN",
       len(stages)==12
       and [x["stage"] for x in stages]==list(STAGES)
       and {x["status"] for x in stages}=={"SANDBOX_VERIFIED","NOT_PROVEN"}
       and sum(x["status"]=="SANDBOX_VERIFIED" for x in stages)==2
       and a["CLOSE_READBACK"]["rule_state"]=="CANDIDATO"
       and a["RETURN"]["status"]!="READY",
       {"stages":stages,
        "global_status":"NOT_PROVEN",
        "positive_VIGENTE_with_real_quote":False,
        "independence_attested":False,
        "native_receipt_3682":False,
        "authentic_profile_run":False,
        "owner_profile_simulated":True})
    after=md5_readback()
    check("MD5_BEFORE_AFTER_IDENTICAL",after==before,
      {"before":before,"after":after,"all_rollback":True})
    artifact={
      "schema_version":"LF_L10_PG18_E2E_TRUTHFUL_STAGE_BOARD_V1",
      "head_source":"L9_PASS1_CHAT_EXPORT_K00E813F0",
      "reviewer_model":"ChatGPT",
      "model_source":"OWNER_DECLARED_NOT_SYSTEM_ATTESTED",
      "reviewer_independence":"CONSISTENCY_NOT_INDEPENDENCE",
      "promotion_gate_md5_before":before,
      "promotion_gate_md5_after":after,
      "stages":stages,
      "global_status":"NOT_PROVEN",
      "variants":{
       "a_allow":{"case":"K00E813F0","line":a["LINE"],"capture":a["CAPTURE"],
           "owner":a["OWNER"],"apply":a["APPLY"],"readback":a["READBACK"],
           "profile_return":a["RETURN"],"rollback":a["ROLLBACK"]},
       "b_block":{"case":"K00A10207","line":b["LINE"],"gate":b["CITATION_GATE_PRE"],
           "apply":b["APPLY"],"rollback":b["ROLLBACK"]},
       "c_short":{"case":"K00C8E827","line":c["LINE"],"gate":c["CITATION_GATE_PRE"],
           "apply":c["APPLY"],"rollback":c["ROLLBACK"]},
       "d_drift":{"case":"K00E813F0","before":d["CITATION_GATE_PRE"],
           "after":d["CITATION_GATE_POST"],"apply":d["APPLY"],
           "readback":d["READBACK"],"rollback":d["ROLLBACK"]}},
      "unverified":[
         "Native IG #3682 receipt for actual K case",
         "Official Step70 signed provenance",
         "Authentic profile/Router/RUN and curated input",
         "Owner-profile authenticated approval",
         "Actual VIGENTE transition in the K case",
         "Profile transport return and terminal receipt"] }
    out=DATA/"lote10_e2e_truthful_12_stage_runtime.json"
    out.write_text(json.dumps(artifact,indent=2,sort_keys=True,ensure_ascii=False)+"\n",encoding="utf-8")
    print("RAW_L10_BOARD_12_STAGES "+json.dumps(stages,ensure_ascii=False,sort_keys=True),flush=True)
    print("RAW_L10_REPORT "+json.dumps({"path":out.name,
       "sha256":hashlib.sha256(out.read_bytes()).hexdigest(),
       "global":"NOT_PROVEN","variant_count":4},sort_keys=True),flush=True)
    print("LF_L10_PG18_SANDBOX_CHECKS_PASS checks="+str(N)+" variants=4",flush=True)
    print("GLOBAL_E2E=NOT_PROVEN REAL_IG_RECEIPT=UNVERIFIED OWNER_PROFILE=SIMULATED ONLY NO_VIGENTE=true",flush=True)
if __name__=="__main__":
    main()
