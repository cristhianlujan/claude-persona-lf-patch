#!/usr/bin/env python3
"""L23: genuine PostgreSQL 18 sandbox SQL Curator guard; no native production Curator.
Requires PG18 service. All scenario writes rollback; no Supabase connection.
"""
import hashlib,json
from pathlib import Path
import test_pg18_lote18_integrated_cycle as l18
import test_pg18_lote20_source_sync as l20
import test_pg18_lote17_actor_identity_adapter as l17
import test_pg18_lote14_quality_wrapper as l14

HERE=Path(__file__).resolve().parents[1]/"rule_quality_lifecycle_v1"
DB="lf_3779_l23_curator_stage_pg18"
CASES=[]
SCENARIOS=[]
EXPECTED=l14.EXPECTED_MD5

def lit(s):return l17.lit(s)
def sql(q,fail=False):return l17.sql(q,fail=fail)
def check(name,truth,expected,observed):
    if not truth:raise AssertionError("FAIL_L23_"+name+" EXPECTED="+str(expected)+" ACTUAL="+json.dumps(observed,ensure_ascii=False,default=str)[:6500])
    row={"id":name,"status":"PASS","expected":expected,"observed":observed}
    CASES.append(row)
    print("PASS_L23_"+name+" "+json.dumps(observed,sort_keys=True,ensure_ascii=False,default=str),flush=True)
def negative(name,script,code):
    observed=sql(script,True)
    check(name,code in observed["stderr"],code,{"stderr":observed["stderr"].splitlines()[0],"exit":observed["exit_code"]})

def owner(claim,q):return l18.owner_session(claim,q)
def saly(claim,q):return l18.saly_session(claim,q)

def setup():
    l18.DB=DB
    l18.bootstrap()
    sql((HERE/"15_l23_curator_stage_pg18.sql").read_text(encoding="utf-8"))
    check("BOOTSTRAP_CLEAN_PG18",True,"L11B+L13+L14+L17+L18+L23 SQL loaded; separate PG18 DB",{"database":DB,"only_sandbox":True})

def run_lf(variant,claim):
    corrected=variant=="B_CORRECTED"
    body=l20.prelude_lf(claim,corrected)
    # A_NEW is a separate, sandbox-only new rule with no preexisting active
    # conflicting source in its category; B_CORRECTED intentionally retains old
    # VIGENTE and requires explicit signed correction lineage.
    if not corrected:
        body="UPDATE lf_ops.reglas SET estado='CANDIDATO' WHERE codigo='RULE-DEPENDENCY-001';\n"+body
    pos=body.rfind("SET SESSION AUTHORIZATION l17_authenticator;")
    if pos<0 or "SELECT 'WRAP|'" not in body[pos:]:
        raise AssertionError("L23_PRELUDE_INSERTION_NOT_AT_FINAL_WRAPPER")
    code=l14.l11b.RULE
    curator=owner(claim,"SELECT 'CURATOR|'||rule_quality_l13.l23_curator_evaluate_v1('lf',"+lit(code)+")::text;")
    body=body[:pos]+curator+"\n"+body[pos:]
    preview=sql("BEGIN;\n"+body[:body.rfind("SET SESSION AUTHORIZATION l17_authenticator;")]+"\nROLLBACK;")
    print("L23_CURATOR_PREVIEW "+json.dumps({"variant":variant,"verdict":preview.get("CURATOR"),"preparation":preview.get("PREP")},ensure_ascii=False,default=str),flush=True)
    observation="SELECT 'BEFORE_ROLLBACK|'||jsonb_build_object(" + (
      "'source',(SELECT estado FROM lf_ops.reglas WHERE codigo="+lit(code)+"),"+
      "'registry',(SELECT state FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code="+lit(code)+"),"+
      "'verdict',(SELECT verdict FROM rule_quality_l13.l23_curator_verdicts WHERE project_code='lf' AND rule_code="+lit(code)+"),"+
      "'ticket',(SELECT status FROM rule_quality_l13.activation_tickets WHERE project_code='lf' AND rule_code="+lit(code)+"))::text;")
    script="BEGIN;\n"+body+"\n"+observation+"\nROLLBACK;\n"+"SELECT 'AFTER_ROLLBACK|'||jsonb_build_object('curator_rows',(SELECT count(*) FROM rule_quality_l13.l23_curator_verdicts WHERE project_code='lf'), 'rule_rows',(SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code="+lit(code)+"))::text;"
    out=sql(script)
    ok=(out["CURATOR"]["verdict"]=="ACEPTAR" and out["CURATOR"]["gate_precondition"] is True
      and out["CURATOR"]["independent_curator_attested"] is False
      and out["WRAP"]["status"]=="READY" and out["WRAP"]["gate"]["status"]=="APPLIED"
      and out["BEFORE_ROLLBACK"]["source"]=="VIGENTE"
      and out["BEFORE_ROLLBACK"]["registry"]=="VIGENTE"
      and out["BEFORE_ROLLBACK"]["ticket"]=="CONSUMED"
      and out["AFTER_ROLLBACK"]["curator_rows"]==0 and out["AFTER_ROLLBACK"]["rule_rows"]==0)
    check("POSITIVE_"+variant,ok,"Curator ACCEPT -> unchanged LF apply APPLIED and L14 readback READY; rollback",out)
    SCENARIOS.append({"scenario":variant,"result":"PASS","curator_status":"REAL_EN_SANDBOX","production_curator":"NO_PROBADO","verdict":out["CURATOR"]["verdict"]})

