#!/usr/bin/env python3
"""L17: PostgREST simulation and signed-claims actor adapter in disposable PG18.
No Supabase Auth, no native Step70/OIDC, no product identity attestation.
"""
import hashlib,json
from pathlib import Path
import test_pg18_lote14_quality_wrapper as l14

ROOT=Path(__file__).resolve().parents[3]
HERE=ROOT/"sandbox/lf_contract_gate_test/rule_quality_lifecycle_v1"
DB="lf_3779_l17_jwt_identity_adapter_pg18"
CASES=[]
def lit(v):return l14.lit(v)
def sql(src,fail=False):return l14.exec_sql(src,should_fail=fail)
def record(name,ok,expected,observed):
    if not ok:raise AssertionError("L17_FAIL_"+name+" expected="+str(expected)+" observed="+str(observed)[:3800])
    CASES.append({"id":name,"status":"PASS","expected":expected,"observed":observed})
    print("PASS_L17_"+name+" "+json.dumps(observed,sort_keys=True,ensure_ascii=False,default=str),flush=True)
def token(project,sub,role,expiry=3600):
    q=("SELECT 'T|'||rule_quality_l13.l17_sandbox_mint("
      +lit(project)+","+lit(sub)+","+lit(role)+","+str(expiry)+")::text;")
    return sql(q)["T"]
def exec_as(role,claim,statement,fail=False,via_session="l17_authenticator"):
    # PostgREST-like transaction: one login, restricted SET ROLE and LOCAL request JWT.
    q="BEGIN;\nSET SESSION AUTHORIZATION "+via_session+";\nSET LOCAL ROLE "+role+";\n"
    if claim is not None:
        q+="SELECT set_config('request.jwt.claims',"+lit(json.dumps(claim,sort_keys=True))+",true);\n"
    q+=statement+"\nROLLBACK;"
    return sql(q,fail=fail)
def expect_error(name,role,claim,stmt,code,via_session="l17_authenticator"):
    r=exec_as(role,claim,stmt,fail=True,via_session=via_session)
    record(name,code in r["stderr"],code,
       {"sql_error":r["stderr"].splitlines()[0][:220],"exit":r["exit_code"]})
def verified_current_user(project):
    return ("SELECT 'CTX|'||jsonb_build_object("
     "'current_user',current_user,'session_user',session_user,"
     "'role',current_setting('role'),'jwt_local',current_setting('request.jwt.claims',true) IS NOT NULL)::text;\n"
     "SELECT 'IDENTITY|'||rule_quality_l13.l17_assert_request_current_user_v2("
     +lit(project)+")::text;")
def setup():
    # PG roles are cluster-scoped; prior L14 standalone script may have created them.
    # The CI deletes prior disposable DBs before each script; remove orphan test-only roles.
    l14.l11b.base.sql("""DROP ROLE IF EXISTS
       l17_authenticator,lf_owner_role,lf_super_role,lf_reader_role,
       lf_no_grant_role,saly_owner_role,saly_super_role;""", db="postgres")
    l14.DB=DB
    l14.bootstrap()
    sql((HERE/"08_l17_postgrest_roles_fixture.sql").read_text(encoding="utf-8"))
    # V1's authentication failure is measured BEFORE replacing trusted_actor_role.
    v1=exec_as("lf_owner_role",None,
       "SELECT rule_quality_l13.trusted_actor_role('lf');",fail=True)
    record("L17_01_V1_SESSION_USER_FAILS",
      "BLOCK_QUALITY_ROLE_UNMAPPED" in v1["stderr"],
      "L14 V1 rejects session_user=l17_authenticator even when current_user=lf_owner_role",
      {"sql_error":v1["stderr"].splitlines()[0],"status":"EXPECTED_NEGATIVE"})
    ctx=exec_as("lf_owner_role",None,
       "SELECT 'CTX|'||jsonb_build_object('session_user',session_user,'current_user',current_user,'role',current_setting('role'))::text;")
    record("L17_02_POSTGREST_CONTEXT",
      ctx["CTX"]["session_user"]=="l17_authenticator"
      and ctx["CTX"]["current_user"]=="lf_owner_role"
      and ctx["CTX"]["role"]=="lf_owner_role",
      "authenticator session, owner current_user after SET LOCAL ROLE",ctx["CTX"])
    sql((HERE/"09_l17_verified_actor_v2.sql").read_text(encoding="utf-8"))
    sql((HERE/"10_l17_quality_trigger_acl.sql").read_text(encoding="utf-8"))
