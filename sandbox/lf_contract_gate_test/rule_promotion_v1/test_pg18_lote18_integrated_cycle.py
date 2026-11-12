#!/usr/bin/env python3
"""L18: one integrated PG18 runner, three complete *sandbox* branches.
Source L11B authority-shaped receipts are synthetic, not official Step70 or IG.
No live Supabase, no production E2E attestation; each full scenario ROLLBACK.
"""
import hashlib, json
from pathlib import Path
import test_pg18_lote17_actor_identity_adapter as l17
import test_pg18_lote14_quality_wrapper as l14

ROOT=Path(__file__).resolve().parents[3]
HERE=ROOT/"sandbox/lf_contract_gate_test/rule_quality_lifecycle_v1"
DB="lf_3779_l18_integrated_cycle_pg18"
EXPECTED=l14.EXPECTED_MD5
CASE_ROWS=[]
STAGES=("Router","Perfil","RUN","IG","Curator","Validator","Retorno perfil",
        "Ejecucion","Promocion","VIGENTE","Readback","Cierre")
VALID_STATES={"REAL_EN_SANDBOX","SINTETICO","NO_PROBADO"}
def lit(x):return l17.lit(x)
def sql(s,fail=False):return l17.sql(s,fail=fail)
def claim_set(token):
    return "SELECT set_config('request.jwt.claims',"+lit(json.dumps(token,sort_keys=True))+",true);\n"
def owner_session(token,statements):
    return "SET SESSION AUTHORIZATION l17_authenticator;\nSET LOCAL ROLE lf_owner_role;\n"+claim_set(token)+statements+"\nRESET SESSION AUTHORIZATION;\n"
def saly_session(token,statements):
    return "SET SESSION AUTHORIZATION l17_authenticator;\nSET LOCAL ROLE saly_owner_role;\n"+claim_set(token)+statements+"\nRESET SESSION AUTHORIZATION;\n"
def check(case_id,ok,expected,raw):
    if not ok:raise AssertionError("L18_FAIL_"+case_id+" EXPECTED "+str(expected)+" RAW "+json.dumps(raw,ensure_ascii=False,default=str)[:6500])
    row={"id":case_id,"status":"PASS","expected":expected,"observed":raw}
    CASE_ROWS.append(row)
    print("PASS_L18_"+case_id+" "+json.dumps(raw,ensure_ascii=False,sort_keys=True,default=str),flush=True)
def boards(project,out,variant):
    if project=="lf":
        states={"Router":"SINTETICO","Perfil":"SINTETICO","RUN":"SINTETICO",
                "IG":"SINTETICO","Curator":"NO_PROBADO",
                "Validator":"REAL_EN_SANDBOX","Retorno perfil":"REAL_EN_SANDBOX",
                "Ejecucion":"SINTETICO","Promocion":"REAL_EN_SANDBOX",
                "VIGENTE":"REAL_EN_SANDBOX","Readback":"REAL_EN_SANDBOX","Cierre":"SINTETICO"}
        ev={"Router":"Synthetic parent manifest and handoff; ACT-0001 NOT run",
         "Perfil":"Synthetic source/owner profile; not a native profile execution",
         "RUN":"Synthetic PG18 execution rows; no native RUN",
         "IG":"L11B stub + simulated Step70 field, not native IG",
         "Curator":"No authentic Curator invocation",
         "Validator":"Frozen L7/L8 SQL capture/verification executed; verdict has synthetic provenance",
         "Retorno perfil":"Frozen profile_return_readback SQL returned READY; no real transport",
         "Ejecucion":"SQL stub parent + owner execution, not complete 11-step execution",
         "Promocion":"Frozen apply returned APPLIED in PG18 transaction",
         "VIGENTE":"PG18 source and quality row activated within transaction",
         "Readback":"SQL readback and quality metadata checked before ROLLBACK",
         "Cierre":"L18 sandbox-only closure receipt; native profile closure NOT proven"}
    else:
        states={"Router":"NO_PROBADO","Perfil":"NO_PROBADO","RUN":"NO_PROBADO",
            "IG":"NO_PROBADO","Curator":"NO_PROBADO","Validator":"REAL_EN_SANDBOX",
            "Retorno perfil":"SINTETICO","Ejecucion":"REAL_EN_SANDBOX",
            "Promocion":"REAL_EN_SANDBOX","VIGENTE":"REAL_EN_SANDBOX",
            "Readback":"REAL_EN_SANDBOX","Cierre":"SINTETICO"}
        ev={"Router":"No SALY native Router path",
           "Perfil":"No native SALY profile",
           "RUN":"No SALY RUN",
           "IG":"LF frozen L7/L8 not a SALY adapter; no SALY IG receipt",
           "Curator":"No SALY Curator",
           "Validator":"L17 signed identity and L13 family review mechanically verified",
           "Retorno perfil":"Synthetic SALY fixture READY; no real return",
           "Ejecucion":"SALY SQL fixture executed via same quality_apply_envelope_v2",
           "Promocion":"SALY fixture apply executed, NOT native production apply",
           "VIGENTE":"PG18 synthetic SALY source and quality activated",
           "Readback":"PG18 state, family and next_review_at checked",
           "Cierre":"L18 sandbox-only closure ledger, no native close"}
    return [{"stage":st,"status":states[st],"evidence":ev[st]} for st in STAGES]