def run_saly(claim):
    q=(
      "SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('saly','SALY-L14-NEW','MOTOR_DISPONIBLE')::text;\n"
      "SELECT 'CURATOR|'||rule_quality_l13.l23_curator_evaluate_v1('saly','SALY-L14-NEW')::text;\n"
      "SELECT 'APPLIED|'||rule_quality_l13.quality_apply_envelope_v2('saly','SALY-L14-NEW')::text;")
    out=sql("BEGIN;\n"+saly(claim,q)+"\nSELECT 'PRE|'||jsonb_build_object("
      "'source',(SELECT vigente FROM rule_quality_l13.saly_source_synthetic WHERE codigo='SALY-L14-NEW'),"
      "'verdict',(SELECT verdict FROM rule_quality_l13.l23_curator_verdicts WHERE project_code='saly' AND rule_code='SALY-L14-NEW'))::text;\n"
      "ROLLBACK;\nSELECT 'AFTER|'||jsonb_build_object("
      "'source',(SELECT vigente FROM rule_quality_l13.saly_source_synthetic WHERE codigo='SALY-L14-NEW'),"
      "'quality',(SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='saly' AND rule_code='SALY-L14-NEW'),"
      "'verdict',(SELECT count(*) FROM rule_quality_l13.l23_curator_verdicts WHERE project_code='saly'))::text;")
    check("POSITIVE_C_SALY_NEW",
      out["CURATOR"]["verdict"]=="ACEPTAR"
      and out["APPLIED"]["status"]=="READY" and out["APPLIED"]["gate"]["fixture_only"] is True
      and out["PRE"]=={"source":True,"verdict":"ACEPTAR"}
      and out["AFTER"]=={"source":False,"quality":0,"verdict":0},
      "Curator ACCEPT -> SALY fixture READY, rollback; no native SALY gate",out)
    SCENARIOS.append({"scenario":"C_SALY_NEW","result":"PASS","curator_status":"REAL_EN_SANDBOX","production_curator":"NO_PROBADO","verdict":out["CURATOR"]["verdict"]})

def saly_prep(claim,tail=""):
    return "BEGIN;\n"+saly(claim,"SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('saly','SALY-L14-NEW','MOTOR_DISPONIBLE')::text;\n"+tail)+"\nROLLBACK;"

def negative_missing(claim):
    negative("N1_MISSING_VERDICT_BLOCKS_WRAPPER",saly_prep(claim,
      "SELECT rule_quality_l13.quality_apply_envelope_v2('saly','SALY-L14-NEW');"),
      "BLOCK_L23_CURATOR_NOT_ACCEPTED")
    read=sql("SELECT 'AFTER|'||jsonb_build_object("
      "'active',(SELECT vigente FROM rule_quality_l13.saly_source_synthetic WHERE codigo='SALY-L14-NEW'),"
      "'tickets',(SELECT count(*) FROM rule_quality_l13.activation_tickets WHERE project_code='saly'),"
      "'verdicts',(SELECT count(*) FROM rule_quality_l13.l23_curator_verdicts WHERE project_code='saly'))::text;")["AFTER"]
    check("N1_NO_SIDE_EFFECT",read=={"active":False,"tickets":0,"verdicts":0},"no bypass and no side effects",read)

