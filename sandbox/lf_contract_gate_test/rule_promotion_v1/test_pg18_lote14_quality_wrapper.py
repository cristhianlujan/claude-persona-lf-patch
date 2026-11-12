#!/usr/bin/env python3
"""L14 PG18.6 disposable only: wrapper, role tests, L11B mechanical chain.
No real actor attestation, no independent native IG/owner approval and no production.
Every integration scenario is rollback-only. Existing frozen SQL gates are unchanged.
"""
import hashlib, json, os, re, subprocess
from pathlib import Path
import test_pg18_lote11b_mechanical_positive as l11b

ROOT=Path(__file__).resolve().parents[3]
HERE=ROOT/"sandbox/lf_contract_gate_test/rule_quality_lifecycle_v1"
DB="lf_3779_l14_quality_wrapper_pg18"
CASES=[]
EXPECTED_MD5={
 "apply":"86b0494984edf95cf0f9c0a0df67000b",
 "capture_record":"89cbfac4162dbc9f8ecca59f2c3ab4c3",
 "citation_verify":"773a62783baa5edbe967200cac66b8c3",
 "l8_guard":"522d12f0843be1da3c785cef3c0bf3fc",
}
def lit(s):return l11b.lit(s)
def exec_sql(text,should_fail=False):
    env={**os.environ,"PGHOST":"127.0.0.1","PGPORT":"5432","PGUSER":"postgres","PGPASSWORD":"postgres"}
    cmd=["psql","-X","-q","-A","-t","-v","ON_ERROR_STOP=1","-v","VERBOSITY=verbose","-d",DB]
    proc=subprocess.run(cmd,input=text,text=True,capture_output=True,env=env,timeout=300)
    if should_fail:
        if proc.returncode==0:raise AssertionError("EXPECTED_PG_FAILURE_BUT_SQL_SUCCEEDED")
        err=proc.stderr.strip()
        return {"exit_code":proc.returncode,"stderr":err[-2500:]}
    if proc.returncode:raise AssertionError("PG18_L14_SQL_FAILED "+proc.stderr[-4500:])
    output={}
    for ln in proc.stdout.splitlines():
        if "|" in ln:
            k,v=ln.split("|",1)
            try:output[k]=json.loads(v)
            except ValueError:output[k]=v
    return output
def check(test_id,condition,expected,observed):
    if not condition:raise AssertionError(test_id+" EXPECTED="+str(expected)+" OBSERVED="+json.dumps(observed,default=str,ensure_ascii=False)[:4500])
    row={"id":test_id,"status":"PASS","expected":expected,"observed":observed}
    CASES.append(row)
    print("PASS_L14_"+test_id+" "+json.dumps(observed,ensure_ascii=False,sort_keys=True,default=str),flush=True)
def negative(test_id,stmt,sqlstate,token):
    output=exec_sql(stmt,should_fail=True)
    okay=(sqlstate in output["stderr"] and token in output["stderr"])
    check(test_id,okay,{"sqlstate":sqlstate,"blocking_code":token},output)
def admin_sql(script):
    return exec_sql(script)
def role_session(role,body,claim=None):
    lines=["BEGIN;",f"SET SESSION AUTHORIZATION {role};"]
    if claim is not None:lines.append("SET app.l14_actor_claim="+lit(claim)+";")
    lines.append(body)
    lines.extend(["RESET SESSION AUTHORIZATION;","ROLLBACK;"])
    return "\n".join(lines)
