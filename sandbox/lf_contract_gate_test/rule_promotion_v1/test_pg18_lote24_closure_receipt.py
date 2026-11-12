#!/usr/bin/env python3
"""L24 verifiable closure receipt (PG18 only). No native RUN/Step70/Supabase Auth."""
import hashlib,json
from pathlib import Path
import test_pg18_lote20_source_sync as l20
import test_pg18_lote17_actor_identity_adapter as l17
import test_pg18_lote18_integrated_cycle as l18
import test_pg18_lote14_quality_wrapper as l14

ROOT=Path(__file__).resolve().parents[3]
HERE=ROOT/"sandbox/lf_contract_gate_test/rule_quality_lifecycle_v1"
DB="lf_3779_l24_closure_receipt_pg18"
CASES=[];SCENARIOS=[]
EXPECTED=l14.EXPECTED_MD5
CODE=l14.l11b.RULE
PROMO=l14.l11b.PROMO
RUN=l14.l11b.OWNER_RUN
def sql(q,fail=False):return l17.sql(q,fail=fail)
def lit(x):return l17.lit(x)
def owner(jwt,body):return l18.owner_session(jwt,body)
def saly(jwt,body):return l18.saly_session(jwt,body)
def check(id,condition,expected,observed):
 if not condition:raise AssertionError("L24_FAIL_"+id+" EXPECTED="+str(expected)+" OBSERVED="+json.dumps(observed,ensure_ascii=False,sort_keys=True,default=str)[:10000])
 CASES.append({"id":id,"status":"PASS","expected":expected,"observed":observed})
 print("PASS_L24_"+id+" "+json.dumps(observed,ensure_ascii=False,sort_keys=True,default=str),flush=True)
def err(id,script,code):
 out=sql(script,fail=True)
 check(id,code in out["stderr"] and out["exit_code"]!=0,code,{"exit_code":out["exit_code"],"stderr_tail":out["stderr"].splitlines()[-5:]})
def bootstrap():
 l20.DB=DB
 l20.bootstrap()
 sql((HERE/"15_l24_verifiable_closure_pg18.sql").read_text(encoding="utf-8"))
 check("BOOTSTRAP_ALL_LAYERS",True,"L11B/L13/L14/L17/L18/L20/L24 PG18 only",
       {"db":DB,"issuer":"L17_TEST_ISSUER_NOT_SUPABASE","native_profile":False})
def emit(project,code,token,run=None,inject=False):
 who=owner if project=="lf" else saly
 return who(token,"SELECT 'CLOSE|'||rule_quality_l13.l24_emit_closure_v1("
   +lit(project)+","+lit(code)+","+lit("PROM-TEST" if project=="lf" else "SALY-L24-SBX-A")
   +","+("NULL" if run is None else lit(run))
   +", "+("true" if inject else "false")+")::text;")
def verify(project,code,promo,token):
 who=owner if project=="lf" else saly
 return who(token,"SELECT 'VERIFY_CLOSURE|'||rule_quality_l13.l24_verify_closure_v1("
   +lit(project)+","+lit(code)+","+lit(promo)+")::text;")
def receipt_count(project,code):
 return ("SELECT 'RECEIPT_ROWS|'||jsonb_build_object("
  "'n',(SELECT count(*) FROM rule_quality_l13.l24_closure_receipts "
  "WHERE project_code="+lit(project)+" AND rule_code="+lit(code)+"),"
  "'total',(SELECT count(*) FROM rule_quality_l13.l24_closure_receipts))::text;")
def board(project):
 baseline=l18.boards(project,{},"L24")
 for s in baseline:
  if s["stage"]=="Cierre":
   s["status"]="REAL_EN_SANDBOX"
   s["evidence"]="L24 PG18 row INSERT, deterministic SHA256 proposal/readback/receipt, L17 HMAC identity, verification function and append-only trigger; official RUN terminal receiver NOT_PROBADO"
 return baseline
