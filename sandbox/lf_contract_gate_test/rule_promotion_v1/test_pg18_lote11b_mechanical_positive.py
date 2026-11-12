#!/usr/bin/env python3
"""L11B: sandbox-only mechanical authorization-positive and four paired negatives.
The fixture deliberately contains a sentinel that resembles official provenance.
It is wholly synthetic, non-native, non-attested, and rolled back in PG18.
This measures SQL branch reachability, not a real authorization or E2E.
"""
import hashlib
import json
from pathlib import Path
import test_pg18_lote5_real_verdict_profile_return as l5
import test_pg18_lote7_exact_citation_capture as l7
import test_pg18_lote4b_validator_reuse as base

ROOT=Path(__file__).resolve().parents[3]
HERE=ROOT/"sandbox/lf_contract_gate_test/rule_promotion_v1"
DATA=json.loads((HERE/"lote4c_fresh_blind_v1.json").read_text(encoding="utf-8"))["cases"]
CASE=next(x for x in DATA if x["id"]=="K00E813F0")
CASE_ID=CASE["id"]
RULE=CASE["base_rule"]["code"]
QUOTE=next(line.split("|",2)[2] for line in
 (HERE/"lote9_real_review_pass1_chat_export_model_unattested.txt").read_text(encoding="utf-8").splitlines()
 if line.startswith(CASE_ID+"|ALLOW|"))
BASE_QUOTE="En producción el otp_code debe almacenarse como hash"
DB="lf_3779_l11b_positive_mechanical_pg18"
LABEL="MECHANICAL_ONLY_SYNTHETIC_PROVENANCE_NOT_E2E"
PROMO="PROM-TEST"
OWNER_RUN="EXEC-OWNER-L11B-001"
IG_ACTOR="INPUT_VALIDATOR:EDGE:input-governance-validator-v1:abcdef"
N=0

def lit(x):return base.lit(x)
def js(x):return lit(json.dumps(x,ensure_ascii=False,sort_keys=True))+"::jsonb"
def sql(q):return base.sql(q,db=DB)
def checked(name,cond,raw):
    global N
    print("RAW_L11B_"+name+" "+json.dumps(raw,ensure_ascii=False,sort_keys=True,default=str),flush=True)
    if not cond:raise AssertionError("L11B_FAIL_"+name+" "+json.dumps(raw,ensure_ascii=False,sort_keys=True,default=str)[:5900])
    N+=1
    print("PASS_L11B_"+name,flush=True)
def md5s():
    return sql("""SELECT 'M|'||jsonb_build_object(
      'apply',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
      'capture_record',md5(pg_get_functiondef('public.lf_rule_promotion_citation_record_v1(text,text,text)'::regprocedure)),
      'citation_verify',md5(pg_get_functiondef('public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure)),
      'l8_guard',md5(pg_get_functiondef('public.lf_rule_promotion_citation_scope_guard_v2()'::regprocedure)))::text;""")["M"]