def auth_tests():
    lf=token("lf","lf-sub-owner-001","lf_owner_role")
    saly=token("saly","saly-sub-owner-001","saly_owner_role")
    lf_super=token("lf","lf-sub-super-001","lf_super_role")
    lf_reader=token("lf","lf-sub-reader-001","lf_reader_role")
    good=exec_as("lf_owner_role",lf,verified_current_user("lf"))
    record("L17_03_LF_SIGNED_SUB_ROLE_PASS",
      good["CTX"]["session_user"]=="l17_authenticator"
      and good["CTX"]["current_user"]=="lf_owner_role"
      and good["IDENTITY"]["role"]=="lf_owner_role"
      and good["IDENTITY"]["sub"]=="lf-sub-owner-001"
      and good["IDENTITY"]["project_code"]=="lf",
      "valid LF HMAC claim + role + sub + project mapping",good)
    good_saly=exec_as("saly_owner_role",saly,verified_current_user("saly"))
    record("L17_04_SALY_SAME_VERIFIER_PASS",
      good_saly["IDENTITY"]["project_code"]=="saly"
      and good_saly["IDENTITY"]["role"]=="saly_owner_role"
      and good_saly["IDENTITY"]["sub"]=="saly-sub-owner-001",
      "same verification functions with SALY adapter",good_saly)
    # Four paired negatives directly against the two positive checks.
    tampered=dict(lf);tampered["sub"]="lf-sub-reader-001"
    expect_error("L17_05_BAD_HMAC", "lf_owner_role",tampered,
      "SELECT rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD');",
      "BLOCK_L17_JWT_SIGNATURE_INVALID")
    cross=token("saly","saly-sub-owner-001","lf_owner_role")
    expect_error("L17_06_OTHER_PROJECT", "lf_owner_role",cross,
      "SELECT rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD');",
      "BLOCK_L17_JWT_PROJECT_MISMATCH")
    unknown=token("lf","lf-sub-nonexistent","lf_owner_role")
    expect_error("L17_07_UNMAPPED_SUB", "lf_owner_role",unknown,
      "SELECT rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD');",
      "BLOCK_L17_JWT_SUB_UNMAPPED")
    expect_error("L17_08_ROLE_MISMATCH", "lf_reader_role",lf,
      "SELECT rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD');",
      "BLOCK_L17_JWT_EFFECTIVE_ROLE_MISMATCH")
    expect_error("L17_09_SUPER_ADMIN_DENIED","lf_super_role",lf_super,
      "SELECT rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD');",
      "BLOCK_SUPER_ADMIN_APPROVAL")
    expect_error("L17_10_READER_DENIED","lf_reader_role",lf_reader,
      "SELECT rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD');",
      "BLOCK_L17_NOT_PROJECT_OWNER")
    expired=token("lf","lf-sub-owner-001","lf_owner_role",-30)
    expect_error("L17_11_EXPIRED_JWT","lf_owner_role",expired,
      "SELECT rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD');",
      "BLOCK_L17_JWT_EXPIRED_OR_NOT_YET_VALID")
    expect_error("L17_12_CLAIMS_MISSING","lf_owner_role",None,
      "SELECT rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD');",
      "BLOCK_L17_JWT_MISSING")
    expect_error("L17_13_DIRECT_LOGIN_NOT_POSTGREST","lf_owner_role",lf,
      "SELECT rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD');",
      "BLOCK_L17_NOT_AUTHENTICATOR_SESSION",via_session="lf_owner_role")
    expect_error("L17_14_DIRECT_DML_BLOCKED","lf_owner_role",lf,
      "UPDATE rule_quality_l13.rules SET state='VIGENTE' WHERE project_code='lf';",
      "permission denied for table rules")
    expect_error("L17_15_SIGNING_ORACLE_BLOCKED","lf_owner_role",lf,
      "SELECT rule_quality_l13.l17_sandbox_mint('lf','lf-sub-owner-001','lf_owner_role');",
      "permission denied for function l17_sandbox_mint")
    expect_error("L17_16_SOURCE_TRIGGER_DISABLE_BLOCKED","lf_owner_role",lf,
      "ALTER TABLE rule_quality_l13.saly_source_synthetic DISABLE TRIGGER trg_l14_saly_quality_activate;",
      "must be owner of table saly_source_synthetic")
    expect_error("L17_17_LEGACY_DEFINER_NO_JWT_BYPASS","lf_owner_role",None,
      "SELECT rule_quality_l13.quality_prepare_new('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD');",
      "BLOCK_L17_JWT_MISSING")
    no_claim=exec_as("lf_owner_role",None,
      "SELECT 'ROLE_ONLY|'||jsonb_build_object('role',current_user,'session',session_user)::text;")
    record("L17_18_ROLE_ALONE_NOT_AUTHORITY",
      no_claim["ROLE_ONLY"]["session"]=="l17_authenticator",
      "SET ROLE is not authorization: valid signed sub required",no_claim)
    # Existing canonical actor table is not exposed, despite a verified owner token.
    expect_error("L17_19_DIRECT_ACTOR_MAP_DML_BLOCKED","lf_owner_role",lf,
      "UPDATE rule_quality_l13.l17_actor_subjects SET actor_code='lf_owner_role';",
      "permission denied for table l17_actor_subjects")
    # Test GUC is set LOCAL and cannot survive rollback on pooled connection.
    after=sql("SELECT 'LOCAL_CLAIMS|'||current_setting('request.jwt.claims',true);")
    record("L17_20_TRANSACTION_LOCAL_CLAIMS_RESET",
      after.get("LOCAL_CLAIMS","") in ("",None),
      "transaction-local claims not retained in next connection",
      {"claim_after_rollback":after.get("LOCAL_CLAIMS")})
    return lf,saly