def test_lf(label,jwt,is_correction):
 setup=l20.prelude_lf(jwt,is_correction)
 sync=("" if not is_correction else owner(jwt,
    "SELECT 'PREDECESSOR_SYNC|'||rule_quality_l13.l20_owner_decide_and_sync_v1("
    "'lf','RULE-DEPENDENCY-001','SUPERSEDE',"
    "'{\"source_ref\":\"L24-PREVIOUS-SBX\",\"rationale\":\"owner explicit predecessor sync for corrected rule\"}'::jsonb,"
    "clock_timestamp(),"+lit(CODE)+")::text;"))
 body=emit("lf",CODE,jwt,RUN)+verify("lf",CODE,PROMO,jwt)
 script="BEGIN;\n"+setup+sync+body+receipt_count("lf",CODE)+"\nROLLBACK;\n"+receipt_count("lf",CODE)
 out=sql(script)
 close=out["CLOSE"];verify_out=out["VERIFY_CLOSURE"]
 isgood=(out["VERIFY"]["status"]=="VERIFIED_CAPTURE_BINDING"
    and out["WRAP"]["status"]=="READY"
    and out["WRAP"]["gate"]["status"]=="APPLIED"
    and out["WRAP"]["profile_return"]["status"]=="READY"
    and close["status"]=="CLOSED_VERIFIABLE_SANDBOX"
    and close["final_state"]=="VIGENTE"
    and len(close["receipt_sha256"])==64
    and close["version"]=="sha256:"+close["proposal_sha256"]
    and close["readback_sha256"]!=close["proposal_sha256"]
    and verify_out["status"]=="VERIFIED_CLOSURE_HASH"
    and close["receipt_sha256"]==verify_out["receipt_sha256"]
    and close["official_receiver_attested"] is False
    and out["RECEIPT_ROWS"]=={"n":0,"total":0})
 if is_correction:
  isgood=isgood and out["PREDECESSOR_SYNC"]["status"]=="SYNCED_ATOMIC_PG18" and out["PREDECESSOR_SYNC"]["registry_state"]=="SUCEDIDA"
 check(label+"_CLOSURE_RECEIPT_VERIFIED",isgood,
  "source+L13 VIGENTE, readback READY, hash verified, old SUCEDIDA if corrected, rollback",
  {k:out.get(k) for k in ("WRAP","PREDECESSOR_SYNC","CLOSE","VERIFY_CLOSURE","RECEIPT_ROWS")})
 b=board("lf")
 check(label+"_BOARD_12_STAGES",len(b)==12 and b[-1]["stage"]=="Cierre" and b[-1]["status"]=="REAL_EN_SANDBOX"
   and all(x["status"] in {"REAL_EN_SANDBOX","SINTETICO","NO_PROBADO"} for x in b),
   "mechanical closure real only in PG18, Router/Perfil/RUN synthetic",b)
 SCENARIOS.append({"scenario":label,"status":"PASS","receipt":close,
  "verification":verify_out,"board":b,"synthetic_origin":True})