def bootstrap():
    l5.DB=DB
    l5.l4d.DB=DB
    l5.bootstrap()
    sql(l7.M7.read_text(encoding="utf-8"))
    sql(l7.M8.read_text(encoding="utf-8"))
    # Replace ONLY the existing PG18 #3682 API stub, never a live service.
    # All receipt fields remain synthetic; use the actual rule snapshot, packet,
    # policy and dependency hashes, rather than inventing a working schema.
    sql(f"""
CREATE OR REPLACE FUNCTION public.fn_input_governance_semantic_external_receipt_readback_v1(
 p_run_id bigint,p_identity text,p_handoff bigint,p_ticket uuid,p_candidate text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql VOLATILE AS $mock_l11b$
 SELECT jsonb_build_object(
   'status','SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE',
   'run_id',p_run_id,
   'candidate_sha256',s.candidate_sha256,
   'candidate_evidence_receipt_id',101,'candidate_evidence_receipt_sha256',repeat('c',64),
   'independent_audit_receipt_id',202,'independent_audit_receipt_sha256',repeat('d',64),
   'audit_verdict','PASS','model_candidate_verified',true,'auditor_verified',true,
   'semantic_independence_credited',false,'official_write_authorized',false,
   'promotion_authorized',false,'production_authorized',false,
   'sandbox_fixture_provenance',{lit(LABEL)},
   'reviewer_model_owner_declared','ChatGPT',
   'system_attestation',false,
   'semantic_review',jsonb_build_object(
       'promotion_id','PROM-TEST','ig_run_id',p_run_id,
       'rule_code',{lit(RULE)},
       'rule_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',{lit(RULE)}),
       'packet_sha256',repeat('b',64),'candidate_sha256',s.candidate_sha256,
       'security_policy_set_sha256',public.lf_rule_promotion_quality_judge_v1('PROM-TEST')->>'security_policy_set_sha256',
       'dependency_sha256',public.lf_rule_promotion_quality_judge_v1('PROM-TEST')->>'dependency_sha256',
       'verdict','PERMITIR',
       'cited_evidence',jsonb_build_array(jsonb_build_object(
           'source_code',{lit(RULE)},
           'source_sha256',public.lf_asset_snapshot_sha_v1('REGLA',{lit(RULE)}),
           'exact_excerpt',{lit(BASE_QUOTE)},
           'implication','PG18 test-only literal evidence; no real IG approval'))),
   'l5_blind_case_verdict',jsonb_build_object(
       'id',{lit(CASE_ID)},'verdict','ALLOW','exact_excerpt',{lit(QUOTE)},
       'source_code',{lit(RULE)},
       'source_sha256',public.lf_asset_snapshot_sha_v1('REGLA',{lit(RULE)}),
       'rule_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',{lit(RULE)}),
       'packet_sha256',repeat('b',64),'candidate_sha256',s.candidate_sha256,
       'sandbox_fixture_provenance',{lit(LABEL)}))
 FROM public.l4b_ig_stub_state s WHERE s.id=true
$mock_l11b$;
""")

