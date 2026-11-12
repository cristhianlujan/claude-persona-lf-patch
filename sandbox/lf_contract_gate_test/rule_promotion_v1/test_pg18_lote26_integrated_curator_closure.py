#!/usr/bin/env python3
"""L26: one measured PG18 transaction from signed owner + Curator through L24 closure.
No native Router/RUN, no Supabase writes, no external judge or receiver.
"""
import hashlib,json
from pathlib import Path
import test_pg18_lote20_source_sync as l20
import test_pg18_lote18_integrated_cycle as l18
import test_pg18_lote17_actor_identity_adapter as l17
import test_pg18_lote14_quality_wrapper as l14

HERE=Path(__file__).resolve().parents[1]/"rule_quality_lifecycle_v1"
DB="lf_3779_l26_integrated_pg18"
CODE=l14.l11b.RULE
RUN=l14.l11b.OWNER_RUN
EXPECTED=l14.EXPECTED_MD5
CASES=[];SCENARIOS=[]
STAGES=["Router","Perfil","RUN","IG","Curator","Validator",
 "Retorno perfil","Ejecucion","Promocion","VIGENTE","Readback","Cierre"]
ROLES=["lf_owner_role","lf_super_role","lf_reader_role","lf_no_grant_role",
 "saly_owner_role","saly_super_role","l17_authenticator"]
TABLES=["l23_curator_verdicts","l26_promotion_receipts","l24_closure_receipts"]
def lit(x):return l17.lit(x)
def sql(q,fail=False):return l17.sql(q,fail=fail)
def owner(token,q):return l18.owner_session(token,q)
def saly(token,q):return l18.saly_session(token,q)
def check(id,ok,expected,observed):
 if not ok:
  raise AssertionError("L26_FAIL_"+id+" EXPECTED="+str(expected)+
    " OBSERVED="+json.dumps(observed,sort_keys=True,ensure_ascii=False,default=str)[:8500])
 CASES.append({"id":id,"status":"PASS","expected":expected,"observed":observed})
 print("PASS_L26_"+id+" "+json.dumps(observed,sort_keys=True,ensure_ascii=False,default=str),flush=True)
def fail(id,q,marker):
 r=sql(q,fail=True)
 check(id,marker in r["stderr"] and r["exit_code"]!=0,marker,
   {"exit":r["exit_code"],"last_stderr_lines":r["stderr"].splitlines()[-5:]})
def bootstrap():
 l20.DB=DB
 l20.bootstrap()
 sql((HERE/"15_l23_curator_stage_pg18.sql").read_text(encoding="utf-8"))
 sql((HERE/"15_l24_verifiable_closure_pg18.sql").read_text(encoding="utf-8"))
 sql((HERE/"16_l26_curator_to_closure_bridge_pg18.sql").read_text(encoding="utf-8"))
 check("BOOTSTRAP_ALL_LAYERS",True,
  "L13/L14/L17/L18/L20 and exact L23/L24 imported SQL + L26 bridge in clean PG18",{"database":DB})
def prelude_lf(token,corrected=False,with_curator=True):
 p=l20.prelude_lf(token,corrected)
 if with_curator:
  position=p.rfind("SET SESSION AUTHORIZATION l17_authenticator;")
  if position<0 or "SELECT 'WRAP|'" not in p[position:]:
   raise AssertionError("INVALID_L20_PRELUDE_INSERTION")
  v=owner(token,
   "SELECT 'CURATOR|'||rule_quality_l13.l23_curator_evaluate_v1('lf',"+lit(CODE)+")::text;")
  p=p[:position]+v+"\n"+p[position:]
 return p
def command_promote(project,rule,token,promotion,run=None):
 fn=owner if project=="lf" else saly
 return fn(token,"SELECT 'PROMOTION_RECEIPT|'||rule_quality_l13.l26_record_promotion_v1("+
  lit(project)+","+lit(rule)+","+lit(promotion)+","+
  ("NULL" if run is None else lit(run))+")::text;")