def negative_duplicate(lf_claim):
    setup_sql="""INSERT INTO lf_ops.reglas(id,codigo,descripcion,estado,categoria,owner_name,valor_config)
      SELECT 991001,'L23-EXACT-DUP',descripcion,'CANDIDATO',categoria,'LF_GOVERNANCE',valor_config
      FROM lf_ops.reglas WHERE codigo='RULE-DEPENDENCY-001';"""
    q="SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('lf','L23-EXACT-DUP','IDENTIDAD_SEGURIDAD')::text;\nSELECT 'CURATOR|'||rule_quality_l13.l23_curator_evaluate_v1('lf','L23-EXACT-DUP')::text;"
    out=sql("BEGIN;\n"+setup_sql+"\n"+owner(lf_claim,q)+"\nROLLBACK;")
    check("N2_EXACT_DUPLICATE",out["CURATOR"]["verdict"]=="DEVOLVER_CON_MOTIVO" and
      out["CURATOR"]["reason_code"]=="EXACT_DUPLICATE_VIGENTE",
      "duplicate VIGENTE must be DEVOLVER",out["CURATOR"])

def negative_conflict(lf_claim):
    setup_sql="""INSERT INTO rule_quality_l13.rules(project_code,rule_code,family_code,category_raw,
     entity_code,definition_text,config,state,reviewed_at,next_review_at,effective_from)
      VALUES('lf','L23-CONFLICT-BASE','IDENTIDAD_SEGURIDAD','SECURITY',
       'GENERAL','Existing PG18 security rate limit','{"l23_limit":2}'::jsonb,
       'VIGENTE',clock_timestamp(),clock_timestamp()+interval '90 days',clock_timestamp());
     INSERT INTO lf_ops.reglas(id,codigo,descripcion,estado,categoria,owner_name,valor_config)
      VALUES(991002,'L23-CONFLICT-CAND','Candidate PG18 divergent limit','CANDIDATO','SECURITY',
       'LF_GOVERNANCE','{"l23_limit":5}'::jsonb);"""
    q="SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('lf','L23-CONFLICT-CAND','IDENTIDAD_SEGURIDAD')::text;\nSELECT 'CURATOR|'||rule_quality_l13.l23_curator_evaluate_v1('lf','L23-CONFLICT-CAND')::text;"
    out=sql("BEGIN;\n"+setup_sql+"\n"+owner(lf_claim,q)+"\nROLLBACK;")
    check("N3_CONFLICTING_CONFIG",out["CURATOR"]["verdict"]=="ESCALAR_A_HUMANO" and
      out["CURATOR"]["reason_code"]=="CONFIG_VALUE_CONFLICT",
      "same project/family/category/entity + conflicting JSON key => human review",out["CURATOR"])

def negative_family(lf_claim):
    stmt="SELECT rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','FAMILIA_INEXISTENTE');"
    negative("N4_FAMILY_NOT_FOUND",l17.exec_as.__name__ and
      ("BEGIN;\n"+owner(lf_claim,stmt)+"\nROLLBACK;"),"BLOCK_QUALITY_FAMILY_PROJECT_MISMATCH")

def negative_wrong_owner(lf_claim):
    stmt="UPDATE rule_quality_l13.families SET owner_profile_code='ANOTHER_OWNER_PROFILE' WHERE project_code='lf' AND family_code='IDENTIDAD_SEGURIDAD';\n"
    q=("SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD')::text;\n"
       "SELECT 'CURATOR|'||rule_quality_l13.l23_curator_evaluate_v1('lf','LF-L14-NEW-OK')::text;")
    out=sql("BEGIN;\n"+stmt+owner(lf_claim,q)+"\nROLLBACK;")
    check("N5_WRONG_FAMILY_OWNER",out["CURATOR"]["verdict"]=="DEVOLVER_CON_MOTIVO" and
      out["CURATOR"]["reason_code"]=="FAMILY_OWNER_PROFILE_MISMATCH",
      "project owner and family owner mismatch => return",out["CURATOR"])