def bootstrap():
    l17.DB=DB
    l17.setup()
    sql((HERE/"11_l18_integrated_cycle_sandbox.sql").read_text(encoding="utf-8"))
    check("BOOTSTRAP_L13_L14_L17",True,"all layers loaded in a clean PG18 DB",
      {"db":DB,"source":"L11B frozen + L13 schema/seed + L14 + L17 JWT + L18 extension"})
def exact_gate_md5():
    x=l14.l11b.md5s()
    check("MD5_FROZEN_BEFORE",x==EXPECTED,EXPECTED,x)
    return x
def integrated_lf(variant,owner_jwt):
    is_correction=variant=="B_CORRECTED"
    code=l14.l11b.RULE
    b=l14.l11b.CASE["base_rule"]
    quote=l14.l11b.CASE_ID+"|ALLOW|"+l14.l11b.QUOTE
    # L11B setup creates the real PG18 mechanical-promotion request, synthetic receipts.
    # B additionally seeds an existing VIGENTE legacy rule in the L13 registry.
    predecessor_sql="" if not is_correction else """
INSERT INTO rule_quality_l13.rules(project_code,rule_code,family_code,category_raw,
 entity_code,definition_text,config,state,reviewed_at,next_review_at,effective_from)
SELECT 'lf','RULE-DEPENDENCY-001','IDENTIDAD_SEGURIDAD','SECURITY',
 'GENERAL',descripcion,'{}'::jsonb,'VIGENTE',
 clock_timestamp(),clock_timestamp()+interval '90 days',clock_timestamp()
FROM lf_ops.reglas WHERE codigo='RULE-DEPENDENCY-001';
"""
    if is_correction:
        evidence=json.dumps({"source_ref":"SBX-L18-CORRECTION",
                             "rationale":"explicit successor for existing source rule"})
        prepare=(
         "SELECT 'CORRECTION|'||rule_quality_l13.quality_propose_correction_v2("+
         "'lf','RULE-DEPENDENCY-001',"+lit(code)+","+
         lit(b["description"])+","+lit(evidence)+"::jsonb)::text;\n"+
         "SELECT 'PREP|'||rule_quality_l13.l18_prepare_explicit_successor_v1("+
         "'lf','RULE-DEPENDENCY-001',"+lit(code)+")::text;"
        )
    else:
        prepare="SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('lf',"+lit(code)+",'IDENTIDAD_SEGURIDAD')::text;"
    approval=(
      "SELECT 'JWT_OWNER|'||rule_quality_l13.l18_owner_intent_v1('lf',"
      +lit(code)+",'PROM-TEST')::text;")
    closure=(
      "SELECT 'CLOSED|'||rule_quality_l13.l18_close_sandbox_cycle_v1('lf',"
      +lit(code)+",'PROM-TEST',"+lit(l14.l11b.OWNER_RUN)+")::text;")
    if not is_correction:
        time_cycle="""SELECT 'AS_OF_INITIAL|'||rule_quality_l13.l18_due_snapshot_v1('lf','REG_SEG_004')::text;
SELECT 'RENEW|'||rule_quality_l13.l18_owner_due_decide_v1(
 'lf','REG_SEG_004','KEEP_VIGENTE',
 '{"source_ref":"L18-ASOF-RENEW-SBX","rationale":"explicit owner date-only test renewal"}'::jsonb)::text;
SELECT 'RENEW_READBACK|'||rule_quality_l13.l18_readback_rule_state_v1('lf','REG_SEG_004')::text;
SELECT 'AS_OF_SECOND|'||rule_quality_l13.l18_due_snapshot_v1('lf','REG_SEG_004')::text;
SELECT 'EXPIRE|'||rule_quality_l13.l18_owner_due_decide_v1(
 'lf','REG_SEG_004','EXPIRE',
 '{"source_ref":"L18-ASOF-EXPIRE-SBX","rationale":"explicit owner test caducity after second due date"}'::jsonb)::text;
SELECT 'EXPIRE_READBACK|'||rule_quality_l13.l18_readback_rule_state_v1('lf','REG_SEG_004')::text;"""
        predecessor_readback=""
    else:
        time_cycle="""SELECT 'SUPERSEDE|'||rule_quality_l13.l18_owner_review_decide_v1(
 'lf','RULE-DEPENDENCY-001','SUPERSEDE',clock_timestamp(),
 '{"source_ref":"L18-SUCCEDE-SBX","rationale":"verified signed owner explicit succession"}'::jsonb,
 'REG_SEG_004')::text;"""
        predecessor_readback="""SELECT 'OLD_READBACK|'||jsonb_build_object(
 'model_state',(SELECT state FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code='RULE-DEPENDENCY-001'),
 'model_successor',(SELECT successor_rule_code FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code='RULE-DEPENDENCY-001'),
 'legacy_source_state',(SELECT estado FROM lf_ops.reglas WHERE codigo='RULE-DEPENDENCY-001'),
 'correction_link_rows',(SELECT count(*) FROM rule_quality_l13.correction_requests
  WHERE project_code='lf' AND original_rule_code='RULE-DEPENDENCY-001'
   AND successor_rule_code='REG_SEG_004'))::text;"""
    script=f"""BEGIN;
{l14.l11b.setup("POSITIVE")}
{predecessor_sql}
{owner_session(owner_jwt,prepare)}
SELECT 'LINE|'||public.lf_rule_promotion_citation_line_check_v1('PROM-TEST',{lit(quote)})::text;
SET LOCAL ROLE lf_rule_citation_step70_bridge;
SELECT 'CAPTURE|'||public.lf_rule_promotion_citation_record_v1(
 'PROM-TEST',{lit(quote)},'EXEC-PARENT-TEST-001')::text;
RESET ROLE;
SELECT 'CAPTURE_VERIFY|'||public.lf_rule_promotion_citation_verify_v1('PROM-TEST')::text;
SELECT 'PIN|'||public.lf_rule_promotion_blind_verdict_pin_v1('PROM-TEST')::text;
SELECT 'IG_VERIFY|'||public.lf_rule_promotion_ig_semantic_verify_v1('PROM-TEST')::text;
{owner_session(owner_jwt,approval)}
{l14.l11b.owner_run()}
SELECT 'OWNER_VERIFY|'||public.lf_rule_promotion_profile_owner_verify_v1('PROM-TEST')::text;
{owner_session(owner_jwt,
    "SELECT 'WRAPPED|'||rule_quality_l13.quality_apply_envelope_v2('lf',"+lit(code)+",'PROM-TEST',"+lit(l14.l11b.OWNER_RUN)+")::text;\n"+closure+"\n"+time_cycle)}
{predecessor_readback}
SELECT 'READBACK|'||jsonb_build_object(
  'source_state',(SELECT estado FROM lf_ops.reglas WHERE codigo={lit(code)}),
  'model_state',(SELECT state FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'family',(SELECT family_code FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'reviewed_at',(SELECT reviewed_at FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'next_review_at',(SELECT next_review_at FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'closed',(SELECT status FROM rule_quality_l13.l18_closure_receipts
    WHERE project_code='lf' AND rule_code={lit(code)} AND promotion_id='PROM-TEST'))::text;
SELECT 'MD5|'||jsonb_build_object(
 'apply',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
 'capture_record',md5(pg_get_functiondef('public.lf_rule_promotion_citation_record_v1(text,text,text)'::regprocedure)),
 'citation_verify',md5(pg_get_functiondef('public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure)),
 'l8_guard',md5(pg_get_functiondef('public.lf_rule_promotion_citation_scope_guard_v2()'::regprocedure)))::text;
ROLLBACK;
SELECT 'AFTER_ROLLBACK|'||jsonb_build_object(
 'source_candidate_rows',(SELECT count(*) FROM lf_ops.reglas WHERE codigo={lit(code)}),
 'quality_candidate_rows',(SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
 'owner_intents',(SELECT count(*) FROM rule_quality_l13.l18_owner_intents),
 'close_receipts',(SELECT count(*) FROM rule_quality_l13.l18_closure_receipts),
 'correction_links',(SELECT count(*) FROM rule_quality_l13.correction_requests))::text;
"""
    out=sql(script)
    basic=(out["PREP"]["family"]=="IDENTIDAD_SEGURIDAD" if is_correction
           else out["PREP"]["family_code"]=="IDENTIDAD_SEGURIDAD")
    # Requested temporal experiment intentionally ends in CADUCADA; the READY
    # result is captured BEFORE the as_of decisions and is not a post-expiry claim.
    w=out["WRAPPED"]
    state_from_final=out["READBACK"]["model_state"]
    correct=(out["CAPTURE"]["status"]=="CAPTURED_FOR_GATE_VERIFICATION"
     and out["CAPTURE_VERIFY"]["status"]=="VERIFIED_CAPTURE_BINDING"
     and out["PIN"]["status"]=="REAL_VERDICT_ALLOW_VERIFIED"
     and out["IG_VERIFY"]["status"]=="READY_FOR_PROFILE_APPROVAL"
     and out["JWT_OWNER"]["status"]=="OWNER_JWT_SANDBOX_APPROVED"
     and out["JWT_OWNER"]["official_step70_attested"] is False
     and out["OWNER_APPROVAL"]["status"]=="APPROVED"
     and out["OWNER_VERIFY"]["status"]=="VERIFIED_PROFILE_OWNER"
     and w["status"]=="READY" and w["gate"]["status"]=="APPLIED"
     and w["profile_return"]["status"]=="READY"
     and w["profile_return"]["readback_verified"] is True
     and w["quality_readback"]=="VIGENTE" and w["next_review_at"] is not None
     and w["identity_v2"]["sub"]=="lf-sub-owner-001"
     and out["CLOSED"]["status"]=="CLOSED_SANDBOX_SIMULATION"
     and out["CLOSED"]["native_profile_closed"] is False
     and out["READBACK"]["closed"]=="CLOSED_SANDBOX_SIMULATION"
     and out["MD5"]==EXPECTED
     and out["AFTER_ROLLBACK"]=={
      "source_candidate_rows":0,"quality_candidate_rows":0,
      "owner_intents":0,"close_receipts":0,"correction_links":0} and basic)
    if is_correction:
        correct=correct and (out["CORRECTION"]["status"]=="EN_REVISION"
         and out["PREP"]["status"]=="SUCCESSOR_PREPARED"
         and out["SUPERSEDE"]["decision"]=="SUPERSEDE"
         and out["OLD_READBACK"]["model_state"]=="SUCEDIDA"
         and out["OLD_READBACK"]["model_successor"]==code
         and out["OLD_READBACK"]["correction_link_rows"]==1
         and out["OLD_READBACK"]["legacy_source_state"]=="VIGENTE"
         and state_from_final=="VIGENTE")
    else:
        correct=correct and (out["PREP"]["status"]=="QUALITY_PREPARED"
         and out["AS_OF_INITIAL"]["due"]==1
         and out["AS_OF_INITIAL"]["state"]=="VIGENTE"
         and out["RENEW"]["decision"]=="KEEP_VIGENTE"
         and out["RENEW_READBACK"]["state"]=="VIGENTE"
         and out["RENEW_READBACK"]["decision_rows"]==1
         and out["AS_OF_SECOND"]["due"]==1
         and out["AS_OF_SECOND"]["state"]=="VIGENTE"
         and out["EXPIRE"]["decision"]=="EXPIRE"
         and out["EXPIRE_READBACK"]["state"]=="CADUCADA"
         and out["EXPIRE_READBACK"]["next_review_at"] is None
         and out["READBACK"]["source_state"]=="VIGENTE"
         and out["EXPIRE_READBACK"]["decision_rows"]==2
         and state_from_final=="CADUCADA")
    compact={k:out.get(k) for k in (
     "REQUEST","QUALITY","BIND","SOURCE","LINE","CAPTURE","CAPTURE_VERIFY",
     "PIN","IG_VERIFY","JWT_OWNER","OWNER_APPROVAL","OWNER_VERIFY","PREP",
     "CORRECTION","WRAPPED","CLOSED","READBACK","AS_OF_INITIAL","RENEW",
     "RENEW_READBACK","AS_OF_SECOND","EXPIRE","EXPIRE_READBACK","SUPERSEDE",
     "OLD_READBACK","AFTER_ROLLBACK","MD5")}
    check("A_LF_NEW_FULL_CYCLE" if not is_correction else "B_LF_CORRECTED_FULL_CYCLE",
      correct,"mechanical SQL L7/L8 L11B + verified HMAC owner + L13/14/17, temporal/explicit successor",compact)
    board=boards("lf",out,variant)
    check(variant+"_12_STAGE_BOARD",len(board)==12 and [v["stage"] for v in board]==list(STAGES)
       and all(v["status"] in VALID_STATES for v in board)
       and next(v["status"] for v in board if v["stage"]=="Router")=="SINTETICO"
       and next(v["status"] for v in board if v["stage"]=="Cierre")=="SINTETICO",
       "12 honest stage labels with exact source mechanism",board)
    return {"scenario":variant,"board":board,"readback":compact,
            "reality":"SANDBOX_L11B_MECHANICAL_ONLY_UNATTESTED_NATIVE"}
