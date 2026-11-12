#!/usr/bin/env python3
"""L20 PG18 isolated: owner JWT -> L13 decision -> source sync, all-or-none.
LF L7/L8/L11B receipts remain synthetic. No production, no Supabase DML/DDL.
"""
import hashlib,json
from pathlib import Path
import test_pg18_lote18_integrated_cycle as l18
import test_pg18_lote17_actor_identity_adapter as l17
import test_pg18_lote14_quality_wrapper as l14
ROOT=Path(__file__).resolve().parents[3]
HERE=ROOT/"sandbox/lf_contract_gate_test/rule_quality_lifecycle_v1"
DB="lf_3779_l20_source_sync_pg18"
CASES=[]
SCENARIOS=[]
EXPECTED=l14.EXPECTED_MD5
def lit(s):return l17.lit(s)
def sql(q,fail=False):return l17.sql(q,fail=fail)
def owner(jwt,body):return l18.owner_session(jwt,body)
def saly(jwt,body):return l18.saly_session(jwt,body)
def check(i,ok,expect,observed):
 if not ok:raise AssertionError("FAIL_L20_"+i+" EXPECTED="+str(expect)+" OBSERVED="+json.dumps(observed,ensure_ascii=False,sort_keys=True,default=str)[:6500])
 item={"id":i,"status":"PASS","expected":expect,"observed":observed}
 CASES.append(item)
 print("PASS_L20_"+i+" "+json.dumps(observed,ensure_ascii=False,sort_keys=True,default=str),flush=True)
def negative(i,role,jwt,stmt,code):
 out=l17.exec_as(role,jwt,stmt,fail=True)
 check(i,code in out["stderr"],code,{"pg_error":out["stderr"].splitlines()[0],"exit_code":out["exit_code"]})
def bootstrap():
 l18.DB=DB
 l18.bootstrap()
 sql((HERE/"12_l20_atomic_owner_source_sync_pg18.sql").read_text(encoding="utf-8"))
 check("SETUP_L13_L14_L17_L18_L20",True,
       "L11B frozen + quality registry + JWT actor + owner/sync SQL; disposable DB",
       {"db":DB,"current_git_layer":"12_l20_atomic_owner_source_sync_pg18.sql","production":False})
def seed_old():
 return """INSERT INTO rule_quality_l13.rules(project_code,rule_code,family_code,category_raw,
  entity_code,definition_text,config,state,reviewed_at,next_review_at,effective_from)
 SELECT 'lf','RULE-DEPENDENCY-001','IDENTIDAD_SEGURIDAD','SECURITY',
  'GENERAL',descripcion,'{}'::jsonb,'VIGENTE',
  clock_timestamp(),clock_timestamp()+interval '90 days',clock_timestamp()
 FROM lf_ops.reglas WHERE codigo='RULE-DEPENDENCY-001';"""
def prelude_lf(jwt,correction=False):
 code=l14.l11b.RULE
 quote=l14.l11b.CASE_ID+"|ALLOW|"+l14.l11b.QUOTE
 b=l14.l11b.CASE["base_rule"]
 if correction:
  evidence=json.dumps({"source_ref":"L20-SBX-CORRECTED","rationale":"approved sandbox successor explicitly separated"})
  prepare=("SELECT 'CORRECTION|'||rule_quality_l13.quality_propose_correction_v2("
    "'lf','RULE-DEPENDENCY-001',"+lit(code)+","+lit(b["description"])+","+lit(evidence)+"::jsonb)::text;\n"
    "SELECT 'PREP|'||rule_quality_l13.l18_prepare_explicit_successor_v1("
    "'lf','RULE-DEPENDENCY-001',"+lit(code)+")::text;")
 else:
  prepare="SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('lf',"+lit(code)+",'IDENTIDAD_SEGURIDAD')::text;"
 return (l14.l11b.setup("POSITIVE")+"\n"
  +(seed_old()+"\n" if correction else "")
  +owner(jwt,prepare)+"\n"
  +"SELECT 'LINE|'||public.lf_rule_promotion_citation_line_check_v1('PROM-TEST',"+lit(quote)+")::text;\n"
  +"SET LOCAL ROLE lf_rule_citation_step70_bridge;\n"
  +"SELECT 'CAPTURE|'||public.lf_rule_promotion_citation_record_v1("
  "'PROM-TEST',"+lit(quote)+",'EXEC-PARENT-TEST-001')::text;\n"
  +"RESET ROLE;\n"
  +"SELECT 'VERIFY|'||public.lf_rule_promotion_citation_verify_v1('PROM-TEST')::text;\n"
  +"SELECT 'PIN|'||public.lf_rule_promotion_blind_verdict_pin_v1('PROM-TEST')::text;\n"
  +"SELECT 'IG|'||public.lf_rule_promotion_ig_semantic_verify_v1('PROM-TEST')::text;\n"
  +owner(jwt,"SELECT 'JWT_OWNER|'||rule_quality_l13.l18_owner_intent_v1('lf',"
       +lit(code)+",'PROM-TEST')::text;")+"\n"
  +l14.l11b.owner_run()+"\n"
  +"SELECT 'OWNER|'||public.lf_rule_promotion_profile_owner_verify_v1('PROM-TEST')::text;\n"
  +owner(jwt,"SELECT 'WRAP|'||rule_quality_l13.quality_apply_envelope_v2("
        "'lf',"+lit(code)+",'PROM-TEST',"+lit(l14.l11b.OWNER_RUN)+")::text;")+"\n")