def test_saly(jwt):
 body=("SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('saly','SALY-L14-NEW','MOTOR_DISPONIBLE')::text;\n"
   "SELECT 'JWT_OWNER|'||rule_quality_l13.l18_owner_intent_v1('saly','SALY-L14-NEW','SALY-L24-SBX-A')::text;\n"
   "SELECT 'WRAP|'||rule_quality_l13.quality_apply_envelope_v2('saly','SALY-L14-NEW')::text;\n")
 out=sql("BEGIN;\n"+saly(jwt,body)+emit("saly","SALY-L14-NEW",jwt)
     +verify("saly","SALY-L14-NEW","SALY-L24-SBX-A",jwt)
     +receipt_count("saly","SALY-L14-NEW")
     +"\nROLLBACK;\n"+receipt_count("saly","SALY-L14-NEW"))
 c=out["CLOSE"];v=out["VERIFY_CLOSURE"]
 ok=(out["PREP"]["status"]=="QUALITY_PREPARED" and out["WRAP"]["status"]=="READY"
  and out["WRAP"]["gate"]["fixture_only"] is True
  and c["status"]=="CLOSED_VERIFIABLE_SANDBOX"
  and c["final_state"]=="VIGENTE" and v["status"]=="VERIFIED_CLOSURE_HASH"
  and v["native_receiver_attested"] is False and c["receipt_sha256"]==v["receipt_sha256"]
  and out["RECEIPT_ROWS"]=={"n":0,"total":0})
 check("C_SALY_NEW_SAME_RECEIPT_API",ok,
  "SALY synthesized L14 READY, same L24 receipt hash verification, no native return",out)
 b=board("saly")
 check("C_SALY_12_STAGE_BOARD",len(b)==12 and b[-1]["status"]=="REAL_EN_SANDBOX"
  and b[3]["status"]=="NO_PROBADO" and b[6]["status"]=="SINTETICO",
  "SALY no real IG or profile return",b)
 SCENARIOS.append({"scenario":"C_SALY_NEW","status":"PASS","receipt":c,
  "verification":v,"board":b,"synthetic_origin":True})
def no_ready_negative(jwt):
 # After a valid LF promotion and matching VIGENTE source/registry, force only
 # the L14 activation readback ticket to ARMED. This isolates missing READY,
 # instead of a candidate EN_REVISION that L20 correctly classifies divergent.
 script=("BEGIN;\n"+l20.prelude_lf(jwt,False)
  +"UPDATE rule_quality_l13.activation_tickets SET status='ARMED' "
    "WHERE project_code='lf' AND rule_code="+lit(CODE)+";\n"
  +emit("lf",CODE,jwt,RUN)+"\nROLLBACK;")
 err("N1_NO_READBACK_READY",script,"BLOCK_L24_READBACK_NOT_READY")
def divergence_negative(jwt):
 # L20 mismatch in PG18 source/registry. The source remains VIGENTE;
 # only registry is temporarily altered. This cannot be promoted to "ready".
 script=("BEGIN;\n"+l20.prelude_lf(jwt,False)
    +"UPDATE rule_quality_l13.rules SET state='CADUCADA' "
      "WHERE project_code='lf' AND rule_code="+lit(CODE)+";\n"
    +emit("lf",CODE,jwt,RUN)+"\nROLLBACK;")
 err("N2_L13_SOURCE_DIVERGENCE",script,"BLOCK_L24_DIVERGENCE_REGISTER_SOURCE")
def seed_signed_real_fixture(jwt):
 # Persist a sandbox-only receipt for mutation/tamper/idempotent security checks.
 out=sql("BEGIN;\n"+l20.prelude_lf(jwt,False)
  +emit("lf",CODE,jwt,RUN)+"\nCOMMIT;\n"+receipt_count("lf",CODE))
 check("NEGATIVE_FIXTURE_PERSISTED_PG18",
  out["CLOSE"]["status"]=="CLOSED_VERIFIABLE_SANDBOX"
  and out["RECEIPT_ROWS"]=={"n":1,"total":1},
  "1 real PG18 closure receipt for attack tests, never live",out["RECEIPT_ROWS"])
 return out["CLOSE"]