def setup(variant):
    actor=IG_ACTOR if variant=="OWNER_EQ_IG" else "PERFIL-OWNER-RULE-LF"
    b=CASE["base_rule"]
    line=CASE_ID+"|ALLOW|"+QUOTE
    return f"""
-- A single disposable SQL transaction. All the following are TEST-ONLY rows.
INSERT INTO lf_ops.reglas(id,codigo,descripcion,estado,valor_config,origen,owner_name,created_by)
SELECT 3,{lit(RULE)},{lit(b["description"])},'CANDIDATO',
 valor_config,origen,'LF_GOVERNANCE','PG18_L11B_NOT_OFFICIAL'
FROM lf_ops.reglas WHERE codigo='RULE-TEST-001';

UPDATE public.lf_decisiones_gov
  SET raw_payload=raw_payload || jsonb_build_object(
     'rule_code',{lit(RULE)},'owner_profile_code',{lit(actor)},
     'sandbox_fixture_provenance',{lit(LABEL)})
WHERE decision_number=101;

UPDATE public.lf_operation_execution SET
 manifest=jsonb_set(manifest,'{{router_profile_handoff,scope,target_hint}}',
  to_jsonb({lit(RULE)}::text),true)
   || jsonb_build_object('sandbox_fixture_provenance',{lit(LABEL)})
WHERE execution_id='EXEC-PARENT-TEST-001';

UPDATE public.lf_operation_execution_steps SET evidence_payload=
 jsonb_set(jsonb_set(evidence_payload,'{{input_governance,rule_code}}',
   to_jsonb({lit(RULE)}::text),true),
   '{{input_governance,rule_source_sha256}}',
   to_jsonb(public.lf_asset_snapshot_sha_v1('REGLA',{lit(RULE)})),true)
WHERE execution_id='EXEC-PARENT-TEST-001' AND step_id='input_validate';

UPDATE public.lf_operation_execution_steps
 SET evidence_ref='PG18-L11B-STEP70-SIMULATED',
 created_by_execution_id='EXEC-PARENT-TEST-001',
 evidence_payload=evidence_payload || jsonb_build_object(
    'test_only_synthetic',false,
    'sandbox_fixture_provenance',{lit(LABEL)},
    'system_attestation',false,
    'semantic_judge_result',jsonb_build_object(
       'status','PASS','validator_status','PASS','model_call_count',1,
       'verdict','PASS_REVIEWED_CURRENT_CONTEXT','unsupported_claims','[]'::jsonb))
WHERE execution_id='EXEC-PARENT-TEST-001' AND step_id='semantic_judge';

UPDATE public.l4b_ig_stub_state
 SET receipt_status='SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE',
     audit_verdict='PASS',semantic_verdict='PERMITIR',
     l5_case_verdict='ALLOW',l5_case_quote={lit(QUOTE)},l5_case_id={lit(CASE_ID)};

SELECT 'REQUEST|'||public.lf_rule_promotion_request_v1(
  'EXEC-PARENT-TEST-001',{lit(RULE)},'L11B TEST ONLY, no real authority')::text;
SELECT 'QUALITY|'||public.lf_rule_promotion_quality_judge_v1('PROM-TEST')::text;
SELECT 'BIND|'||public.lf_rule_promotion_bind_ig_semantic_v1(
  'PROM-TEST',9001,{lit(IG_ACTOR)},7001,
  '00000000-0000-0000-0000-000000000001'::uuid,repeat('a',64))::text;
SET LOCAL ROLE lf_rule_citation_source_custodian;
SELECT 'SOURCE|'||public.lf_rule_promotion_citation_source_publish_v1(
  'PROM-TEST',{lit(CASE_ID)},{js(b)},{js(CASE["proposal"])},
  {lit(hashlib.sha256((HERE/"lote4c_fresh_blind_v1.json").read_bytes()).hexdigest())},
  'github:lote4c_fresh_blind_v1.json:PG18-ONLY')::text;
RESET ROLE;

UPDATE public.lf_operation_execution_steps st SET evidence_payload=
 st.evidence_payload || jsonb_build_object(
   'rule_promotion_citation_line',{lit(line)},
   'rule_promotion_citation_case_id',{lit(CASE_ID)},
   'rule_promotion_citation_source_sha256',src.frozen_case_sha256,
   'rule_promotion_citation_ig_receipt_sha256',p.ig_semantic_external_receipt_sha256,
   -- This sentinel is SYNTHETIC test input; its official-like words are not evidence of authentication.
   'rule_promotion_citation_provenance','OFFICIAL_STEP70_VERIFIED_NATIVE_IG',
   'sandbox_fixture_provenance',{lit(LABEL)},'system_attestation',false)
FROM public.lf_rule_promotion_citation_source_v1 src
JOIN public.lf_rule_promotion_v1 p ON p.promotion_id=src.promotion_id
WHERE st.execution_id='EXEC-PARENT-TEST-001' AND st.step_id='semantic_judge'
 AND src.promotion_id='PROM-TEST';

INSERT INTO public.lf_rule_promotion_profile_owner_v1(
 rule_code,owner_profile_code,source_decision_sha256,status)
SELECT p.rule_code,{lit(actor)},
 public.lf_rule_promotion_quality_judge_v1('PROM-TEST')->>'source_decision_sha256',
 'ACTIVE' FROM public.lf_rule_promotion_v1 p WHERE p.promotion_id='PROM-TEST';
"""

def owner_run():
    return f"""
INSERT INTO public.lf_operation_execution(
 execution_id,operation_code,target_code,status,manifest)
SELECT {lit(OWNER_RUN)},'EJECUCION_PERFIL_LF',m.owner_profile_code,
 'COMPLETED',jsonb_build_object('profile_decision_mode','RULE_PROMOTION_OWNER_APPROVAL',
   'sandbox_fixture_provenance',{lit(LABEL)},'system_attestation',false)
FROM public.lf_rule_promotion_profile_owner_v1 m WHERE m.rule_code={lit(RULE)};
INSERT INTO public.lf_operation_execution_steps(
 execution_id,step_id,status,evidence_payload,evidence_ref,created_by_execution_id)
SELECT {lit(OWNER_RUN)},'semantic_judge','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('test_only_synthetic',false,
   'sandbox_fixture_provenance',{lit(LABEL)},'system_attestation',false,
   'semantic_judge_result',jsonb_build_object('status','PASS','validator_status','PASS'),
   'rule_promotion_owner_approval',jsonb_build_object(
     'schema_version','LF_RULE_PROMOTION_OWNER_APPROVAL_V1',
     'decision','APPROVE',
     'promotion_id',p.promotion_id,'owner_profile_code',m.owner_profile_code,
     'owner_execution_id',{lit(OWNER_RUN)},
     'proposer_profile_code',p.requested_by_profile,
     'ig_proposer_identity',p.ig_semantic_validator_identity,
     'ig_run_id',p.ig_semantic_run_id,'rule_code',p.rule_code,
     'rule_snapshot_sha256',p.request_snapshot_sha256,
     'packet_sha256',p.ig_semantic_packet_sha256,
     'candidate_sha256',p.ig_semantic_candidate_sha256,
     'ig_external_receipt_sha256',p.ig_semantic_external_receipt_sha256,
     'ig_review_sha256',p.ig_semantic_review_sha256,
     'ig_binding_sha256',p.ig_semantic_binding_sha256,
     'policy_sha256',p.ig_semantic_policy_set_sha256,
     'dependency_sha256',p.ig_semantic_dependency_sha256,
     'source_decision_sha256',m.source_decision_sha256)),
 'PG18-OWNER-STEP70-SIMULATED',{lit(OWNER_RUN)}
FROM public.lf_rule_promotion_v1 p
JOIN public.lf_rule_promotion_profile_owner_v1 m ON m.rule_code=p.rule_code
WHERE p.promotion_id='PROM-TEST';
SELECT 'OWNER_APPROVAL|'||public.lf_rule_promotion_profile_approve_v1(
   'PROM-TEST',{lit(OWNER_RUN)})::text;
"""