def after_rollback(name,code,old="RULE-DEPENDENCY-001"):
 return ("SELECT '"+name+"|'||jsonb_build_object("
  "'candidate',(SELECT count(*) FROM lf_ops.reglas WHERE codigo="+lit(code)+"),"
  "'quality_candidate',(SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code="+lit(code)+"),"
  "'source_old',(SELECT estado FROM lf_ops.reglas WHERE codigo="+lit(old)+"),"
  "'quality_old',(SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code="+lit(old)+"),"
  "'sync_receipts',(SELECT count(*) FROM rule_quality_l13.l20_sync_receipts),"
  "'review_decisions',(SELECT count(*) FROM rule_quality_l13.review_decisions WHERE rule_code="+lit(old)+"))::text;")
def b_correction_full_cycle(jwt):
 code=l14.l11b.RULE
 evidence='{"source_ref":"L20-B-OWNER-SANDBOX","rationale":"explicit trusted owner supersession with full source readback"}'
 action=("SELECT 'BEFORE|'||rule_quality_l13.l20_target_readback_v1("
        "'lf','RULE-DEPENDENCY-001',"+lit(code)+")::text;\n"
   "SELECT 'SYNC|'||rule_quality_l13.l20_owner_decide_and_sync_v1("
   "'lf','RULE-DEPENDENCY-001','SUPERSEDE',"+lit(evidence)+"::jsonb,clock_timestamp(),"
   +lit(code)+")::text;\n"
   "SELECT 'DECISION_COUNT_BEFORE_RETRY|'||("
   "rule_quality_l13.l20_target_readback_v1('lf','RULE-DEPENDENCY-001')->>'decision_count');\n"
   "SELECT 'RETRY|'||rule_quality_l13.l20_owner_decide_and_sync_v1("
   "'lf','RULE-DEPENDENCY-001','SUPERSEDE',"+lit(evidence)+"::jsonb,clock_timestamp(),"
   +lit(code)+")::text;\n"
   "SELECT 'DECISION_COUNT_AFTER_RETRY|'||("
   "rule_quality_l13.l20_target_readback_v1('lf','RULE-DEPENDENCY-001')->>'decision_count');\n"
   "SELECT 'AFTER|'||rule_quality_l13.l20_target_readback_v1("
   "'lf','RULE-DEPENDENCY-001',"+lit(code)+")::text;")
 script=("BEGIN;\n"+prelude_lf(jwt,True)+"\n"+owner(jwt,action)
   +"\nROLLBACK;\n"+after_rollback("FINAL_ROLLBACK",code))
 out=sql(script)
 a=out["SYNC"];ret=out["RETRY"]
 ok=(out["VERIFY"]["status"]=="VERIFIED_CAPTURE_BINDING"
     and out["IG"]["status"]=="READY_FOR_PROFILE_APPROVAL"
     and out["WRAP"]["status"]=="READY"
     and out["WRAP"]["gate"]["status"]=="APPLIED"
     and out["WRAP"]["profile_return"]["status"]=="READY"
     and out["BEFORE"]["target_divergence"]==0
     and out["BEFORE"]["registry"]==out["BEFORE"]["source"]=="VIGENTE"
     and a["status"]=="SYNCED_ATOMIC_PG18"
     and a["target_divergences_before_sync"]==1
     and a["target_divergences_after_sync"]==0
     and a["owner_sub"]=="lf-sub-owner-001"
     and a["registry_state"]=="SUCEDIDA" and a["source_state"]=="SUCEDIDA"
     and a["source_rows_updated"]==1
     and out["AFTER"]["target_divergence"]==0
     and out["AFTER"]["registry"]==out["AFTER"]["source"]=="SUCEDIDA"
     and out["AFTER"]["registry_successor"]==code
     and out["AFTER"]["successor_source"]==out["AFTER"]["successor_registry"]=="VIGENTE"
     and out["AFTER"]["receipt_count"]==1
     and ret["status"]=="ALREADY_SYNCED_NOOP" and ret["rows_updated"]==0
     and ret["decisions_added"]==0 and ret["receipts_added"]==0
     and out["DECISION_COUNT_BEFORE_RETRY"]==out["DECISION_COUNT_AFTER_RETRY"]==1
     and out["FINAL_ROLLBACK"]=={
       "candidate":0,"quality_candidate":0,"source_old":"VIGENTE",
       "quality_old":0,"sync_receipts":0,"review_decisions":0})
 check("B_CORRECTED_BOTH_SOURCES_SUCCEEDED",ok,
    "L18 full L7/L8/L11B+L13/14/17 -> old source+registry SUCEDIDA; successor both VIGENTE; rollback",
    {k:out.get(k) for k in ("CAPTURE","VERIFY","IG","WRAP","BEFORE","SYNC","RETRY","AFTER","FINAL_ROLLBACK")})
 check("N6_IDEMPOTENT_SECOND_SYNC_NO_MUTATION",
    ret["status"]=="ALREADY_SYNCED_NOOP"
    and ret["rows_updated"]==0 and ret["decisions_added"]==0
    and out["DECISION_COUNT_BEFORE_RETRY"]==out["DECISION_COUNT_AFTER_RETRY"]==1,
    "same JWT owner retry returns 0 writes, 0 new decisions and same receipt",
    {"retry":ret,"counts":[out["DECISION_COUNT_BEFORE_RETRY"],out["DECISION_COUNT_AFTER_RETRY"]]})
 SCENARIOS.append({"scenario":"B_CORRECTED_SYNC","status":"PASS",
                    "source_and_registry":"SUCEDIDA","successor":"VIGENTE",
                    "readback":out["AFTER"],"sync":a,"rollback":out["FINAL_ROLLBACK"]})