def negatives(jwt,superjwt,salyjwt,stored):
 query="SELECT rule_quality_l13.l24_emit_closure_v1('lf',"+lit(CODE)+",'PROM-TEST',"+lit(RUN)+");"
 bad=dict(jwt)
 bad["test_signature"]="f"*64
 bad_stmt="SELECT rule_quality_l13.l24_verify_closure_v1('lf',"+lit(CODE)+",'PROM-TEST');"
 err("N3_BAD_JWT_SIGNATURE",
  "BEGIN;\nSET SESSION AUTHORIZATION l17_authenticator;\nSET LOCAL ROLE lf_owner_role;\n"
  "SELECT set_config('request.jwt.claims',"+lit(json.dumps(bad,sort_keys=True))+",true);\n"
  +bad_stmt+"\nROLLBACK;","BLOCK_L17_JWT_SIGNATURE_INVALID")
 invalid=l17.exec_as("lf_owner_role",None,bad_stmt,fail=True)
 check("N3B_MISSING_JWT", "BLOCK_L17_JWT_MISSING" in invalid["stderr"],
       "42501 no signed request.jwt.claims",invalid["stderr"].splitlines()[-5:])
 badsuper=l17.exec_as("lf_super_role",superjwt,query,fail=True)
 check("N4_SUPER_ADMIN_CANNOT_CLOSE", "BLOCK_SUPER_ADMIN_APPROVAL" in badsuper["stderr"],
       "L17 forbids signed SUPER_ADMIN closure",badsuper["stderr"].splitlines()[-5:])
 app=l17.exec_as("lf_owner_role",jwt,
     "UPDATE rule_quality_l13.l24_closure_receipts SET receipt_sha256=repeat('e',64);",fail=True)
 check("N5_APP_ROLE_DIRECT_DML_DENIED",
  "permission denied" in app["stderr"],
  "app actor has no UPDATE permission on receipt",app["stderr"].splitlines()[-5:])
 for action in ("UPDATE","DELETE"):
  stmt=("UPDATE rule_quality_l13.l24_closure_receipts SET receipt_sha256=repeat('a',64) "
        "WHERE project_code='lf' AND rule_code="+lit(CODE)+";" if action=="UPDATE"
         else "DELETE FROM rule_quality_l13.l24_closure_receipts WHERE project_code='lf' AND rule_code="+lit(CODE)+";")
  err("N6_APPEND_ONLY_"+action,stmt,"BLOCK_L24_APPEND_ONLY_RECEIPT")
 retried=l17.exec_as("lf_owner_role",jwt,
   "SELECT 'R|'||rule_quality_l13.l24_emit_closure_v1('lf',"+lit(CODE)+",'PROM-TEST',"+lit(RUN)+")::text;")
 cnt=sql(receipt_count("lf",CODE))["RECEIPT_ROWS"]
 check("N7_IDEMPOTENT_DUPLICATE_NOOP",
    retried["R"]["status"]=="ALREADY_CLOSED_NOOP"
    and retried["R"]["rows_written"]==0
    and retried["R"]["receipt_id"]==stored["receipt_id"]
    and cnt=={"n":1,"total":1},"no duplicate receipt and identical receipt id",
    {"retry":retried["R"],"rows":cnt})
 # Force a privileged tamper with session_replication_role=replica in a
 # disposable PG18 transaction, then restore triggers and test verifier.
 # Normal UPDATE and DELETE are already proven to be rejected above.
 tamper=("BEGIN;\nSET LOCAL session_replication_role=replica;\n"
  "UPDATE rule_quality_l13.l24_closure_receipts SET receipt_sha256=repeat('f',64) "
  "WHERE project_code='lf' AND rule_code="+lit(CODE)+";\n"
  "SET LOCAL session_replication_role=origin;\n"
  +verify("lf",CODE,"PROM-TEST",jwt)+"\nROLLBACK;")
 err("N8_HASH_TAMPER_DETECTED",tamper,"BLOCK_L24_HASH_OR_RECEIPT_TAMPER")
 good=l17.exec_as("lf_owner_role",jwt,"SELECT 'R|'||rule_quality_l13.l24_verify_closure_v1('lf',"+lit(CODE)+",'PROM-TEST')::text;")
 check("N8B_TAMPER_ROLLBACK_RESTORES",good["R"]["status"]=="VERIFIED_CLOSURE_HASH",
   "original persisted receipt remains valid after forensic test rolled back",good["R"])
 # Use a previously unused SALY candidate and trigger test-only fault AFTER
 # INSERT. Entire statement transaction must roll back, including L13.
 startup=("SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('saly','SALY-L14-NEW','MOTOR_DISPONIBLE')::text;\n"
    "SELECT 'JWT_OWNER|'||rule_quality_l13.l18_owner_intent_v1('saly','SALY-L14-NEW','SALY-L24-SBX-A')::text;\n"
    "SELECT 'WRAP|'||rule_quality_l13.quality_apply_envelope_v2('saly','SALY-L14-NEW')::text;\n")
 fault=("BEGIN;\n"+saly(salyjwt,startup)
   +emit("saly","SALY-L14-NEW",salyjwt,None,True)+"\nROLLBACK;")
 err("N9_FAIL_MIDWAY_ROLLBACK",fault,"L24_INJECTED_AFTER_INSERT_ROLLBACK_ALL")
 post=sql("SELECT 'POST|'||jsonb_build_object("
   "'receipts',(SELECT count(*) FROM rule_quality_l13.l24_closure_receipts),"
   "'saly_quality',(SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='saly' AND rule_code='SALY-L14-NEW'),"
   "'saly_active',(SELECT vigente FROM rule_quality_l13.saly_source_synthetic WHERE codigo='SALY-L14-NEW'),"
   "'saly_approvals',(SELECT count(*) FROM rule_quality_l13.l18_owner_intents WHERE project_code='saly'))::text;")["POST"]
 check("N9B_ATOMIC_POST_FAILURE_READBACK",
   post=={"receipts":1,"saly_quality":0,"saly_active":False,"saly_approvals":0},
   "no partial receipt; no SALY activation or owner intent, one LF fixture unchanged",post)
