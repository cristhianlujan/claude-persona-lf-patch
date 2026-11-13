#!/usr/bin/env python3
"""L29: ONE reproducible E2E PG18 runner for NEW / MODIFY_CANDIDATE /
CORRECT_VIGENTE plus privilege, separation-of-duties, evidence, replay and rollback.
Native ACT-0001/IG/Step70/production still NOT EXECUTED; HMAC fixture only.
"""
import hashlib,json
from pathlib import Path
import test_pg18_lote26_integrated_curator_closure as l26
import test_pg18_lote20_source_sync as l20
import test_pg18_lote18_integrated_cycle as l18
import test_pg18_lote17_actor_identity_adapter as l17
import test_pg18_lote14_quality_wrapper as l14

HERE=Path(__file__).resolve().parents[1]/"rule_quality_lifecycle_v1"
EXPECTED=l14.EXPECTED_MD5
CODE=l14.l11b.RULE
RUN=l14.l11b.OWNER_RUN
CASES=[]
SCENARIOS=[]

def lit(x):return l17.lit(x)
def sql(q,fail=False):return l17.sql(q,fail=fail)
def check(name,truth,expected,observed):
 if not truth:raise AssertionError("L29_FAIL_"+name+" EXPECTED "+str(expected)+" OBSERVED "+json.dumps(observed,sort_keys=True,ensure_ascii=False,default=str)[:6000])
 CASES.append({"id":name,"status":"PASS","expected":expected,"observed":observed})
 print("PASS_L29_"+name+" "+json.dumps(observed,sort_keys=True,ensure_ascii=False,default=str),flush=True)
def negative(name,q,reason):
 out=sql(q,True)
 check(name,out["exit_code"]!=0 and reason in out["stderr"],reason,
       {"exit":out["exit_code"],"stderr_last":out["stderr"].splitlines()[-4:]})
def owner(token,q):return l18.owner_session(token,q)
def reader(token,q):
 return ("SET SESSION AUTHORIZATION l17_authenticator;\nSET LOCAL ROLE lf_reader_role;\n"+
  "SELECT set_config('request.jwt.claims',"+lit(json.dumps(token,sort_keys=True))+",true);\n"+
  q+"\nRESET SESSION AUTHORIZATION;\n")
def as_role(role,token,q):
 return ("SET SESSION AUTHORIZATION l17_authenticator;\nSET LOCAL ROLE "+role+";\n"+
  "SELECT set_config('request.jwt.claims',"+lit(json.dumps(token,sort_keys=True))+",true);\n"+
  q+"\nRESET SESSION AUTHORIZATION;\n")
def evidence(label):
 return {"source_ref":"L29-PG18-"+label,"rationale":"test-only request bound to candidate snapshot; no product approval"}
def intake(token,request_id,kind,ev,attempts=2):
 args=",".join([lit(request_id),lit("lf"),lit(CODE),lit(kind),lit(json.dumps(ev,sort_keys=True))+"::jsonb"])
 fn="rule_quality_l13.l29_submit_request_v1("+args+")::text"
 statements="SELECT 'REQUEST|'||"+fn+";\n"
 if attempts>1:statements+="SELECT 'REQUEST_REPLAY|'||"+fn+";\n"
 return reader(token,statements)
def setup(db,nonconflicting):
 l26.bootstrap(db,nonconflicting_a_seed=nonconflicting)
 sql((HERE/"17_l29_e2e_request_sod_retry_pg18.sql").read_text(encoding="utf-8"))
 check("BOOTSTRAP_"+db,True,"clean L26 PG18 with additive L29 intake guard",{ "db":db,"nonconflicting":nonconflicting,"native_router":False})