def bootstrap():
    l11b.DB=DB
    l11b.bootstrap()
    for name in ("01_schema.sql","02_seed_synthetic.sql",
                 "05_quality_wrapper_identity_and_prepare.sql",
                 "06_quality_wrapper_correction_guard.sql",
                 "07_quality_wrapper_apply_and_acl.sql"):
        print("L14_PG_SOURCE "+name,flush=True)
        exec_sql((HERE/name).read_text(encoding="utf-8"))
    # Source candidates for negative validation and SALY new-rule activation.
    exec_sql("""
    INSERT INTO lf_ops.reglas(id,codigo,descripcion,estado,categoria,owner_name)
    VALUES(2001,'LF-L14-NEG-NO-FAM','L14 synthetic LF candidate','CANDIDATO','SECURITY','LF_GOVERNANCE'),
          (2002,'LF-L14-NEW-OK','L14 synthetic LF valid-family case','CANDIDATO','SECURITY','LF_GOVERNANCE');
    INSERT INTO rule_quality_l13.saly_source_synthetic
      (codigo,categoria,regla,valor_config,vigente,decision_id,fuente,metadata)
    VALUES('SALY-L14-NEW','MOTOR_DISPONIBLE','L14 synthetic SALY new candidate',
      '{}'::jsonb,false,999,'SYNTHETIC_ONLY','{"version":"L14-SBX"}'::jsonb);
    """)
def test_permissions_and_negatives():
    negative("N1_NO_FAMILY",
      role_session("lf_owner_role","SELECT rule_quality_l13.quality_prepare_new('lf','LF-L14-NEG-NO-FAM',NULL);","lf_owner_role"),
      "23514","BLOCK_QUALITY_FAMILY_REQUIRED")
    negative("N2_CROSS_PROJECT_FAMILY",
      role_session("lf_owner_role","SELECT rule_quality_l13.quality_prepare_new('lf','LF-L14-NEG-NO-FAM','MOTOR_DISPONIBLE');","lf_owner_role"),
      "23514","BLOCK_QUALITY_FAMILY_PROJECT_MISMATCH")
    negative("N3_FORGED_GUC",
      role_session("lf_reader_role","SELECT rule_quality_l13.quality_prepare_new('lf','LF-L14-NEG-NO-FAM','IDENTIDAD_SEGURIDAD');","lf_owner_role"),
      "42501","BLOCK_QUALITY_GUC_IDENTITY_MISMATCH")
    negative("N4_DIRECT_DML_NO_GRANT",
      role_session("lf_no_grant_role","UPDATE rule_quality_l13.rules SET state='VIGENTE' WHERE project_code='lf';"),
      "42501","permission denied for table rules")
    negative("N5_SUPER_ADMIN_FORBIDDEN",
      role_session("lf_super_role","SELECT rule_quality_l13.quality_prepare_new('lf','LF-L14-NEG-NO-FAM','IDENTIDAD_SEGURIDAD');","lf_super_role"),
      "42501","BLOCK_SUPER_ADMIN_APPROVAL")
    negative("N6_NO_QUALITY_METADATA_DIRECT_SOURCE",
      "BEGIN; UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo='LF-L14-NEG-NO-FAM'; ROLLBACK;",
      "23514","BLOCK_QUALITY_ACTIVE_METADATA_MISSING")
    positive=exec_sql(role_session("lf_owner_role",
      """SELECT 'PREPARED|'||rule_quality_l13.quality_prepare_new(
           'lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD')::text;""",
      "lf_owner_role"))
    prepared=positive["PREPARED"]
    check("P1_VALID_FAMILY_REVIEW_SCHEDULED",
      prepared["status"]=="QUALITY_PREPARED" and prepared["family_code"]=="IDENTIDAD_SEGURIDAD"
      and prepared["next_review_at"] is not None,
      "correct LF family and 90-day review scheduled, no source activation",prepared)
    negative("N7_NO_TICKET_CANNOT_BYPASS_WRAP",
      "BEGIN; UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo='LF-L14-NEW-OK'; ROLLBACK;",
      "23514","BLOCK_QUALITY_ACTIVE_METADATA_MISSING")
    # Because previous P1 transaction ROLLBACK, quality metadata was not persisted.
    # Re-run P1 in a transaction and attempt bypass to ensure ticket-specific denial.
    negative("N10_REVIEW_TIME_CANNOT_BE_SPOOFED",
      role_session("lf_owner_role",
       "SELECT rule_quality_l13.quality_prepare_new('lf','LF-L14-NEG-NO-FAM','IDENTIDAD_SEGURIDAD','2099-01-01T00:00:00Z');",
       "lf_owner_role"),
      "23514","BLOCK_QUALITY_CALLER_REVIEW_TIME_FORBIDDEN")
    negative("N11_VIGENTE_CONTENT_IS_IMMUTABLE",
      "BEGIN; UPDATE lf_ops.reglas SET descripcion='illicit in-place rewrite' WHERE codigo='RULE-DEPENDENCY-001'; ROLLBACK;",
      "23514","BLOCK_QUALITY_ACTIVE_RULE_IN_PLACE_MUTATION")
    negative("N8_NO_TICKET_EVEN_WITH_METADATA",
      """BEGIN;
      SET SESSION AUTHORIZATION lf_owner_role;
      SET app.l14_actor_claim='lf_owner_role';
      SELECT rule_quality_l13.quality_prepare_new('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD');
      RESET SESSION AUTHORIZATION;
      RESET app.l14_actor_claim;
      UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo='LF-L14-NEW-OK';
      ROLLBACK;""",
      "42501","BLOCK_QUALITY_NO_ACTIVATION_TICKET")