def readback_fault():
    # Fault-injection into PG18 table only; no gate function is changed.
    # This test trigger silently declines the VIGENTE state transition,
    # allowing the normal readback to detect CANDIDATO and RETRY_REQUIRED.
    return f"""
CREATE FUNCTION public.l11b_fault_readback_v1() RETURNS trigger
 LANGUAGE plpgsql AS $fault$ BEGIN
 IF NEW.codigo={lit(RULE)} AND NEW.estado='VIGENTE'
 THEN NEW.estado:='CANDIDATO'; END IF;
 RETURN NEW; END $fault$;
CREATE TRIGGER trg_l11b_fault_readback
 BEFORE UPDATE OF estado ON lf_ops.reglas FOR EACH ROW
 EXECUTE FUNCTION public.l11b_fault_readback_v1();
"""

def scenario(variant):
    altered=QUOTE[:-1]+("X" if not QUOTE.endswith("X") else "Y")
    line=CASE_ID+"|ALLOW|"+(altered if variant=="QUOTE_TAMPER" else QUOTE)
    drift=(f"UPDATE lf_ops.reglas SET descripcion=descripcion||' POST_CAPTURE_DRIFT' WHERE codigo={lit(RULE)};" if variant=="RULE_DRIFT" else "")
    extra=readback_fault() if variant=="READBACK_FAILURE" else ""
    q=f"""BEGIN;
{setup(variant)}
SELECT 'LINE|'||public.lf_rule_promotion_citation_line_check_v1('PROM-TEST',{lit(line)})::text;
SET LOCAL ROLE lf_rule_citation_step70_bridge;
SELECT 'CAPTURE|'||public.lf_rule_promotion_citation_record_v1(
 'PROM-TEST',{lit(line)},'EXEC-PARENT-TEST-001')::text;
RESET ROLE;
SELECT 'CAPTURE_VERIFY|'||public.lf_rule_promotion_citation_verify_v1('PROM-TEST')::text;
SELECT 'PIN|'||public.lf_rule_promotion_blind_verdict_pin_v1('PROM-TEST')::text;
SELECT 'IG_VERIFY|'||public.lf_rule_promotion_ig_semantic_verify_v1('PROM-TEST')::text;
{owner_run()}
SELECT 'OWNER_VERIFY|'||public.lf_rule_promotion_profile_owner_verify_v1('PROM-TEST')::text;
{drift}
{extra}
SELECT 'PREAPPLY_VERIFY|'||public.lf_rule_promotion_citation_verify_v1('PROM-TEST')::text;
SELECT 'APPLY|'||public.lf_rule_promotion_apply_v1('PROM-TEST')::text;
SELECT 'READBACK|'||public.lf_rule_promotion_rule_readback_v1({lit(RULE)})::text;
SELECT 'RETURN|'||public.lf_rule_promotion_profile_return_readback_v1(
 'PROM-TEST',{lit(OWNER_RUN)})::text;
SELECT 'IN_TX|'||jsonb_build_object(
  'rule',(SELECT estado FROM lf_ops.reglas WHERE codigo={lit(RULE)}),
  'promotion',(SELECT status FROM public.lf_rule_promotion_v1 WHERE promotion_id='PROM-TEST'),
  'return',(SELECT rule_return_status FROM public.lf_rule_promotion_v1 WHERE promotion_id='PROM-TEST'),
  'captures',(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1))::text;
ROLLBACK;
SELECT 'ROLLBACK|'||jsonb_build_object(
  'rule_rows',(SELECT count(*) FROM lf_ops.reglas WHERE codigo={lit(RULE)}),
  'promotions',(SELECT count(*) FROM public.lf_rule_promotion_v1),
  'captures',(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1),
  'owner_runs',(SELECT count(*) FROM public.lf_operation_execution WHERE execution_id={lit(OWNER_RUN)}))::text;
"""
    return sql(q)