def lf_expiry_full_cycle(jwt):
 code=l14.l11b.RULE
 evidence='{"source_ref":"L20-A-EXPIRY","rationale":"explicit simulated-date owner expiry"}'
 decision=("SELECT 'BEFORE|'||("
  "rule_quality_l13.l20_target_readback_v1('lf',"+lit(code)+") || "
  "jsonb_build_object('due', (rule_quality_l13.l18_due_snapshot_v1('lf',"+lit(code)+")->>'due')::int))::text;\n"
  "SELECT 'SYNC|'||rule_quality_l13.l20_owner_decide_and_sync_v1("
  "'lf',"+lit(code)+",'EXPIRE',"+lit(evidence)+"::jsonb,"
  "(rule_quality_l13.l18_due_snapshot_v1('lf',"+lit(code)+")->>'as_of_simulated')::timestamptz)::text;\n"
  "SELECT 'AFTER|'||rule_quality_l13.l20_target_readback_v1('lf',"+lit(code)+")::text;")
 script=("BEGIN;\n"+prelude_lf(jwt,False)+owner(jwt,decision)
   +"\nROLLBACK;\n"+after_rollback("FINAL_ROLLBACK",code))
 out=sql(script)
 ok=(out["VERIFY"]["status"]=="VERIFIED_CAPTURE_BINDING"
     and out["WRAP"]["status"]=="READY" and out["WRAP"]["gate"]["status"]=="APPLIED"
     and out["BEFORE"]["source"]==out["BEFORE"]["registry"]=="VIGENTE"
     and out["BEFORE"]["due"]==1
     and out["SYNC"]["status"]=="SYNCED_ATOMIC_PG18"
     and out["SYNC"]["source_state"]==out["SYNC"]["registry_state"]=="CADUCADA"
     and out["SYNC"]["target_divergences_before_sync"]==1
     and out["SYNC"]["target_divergences_after_sync"]==0
     and out["AFTER"]["source"]==out["AFTER"]["registry"]=="CADUCADA"
     and out["AFTER"]["target_divergence"]==0
     and out["AFTER"]["next_review_at"] is None
     and out["AFTER"]["effective_to"] is not None
     and out["FINAL_ROLLBACK"]["candidate"]==0
     and out["FINAL_ROLLBACK"]["sync_receipts"]==0)
 check("LF_EXPIRY_BOTH_SOURCES_CADUCADA",ok,
    "L18 LF new promotion then signed owner due date -> registry/source CADUCADA atomic",
    {k:out.get(k) for k in ("VERIFY","WRAP","BEFORE","SYNC","AFTER","FINAL_ROLLBACK")})
 SCENARIOS.append({"scenario":"A_LF_EXPIRE_SYNC","status":"PASS","source_and_registry":"CADUCADA",
                   "sync":out["SYNC"],"readback":out["AFTER"],"rollback":out["FINAL_ROLLBACK"]})