def command_close(project,rule,token,promotion,run=None,direct_l24=False):
 fn=owner if project=="lf" else saly
 f="l24_emit_closure_v1" if direct_l24 else "l26_close_integrated_v1"
 return fn(token,"SELECT 'CLOSE|'||rule_quality_l13."+f+"("+
  lit(project)+","+lit(rule)+","+lit(promotion)+","+
  ("NULL" if run is None else lit(run))+")::text;")
def command_verify(project,rule,token,promotion):
 fn=owner if project=="lf" else saly
 return fn(token,"SELECT 'VERIFY_CLOSURE|'||rule_quality_l13.l24_verify_closure_v1("+
  lit(project)+","+lit(rule)+","+lit(promotion)+")::text;")
def measure_sql(project,rule,promotion,corrected=False):
 old=("'previous_state',(SELECT state FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code='RULE-DEPENDENCY-001'),"
 "'previous_source',(SELECT estado FROM lf_ops.reglas WHERE codigo='RULE-DEPENDENCY-001'),") if corrected else ""
 source=("(SELECT estado FROM lf_ops.reglas WHERE codigo="+lit(rule)+")" if project=="lf"
         else "(SELECT CASE WHEN vigente THEN 'VIGENTE' ELSE 'INACTIVE' END FROM rule_quality_l13.saly_source_synthetic WHERE codigo="+lit(rule)+")")
 run=("'run_status',(SELECT status FROM public.lf_operation_execution WHERE execution_id="+lit(RUN)+"),"+
      "'run_fixture_attested',(SELECT manifest->>'system_attestation' FROM public.lf_operation_execution WHERE execution_id="+lit(RUN)+"),"
      if project=="lf" else "'run_status',null,'run_fixture_attested',null,")
 return (
 "SELECT 'MEASURED|'||jsonb_build_object("
 "'project',"+lit(project)+",'rule_code',"+lit(rule)+","
 "'curator',(SELECT verdict FROM rule_quality_l13.l23_curator_verdicts WHERE project_code="+lit(project)+" AND rule_code="+lit(rule)+"),"
 "'curator_seal',(SELECT seal_hmac_sha256 FROM rule_quality_l13.l23_curator_verdicts WHERE project_code="+lit(project)+" AND rule_code="+lit(rule)+"),"
 "'quality',(SELECT state FROM rule_quality_l13.rules WHERE project_code="+lit(project)+" AND rule_code="+lit(rule)+"),"
 "'source',"+source+","
 "'promotion_receipts',(SELECT count(*) FROM rule_quality_l13.l26_promotion_receipts WHERE project_code="+lit(project)+" AND rule_code="+lit(rule)+"),"
 "'closure_receipts',(SELECT count(*) FROM rule_quality_l13.l24_closure_receipts WHERE project_code="+lit(project)+" AND rule_code="+lit(rule)+"),"
 "'ticket',(SELECT status FROM rule_quality_l13.activation_tickets WHERE project_code="+lit(project)+" AND rule_code="+lit(rule)+"),"
 +old+run+
 "'divergences',(SELECT count(*) FROM rule_quality_l13.l20_list_divergences_v1("+lit(project)+") d WHERE d.rule_code="+lit(rule)+")"
 ")::text;")
def after_sql(project,rule):
 src=("(SELECT count(*) FROM lf_ops.reglas WHERE codigo="+lit(rule)+")" if project=="lf"
 else "(SELECT CASE WHEN vigente THEN 1 ELSE 0 END FROM rule_quality_l13.saly_source_synthetic WHERE codigo="+lit(rule)+")")
 return ("SELECT 'AFTER_ROLLBACK|'||jsonb_build_object("
  "'quality',(SELECT count(*) FROM rule_quality_l13.rules WHERE project_code="+lit(project)+" AND rule_code="+lit(rule)+"),"
  "'curator',(SELECT count(*) FROM rule_quality_l13.l23_curator_verdicts WHERE project_code="+lit(project)+" AND rule_code="+lit(rule)+"),"
  "'promotion',(SELECT count(*) FROM rule_quality_l13.l26_promotion_receipts WHERE project_code="+lit(project)+" AND rule_code="+lit(rule)+"),"
  "'closure',(SELECT count(*) FROM rule_quality_l13.l24_closure_receipts WHERE project_code="+lit(project)+" AND rule_code="+lit(rule)+"),"
  "'source_count_or_active',"+src+")::text;")