def saly_new_cycle(saly_jwt):
    script="""BEGIN;
"""+saly_session(saly_jwt,"""
SELECT 'REQUEST|'||jsonb_build_object('project','saly','action','NEW_RULE','source','SANDBOX_ONLY')::text;
SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('saly','SALY-L14-NEW','MOTOR_DISPONIBLE')::text;
SELECT 'JWT_OWNER|'||rule_quality_l13.l18_owner_intent_v1('saly','SALY-L14-NEW','SALY-L18-SBX-A')::text;
SELECT 'WRAPPED|'||rule_quality_l13.quality_apply_envelope_v2('saly','SALY-L14-NEW')::text;
SELECT 'CLOSED|'||rule_quality_l13.l18_close_sandbox_cycle_v1('saly','SALY-L14-NEW','SALY-L18-SBX-A')::text;
""")+"""
SELECT 'READBACK|'||jsonb_build_object(
  'source_vigente',(SELECT vigente FROM rule_quality_l13.saly_source_synthetic WHERE codigo='SALY-L14-NEW'),
  'model_state',(SELECT state FROM rule_quality_l13.rules WHERE project_code='saly' AND rule_code='SALY-L14-NEW'),
  'family',(SELECT family_code FROM rule_quality_l13.rules WHERE project_code='saly' AND rule_code='SALY-L14-NEW'),
  'reviewed_at',(SELECT reviewed_at FROM rule_quality_l13.rules WHERE project_code='saly' AND rule_code='SALY-L14-NEW'),
  'next_review_at',(SELECT next_review_at FROM rule_quality_l13.rules WHERE project_code='saly' AND rule_code='SALY-L14-NEW'),
  'closed',(SELECT status FROM rule_quality_l13.l18_closure_receipts WHERE project_code='saly' AND rule_code='SALY-L14-NEW'))::text;
ROLLBACK;
SELECT 'AFTER_ROLLBACK|'||jsonb_build_object(
 'quality',(SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='saly' AND rule_code='SALY-L14-NEW'),
 'owner_intents',(SELECT count(*) FROM rule_quality_l13.l18_owner_intents),
 'closures',(SELECT count(*) FROM rule_quality_l13.l18_closure_receipts))::text;
"""
    out=sql(script)
    ok=(out["PREP"]["status"]=="QUALITY_PREPARED"
        and out["PREP"]["family_code"]=="MOTOR_DISPONIBLE"
        and out["JWT_OWNER"]["status"]=="OWNER_JWT_SANDBOX_APPROVED"
        and out["WRAPPED"]["status"]=="READY"
        and out["WRAPPED"]["gate"]["fixture_only"] is True
        and out["WRAPPED"]["next_review_at"] is not None
        and out["CLOSED"]["status"]=="CLOSED_SANDBOX_SIMULATION"
        and out["READBACK"]["source_vigente"] is True
        and out["READBACK"]["model_state"]=="VIGENTE"
        and out["READBACK"]["closed"]=="CLOSED_SANDBOX_SIMULATION"
        and out["AFTER_ROLLBACK"]=={"quality":0,"owner_intents":0,"closures":0})
    check("C_SALY_NEW_SAME_FUNCTIONS",ok,
      "shared L13+L14+L17+L18 functions, synthetic SALY apply, rollback",out)
    board=boards("saly",out,"C_SALY_NEW")
    check("C_SALY_NEW_12_STAGE_BOARD",
      len(board)==12 and [r["stage"] for r in board]==list(STAGES)
      and all(r["status"] in VALID_STATES for r in board)
      and next(r["status"] for r in board if r["stage"]=="IG")=="NO_PROBADO",
      "SALY no real L7/L8, no false IG attestation",board)
    return {"scenario":"C_SALY_NEW","board":board,"readback":out,
            "reality":"SALY_SYNTHETIC_ADAPTER_NOT_NATIVE"}