def test_correction():
    evidence='{"source_ref":"L14-PG-SYN","rationale":"explicit changed source contract"}'
    before=admin_sql("""SELECT 'BEFORE|'||jsonb_build_object('state',state,'definition_text',definition_text)::text
      FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code='LF-SYN-0009';""")["BEFORE"]
    result=admin_sql("""BEGIN;
      SET SESSION AUTHORIZATION lf_owner_role;
      SET app.l14_actor_claim='lf_owner_role';
      SELECT 'CORRECTION|'||rule_quality_l13.quality_propose_correction(
         'lf','LF-SYN-0009','LF-SYN-0009-V2','L14 corrected synthetic statement',
         """+lit(evidence)+"""::jsonb)::text;
      RESET SESSION AUTHORIZATION;
      SELECT 'OLD|'||jsonb_build_object('state',state,'definition_text',definition_text)::text
       FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code='LF-SYN-0009';
      SELECT 'NEW|'||jsonb_build_object('state',state,'definition_text',definition_text)::text
       FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code='LF-SYN-0009-V2';
      ROLLBACK;""")
    check("P2_EXPLICIT_SUCCESSOR_NOT_EDIT_IN_PLACE",
      result["CORRECTION"]["status"]=="EN_REVISION"
      and result["OLD"]==before and result["NEW"]["state"]=="EN_REVISION"
      and result["NEW"]["definition_text"]!=before["definition_text"],
      "old VIGENTE unchanged, successor EN_REVISION, distinct code",result)
    negative("N9_CORRECTION_NO_SUCCESSOR",
      role_session("lf_owner_role",
       "SELECT rule_quality_l13.quality_propose_correction('lf','LF-SYN-0009',NULL,'No successor',"
        +lit(evidence)+"::jsonb);","lf_owner_role"),
      "23514","BLOCK_QUALITY_EXPLICIT_SUCCESSOR_REQUIRED")
def test_saly_same_functions():
    output=admin_sql("""BEGIN;
      SET SESSION AUTHORIZATION saly_owner_role;
      SET app.l14_actor_claim='saly_owner_role';
      SELECT 'PREPARED|'||rule_quality_l13.quality_prepare_new(
        'saly','SALY-L14-NEW','MOTOR_DISPONIBLE')::text;
      SELECT 'WRAPPED|'||rule_quality_l13.quality_apply_envelope(
        'saly','SALY-L14-NEW')::text;
      RESET SESSION AUTHORIZATION;
      SELECT 'READBACK|'||jsonb_build_object(
        'source_vigente',(SELECT vigente FROM rule_quality_l13.saly_source_synthetic
          WHERE codigo='SALY-L14-NEW'),
        'quality_state',(SELECT state FROM rule_quality_l13.rules WHERE project_code='saly'
          AND rule_code='SALY-L14-NEW'),
        'reviewed_at',(SELECT reviewed_at FROM rule_quality_l13.rules WHERE project_code='saly'
          AND rule_code='SALY-L14-NEW'),
        'next_review_at',(SELECT next_review_at FROM rule_quality_l13.rules WHERE project_code='saly'
          AND rule_code='SALY-L14-NEW'))::text;
      ROLLBACK;""")
    ok=(output["PREPARED"]["status"]=="QUALITY_PREPARED"
       and output["WRAPPED"]["status"]=="READY"
       and output["WRAPPED"]["gate"]["fixture_only"] is True
       and output["READBACK"]["source_vigente"] is True
       and output["READBACK"]["quality_state"]=="VIGENTE"
       and output["READBACK"]["next_review_at"] is not None)
    check("P3_SALY_SAME_WRAPPER_ADAPTER",ok,
       "SALY fixture: same quality_prepare_new + quality_apply_envelope, no edits to functions",output)