def board_measured(project,out):
 """Build directly from this SAME transaction's actual RAW data, never L23+L24 math."""
 m=out["MEASURED"];c=out["CURATOR"];p=out["PROMOTION_RECEIPT"];cl=out["CLOSE"];v=out["VERIFY_CLOSURE"]
 wrap=out["WRAP"];source_ok=m["quality"]==m["source"]=="VIGENTE"
 def cell(stage,status,evidence,ok=True):
  if not ok:raise AssertionError("L26_BOARD_UNSUPPORTED_"+stage+" "+str(evidence))
  return {"stage":stage,"status":status,"evidence":evidence}
 board=[]
 if project=="lf":
  board.extend([
   cell("Router","SINTETICO","L11B parent fixture, ACT-0001 no se invoco",m["run_status"]=="COMPLETED"),
   cell("Perfil","SINTETICO","L11B fake owner profile; no ejecucion nativa"),
   cell("RUN","SINTETICO","L11B system_attestation=false, no 11/11 real",m["run_fixture_attested"]=="false"),
   cell("IG","SINTETICO","L11B stub + IG gate status "+out["IG"]["status"],"IG" in out),
  ])
 else:
  board.extend([
   cell("Router","NO_PROBADO","No router SALY invocado"),
   cell("Perfil","NO_PROBADO","No perfil SALY nativo"),
   cell("RUN","NO_PROBADO","No RUN SALY nativo"),
   cell("IG","NO_PROBADO","No IG nativo SALY"),
  ])
 board.append(cell("Curator","REAL_EN_SANDBOX",
  "Misma transaccion: L23 ACEPTAR, sello HMAC "+m["curator_seal"][:16],
  c["verdict"]=="ACEPTAR" and c["gate_precondition"] is True and m["curator"]=="ACEPTAR"))
 if project=="lf":
  board.append(cell("Validator","REAL_EN_SANDBOX",
   "L7 exact capture VERIFY="+out["VERIFY"]["status"]+" e IG="+out["IG"]["status"],
   out["VERIFY"]["status"]=="VERIFIED_CAPTURE_BINDING" and out["IG"]["status"]=="READY_FOR_PROFILE_APPROVAL"))
  board.append(cell("Retorno perfil","REAL_EN_SANDBOX",
   "Gate LF profile_return READY from frozen function",
   wrap["profile_return"]["status"]=="READY" and wrap["profile_return"]["readback_verified"] is True))
  board.append(cell("Ejecucion","SINTETICO","L11B owner RUN fixture with system_attestation=false"))
  board.append(cell("Promocion","REAL_EN_SANDBOX",
    "L14 SQL gate LF APPLIED + L26 promotion receipt "+p["receipt_sha256"][:16],
    wrap["gate"]["status"]=="APPLIED" and p["status"]=="PROMOTION_RECEIPT_RECORDED" and m["promotion_receipts"]==1))
 else:
  board.append(cell("Validator","REAL_EN_SANDBOX",
   "L13 familia preparada + L17 signed HMAC + L23 guard",
   out["PREP"]["status"]=="QUALITY_PREPARED"))
  board.append(cell("Retorno perfil","SINTETICO","L14 SALY fixture READY (no transporte real)",
    wrap["profile_return"]["status"]=="READY" and wrap["profile_return"].get("sandbox_fixture") is True))
  board.append(cell("Ejecucion","REAL_EN_SANDBOX","SQL SALY L14 adapter actually ran, not product execution",
    wrap["status"]=="READY"))
  board.append(cell("Promocion","REAL_EN_SANDBOX",
   "SALY synthetic L14 SQL applied + L26 separate promotion receipt "+p["receipt_sha256"][:16],
   wrap["gate"]["fixture_only"] is True and p["status"]=="PROMOTION_RECEIPT_RECORDED" and m["promotion_receipts"]==1))
 board.append(cell("VIGENTE","REAL_EN_SANDBOX","L13/source source="+m["source"]+" registry="+m["quality"],
   source_ok and m["ticket"]=="CONSUMED"))
 board.append(cell("Readback","REAL_EN_SANDBOX",
  "L20 detector target=0, L26 promotion record READY",
  m["divergences"]==0 and p["readback_status"]=="READY"))
 board.append(cell("Cierre","REAL_EN_SANDBOX",
  "L26 closure insert + L24 VERIFY_CLOSURE_HASH="+v["status"],
  cl["status"]=="INTEGRATED_CLOSED_VERIFIED_PG18" and v["status"]=="VERIFIED_CLOSURE_HASH"
  and m["closure_receipts"]==1 and cl["production_attested"] is False))
 if [x["stage"] for x in board]!=STAGES:raise AssertionError("STAGE_ORDER_INVALID")
 return board