def prelude(owner_token,reader_token,kind,scenario):
 corrected=kind=="CORRECT_VIGENTE"
 p=l26.prelude_lf(owner_token,corrected)
 fixture=l14.l11b.setup("POSITIVE")+"\n"
 if not p.startswith(fixture):raise AssertionError("L29_FIXTURE_BOUNDARY_NOT_FOUND")
 extra=""
 if kind=="MODIFY_CANDIDATE":
  extra=("SELECT 'CANDIDATE_PREIMAGE|'||encode(extensions.digest(convert_to(to_jsonb(s)::text,'UTF8'),'sha256'),'hex') "
        "FROM lf_ops.reglas s WHERE codigo="+lit(CODE)+";\n"
   "UPDATE lf_ops.reglas SET valor_config=jsonb_set(coalesce(valor_config,'{}'::jsonb),"
   "'{l29_revision}','\"2\"'::jsonb,true) WHERE codigo="+lit(CODE)+" AND estado='CANDIDATO';\n"
   "SELECT 'CANDIDATE_POSTIMAGE|'||encode(extensions.digest(convert_to(to_jsonb(s)::text,'UTF8'),'sha256'),'hex') "
   "FROM lf_ops.reglas s WHERE codigo="+lit(CODE)+";\n")
 extra+=intake(reader_token,"REQ-L29-"+scenario,kind,evidence(scenario))
 return fixture+extra+p[len(fixture):]
def promote(token,promotion="PROM-TEST"):
 return owner(token,"SELECT 'PROMOTION_RECEIPT|'||rule_quality_l13.l29_promotion_once_v1('lf',"+
  lit(CODE)+","+lit(promotion)+","+lit(RUN)+")::text;")
def close(token,promotion="PROM-TEST"):
 return owner(token,"SELECT 'CLOSE|'||rule_quality_l13.l29_close_once_v1('lf',"+
  lit(CODE)+","+lit(promotion)+","+lit(RUN)+")::text;")
def replay(token):
 return owner(token,
   "SELECT 'PROMOTION_REPLAY|'||rule_quality_l13.l29_promotion_once_v1('lf',"+
    lit(CODE)+",'PROM-TEST',"+lit(RUN)+")::text;\n"
   "SELECT 'CLOSURE_REPLAY|'||rule_quality_l13.l29_close_once_v1('lf',"+
    lit(CODE)+",'PROM-TEST',"+lit(RUN)+")::text;")
def request_readback():
 return ("SELECT 'INTAKE_READBACK|'||jsonb_build_object("
  "'request_count',(SELECT count(*) FROM rule_quality_l13.l29_request_evidence WHERE rule_code="+lit(CODE)+"),"
  "'creator',(SELECT creator_actor FROM rule_quality_l13.l29_request_evidence WHERE rule_code="+lit(CODE)+"),"
  "'kind',(SELECT request_kind FROM rule_quality_l13.l29_request_evidence WHERE rule_code="+lit(CODE)+"),"
  "'owner_intents',(SELECT count(*) FROM rule_quality_l13.l18_owner_intents WHERE rule_code="+lit(CODE)+"),"
  "'promotion',(SELECT count(*) FROM rule_quality_l13.l26_promotion_receipts WHERE rule_code="+lit(CODE)+"),"
  "'closure',(SELECT count(*) FROM rule_quality_l13.l24_closure_receipts WHERE rule_code="+lit(CODE)+"))::text;\n")
def after_rollback():
 return ("SELECT 'AFTER_L29_ROLLBACK|'||jsonb_build_object("
  "'request',(SELECT count(*) FROM rule_quality_l13.l29_request_evidence),"
  "'curator',(SELECT count(*) FROM rule_quality_l13.l23_curator_verdicts),"
  "'owner_intent',(SELECT count(*) FROM rule_quality_l13.l18_owner_intents),"
  "'promotion',(SELECT count(*) FROM rule_quality_l13.l26_promotion_receipts),"
  "'closure',(SELECT count(*) FROM rule_quality_l13.l24_closure_receipts),"
  "'candidate',(SELECT count(*) FROM lf_ops.reglas WHERE codigo="+lit(CODE)+"))::text;")