def saly_expiry_cycle(jwt):
 evidence='{"source_ref":"L20-SALY-EXPIRE","rationale":"same signed owner source sync via SALY adapter"}'
 body="""SELECT 'PREP|'||rule_quality_l13.quality_prepare_new_v2('saly','SALY-L14-NEW','MOTOR_DISPONIBLE')::text;
SELECT 'APPLIED|'||rule_quality_l13.quality_apply_envelope_v2('saly','SALY-L14-NEW')::text;
SELECT 'BEFORE|'||rule_quality_l13.l20_target_readback_v1('saly','SALY-L14-NEW')::text;
SELECT 'SYNC|'||rule_quality_l13.l20_owner_decide_and_sync_v1(
 'saly','SALY-L14-NEW','EXPIRE',"""+lit(evidence)+"""::jsonb,
 (rule_quality_l13.l18_due_snapshot_v1('saly','SALY-L14-NEW')->>'as_of_simulated')::timestamptz)::text;
SELECT 'AFTER|'||rule_quality_l13.l20_target_readback_v1('saly','SALY-L14-NEW')::text;"""
 out=sql("BEGIN;\n"+saly(jwt,body)+"\nROLLBACK;\n"+
  """SELECT 'FINAL_ROLLBACK|'||jsonb_build_object(
  'source_vigente',(SELECT vigente FROM rule_quality_l13.saly_source_synthetic WHERE codigo='SALY-L14-NEW'),
  'registry_rows',(SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='saly' AND rule_code='SALY-L14-NEW'),
  'receipts',(SELECT count(*) FROM rule_quality_l13.l20_sync_receipts WHERE project_code='saly'))::text;""")
 ok=(out["PREP"]["status"]=="QUALITY_PREPARED"
   and out["APPLIED"]["status"]=="READY"
   and out["APPLIED"]["gate"]["fixture_only"] is True
   and out["BEFORE"]["source_vigente"] is True
   and out["BEFORE"]["registry"]=="VIGENTE"
   and out["SYNC"]["status"]=="SYNCED_ATOMIC_PG18"
   and out["SYNC"]["registry_state"]==out["SYNC"]["source_state"]=="CADUCADA"
   and out["SYNC"]["target_divergences_before_sync"]==1
   and out["SYNC"]["target_divergences_after_sync"]==0
   and out["AFTER"]["source_vigente"] is False
   and out["AFTER"]["source_terminal"]=="CADUCADA"
   and out["AFTER"]["registry"]=="CADUCADA"
   and out["AFTER"]["target_divergence"]==0
   and out["FINAL_ROLLBACK"]=={"source_vigente":False,"registry_rows":0,"receipts":0})
 check("SALY_EXPIRE_SAME_SYNC_FUNCTION",ok,
    "Saly false + explicit terminal metadata in synthetic adapter, L13 CADUCADA, no native SALY apply",
    out)
 SCENARIOS.append({"scenario":"C_SALY_EXPIRE_SYNC","status":"PASS","source_active":False,
                   "registry":"CADUCADA","readback":out["AFTER"],"rollback":out["FINAL_ROLLBACK"]})