def positive_lf(label,token,corrected):
 p=prelude_lf(token,corrected)
 sync="" if not corrected else owner(token,
  "SELECT 'SYNC_PREVIOUS|'||rule_quality_l13.l20_owner_decide_and_sync_v1("
  "'lf','RULE-DEPENDENCY-001','SUPERSEDE',"
  """'{"source_ref":"L26-B-INTEGRATED","rationale":"owner explicitly approves predecessor sync"}'::jsonb,"""+
  "clock_timestamp(),"+lit(CODE)+")::text;")
 pre=(owner(token,"SELECT 'READBACK_READY|'||rule_quality_l13.l24_ready_payload_v1("+
   "'lf',"+lit(CODE)+",'PROM-TEST',"+lit(RUN)+")::text;"))
 script=("BEGIN;\n"+p+pre+sync+
  command_promote("lf",CODE,token,"PROM-TEST",RUN)+
  command_close("lf",CODE,token,"PROM-TEST",RUN)+
  command_verify("lf",CODE,token,"PROM-TEST")+
  measure_sql("lf",CODE,"PROM-TEST",corrected)+"\nROLLBACK;\n"+after_sql("lf",CODE))
 out=sql(script)
 board=board_measured("lf",out)
 rb=out["READBACK_READY"]
 after=out["AFTER_ROLLBACK"]
 ok=(rb["status"]=="READY"
  and out["CURATOR"]["verdict"]=="ACEPTAR"
  and out["WRAP"]["status"]=="READY"
  and out["PROMOTION_RECEIPT"]["status"]=="PROMOTION_RECEIPT_RECORDED"
  and out["CLOSE"]["status"]=="INTEGRATED_CLOSED_VERIFIED_PG18"
  and out["CLOSE"]["closure_verification"]["status"]=="VERIFIED_CLOSURE_HASH"
  and out["MEASURED"]["promotion_receipts"]==out["MEASURED"]["closure_receipts"]==1
  and out["MEASURED"]["divergences"]==0
  and after=={"quality":0,"curator":0,"promotion":0,"closure":0,"source_count_or_active":0}
  and len(board)==12)
 if corrected:
  ok=ok and out["SYNC_PREVIOUS"]["status"]=="SYNCED_ATOMIC_PG18" and out["MEASURED"]["previous_state"]==out["MEASURED"]["previous_source"]=="SUCEDIDA"
 check("POS_"+label+"_SINGLE_MEASURED_SEQUENCE",ok,
  "same BEGIN contains L17 owner -> L23 ACEPTAR -> LF frozen apply -> READY -> L20 -> L26 promotion receipt -> L24 closure; ROLLBACK",
  {"actual":{"curator":out["CURATOR"],"wrap":out["WRAP"]["status"],
   "sync":out.get("SYNC_PREVIOUS"),"promote":out["PROMOTION_RECEIPT"],
   "close":out["CLOSE"],"measured":out["MEASURED"]},
   "after":after})
 SCENARIOS.append({"scenario":label,"status":"PASS","board":board,
  "measurement":out["MEASURED"],"curator":out["CURATOR"],"promotion":out["PROMOTION_RECEIPT"],
  "closure":out["CLOSE"],"rollback":after,
  "sequence":"ONE_BEGIN_ONE_SQL_CONNECTION_ONE_ROLLBACK"})