def positive(label,kind,owner_jwt,reader_jwt):
 p=prelude(owner_jwt,reader_jwt,kind,label)
 corrected=(kind=="CORRECT_VIGENTE")
 sync=("" if not corrected else owner(owner_jwt,
  "SELECT 'SYNC_PREVIOUS|'||rule_quality_l13.l20_owner_decide_and_sync_v1("
  "'lf','RULE-DEPENDENCY-001','SUPERSEDE',"
  """'{"source_ref":"L29-CORRECT","rationale":"owner explicit successor fixture"}'::jsonb,"""+
  "clock_timestamp(),"+lit(CODE)+")::text;"))
 script=("BEGIN;\n"+p+
  owner(owner_jwt,"SELECT 'READBACK_READY|'||rule_quality_l13.l20_target_readback_v1('lf',"+lit(CODE)+")::text;")+
  sync+promote(owner_jwt)+close(owner_jwt)+replay(owner_jwt)+
  l26.command_verify("lf",CODE,owner_jwt,"PROM-TEST")+
  l26.measure_sql("lf",CODE,"PROM-TEST",owner_jwt,corrected)+
  request_readback()+"\nROLLBACK;\n"+after_rollback())
 out=sql(script)
 board=l26.board_measured("lf",out)
 a=out["AFTER_L29_ROLLBACK"]
 ok=(out["REQUEST"]["status"]=="REQUEST_RECEIVED_PG18"
  and out["REQUEST_REPLAY"]["status"]=="ALREADY_REQUESTED_NOOP"
  and out["INTAKE_READBACK"]["request_count"]==1
  and out["INTAKE_READBACK"]["owner_intents"]==1
  and out["INTAKE_READBACK"]["creator"]=="lf_reader_role"
  and out["INTAKE_READBACK"]["kind"]==kind
  and out["CURATOR"]["verdict"]=="ACEPTAR"
  and out["WRAP"]["gate"]["status"]=="APPLIED"
  and out["WRAP"]["status"]=="READY"
  and out["READBACK_READY"]["target_divergence"]==0
  and out["READBACK_READY"]["registry"]==out["READBACK_READY"]["source"]=="VIGENTE"
  and out["PROMOTION_RECEIPT"]["status"]=="PROMOTION_RECEIPT_RECORDED"
  and out["CLOSE"]["status"]=="INTEGRATED_CLOSED_VERIFIED_PG18"
  and out["PROMOTION_REPLAY"]["status"]=="ALREADY_PROMOTED_VERIFIED_NOOP"
  and out["CLOSURE_REPLAY"]["status"]=="ALREADY_CLOSED_VERIFIED_NOOP"
  and out["VERIFY_CLOSURE"]["status"]=="VERIFIED_CLOSURE_HASH"
  and out["INTAKE_READBACK"]["promotion"]==out["INTAKE_READBACK"]["closure"]==1
  and out["MEASURED"]["promotion_receipts"]==out["MEASURED"]["closure_receipts"]==1
  and a=={"request":0,"curator":0,"owner_intent":0,"promotion":0,"closure":0,"candidate":0}
  and len(board)==12)
 if corrected:ok=ok and out["SYNC_PREVIOUS"]["status"]=="SYNCED_ATOMIC_PG18" and out["MEASURED"]["previous_state"]==out["MEASURED"]["previous_source"]=="SUCEDIDA"
 if kind=="MODIFY_CANDIDATE":
  ok=ok and out["CANDIDATE_PREIMAGE"]!=out["CANDIDATE_POSTIMAGE"]
 check("POS_"+label,ok,"creator(request)+distinct owner+Curator+unchanged gate+VIGENTE+hash closure+idempotent replay+rollback",{
  "kind":kind,"request":out.get("REQUEST"),"request_replay":out.get("REQUEST_REPLAY"),
  "preimage_changed":out.get("CANDIDATE_PREIMAGE")!=out.get("CANDIDATE_POSTIMAGE"),
  "curator":out.get("CURATOR"),"apply":out.get("WRAP",{}).get("gate",{}).get("status"),
  "promotion":out.get("PROMOTION_RECEIPT",{}).get("status"),
  "closure":out.get("CLOSE",{}).get("status"),
  "promote_replay":out.get("PROMOTION_REPLAY",{}).get("status"),
  "close_replay":out.get("CLOSURE_REPLAY",{}).get("status"),"intake":out.get("INTAKE_READBACK"),"after":a})
 SCENARIOS.append({"scenario":label,"kind":kind,"status":"PASS","board":board,
  "request":out["REQUEST"],"creator":"lf_reader_role","owner":"lf_owner_role",
  "candidate_revision_preimage":out.get("CANDIDATE_PREIMAGE"),
  "candidate_revision_postimage":out.get("CANDIDATE_POSTIMAGE"),
  "curator":out["CURATOR"],"promoted":out["PROMOTION_RECEIPT"],
  "closed":out["CLOSE"],"replays":{"request":out["REQUEST_REPLAY"],"promotion":out["PROMOTION_REPLAY"],"closure":out["CLOSURE_REPLAY"]},
  "rollback":a,"measured":out["MEASURED"],
  "transaction":"ONE_BEGIN_ONE_ROLLBACK","native_authority":False})