def seed_negative_baseline():
 # Verified independent persistent baseline ONLY in this disposable PG18 database.
 sql(seed_old())
 data=sql("""SELECT 'BASE|'||jsonb_build_object(
  'source',(SELECT estado FROM lf_ops.reglas WHERE codigo='RULE-DEPENDENCY-001'),
  'registry',(SELECT state FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code='RULE-DEPENDENCY-001'),
  'decisions',(SELECT count(*) FROM rule_quality_l13.review_decisions WHERE project_code='lf' AND rule_code='RULE-DEPENDENCY-001'),
  'receipts',(SELECT count(*) FROM rule_quality_l13.l20_sync_receipts))::text;""")["BASE"]
 check("PREFAULT_BOTH_SOURCES_VIGENTE",data=={"source":"VIGENTE","registry":"VIGENTE","decisions":0,"receipts":0},
       "real PG rows persisted in sandbox before mid-flight failure",data)
def six_negatives(owner_jwt,super_jwt):
 evidence=lit('{"source_ref":"L20-NEGATIVE-SBX","rationale":"negative atomic lifecycle experiment"}')+"::jsonb"
 base="'lf','RULE-DEPENDENCY-001'"
 negative("N1_NO_OWNER_DECISION","lf_owner_role",owner_jwt,
   "SELECT rule_quality_l13.l20_owner_decide_and_sync_v1("+base+",NULL,"+evidence+",clock_timestamp());",
   "BLOCK_L20_OWNER_DECISION_REQUIRED")
 negative("N2_SUPER_ADMIN_JWT","lf_super_role",super_jwt,
   "SELECT rule_quality_l13.l20_owner_decide_and_sync_v1("+base+",'EXPIRE',"+evidence+",clock_timestamp());",
   "BLOCK_SUPER_ADMIN_APPROVAL")
 extra=("SELECT rule_quality_l13.quality_propose_correction_v2("
   "'lf','RULE-DEPENDENCY-001','LF-L20-SUCC-NOT-READY','A proposed, never promoted rule',"
   "'{\"source_ref\":\"L20-NEG-SUCCESSOR\",\"rationale\":\"test incompatible successor\"}'::jsonb);\n")
 negative("N3_SUCCESSOR_NOT_VIGENTE","lf_owner_role",owner_jwt,
   extra+"SELECT rule_quality_l13.l20_owner_decide_and_sync_v1("+base+
   ",'SUPERSEDE',"+evidence+",clock_timestamp(),'LF-L20-SUCC-NOT-READY');",
   "BLOCK_L20_SUCCESSOR_NOT_VIGENTE")
 negative("N4_FORCED_MID_TRANSACTION_ROLLBACK","lf_owner_role",owner_jwt,
   "SELECT rule_quality_l13.l20_owner_decide_and_sync_v1("+base+
   ",'EXPIRE',"+evidence+",clock_timestamp(),NULL,true);",
   "L20_INJECTED_MIDWAY_FAIL_ROLLBACK_ALL")
 after=sql("""SELECT 'AFTER_FAULT|'||jsonb_build_object(
  'source',(SELECT estado FROM lf_ops.reglas WHERE codigo='RULE-DEPENDENCY-001'),
  'registry',(SELECT state FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code='RULE-DEPENDENCY-001'),
  'decisions',(SELECT count(*) FROM rule_quality_l13.review_decisions WHERE project_code='lf' AND rule_code='RULE-DEPENDENCY-001'),
  'receipts',(SELECT count(*) FROM rule_quality_l13.l20_sync_receipts WHERE project_code='lf'),
  'target_divergences',(SELECT count(*) FROM rule_quality_l13.rules rr
    JOIN lf_ops.reglas sr ON sr.codigo=rr.rule_code
   WHERE rr.project_code='lf' AND rr.rule_code='RULE-DEPENDENCY-001' AND rr.state<>sr.estado))::text;""")["AFTER_FAULT"]
 check("FORCED_FAILURE_ATOMIC_ROLLBACK_READBACK",
   after=={"source":"VIGENTE","registry":"VIGENTE","decisions":0,"receipts":0,"target_divergences":0},
   "source + L13 + decisions + tickets all unchanged after exception, no divergent state",after)
 negative("N5_DIRECT_SOURCE_DML_DENIED","lf_owner_role",owner_jwt,
   "UPDATE lf_ops.reglas SET estado='CADUCADA' WHERE codigo='RULE-DEPENDENCY-001';",
   "permission denied for schema lf_ops")
 negative("N5B_SALY_DIRECT_SOURCE_DML_DENIED","saly_owner_role",l17.token("saly","saly-sub-owner-001","saly_owner_role"),
   "UPDATE rule_quality_l13.saly_source_synthetic SET vigente=false WHERE codigo='SALY-L14-NEW';",
   "permission denied for table saly_source_synthetic")