def test_due_only_proposal():
    result=admin_sql("""BEGIN;
    UPDATE rule_quality_l13.rules SET next_review_at='2026-10-01T00:00:00Z'
      WHERE project_code='lf' AND rule_code='LF-SYN-0003';
    SELECT 'BEFORE|'||jsonb_build_object('state',state,'next_review_at',next_review_at)::text
      FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code='LF-SYN-0003';
    SELECT 'DUE|'||jsonb_build_object('rule_code',rule_code,'proposal',proposal)::text
      FROM rule_quality_l13.list_review_due('lf','2026-11-12T00:00:00Z') WHERE rule_code='LF-SYN-0003';
    SELECT 'AFTER|'||jsonb_build_object('state',state,'next_review_at',next_review_at)::text
      FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code='LF-SYN-0003';
    ROLLBACK;""")
    check("P4_DUE_IS_PROPOSAL_NEVER_AUTO_MUTATION",
       result["DUE"]["proposal"]=="PROPONER_REVISION" and result["BEFORE"]==result["AFTER"],
       "read-only due proposal leaves VIGENTE and timestamp unchanged",result)
def l11b_chain():
    quote_line=l11b.CASE_ID+"|ALLOW|"+l11b.QUOTE
    code=l11b.RULE
    sqltext=f"""BEGIN;
{l11b.setup("POSITIVE")}
SET SESSION AUTHORIZATION lf_owner_role;
SET app.l14_actor_claim='lf_owner_role';
SELECT 'L14_PREPARE|'||rule_quality_l13.quality_prepare_new('lf',{lit(code)},'IDENTIDAD_SEGURIDAD')::text;
RESET SESSION AUTHORIZATION;
RESET app.l14_actor_claim;
SELECT 'LINE|'||public.lf_rule_promotion_citation_line_check_v1('PROM-TEST',{lit(quote_line)})::text;
SET LOCAL ROLE lf_rule_citation_step70_bridge;
SELECT 'CAPTURE|'||public.lf_rule_promotion_citation_record_v1(
  'PROM-TEST',{lit(quote_line)},'EXEC-PARENT-TEST-001')::text;
RESET ROLE;
SELECT 'CAPTURE_VERIFY|'||public.lf_rule_promotion_citation_verify_v1('PROM-TEST')::text;
SELECT 'PIN|'||public.lf_rule_promotion_blind_verdict_pin_v1('PROM-TEST')::text;
SELECT 'IG_VERIFY|'||public.lf_rule_promotion_ig_semantic_verify_v1('PROM-TEST')::text;
{l11b.owner_run()}
SELECT 'OWNER_VERIFY|'||public.lf_rule_promotion_profile_owner_verify_v1('PROM-TEST')::text;
SET SESSION AUTHORIZATION lf_owner_role;
SET app.l14_actor_claim='lf_owner_role';
SELECT 'WRAPPED|'||rule_quality_l13.quality_apply_envelope('lf',{lit(code)},'PROM-TEST',{lit(l11b.OWNER_RUN)})::text;
RESET SESSION AUTHORIZATION;
RESET app.l14_actor_claim;
SELECT 'READBACK|'||public.lf_rule_promotion_rule_readback_v1({lit(code)})::text;
SELECT 'QUALITY_READBACK|'||jsonb_build_object(
  'source',(SELECT estado FROM lf_ops.reglas WHERE codigo={lit(code)}),
  'quality',(SELECT state FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'family',(SELECT family_code FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'reviewed_at',(SELECT reviewed_at FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'next_review_at',(SELECT next_review_at FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
  'ticket',(SELECT status FROM rule_quality_l13.activation_tickets WHERE project_code='lf' AND rule_code={lit(code)}))::text;
SELECT 'GATE_MD5|'||jsonb_build_object(
 'apply',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
 'capture_record',md5(pg_get_functiondef('public.lf_rule_promotion_citation_record_v1(text,text,text)'::regprocedure)),
 'citation_verify',md5(pg_get_functiondef('public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure)),
 'l8_guard',md5(pg_get_functiondef('public.lf_rule_promotion_citation_scope_guard_v2()'::regprocedure)))::text;
ROLLBACK;
SELECT 'ROLLED_BACK|'||jsonb_build_object(
 'lf_source_rows',(SELECT count(*) FROM lf_ops.reglas WHERE codigo={lit(code)}),
 'lf_quality_rows',(SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code={lit(code)}),
 'activation_tickets',(SELECT count(*) FROM rule_quality_l13.activation_tickets WHERE project_code='lf' AND rule_code={lit(code)}))::text;
"""
    out=exec_sql(sqltext)
    checked=(out["L14_PREPARE"]["status"]=="QUALITY_PREPARED"
     and out["CAPTURE_VERIFY"]["status"]=="VERIFIED_CAPTURE_BINDING"
     and out["OWNER_VERIFY"]["status"]=="VERIFIED_PROFILE_OWNER"
     and out["WRAPPED"]["status"]=="READY"
     and out["WRAPPED"]["gate"]["status"]=="APPLIED"
     and out["WRAPPED"]["profile_return"]["status"]=="READY"
     and out["WRAPPED"]["profile_return"]["readback_verified"] is True
     and out["QUALITY_READBACK"]["source"]=="VIGENTE"
     and out["QUALITY_READBACK"]["quality"]=="VIGENTE"
     and out["QUALITY_READBACK"]["family"]=="IDENTIDAD_SEGURIDAD"
     and out["QUALITY_READBACK"]["next_review_at"] is not None
     and out["QUALITY_READBACK"]["ticket"]=="CONSUMED"
     and out["GATE_MD5"]==EXPECTED_MD5
     and out["ROLLED_BACK"]=={"lf_source_rows":0,"lf_quality_rows":0,"activation_tickets":0})
    check("P5_L11B_FROZEN_APPLY_WRAPPER_READY",checked,
      "frozen apply APPLIED, profile READY, source + quality VIGENTE, family+review date, ROLLBACK",out)