def positive_saly(token):
 p=("SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('saly','SALY-L14-NEW','MOTOR_DISPONIBLE')::text;\n"
 "SELECT 'OWNER_INTENT|'||rule_quality_l13.l18_owner_intent_v1('saly','SALY-L14-NEW','SALY-L26-PROM-A')::text;\n"
 "SELECT 'CURATOR|'||rule_quality_l13.l23_curator_evaluate_v1('saly','SALY-L14-NEW')::text;\n"
 "SELECT 'WRAP|'||rule_quality_l13.quality_apply_envelope_v2('saly','SALY-L14-NEW')::text;\n"
 "SELECT 'READBACK_READY|'||rule_quality_l13.l24_ready_payload_v1('saly','SALY-L14-NEW','SALY-L26-PROM-A',NULL)::text;\n")
 script=("BEGIN;\n"+saly(token,p)+
  command_promote("saly","SALY-L14-NEW",token,"SALY-L26-PROM-A")+
  command_close("saly","SALY-L14-NEW",token,"SALY-L26-PROM-A")+
  command_verify("saly","SALY-L14-NEW",token,"SALY-L26-PROM-A")+
  measure_sql("saly","SALY-L14-NEW","SALY-L26-PROM-A")+
  "\nROLLBACK;\n"+after_sql("saly","SALY-L14-NEW"))
 out=sql(script);board=board_measured("saly",out)
 ok=(out["CURATOR"]["verdict"]=="ACEPTAR" and out["WRAP"]["status"]=="READY"
  and out["READBACK_READY"]["status"]=="READY"
  and out["CLOSE"]["status"]=="INTEGRATED_CLOSED_VERIFIED_PG18"
  and out["MEASURED"]["divergences"]==0
  and out["AFTER_ROLLBACK"]=={"quality":0,"curator":0,"promotion":0,"closure":0,"source_count_or_active":0}
  and len(board)==12)
 check("POS_C_SALY_NEW_SINGLE_MEASURED_SEQUENCE",ok,
  "same transaction SALY owner -> Curator -> synthetic apply -> READY -> L20 0 -> 2 receipts; rollback",out)
 SCENARIOS.append({"scenario":"C_SALY_NEW","status":"PASS","board":board,
  "measurement":out["MEASURED"],"curator":out["CURATOR"],"promotion":out["PROMOTION_RECEIPT"],
  "closure":out["CLOSE"],"rollback":out["AFTER_ROLLBACK"],
  "sequence":"ONE_BEGIN_ONE_SQL_CONNECTION_ONE_ROLLBACK"})
def whole_good_prelude(token):
 return prelude_lf(token,False)