def detector_readonly(owner_jwt):
 # Proves a genuine pre-sync mismatch outside the L20 wrapper:
 # L18 signed owner makes a registral expiry, source remains VIGENTE; the detector
 # lists the mismatch, then ROLLBACK restores both. No background auto-sync.
 evidence='{"source_ref":"L20-DETECTOR-PROBE","rationale":"prove detector without source mutation"}'
 body=("SELECT 'CHANGE|'||rule_quality_l13.l18_owner_review_decide_v1("
   "'lf','RULE-DEPENDENCY-001','EXPIRE',clock_timestamp()+interval '1 day',"
   +lit(evidence)+"::jsonb)::text;\n"
   "SELECT 'DETECT|'||jsonb_agg(jsonb_build_object('rule',rule_code,"
   "'registry',registry_state,'source',source_state,'classification',classification))::text "
   "FROM rule_quality_l13.l20_list_divergences_v1('lf') "
   "WHERE rule_code='RULE-DEPENDENCY-001';")
 out=sql("BEGIN;\n"+owner(owner_jwt,body)+"\nROLLBACK;\n"+
  """SELECT 'POST_ROLLBACK|'||jsonb_build_object(
  'source',(SELECT estado FROM lf_ops.reglas WHERE codigo='RULE-DEPENDENCY-001'),
  'registry',(SELECT state FROM rule_quality_l13.rules WHERE project_code='lf' AND rule_code='RULE-DEPENDENCY-001'),
  'decision_rows',(SELECT count(*) FROM rule_quality_l13.review_decisions WHERE rule_code='RULE-DEPENDENCY-001'))::text;""")
 detected=out["DETECT"]
 ok=(out["CHANGE"]["state"]=="CADUCADA"
    and isinstance(detected,list) and len(detected)==1
    and detected[0]["registry"]=="CADUCADA"
    and detected[0]["source"]=="VIGENTE"
    and detected[0]["classification"]=="LIFECYCLE_STATE_MISMATCH"
    and out["POST_ROLLBACK"]=={"source":"VIGENTE","registry":"VIGENTE","decision_rows":0})
 check("READ_ONLY_DETECTOR_SEES_DIVERGENCE_BEFORE_SYNC",ok,
    "L18 decision alone creates visible mismatch, detector no mutation, rollback restores baseline",
    {"detected":detected,"before":{"registry":"VIGENTE","source":"VIGENTE"},
     "restored":out["POST_ROLLBACK"]})