def prepare_and_apply_saly(saly):
    q="""SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2(
      'saly','SALY-L14-NEW','MOTOR_DISPONIBLE')::text;
      SELECT 'WRAP|'||rule_quality_l13.quality_apply_envelope_v2(
      'saly','SALY-L14-NEW')::text;"""
    out=exec_as("saly_owner_role",saly,q)
    prep,wrap=out["PREP"],out["WRAP"]
    record("L17_21_SALY_PREPARE_APPLY_READY",
      prep["status"]=="QUALITY_PREPARED"
      and wrap["status"]=="READY" and wrap["gate"]["fixture_only"] is True
      and wrap["quality_readback"]=="VIGENTE"
      and wrap["next_review_at"] is not None
      and wrap["identity_v2"]["sub"]=="saly-sub-owner-001",
      "Saly same v2 functions; synthetic mechanic only",out)
def correction_v2(lf):
    ev='{"source_ref":"SBX-L17","rationale":"owner-signed verified correction"}'
    q=("SELECT 'CORRECTION|'||rule_quality_l13.quality_propose_correction_v2("
      "'lf','LF-SYN-0009','LF-SYN-0009-L17','corrected with explicit version',"
      +lit(ev)+"::jsonb)::text;")
    out=exec_as("lf_owner_role",lf,q)
    record("L17_22_EXPLICIT_VERSION_REVIEW",
      out["CORRECTION"]["status"]=="EN_REVISION"
      and out["CORRECTION"]["successor_rule_code"]=="LF-SYN-0009-L17",
      "valid signed owner proposes new version; never silent edit",out)