def main():
 bootstrap()
 before=l14.l11b.md5s()
 check("GATES_MD5_BEFORE",before==EXPECTED,EXPECTED,before)
 lf=l17.token("lf","lf-sub-owner-001","lf_owner_role")
 su=l17.token("lf","lf-sub-super-001","lf_super_role")
 sy=l17.token("saly","saly-sub-owner-001","saly_owner_role")
 test_lf("A_LF_NEW",lf,False)
 test_lf("B_LF_CORRECTED",lf,True)
 test_saly(sy)
 no_ready_negative(lf)
 divergence_negative(lf)
 stored=seed_signed_real_fixture(lf)
 negatives(lf,su,sy,stored)
 after=l14.l11b.md5s()
 check("GATES_MD5_AFTER",before==after==EXPECTED,EXPECTED,after)
 report={"schema_version":"LF_LOTE24_VERIFIABLE_CLOSURE_PG18_V1",
 "status":"SANDBOX_VERIFIED","production":"NO_GO_UNVERIFIED",
 "source_commit":"L22_48f1e316","cases":CASES,"case_count":len(CASES),
 "scenarios":SCENARIOS,"gate_md5_before":before,"gate_md5_after":after,
 "new_receipt_count_test_fixture":1,
 "native_supabase_auth":False,"native_step70":False,"native_receiver":False,
 "independent_judge":False,"identity":"L17_HMAC_TEST_JWT",
 "source_evidence":"MECHANICAL_ONLY_SYNTHETIC_PROVENANCE_NOT_E2E",
 "live_supabase_writes":0,"frozen_gate_edits":0}
 path=HERE/"lote24_runtime.json"
 path.write_text(json.dumps(report,ensure_ascii=False,sort_keys=True,indent=2,default=str)+"\n",encoding="utf-8")
 print("RAW_L24_REPORT "+json.dumps(report,ensure_ascii=False,sort_keys=True,default=str),flush=True)
 print("RAW_L24_REPORT_SHA256 "+hashlib.sha256(path.read_bytes()).hexdigest(),flush=True)
 print("L24_VERIFIED_CLOSURE_COMPLETE cases="+str(len(CASES))+" scenarios=3 frozen_md5=true",flush=True)
if __name__=="__main__":main()