def negatives(owner_jwt,reader_jwt):
 fixture=l14.l11b.setup("POSITIVE")
 negative("NO_EVIDENCE", "BEGIN;\n"+fixture+"\n"+
  intake(reader_jwt,"REQ-L29-EMPTY","NEW",{},attempts=1)+"\nROLLBACK;",
  "BLOCK_L29_EVIDENCE_REQUIRED")
 negative("NO_PERMISSION_APPROVE", "BEGIN;\n"+fixture+"\n"+
  as_role("lf_reader_role",reader_jwt,
   "SELECT rule_quality_l13.quality_prepare_new_v2('lf',"+lit(CODE)+",'IDENTIDAD_SEGURIDAD');")+
  "\nROLLBACK;","BLOCK_L17_NOT_PROJECT_OWNER")
 superjwt=l17.token("lf","lf-sub-super-001","lf_super_role")
 negative("SUPER_ADMIN_DENIED","BEGIN;\n"+fixture+"\n"+
  as_role("lf_super_role",superjwt,
   "SELECT rule_quality_l13.quality_prepare_new_v2('lf',"+lit(CODE)+",'IDENTIDAD_SEGURIDAD');")+
  "\nROLLBACK;","BLOCK_SUPER_ADMIN_APPROVAL")
 negative("OWNER_CANNOT_CREATE_REQUEST","BEGIN;\n"+fixture+"\n"+
  as_role("lf_owner_role",owner_jwt,
   "SELECT rule_quality_l13.l29_submit_request_v1('REQ-SELF','lf',"+lit(CODE)+
    ",'NEW','{\"source_ref\":\"fixture\",\"rationale\":\"self approval\"}'::jsonb);")+
  "\nROLLBACK;","BLOCK_L29_CREATOR_ROLE_NOT_ALLOWED")
 base=l26.prelude_lf(owner_jwt,True)
 head=fixture+"\n"
 if not base.startswith(head):raise AssertionError("negative correction prelude malformed")
 forgery=(
 "INSERT INTO rule_quality_l13.l29_request_evidence(request_id,project_code,rule_code,request_kind,"
 "creator_actor,creator_sub,creator_role,evidence,source_sha256)"
 " SELECT 'REQ-FORGED','lf',codigo,'CORRECT_VIGENTE','lf_owner_role','lf-sub-owner-001',"
 "'lf_owner_role','{\"source_ref\":\"forged fixture\",\"rationale\":\"same actor\"}'::jsonb,"
 "encode(extensions.digest(convert_to(to_jsonb(s)::text,'UTF8'),'sha256'),'hex')"
 " FROM lf_ops.reglas s WHERE codigo="+lit(CODE)+";\n")
 negative("SAME_ACTOR_CREATOR_APPROVER_BLOCKED",
   "BEGIN;\n"+head+forgery+base[len(head):]+"\nROLLBACK;",
   "BLOCK_L29_SAME_ACTOR_CREATOR_APPROVER")
 negative("REQUEST_MISSING_BLOCKS_OWNER","BEGIN;\n"+base+"\nROLLBACK;","BLOCK_L29_REQUEST_REQUIRED")
 bad_evidence1=evidence("CONFLICT")
 bad_evidence2={"source_ref":"L29-PG18-CHANGED","rationale":"different payload with same id"}
 negative("REQUEST_IDEMPOTENCY_CONFLICT","BEGIN;\n"+fixture+"\n"+
   intake(reader_jwt,"REQ-COLLIDE","NEW",bad_evidence1,1)+
   intake(reader_jwt,"REQ-COLLIDE","NEW",bad_evidence2,1)+"\nROLLBACK;",
   "BLOCK_L29_IDEMPOTENCY_KEY_CONFLICT")
 negative("DIRECT_REQUEST_DML_DENIED","BEGIN;\n"+
   as_role("lf_reader_role",reader_jwt,"INSERT INTO rule_quality_l13.l29_request_evidence DEFAULT VALUES;")+
   "\nROLLBACK;","permission denied for table l29_request_evidence")
 # Failure after frozen apply but before close: no partial persistence.
 p=prelude(owner_jwt,reader_jwt,"CORRECT_VIGENTE","FAULT")
 negative("POST_PROMOTION_FAULT_ROLLBACK","BEGIN;\n"+p+promote(owner_jwt)+
  "SELECT rule_quality_l13.l26_injected_fail_between_promotion_and_closure_v1();\nROLLBACK;",
  "L26_INJECTED_AFTER_PROMOTION_BEFORE_CLOSURE")
 rb=sql(after_rollback())["AFTER_L29_ROLLBACK"]
 check("NO_PARTIAL_ROWS_AFTER_FAILURE",rb=={"request":0,"curator":0,"owner_intent":0,"promotion":0,"closure":0,"candidate":0},
  "zero transient rows following injected failure",rb)