def l11b_full_chain(lf):
    quote=l14.l11b.CASE_ID+"|ALLOW|"+l14.l11b.QUOTE
    code=l14.l11b.RULE
    setup=l14.l11b.setup("POSITIVE")
    owner=l14.l11b.owner_run()
    injected="SELECT set_config('request.jwt.claims',"+lit(json.dumps(lf,sort_keys=True))+",true);"
    script=f"""BEGIN;
{setup}
SET SESSION AUTHORIZATION l17_authenticator;
SET LOCAL ROLE lf_owner_role;
{injected}
SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('lf',{lit(code)},'IDENTIDAD_SEGURIDAD')::text;
RESET SESSION AUTHORIZATION;
SELECT 'LINE|'||public.lf_rule_promotion_citation_line_check_v1('PROM-TEST',{lit(quote)})::text;
SET LOCAL ROLE lf_rule_citation_step70_bridge;
SELECT 'CAPTURE|'||public.lf_rule_promotion_citation_record_v1(
  'PROM-TEST',{lit(quote)},'EXEC-PARENT-TEST-001')::text;
RESET ROLE;
SELECT 'VERIFY|'||public.lf_rule_promotion_citation_verify_v1('PROM-TEST')::text;
SELECT 'PIN|'||public.lf_rule_promotion_blind_verdict_pin_v1('PROM-TEST')::text;
SELECT 'IG|'||public.lf_rule_promotion_ig_semantic_verify_v1('PROM-TEST')::text;
{owner}
SELECT 'OWNER|'||public.lf_rule_promotion_profile_owner_verify_v1('PROM-TEST')::text;
SET SESSION AUTHORIZATION l17_authenticator;
SET LOCAL ROLE lf_owner_role;
{injected}
SELECT 'WRAP|'||rule_quality_l13.quality_apply_envelope_v2(
  'lf',{lit(code)},'PROM-TEST',{lit(l14.l11b.OWNER_RUN)})::text;
RESET SESSION AUTHORIZATION;
SELECT 'READBACK|'||jsonb_build_object(
  'source',(SELECT estado FROM lf_ops.reglas WHERE codigo={lit(code)}),
  'quality',(SELECT state FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'family',(SELECT family_code FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'reviewed_at',(SELECT reviewed_at FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'next_review_at',(SELECT next_review_at FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'ticket',(SELECT status FROM rule_quality_l13.activation_tickets WHERE project_code='lf' AND rule_code={lit(code)}))::text;
SELECT 'MD5|'||jsonb_build_object(
 'apply',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
 'capture_record',md5(pg_get_functiondef('public.lf_rule_promotion_citation_record_v1(text,text,text)'::regprocedure)),
 'citation_verify',md5(pg_get_functiondef('public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure)),
 'l8_guard',md5(pg_get_functiondef('public.lf_rule_promotion_citation_scope_guard_v2()'::regprocedure)))::text;
ROLLBACK;
SELECT 'AFTER_ROLLBACK|'||jsonb_build_object(
  'source_rule_rows',(SELECT count(*) FROM lf_ops.reglas WHERE codigo={lit(code)}),
  'quality_rule_rows',(SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'tickets',(SELECT count(*) FROM rule_quality_l13.activation_tickets WHERE project_code='lf' AND rule_code={lit(code)}))::text;"""
    out=sql(script)
    w=out["WRAP"];read=out["READBACK"]
    ok=(out["VERIFY"]["status"]=="VERIFIED_CAPTURE_BINDING"
      and out["OWNER"]["status"]=="VERIFIED_PROFILE_OWNER"
      and w["status"]=="READY" and w["gate"]["status"]=="APPLIED"
      and w["profile_return"]["status"]=="READY"
      and w["profile_return"]["readback_verified"] is True
      and w["identity_v2"]["sub"]=="lf-sub-owner-001"
      and read["source"]=="VIGENTE" and read["quality"]=="VIGENTE"
      and read["family"]=="IDENTIDAD_SEGURIDAD" and read["next_review_at"] is not None
      and read["ticket"]=="CONSUMED"
      and out["MD5"]==l14.EXPECTED_MD5
      and out["AFTER_ROLLBACK"]=={"source_rule_rows":0,"quality_rule_rows":0,"tickets":0})
    compact={"prepare":out.get("PREP"),"gate":w.get("gate"),"return":w.get("profile_return"),
      "identity":w.get("identity_v2"),"readback":read,"rollback":out["AFTER_ROLLBACK"],
      "gate_md5":out["MD5"]}
    record("L17_23_L11B_SIGNED_SUB_WRAP_READY",ok,
      "L11B mechanistic apply APPLIED -> source & quality VIGENTE + READY -> all rollback",compact)
def main():
    setup()
    before=l14.l11b.md5s()
    record("L17_00_FROZEN_GATE_MD5_BEFORE",before==l14.EXPECTED_MD5,
      l14.EXPECTED_MD5,before)
    lf,saly=auth_tests()
    prepare_and_apply_saly(saly)
    correction_v2(lf)
    l11b_full_chain(lf)
    after=l14.l11b.md5s()
    record("L17_24_FROZEN_GATE_MD5_AFTER",after==before==l14.EXPECTED_MD5,
      l14.EXPECTED_MD5,after)
    report={"schema_version":"LF_L17_ACTOR_IDENTITY_ADAPTER_PG18_V1",
      "global_status":"NO_GO_UNVERIFIED","scope":"PG18_SYNTHETIC_ONLY",
      "caller_identity":"l17_authenticator with SET LOCAL ROLE",
      "effective_user":"current_user outside SECURITY DEFINER",
      "function_effective_role":"PostgreSQL role GUC inside SECURITY DEFINER",
      "jwt_source":"set_config(request.jwt.claims,..,true)",
      "jwt_auth":"SANDBOX_HMAC_NOT_SUPABASE_AUTH",
      "frozen_gate_md5_before":before,"frozen_gate_md5_after":after,
      "case_count":len(CASES),"cases":CASES,
      "native_step70":False,"native_oidc":False,"native_supabase_auth":False,
      "live_db_changes":0}
    path=HERE/"lote17_runtime.json"
    path.write_text(json.dumps(report,ensure_ascii=False,sort_keys=True,indent=2,default=str)+"\n",encoding="utf-8")
    print("RAW_L17_REPORT "+json.dumps(report,ensure_ascii=False,sort_keys=True,default=str),flush=True)
    print("RAW_L17_REPORT_SHA256 "+hashlib.sha256(path.read_bytes()).hexdigest(),flush=True)
    print("L17_SANDBOX_PASS tests="+str(len(CASES))+" gate_md5_unchanged=true",flush=True)
if __name__=="__main__":main()