def negative_tampered(lf_claim):
    # A privileged PG18 test-fixture actor tampers with the sealed row;
    # ordinary application roles lack DML, tested separately.
    script=("BEGIN;\n"+
      owner(lf_claim,"SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD')::text;\n"+
                     "SELECT 'C|'||rule_quality_l13.l23_curator_evaluate_v1('lf','LF-L14-NEW-OK')::text;")+
      "\nUPDATE rule_quality_l13.l23_curator_verdicts SET reason_text='attacker modified reason'"
      " WHERE project_code='lf' AND rule_code='LF-L14-NEW-OK';\n"+
      owner(lf_claim,"SELECT rule_quality_l13.quality_apply_envelope_v2('lf','LF-L14-NEW-OK','PROM-TEST','EXEC-OWNER-L11B-001');")+
      "\nROLLBACK;")
    negative("N6_TAMPERED_VERDICT_SEAL",script,"BLOCK_L23_CURATOR_SEAL_INVALID")

def negative_no_grant(lf_claim):
    negative("N7_DIRECT_VERDICT_DML_DENIED",
      "BEGIN;\n"+owner(lf_claim,
       "UPDATE rule_quality_l13.l23_curator_verdicts SET verdict='ACEPTAR' WHERE project_code='lf';")+
      "\nROLLBACK;","permission denied for table l23_curator_verdicts")

def negative_stale(lf_claim):
    # Create accepted verdict in transaction then modify source candidate content (no active edit).
    q="SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('lf','LF-L14-NEW-OK','IDENTIDAD_SEGURIDAD')::text;\nSELECT 'C|'||rule_quality_l13.l23_curator_evaluate_v1('lf','LF-L14-NEW-OK')::text;"
    script=("BEGIN;\n"+owner(lf_claim,q)+
     "\nUPDATE lf_ops.reglas SET valor_config=jsonb_build_object('l23_after','changed') "
     "WHERE codigo='LF-L14-NEW-OK';\n"+
     owner(lf_claim,"SELECT rule_quality_l13.quality_apply_envelope_v2('lf','LF-L14-NEW-OK','PROM-TEST','EXEC-OWNER-L11B-001');")+
     "\nROLLBACK;")
    negative("N8_ACCEPTED_VERDICT_STALE_CANDIDATE",script,"BLOCK_L23_CURATOR_SNAPSHOT_STALE")

def main():
    setup()
    before=l14.l11b.md5s()
    check("MD5_FROZEN_BEFORE",before==EXPECTED,EXPECTED,before)
    lf=l17.token("lf","lf-sub-owner-001","lf_owner_role")
    sy=l17.token("saly","saly-sub-owner-001","saly_owner_role")
    run_lf("A_NEW",lf)
    run_lf("B_CORRECTED",lf)
    run_saly(sy)
    negative_missing(sy)
    negative_duplicate(lf)
    negative_conflict(lf)
    negative_family(lf)
    negative_wrong_owner(lf)
    negative_tampered(lf)
    negative_no_grant(lf)
    negative_stale(lf)
    after=l14.l11b.md5s()
    check("MD5_FROZEN_AFTER",after==before==EXPECTED,EXPECTED,after)
    report={"lote":23,"mode":"PG18_DISPOSABLE","global_status":"NO_GO_UNVERIFIED",
      "curator_engine":"DETERMINISTIC_SQL_SANDBOX_NOT_NATIVE_CURATOR",
      "curator_model_identity":"GPT6_SAME_MODEL_NOT_INDEPENDENT",
      "supabase_auth_real":False,"real_step70":False,"production_write_count":0,
      "scenarios":SCENARIOS,"cases":CASES,"case_count":len(CASES),
      "gate_md5_before":before,"gate_md5_after":after,
      "production_curator_status":"NO_PROBADO"}
    target=HERE/"lote23_runtime.json"
    target.write_text(json.dumps(report,ensure_ascii=False,sort_keys=True,indent=2,default=str)+"\n",encoding="utf-8")
    digest=hashlib.sha256(target.read_bytes()).hexdigest()
    print("L23_RAW_JSON_SHA256 "+digest,flush=True)
    print("L23_SANDBOX_PASS "+str(len(CASES))+" cases, 3 positive scenarios, 8 negative test cases incl no-write, 4 gates unchanged",flush=True)

if __name__=="__main__":main()