def stage_board():
    stages=("Router","Perfil","RUN","IG","Curator","Validator",
      "Retorno perfil","Ejecucion","Promocion","VIGENTE","Readback","Cierre")
    positives={"Validator","Retorno perfil","Promocion","VIGENTE","Readback"}
    return [{"stage":name,"status":"SANDBOX_VERIFIED" if name in positives else "NOT_PROVEN",
       "scope":"SQL mechanical PG18 only" if name in positives
         else "No real Router/IG/RUN/owner/Curator/execution/closure receipt"}
      for name in stages]

def main():
    assert BASE_QUOTE in CASE["base_rule"]["description"]
    assert QUOTE in CASE["proposal"]["description"]
    export=(HERE/"lote9_real_review_pass1_chat_export_model_unattested.txt").read_bytes()
    checked("ACTUAL_K_QUOTE_SHA",hashlib.sha256(export).hexdigest()
      =="d319670079ece0e0285e37a3194a1e1c9e784e9b7b6f5e7d35ed4882200bf4bc",
      {"case":CASE_ID,"quote":QUOTE,"label":LABEL,"raw_file_sha":hashlib.sha256(export).hexdigest()})
    bootstrap()
    before=md5s()
    expected={"apply":"86b0494984edf95cf0f9c0a0df67000b",
      "capture_record":"89cbfac4162dbc9f8ecca59f2c3ab4c3",
      "citation_verify":"773a62783baa5edbe967200cac66b8c3",
      "l8_guard":"522d12f0843be1da3c785cef3c0bf3fc"}
    checked("FROZEN_GATE_MD5",before==expected,{"expected":expected,"actual":before})
    outcomes={}
    for variant in ("POSITIVE","QUOTE_TAMPER","RULE_DRIFT","OWNER_EQ_IG","READBACK_FAILURE"):
        x=scenario(variant);outcomes[variant]=x
        print("RAW_L11B_VARIANT_"+variant+" "+json.dumps(x,ensure_ascii=False,sort_keys=True,default=str),flush=True)
        assert x["ROLLBACK"]=={"rule_rows":0,"promotions":0,"captures":0,"owner_runs":0},x["ROLLBACK"]
        if variant=="POSITIVE":
            ok=(x["QUALITY"]["classification"]=="AUTO_APPROVABLE"
             and x["SOURCE"]["status"]=="SOURCE_FROZEN"
             and x["BIND"]["status"]=="BOUND_EXISTING_IG_SEMANTIC_EVIDENCE"
             and x["CAPTURE"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
             and x["CAPTURE_VERIFY"]["status"]=="VERIFIED_CAPTURE_BINDING"
             and x["CAPTURE_VERIFY"]["promotable"] is False
             and x["PIN"]["status"]=="REAL_VERDICT_ALLOW_VERIFIED"
             and x["IG_VERIFY"]["status"]=="READY_FOR_PROFILE_APPROVAL"
             and x["OWNER_APPROVAL"]["status"]=="APPROVED"
             and x["OWNER_VERIFY"]["status"]=="VERIFIED_PROFILE_OWNER"
             and x["APPLY"]["status"]=="APPLIED"
             and x["READBACK"]["estado"]=="VIGENTE"
             and x["RETURN"]["status"]=="READY"
             and x["RETURN"]["readback_verified"] is True
             and x["IN_TX"]=={"rule":"VIGENTE","promotion":"APPLIED","return":"READY","captures":1})
        elif variant=="QUOTE_TAMPER":
            ok=(x["LINE"]["status"]=="HUMAN_DECISION_REQUIRED"
             and x["CAPTURE"]["status"]=="HUMAN_DECISION_REQUIRED"
             and x["CAPTURE_VERIFY"]["status"]!="VERIFIED_CAPTURE_BINDING"
             and x["APPLY"]["status"]=="BLOCKED"
             and x["IN_TX"]["rule"]=="CANDIDATO")
        elif variant=="RULE_DRIFT":
            ok=(x["CAPTURE_VERIFY"]["status"]=="VERIFIED_CAPTURE_BINDING"
             and x["PREAPPLY_VERIFY"]["status"]!="VERIFIED_CAPTURE_BINDING"
             and x["APPLY"]["blocking_code"]=="L7_EXACT_CITATION_NOT_CURRENT"
             and x["IN_TX"]["rule"]=="CANDIDATO")
        elif variant=="OWNER_EQ_IG":
            ok=(x["CAPTURE_VERIFY"]["status"]=="VERIFIED_CAPTURE_BINDING"
             and x["OWNER_APPROVAL"]["status"]!="APPROVED"
             and x["APPLY"]["status"]=="BLOCKED"
             and x["IN_TX"]["rule"]=="CANDIDATO")
        else:
            ok=(x["OWNER_APPROVAL"]["status"]=="APPROVED"
             and x["APPLY"]["status"]=="RETRY_REQUIRED"
             and x["APPLY"]["blocking_code"]=="RULE_READBACK_FAILED_NO_VIGENTE"
             and x["IN_TX"]=={"rule":"CANDIDATO","promotion":"APPROVED","return":"RETRY_REQUIRED","captures":1}
             and x["RETURN"]["status"]=="RETRY_REQUIRED")
        checked("PAIR_"+variant,ok,
          {"variant":variant,"source_label":LABEL,"capture":x["CAPTURE"],
           "verify":x["CAPTURE_VERIFY"],"owner":x["OWNER_APPROVAL"],
           "apply":x["APPLY"],"readback":x["READBACK"],
           "return":x["RETURN"],"in_tx":x["IN_TX"],"rollback":x["ROLLBACK"]})
    after=md5s()
    checked("GATE_MD5_BEFORE_AFTER",before==after,{"before":before,"after":after})
    board=stage_board()
    checked("12_STAGE_BOARD_MECHANICAL_NOT_E2E",len(board)==12
      and sum(x["status"]=="NOT_PROVEN" for x in board)==7,
      {"stages":board,"global":"NOT_PROVEN","mechanical":LABEL})
    report={"schema_version":"LF_L11B_MECHANICAL_ONLY_PG18_V1",
      "label":LABEL,"global_e2e":"NOT_PROVEN",
      "real_chat_case":CASE_ID,"real_chat_quote":QUOTE,
      "reviewer_model":"ChatGPT","source":"OWNER_DECLARED_NOT_SYSTEM_ATTESTED",
      "synthetic_official_looking_field_not_authenticated":True,
      "gate_md5_before":before,"gate_md5_after":after,
      "stage_board":board,
      "results":{v:{
        "capture":x["CAPTURE"],"capture_verify":x["CAPTURE_VERIFY"],
        "ig":x["IG_VERIFY"],"owner":x["OWNER_APPROVAL"],
        "apply":x["APPLY"],"readback":x["READBACK"],
        "profile_return":x["RETURN"],"in_tx":x["IN_TX"],
        "rollback":x["ROLLBACK"]} for v,x in outcomes.items()}}
    output=HERE/"lote11b_mechanical_positive_5_variants_runtime.json"
    output.write_text(json.dumps(report,ensure_ascii=False,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print("RAW_L11B_BOARD "+json.dumps(board,ensure_ascii=False,sort_keys=True),flush=True)
    print("RAW_L11B_REPORT "+json.dumps({"file":output.name,
       "sha256":hashlib.sha256(output.read_bytes()).hexdigest()},sort_keys=True),flush=True)
    print("LF_L11B_MECHANICAL_ONLY_PG18_PASS checks="+str(N)+" variants=5",flush=True)
    print("GLOBAL_E2E=NOT_PROVEN OWNER_SIMULATED=true PROVENANCE_NON_NATIVE=true ALL_ROLLBACK=true",flush=True)

if __name__=="__main__":main()