def negatives(token):
 not_curator="BEGIN;\n"+prelude_lf(token,False,False)+"\nROLLBACK;"
 fail("N1_PROMOTION_WITHOUT_CURATOR_BLOCKED",not_curator,"BLOCK_L23_CURATOR_NOT_ACCEPTED")
 no_promo=("BEGIN;\n"+whole_good_prelude(token)+
  command_close("lf",CODE,token,"PROM-TEST",RUN,True)+"\nROLLBACK;")
 fail("N2_CLOSURE_WITHOUT_PROMOTION_RECEIPT",no_promo,"BLOCK_L26_PROMOTION_RECEIPT_REQUIRED")
 tamper=("BEGIN;\n"+whole_good_prelude(token)+
  command_promote("lf",CODE,token,"PROM-TEST",RUN)+
  "UPDATE rule_quality_l13.l23_curator_verdicts SET reason_text='TAMPERED' "
  "WHERE project_code='lf' AND rule_code="+lit(CODE)+";\n"+
  command_close("lf",CODE,token,"PROM-TEST",RUN)+"\nROLLBACK;")
 fail("N3_TAMPERED_CURATOR_BLOCKS_CLOSURE",tamper,"BLOCK_L26_CURATOR_SEAL_TAMPERED")
 divergence=("BEGIN;\n"+whole_good_prelude(token)+
  command_promote("lf",CODE,token,"PROM-TEST",RUN)+
  "UPDATE rule_quality_l13.rules SET state='CADUCADA' "
  "WHERE project_code='lf' AND rule_code="+lit(CODE)+";\n"+
  command_close("lf",CODE,token,"PROM-TEST",RUN)+"\nROLLBACK;")
 fail("N4_DIVERGENCE_BLOCKS_INTEGRATED_CLOSE",divergence,"BLOCK_L24_DIVERGENCE_REGISTER_SOURCE")
 # Replay an HMAC ACEPTAR from one rule on a second, distinct candidate.
 # App roles never receive DML; the copied row is written as PG superuser
 # malicious fixture and must fail at the unmodified L23 ticket trigger.
 second=("BEGIN;\n"+whole_good_prelude(token)+
  "INSERT INTO lf_ops.reglas(id,codigo,descripcion,estado,categoria,owner_name,valor_config) "
  "SELECT 998801,'L26-OTHER-RULE',descripcion,'CANDIDATO',categoria,owner_name,valor_config "
  "FROM lf_ops.reglas WHERE codigo="+lit(CODE)+";\n"+
  owner(token,
   "SELECT 'SECOND_PREP|'||rule_quality_l13.quality_prepare_new_v2('lf','L26-OTHER-RULE','IDENTIDAD_SEGURIDAD')::text;")+
  "INSERT INTO rule_quality_l13.l23_curator_verdicts("
  "project_code,rule_code,verdict,reason_code,reason_text,evidence,"
  "candidate_fingerprint_sha256,actor_code,owner_profile_code,seal_hmac_sha256)"
  " SELECT project_code,'L26-OTHER-RULE',verdict,reason_code,reason_text,evidence,"
  "candidate_fingerprint_sha256,actor_code,owner_profile_code,seal_hmac_sha256 "
  "FROM rule_quality_l13.l23_curator_verdicts "
  "WHERE project_code='lf' AND rule_code="+lit(CODE)+";\n"+
  owner(token,
    "SELECT rule_quality_l13.quality_apply_envelope_v2('lf','L26-OTHER-RULE','PROM-TEST',"+lit(RUN)+");")
  +"\nROLLBACK;")
 fail("N5_ACCEPT_REPLAY_ANOTHER_RULE_BLOCKED",second,"BLOCK_L23_CURATOR_SEAL_INVALID")
 forced=("BEGIN;\n"+whole_good_prelude(token)+
  command_promote("lf",CODE,token,"PROM-TEST",RUN)+
  "SELECT rule_quality_l13.l26_injected_fail_between_promotion_and_closure_v1();\n"
  +"\nROLLBACK;")
 fail("N6_MID_SEQUENCE_ROLLBACK_TRIGGERED",forced,"L26_INJECTED_AFTER_PROMOTION_BEFORE_CLOSURE")
 rb=sql("SELECT 'R|'||jsonb_build_object("
   "'candidate',(SELECT count(*) FROM lf_ops.reglas WHERE codigo="+lit(CODE)+"),"
   "'quality',(SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code="+lit(CODE)+"),"
   "'curator',(SELECT count(*) FROM rule_quality_l13.l23_curator_verdicts WHERE project_code='lf' AND rule_code="+lit(CODE)+"),"
   "'promotion',(SELECT count(*) FROM rule_quality_l13.l26_promotion_receipts),"
   "'closure',(SELECT count(*) FROM rule_quality_l13.l24_closure_receipts),"
   "'owner_intents',(SELECT count(*) FROM rule_quality_l13.l18_owner_intents)"
   ")::text;")["R"]
 check("N6B_ROLLBACK_TOTAL_READBACK",
  rb=={"candidate":0,"quality":0,"curator":0,"promotion":0,"closure":0,"owner_intents":0},
  "injected fault after frozen promotion and L26 promotion receipt leaves zero persisted source, verdict, receipts",rb)