def migration_draft_up_down():
 up=(HERE/"13_l20_proposed_columns_UP_DRAFT_NOT_DEPLOY.sql").read_text(encoding="utf-8")
 down=(HERE/"14_l20_proposed_columns_DOWN_DRAFT_NOT_DEPLOY.sql").read_text(encoding="utf-8")
 # All DDL on PG18 fixture, NEVER on live Supabase (real read-only inspection separate).
 col_expr="""SELECT 'COUNTS|'||jsonb_build_object(
 'lf', (SELECT count(*) FROM information_schema.columns WHERE table_schema='lf_ops'
  AND table_name='reglas' AND column_name IN ('reviewed_at','next_review_at','successor_rule_code','effective_to')),
 'saly',(SELECT count(*) FROM information_schema.columns WHERE table_schema='saly'
  AND table_name='reglas' AND column_name IN ('reviewed_at','next_review_at','successor_rule_code','effective_to','lifecycle_state')),
 'lf_rows',(SELECT count(*) FROM lf_ops.reglas),
 'saly_rows',(SELECT count(*) FROM saly.reglas))::text;"""
 def marker(k):return col_expr.replace("'COUNTS|'","'"+k+"|'")
 script=("BEGIN;\nCREATE SCHEMA IF NOT EXISTS saly;\n"
  "CREATE TABLE saly.reglas (LIKE rule_quality_l13.saly_source_synthetic INCLUDING ALL);\n"
  "INSERT INTO saly.reglas(codigo,categoria,regla,vigente,metadata)"
  " VALUES('SALY-L20-MIGRATE','MOTOR_DISPONIBLE','fixture only',true,'{}'::jsonb);\n"
  +marker("BASE")+"\nSAVEPOINT before_up;\n"+up+"\n"+marker("UP")+"\n"
  +down+"\n"+marker("DOWN")+"\n"
  "SAVEPOINT before_up_rollback;\n"+up+"\n"
  "ROLLBACK TO SAVEPOINT before_up_rollback;\n"+marker("ROLLBACK_SAVEPOINT")+"\n"
  "ROLLBACK;")
 out=sql(script)
 v=out["BASE"];u=out["UP"];d=out["DOWN"];rb=out["ROLLBACK_SAVEPOINT"]
 check("MIGRATION_DRAFT_UP_DOWN_REVERSIBLE",
   v["lf"]==v["saly"]==0 and u["lf"]==4 and u["saly"]==5
   and d==v and rb==v and u["lf_rows"]==d["lf_rows"]
   and u["saly_rows"]==d["saly_rows"]==1,
   "PG18 draft only: columns 0/0 -> 4/5 -> 0/0, same row counts, savepoint rollback",
   {"base":v,"up":u,"down":d,"savepoint_rollback":rb,
    "sandbox_only":True,"live_migration_applied":False})
def main():
 bootstrap()
 before=l14.l11b.md5s()
 check("FROZEN_GATES_BEFORE",before==EXPECTED,EXPECTED,before)
 lf=l17.token("lf","lf-sub-owner-001","lf_owner_role")
 sup=l17.token("lf","lf-sub-super-001","lf_super_role")
 sy=l17.token("saly","saly-sub-owner-001","saly_owner_role")
 b_correction_full_cycle(lf)
 lf_expiry_full_cycle(lf)
 saly_expiry_cycle(sy)
 seed_negative_baseline()
 detector_readonly(lf)
 six_negatives(lf,sup)
 migration_draft_up_down()
 after=l14.l11b.md5s()
 check("FROZEN_GATES_AFTER",before==after==EXPECTED,EXPECTED,after)
 report={"schema_version":"LF_LOTE20_SOURCE_SYNC_PG18_V1",
  "global_status":"NO_GO_UNVERIFIED","scope":"DISPOSABLE_PG18_ONLY",
  "cases":CASES,"case_count":len(CASES),"scenarios":SCENARIOS,
  "gate_md5_before":before,"gate_md5_after":after,
  "owner_identity":"SIGNED_HMAC_PG18_POSTGREST_SIMULATION_NOT_SUPABASE_AUTH",
  "source_sync_atomic":True,"all_scenarios_rollback":True,
  "native_owner_or_oidc":False,"production_write_count":0,
  "schema_draft_requires_owner_approval":True,
  "real_supabase_divergent_rule_count":"NOT_MEASURABLE_WITHOUT_REGISTRY_OR_FIELDS"}
 path=HERE/"lote20_runtime.json"
 path.write_text(json.dumps(report,ensure_ascii=False,sort_keys=True,indent=2,default=str)+"\n",encoding="utf-8")
 print("RAW_L20_REPORT "+json.dumps(report,ensure_ascii=False,sort_keys=True,default=str),flush=True)
 print("RAW_L20_REPORT_SHA256 "+hashlib.sha256(path.read_bytes()).hexdigest(),flush=True)
 print("L20_SANDBOX_COMPLETE checks="+str(len(CASES))+" scenarios=3 required_negatives=6 gates_frozen=true",flush=True)
if __name__=="__main__":main()