def drop_db(name):
 l14.l11b.base.sql("DROP DATABASE IF EXISTS "+name+" WITH (FORCE);",db="postgres")
def main():
 scenarios=[("A_NEW","NEW",True),("B_MODIFIED_CANDIDATE","MODIFY_CANDIDATE",True),
            ("C_CORRECTED_VIGENTE","CORRECT_VIGENTE",False)]
 for i,(name,kind,nonconflicting) in enumerate(scenarios):
  db="lf_3779_l29_e2e_"+str(i)
  setup(db,nonconflicting)
  current=l14.l11b.md5s()
  check("GATE_MD5_BEFORE_"+name,current==EXPECTED,EXPECTED,current)
  owner_jwt=l17.token("lf","lf-sub-owner-001","lf_owner_role")
  reader_jwt=l17.token("lf","lf-sub-reader-001","lf_reader_role")
  positive(name,kind,owner_jwt,reader_jwt)
  if i==2:negatives(owner_jwt,reader_jwt)
  after=l14.l11b.md5s()
  check("GATE_MD5_AFTER_"+name,after==EXPECTED==current,EXPECTED,after)
  drop_db(db)
 real=sum(x["status"]=="REAL_EN_SANDBOX" for sc in SCENARIOS for x in sc["board"])
 synth=sum(x["status"]=="SINTETICO" for sc in SCENARIOS for x in sc["board"])
 none=sum(x["status"]=="NO_PROBADO" for sc in SCENARIOS for x in sc["board"])
 if len(SCENARIOS)!=3 or real+synth+none!=36:raise AssertionError("BOARD_TOTAL_MISSING")
 report={"schema_version":"LF_L29_E2E_SANDBOX_V1","outcome":"SANDBOX_VERIFIED",
  "production":"NO_GO_UNVERIFIED","blockers_closed":0,"blockers_total":14,
  "source_base":"7ef5472865aaf4f86bf8491c8c7bfa82f7492309",
  "scenarios":SCENARIOS,"cases":CASES,"case_count":len(CASES),
  "status_counts":{"REAL_EN_SANDBOX":real,"SINTETICO":synth,"NO_PROBADO":none},
  "stage_coverage":round(real*100/36,2),"baseline_l26_real":21,
  "gates_md5":EXPECTED,"gate_sql_modified":False,
  "same_model_curator":"L23_DETERMINISTIC_SQL_AUTHORED_BY_GPT6_NOT_INDEPENDENT",
  "jwt":"L17_HMAC_SIGNED_FIXTURE_NOT_SUPABASE_AUTH",
  "routing_profile_run_native":False,"ig_native":False,"step70_oidc_native":False,
  "production_writes":0,
  "replay_scope":"REQUEST_PLUS_PROMOTION_AND_CLOSURE_ONCE_PER_LOGICAL_KEY_NOT_NATIVE_RUN",
  "definitions":{"NEW":"new candidate in fixture",
    "MODIFY_CANDIDATE":"existing candidate JSONB revision before owner review; NOT in-place VIGENTE",
    "CORRECT_VIGENTE":"explicit successor link and L20 atomic SUCEDIDA synchronization"}}
 target=HERE/"lote29_e2e_runtime.json"
 target.write_text(json.dumps(report,ensure_ascii=False,sort_keys=True,indent=2,default=str)+"\n",encoding="utf-8")
 print("L29_REPORT_SHA256 "+hashlib.sha256(target.read_bytes()).hexdigest(),flush=True)
 print("L29_RUNNER_COMPLETE "+str(len(CASES))+" cases board="+str(real)+"/36",flush=True)
if __name__=="__main__":main()