def main():
    bootstrap()
    before=l11b.md5s()
    check("GATE_MD5_INITIAL",before==EXPECTED_MD5,EXPECTED_MD5,before)
    test_permissions_and_negatives()
    test_correction()
    test_saly_same_functions()
    test_due_only_proposal()
    l11b_chain()
    after=l11b.md5s()
    check("GATE_MD5_UNCHANGED",before==after==EXPECTED_MD5,EXPECTED_MD5,after)
    report={
      "schema_version":"LF_L14_SANDBOX_QUALITY_WRAPPER_PG18_V1",
      "environment":"CLEAN_ISOLATED_POSTGRES18","global_authority":"UNVERIFIED_NO_GO",
      "provenance":"MECHANICAL_ONLY_SYNTHETIC_L11B_NOT_OFFICIAL",
      "actor_auth":"POSTGRES_SESSION_USER_SANDBOX_ONLY",
      "gate_md5_before":before,"gate_md5_after":after,
      "case_count":len(CASES),"cases":CASES,
      "saly_same_functions":True,"supabase_live_mutations":0,
      "rollback_mechanical":True}
    out=HERE/"lote14_runtime.json"
    out.write_text(json.dumps(report,ensure_ascii=False,sort_keys=True,indent=2,default=str)+"\n",encoding="utf-8")
    print("RAW_L14_REPORT "+json.dumps(report,ensure_ascii=False,sort_keys=True,default=str),flush=True)
    print("RAW_L14_REPORT_SHA256 "+hashlib.sha256(out.read_bytes()).hexdigest(),flush=True)
    print("L14_SANDBOX_PASS tests="+str(len(CASES))+" gate_md5_unchanged=true",flush=True)
if __name__=="__main__":main()