def negatives(lf_owner,lf_super):
    # All six are in the same PG18 runner and reference L18 source/role contracts.
    negs=[
      ("N1_NO_FAMILY",
       lambda:l17.exec_as("lf_owner_role",lf_owner,
         "SELECT rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEG-NO-FAM',NULL);",fail=True),
       "BLOCK_QUALITY_FAMILY_REQUIRED"),
      ("N3_JWT_BAD_SIGNATURE",
       lambda:l17.exec_as("lf_owner_role",{**lf_owner,"sub":"tampered-single-character"},
         "SELECT rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD');",fail=True),
       "BLOCK_L17_JWT_SIGNATURE_INVALID"),
      ("N5_SUPER_ADMIN_CANNOT_APPROVE",
       lambda:l17.exec_as("lf_super_role",lf_super,
         "SELECT rule_quality_l13.l18_owner_intent_v1('lf','REG_SEG_004','PROM-TEST');",fail=True),
       "BLOCK_SUPER_ADMIN_APPROVAL"),
      ("N6_DIRECT_DML_FORBIDDEN",
       lambda:l17.exec_as("lf_owner_role",lf_owner,
         "UPDATE rule_quality_l13.rules SET state='VIGENTE' WHERE project_code='lf';",fail=True),
       "permission denied for table rules")
    ]
    for name,fn,needle in negs:
        output=fn()
        check(name,needle in output["stderr"],needle,
          {"sqlstate_error":output["stderr"].splitlines()[0],"exit_code":output["exit_code"]})
    changed=l14.l11b.scenario("QUOTE_TAMPER")
    check("N2_EXACT_CITATION_1_CHAR_TAMPER",
      changed["LINE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and changed["CAPTURE"]["status"]=="HUMAN_DECISION_REQUIRED"
      and changed["CAPTURE_VERIFY"]["status"]!="VERIFIED_CAPTURE_BINDING"
      and changed["APPLY"]["status"]=="BLOCKED"
      and changed["IN_TX"]["rule"]=="CANDIDATO"
      and changed["ROLLBACK"]["rule_rows"]==0,
      "one-character deviation blocks exact citation and frozen apply",
      {k:changed[k] for k in ("LINE","CAPTURE","CAPTURE_VERIFY","APPLY","IN_TX","ROLLBACK")})
    ig_owner=l14.l11b.scenario("OWNER_EQ_IG")
    check("N4_OWNER_EQUALS_IG_DENIED",
      ig_owner["OWNER_REGISTRY_DENIAL"]["status"]=="REJECTED_IG_OWNER_BY_CANONICAL_CHECK"
      and ig_owner["OWNER_REGISTRY_DENIAL"]["persisted_owner_rows"]==0
      and ig_owner["OWNER_VERIFY"]["blocking_code"]=="PROFILE_OWNER_RULE_AUTHORITY_NOT_ATTESTED"
      and ig_owner["APPLY"]["status"]=="BLOCKED"
      and ig_owner["IN_TX"]["rule"]=="CANDIDATO",
      "canonical owner/IG incompatibility, synthetic Step70 negative",
      {k:ig_owner[k] for k in ("OWNER_REGISTRY_DENIAL","OWNER_VERIFY","APPLY","IN_TX","ROLLBACK")})
def main():
    bootstrap()
    before=exact_gate_md5()
    lf=l17.token("lf","lf-sub-owner-001","lf_owner_role")
    lf_super=l17.token("lf","lf-sub-super-001","lf_super_role")
    saly=l17.token("saly","saly-sub-owner-001","saly_owner_role")
    outputA=integrated_lf("A_NEW",lf)
    outputB=integrated_lf("B_CORRECTED",lf)
    outputS=saly_new_cycle(saly)
    negatives(lf,lf_super)
    after=l14.l11b.md5s()
    check("MD5_FROZEN_AFTER",before==after==EXPECTED,EXPECTED,after)
    report={
     "schema_version":"LF_L18_SINGLE_RUNNER_INTEGRATED_CYCLE_PG18_V1",
     "status":"SANDBOX_VERIFIED","global_status":"NO_GO_UNVERIFIED",
     "identity":"HMAC_SANDBOX_NOT_SUPABASE_AUTH",
     "synthetic_provenance":l14.l11b.LABEL,
     "scenarios":[outputA,outputB,outputS],
     "test_count":len(CASE_ROWS),"cases":CASE_ROWS,
     "gate_md5_before":before,"gate_md5_after":after,
     "step70_native":False,"profile_run_native":False,"router_native":False,
     "live_supabase_writes":0,"full_sandbox_scenarios_rollback":True,
     "native_closed":False,
     "legacy_source_succession_synchronized":False,
     "note":"Quality registry predecessor SUCEDIDA while synthetic lf_ops source old VIGENTE (legacy fixture limits)."
    }
    dest=HERE/"lote18_integrated_runtime.json"
    dest.write_text(json.dumps(report,ensure_ascii=False,sort_keys=True,indent=2,default=str)+"\n",encoding="utf-8")
    print("RAW_L18_REPORT "+json.dumps(report,ensure_ascii=False,sort_keys=True,default=str),flush=True)
    print("RAW_L18_REPORT_SHA256 "+hashlib.sha256(dest.read_bytes()).hexdigest(),flush=True)
    print("L18_SINGLE_INTEGRATED_RUNNER_PASS checks="+str(len(CASE_ROWS))+" scenarios=3 negatives=6",flush=True)
if __name__=="__main__":main()