def permission_matrix():
 # Real Postgres privilege tests, 7 roles * 3 tables * 5 privileged actions.
 # Fixture superuser SET SESSION AUTHORIZATION acts as each app role, and
 # success would fail the suite. No JWT claim grants SQL table ownership.
 ops=("INSERT","UPDATE","DELETE","TRUNCATE","DISABLE_TRIGGER")
 for role in ROLES:
  for table in TABLES:
   rel="rule_quality_l13."+table
   cmds={
    "INSERT":"INSERT INTO "+rel+" DEFAULT VALUES;",
    "UPDATE":"UPDATE "+rel+" SET actor_code='FORGED';",
    "DELETE":"DELETE FROM "+rel+";",
    "TRUNCATE":"TRUNCATE "+rel+";",
    "DISABLE_TRIGGER":"ALTER TABLE "+rel+" DISABLE TRIGGER ALL;"
   }
   raw={}
   for op in ops:
    q=("BEGIN;\nSET SESSION AUTHORIZATION "+role+";\n"+cmds[op]+"\nROLLBACK;")
    r=sql(q,fail=True);head=r["stderr"].splitlines()[0] if r["stderr"].splitlines() else ""
    ok=(r["exit_code"]!=0 and ("permission denied" in r["stderr"].lower()
       or "must be owner" in r["stderr"].lower()
       or "not owner" in r["stderr"].lower()))
    raw[op]={"denied":ok,"error":head[:220],"sqlstate_error":r["exit_code"]}
   check("PERMISSIONS_"+role+"_"+table,
     all(x["denied"] for x in raw.values()),
     "each of INSERT UPDATE DELETE TRUNCATE DISABLE TRIGGER denied for "+role+" / "+table,
     raw)
def main():
 bootstrap()
 before=l14.l11b.md5s()
 check("FROZEN_MD5_BEFORE",before==EXPECTED,EXPECTED,before)
 lf=l17.token("lf","lf-sub-owner-001","lf_owner_role")
 sy=l17.token("saly","saly-sub-owner-001","saly_owner_role")
 positive_lf("A_LF_NEW",lf,False)
 positive_lf("B_LF_CORRECTED",lf,True)
 positive_saly(sy)
 negatives(lf)
 permission_matrix()
 after=l14.l11b.md5s()
 check("FROZEN_MD5_AFTER",before==after==EXPECTED,EXPECTED,after)
 real=sum(r["status"]=="REAL_EN_SANDBOX" for s in SCENARIOS for r in s["board"])
 synthetic=sum(r["status"]=="SINTETICO" for s in SCENARIOS for r in s["board"])
 untested=sum(r["status"]=="NO_PROBADO" for s in SCENARIOS for r in s["board"])
 assert len(SCENARIOS)==3 and real+synthetic+untested==36
 assert len(CASES)==3+3+7+len(ROLES)*len(TABLES), len(CASES)
 report={"schema_version":"LF_LOTE26_MEASURED_INTEGRATION_PG18_V1",
  "status":"SANDBOX_VERIFIED","production":"NO_GO_UNVERIFIED",
  "scenario_count":3,"cases":CASES,"case_count":len(CASES),"scenarios":SCENARIOS,
  "gate_md5_before":before,"gate_md5_after":after,
  "measured_board":{"real":real,"synthetic":synthetic,"no_probado":untested,"total":36,
    "formula":"real/(12*3)*100","real_percent":round(100*real/36,2)},
  "permission_matrix":{"roles":ROLES,"tables":TABLES,"operations":["INSERT","UPDATE","DELETE","TRUNCATE","DISABLE_TRIGGER"],
    "individual_denials_verified":len(ROLES)*len(TABLES)*5},
  "same_transaction_sequence_verified":True,
  "l23_l24_original_sql_modified":False,"frozen_gates_modified":False,
  "curator":"DETERMINISTIC_SQL_SAME_GPT_MODEL_NOT_INDEPENDENT",
  "jwt":"L17_HMAC_FIXTURE_NOT_SUPABASE_AUTH",
  "native_step70":False,"native_router_profile_run":False,"native_receiver":False,
  "production_write_count":0}
 path=HERE/"lote26_runtime.json"
 path.write_text(json.dumps(report,ensure_ascii=False,sort_keys=True,indent=2,default=str)+"\n",encoding="utf-8")
 print("RAW_L26_REPORT "+json.dumps(report,ensure_ascii=False,sort_keys=True,default=str),flush=True)
 print("L26_RAW_JSON_SHA256 "+hashlib.sha256(path.read_bytes()).hexdigest(),flush=True)
 print("L26_COMPLETE cases="+str(len(CASES))+" scenarios=3 measured="+str(real)+"/36",flush=True)
if __name__=="__main__":main()
