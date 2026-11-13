#!/usr/bin/env python3
"""B07 LF only; real PostgreSQL 17.6/18.7 in disposable Docker, no live writes."""
from __future__ import annotations
import hashlib
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/"sandbox/lf_contract_gate_test/input_governance_lifecycle/pg18_live_object_slice_baseline.sql"
V2=ROOT/"supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"
B07=ROOT/"supabase/migrations/20261113180000_lf_ig_b07_parent_child_atomic_v1.sql"

def q(v): return "'"+str(v).replace("'","''")+"'"
def j(v): return q(json.dumps(v,separators=(",",":"),ensure_ascii=False))+"::jsonb"

PARENTS="""SELECT encode(extensions.digest(convert_to(
 coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
 FROM lf_ops.reglas r;"""
CATALOG="""SELECT encode(extensions.digest(convert_to(jsonb_build_object(
 'parents',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.id),'[]'::jsonb) FROM lf_ops.reglas r),
 'schema',(SELECT coalesce(jsonb_agg(n.nspname||'.'||c.relname ORDER BY n.nspname,c.relname),'[]'::jsonb)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('lf_ops','public') AND c.relkind IN ('r','v')),
 'finalizer',pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure)
 )::text,'UTF8'),'sha256'),'hex');"""
INVARIANT="""SELECT count(*) FROM lf_ops.reglas p WHERE NOT EXISTS(
 SELECT 1 FROM lf_ops.reglas_versiones_b07 h WHERE h.rule_id=p.id
 AND h.version_no=(SELECT max(z.version_no) FROM lf_ops.reglas_versiones_b07 z WHERE z.rule_id=p.id)
 AND h.snapshot=to_jsonb(p) AND h.snapshot_sha256=
 encode(extensions.digest(convert_to(h.snapshot::text,'UTF8'),'sha256'),'hex'));"""
HISTORY="""SELECT encode(extensions.digest(convert_to(
 coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.rule_id,h.version_no),'[]'::jsonb)::text,
 'UTF8'),'sha256'),'hex') FROM lf_ops.reglas_versiones_b07 h;"""

REAL_LF_RULE = json.loads("{\"id\":396,\"razon\":\"No confiar únicamente en controles del frontend.\",\"codigo\":\"B2B-RULE-AUTH-001\",\"estado\":\"VIGENTE\",\"origen\":\"HANDOFF_B2B_v0.3\",\"titulo\":\"Denegar por defecto\",\"categoria\":\"SECURITY\",\"created_at\":\"2026-07-21T15:59:54.024242+00:00\",\"created_by\":\"OpenAI\",\"updated_at\":\"2026-08-21T05:56:04.996559+00:00\",\"descripcion\":\"Toda acción operativa del Backoffice posterior a autenticación completa se deniega por defecto y requiere autorización server-side. El servidor resuelve usuario activo, empresa, pantalla/recurso, permiso efectivo y, cuando aplica, transición de estado. Las acciones pre-auth de Login, MFA y recuperación se gobiernan por sus reglas AUTH específicas y nunca conceden por sí mismas permisos operativos.\",\"valor_config\":{\"model\":\"RBAC_PLUS_COMPANY_POLICY\",\"deny_by_default\":true,\"permission_resolution\":\"USER_DENY_GT_USER_ALLOW_GT_PROFILE_ALLOW_GT_DENY_DEFAULT\",\"server_side_enforcement\":true,\"effective_permission_sources\":[\"lf_ops.empresa_usuarios_perfiles\",\"lf_ops.perfiles_permisos\",\"lf_ops.empresa_usuarios_permisos\",\"lf_ops.pantallas_permisos\",\"lf_ops.estados_transiciones\"],\"transition_permission_source\":\"lf_ops.estados_transiciones.required_permission_id\",\"preauth_grants_operational_access\":\"DENY\",\"client_direct_operational_table_access\":\"DENY\",\"screen_access_requires_screen_permission\":true,\"preauth_flows_use_specific_auth_contracts\":true,\"authorization_recheck_on_every_server_action\":\"REQUIRED\",\"operational_access_requires_complete_authentication\":true},\"es_transversal\":true,\"pendiente_detalle\":null,\"pendiente_decision\":false}")
REAL_LF_ROW_SHA = "f8cbf0c21b3cd88b69fef5f640d1d8a19527e43119a05a63534fea24427d5867"

class B07LFOnly(unittest.TestCase):
 def run_pg(self,image,pg_number):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  for file in (BASE,V2,B07): self.assertTrue(file.is_file(),str(file))
  src=B07.read_text(encoding="utf-8")
  self.assertNotIn("saly.",src.lower(),"B07_SCOPE_CROSS_PROJECT")
  self.assertNotIn("saly_",src.lower(),"B07_SALY_WRITER_IN_SCOPE")
  self.assertEqual(src.count("\nBEGIN;\n"),1)
  self.assertEqual(src.count("\nCOMMIT;"),1)
  cid="lf-b07-lf-"+uuid.uuid4().hex[:11]
  started=subprocess.run(["docker","run","-d","--rm","--name",cid,
    "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
    text=True,capture_output=True,timeout=240)
  self.assertEqual(started.returncode,0,started.stderr)
  try:
   def sql(s,fail=None,dbname="postgres",timeout=420):
    r=subprocess.run(["docker","exec","-i",cid,"psql","-X","-q","-t","-A",
      "-v","ON_ERROR_STOP=1","-U","postgres","-d",dbname],
      input=s,capture_output=True,text=True,timeout=timeout)
    if fail:
     self.assertNotEqual(r.returncode,0,"B07_NEGATIVE_ACCEPTED:"+fail)
     self.assertIn(fail,r.stderr[-4000:],r.stderr[-4000:]); return r.stderr
    self.assertEqual(r.returncode,0,"B07_SQL_FAILURE "+r.stderr[-4000:])
    return r.stdout.strip()
   for _ in range(80):
    if subprocess.run(["docker","exec",cid,"pg_isready","-U","postgres","-d","postgres"],capture_output=True,timeout=10).returncode==0: break
    time.sleep(1)
   else: self.fail("B07_PG_NOT_READY")
   self.assertEqual(sql("SHOW server_version_num;"),pg_number)
   sql(BASE.read_text(encoding="utf-8"))
   code="20261113030000_lf_ig_rule_lifecycle_writer_v2"
   exec_id="EXEC-DB-TRAIN-PR3803-20261113030000-R43379990001"
   manifest={"producer":"lf-migration-merge-train","pr":3803,
     "train_run_id":"43379990001","head_sha":"e"*40,
     "router_authority_receipt":{
       "schema_version":"LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
       "operation_code":"ACTUALIZACION_DB_LF",
       "target_repo":"cristhianlujan/claude-persona-lf-patch",
       "target_code":code,
       "target_path":"supabase/migrations/"+code+".sql",
       "route_eligibility_only":True,"scope_attested":False}}
   sql(f"""INSERT INTO public.lf_operation_execution(
     execution_id,operation_code,target_type,target_code,target_repo,target_path,
     status,request_sha256,manifest,idempotency_key,created_by_execution_id)
     VALUES({q(exec_id)},'ACTUALIZACION_DB_LF','MIGRATION',{q(code)},
     'cristhianlujan/claude-persona-lf-patch',{q("supabase/migrations/"+code+".sql")},
     'IN_PROGRESS',{q('f'*64)},{j(manifest)},{q('train:20261113030000:'+'e'*40)},
     'LF-MIGRATION-TRAIN-RUN-43379990001');""")
   sql(V2.read_text(encoding="utf-8"))
   sql("INSERT INTO lf_ops.reglas SELECT (jsonb_populate_record(NULL::lf_ops.reglas,"+j(REAL_LF_RULE)+")).*;")
   self.assertEqual(sql("""SELECT encode(extensions.digest(convert_to(to_jsonb(r)::text,
     'UTF8'),'sha256'),'hex') FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-001';"""),
     REAL_LF_ROW_SHA,"REAL_LF_SNAPSHOT_DRIFT")
   sql("""INSERT INTO lf_ops.reglas(id,codigo,categoria,titulo,descripcion,estado)
      SELECT -90000-g,'LF-B07-TEST-'||lpad(g::text,4,'0'),'B07_FIXTURE',
       'Synthetic '||g,'Content',CASE WHEN g<=412 THEN 'VIGENTE' ELSE 'CANDIDATO' END
      FROM generate_series(2,578) g;""")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas;"),"578")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO';"),"166")
   before=sql(PARENTS)
   # Missing owner must fail CLOSED and leave no installation.
   sql(src,fail="B07_PROJECT_OWNER_AND_PROFILE_REQUIRED")
   self.assertEqual(sql("SELECT to_regclass('lf_ops.reglas_versiones_b07') IS NULL;"),"t")
   sql("""INSERT INTO public.lf_activos(id,codigo_activo,nombre_canonico,tipo_activo,
     estado_documental,estado_operativo,source_spreadsheet_id,
     source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id)
     VALUES(-777777,'PERFIL-PRODUCT-DIRECTOR-LF','CI LF OWNER PROFILE','PERFIL',
       'CANDIDATO','READ_ONLY','CI_SYNTHETIC','CI_SYNTHETIC','CI_ONLY',
       1,'00000000-0000-4000-8000-000000000111'::uuid);""")
   # V2 installs the synthetic LF project-owner row; do not duplicate it.
   self.assertEqual(sql("""SELECT count(*) FROM public.lf_ig_project_owner_v2
      WHERE project_code='LF' AND status='TEMP_DOCUMENTARY_ACTIVE'
      AND owner_profile_code='PERFIL-PRODUCT-DIRECTOR-LF';"""),"1")
   catalog_before=sql(CATALOG)
   inner=src.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
   sql("BEGIN;\n"+inner+"\nROLLBACK;",timeout=600)
   self.assertEqual(sql(CATALOG),catalog_before,"B07_ROLLBACK_EXACT_CATALOG")
   self.assertEqual(sql(PARENTS),before,"B07_ROLLBACK_EXACT_PARENTS")
   self.assertEqual(sql("SELECT to_regclass('lf_ops.reglas_versiones_b07') IS NULL;"),"t")
   print("PASS_B07_LF_PRECOMMIT_ROLLBACK_EXACT_"+image.replace(":","_"),flush=True)
   sql(src,timeout=600)
   self.assertEqual(sql(PARENTS),before,"B07_PARENT_CHANGED_DURING_INSTALL")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas_versiones_b07;"),"578")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas_versiones_b07 WHERE origin='BASELINE_CURRENT_ONLY' AND version_no=1 AND previous_sha256 IS NULL AND identity_verified=false;"),"578")
   self.assertEqual(sql(INVARIANT),"0")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas_versiones_b07 WHERE snapshot_sha256 IS DISTINCT FROM encode(extensions.digest(convert_to(snapshot::text,'UTF8'),'sha256'),'hex');"),"0")
   self.assertEqual(sql("SELECT to_regclass('saly.reglas_versiones_b07') IS NULL;"),"t")
   self.assertEqual(sql("SELECT to_regprocedure('public.lf_ig_saly_rule_finalize_b07_v1(text)') IS NULL;"),"t")
   self.assertEqual(sql("SELECT public.lf_b07_project_preflight_v1('LF')->>'status';"),"PREFLIGHT_PASS")
   sql("SELECT public.lf_b07_project_preflight_v1('SALY');",fail="B07_PROJECT_NOT_ENABLED")
   sql("SELECT public.lf_b07_project_preflight_v1('UNKNOWN');",fail="B07_PROJECT_NOT_ENABLED")
   self.assertEqual(sql("SELECT count(*) FROM public.lf_b07_project_gate_v1;"),"1")
   self.assertEqual(sql("SELECT count(*) FROM public.lf_b07_project_gate_v1 WHERE project_code='LF' AND enabled;"),"1")
   print("PASS_B07_LF_INSTALL_HASH_PREFLIGHT_DENY_CROSS_PROJECT_"+image.replace(":","_"),flush=True)
   sql("""BEGIN; UPDATE lf_ops.reglas SET titulo='UNAUTHORIZED' WHERE codigo='LF-B07-TEST-0001'; COMMIT;""",
       fail="B07_PARENT_LATEST_MISMATCH")
   sql("""UPDATE lf_ops.reglas_versiones_b07 SET snapshot='{}'::jsonb WHERE version_no=1;""",fail="B07_HISTORY_IMMUTABLE")
   sql("""TRUNCATE lf_ops.reglas_versiones_b07;""",fail="B07_HISTORY_TRUNCATE_BLOCKED")
   sql("""BEGIN; SET LOCAL ROLE service_role;
     INSERT INTO lf_ops.reglas_versiones_b07(rule_id,version_no,snapshot,snapshot_sha256,origin)
     VALUES(-90001,20,'{}'::jsonb,repeat('0',64),'BASELINE_CURRENT_ONLY');
     COMMIT;""",fail="permission denied")
   self.assertEqual(sql("SELECT has_function_privilege('service_role','public.lf_b07_append_after_finalize_v1(text)','EXECUTE');"),"f")
   sql("BEGIN; SET LOCAL ROLE anon; SELECT count(*) FROM public.lf_b07_rules_current_v1; COMMIT;",
      fail="permission denied")
   self.assertEqual(sql("SELECT count(*) FROM public.lf_b07_rules_current_v1;"),"412")
   self.assertEqual(sql(INVARIANT),"0")
   self.assertEqual(sql("""SELECT strpos(pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure),
      'PERFORM public.lf_b07_append_after_finalize_v1(p_child);')>0;"""),"t")
   print("PASS_B07_LF_ATOMIC_PARENT_CHILD_ACL_NEGATIVES_"+image.replace(":","_"),flush=True)
   # Real LF V2 parent->owner_decide->child 7 steps->finalize on disposable SQL.
   from test_ig_rule_lifecycle_pg18 import PG18RealSQL
   PG18RealSQL.docker=cid
   sql("""INSERT INTO lf_ops.pantallas(id,codigo,nombre,estado)
     VALUES(999992,'LF-PG18-SCREEN','B07 sandbox','ACTIVA');
     INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id)
     SELECT id,999992 FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-001';""")
   # Actual LF rule snapshot from SELECT; synthetic owner/RUN only inside isolated PG.
   real_code="B2B-RULE-AUTH-001"
   real_id=396
   real_run="EXEC-PROFILE-GATE2-B07REALRULE0396"
   real_patch={"rule_code":real_code,"change_kind":"DOCUMENTARY_ONLY",
     "changes":{"razon":"B07 prueba reversible PG: no persistir"}}
   PG18RealSQL.parent(real_run,real_patch)
   real_preimage=sql("SELECT public.lf_asset_snapshot_sha_v1('REGLA',"+q(real_code)+");")
   real_decision=PG18RealSQL.rule_record(real_run,rule=real_code)
   # A single outer transaction encloses official owner_decide -> skill -> V2 -> parent+child.
   metrics=lambda phase: """SELECT jsonb_build_object(
     'fase',"""+q(phase)+""",'padre_filas',(SELECT count(*) FROM lf_ops.reglas WHERE id=396),
     'hija_filas',(SELECT count(*) FROM lf_ops.reglas_versiones_b07 WHERE rule_id=396),
     'version_max',(SELECT max(version_no) FROM lf_ops.reglas_versiones_b07 WHERE rule_id=396),
     'razon',(SELECT razon FROM lf_ops.reglas WHERE id=396),
     'sha_padre',(SELECT encode(extensions.digest(convert_to(to_jsonb(r)::text,
        'UTF8'),'sha256'),'hex') FROM lf_ops.reglas r WHERE id=396))::text;"""
   statements="""BEGIN;\n"""+metrics("ANTES")+"""
     SET LOCAL ROLE service_role;
     SELECT public.lf_ig_rule_owner_decide_v2(
       """+q(real_run)+","+q(real_code)+","+q(real_preimage)+","+j(real_decision)+""")::text;
     RESET ROLE;
     """+metrics("DENTRO_TX")+"""
     ROLLBACK;"""
   tx_out=sql(statements,timeout=240).splitlines()
   self.assertEqual(len(tx_out),3,"B07_REAL_ROW_SQL_RECEIPTS_NOT_THREE:"+str(tx_out))
   pre_rec=json.loads(tx_out[0]); result_rec=json.loads(tx_out[1]); post_rec=json.loads(tx_out[2])
   final_rec=json.loads(sql(metrics("DESPUES_ROLLBACK")))
   self.assertEqual(result_rec.get("status"),"APPROVED_AND_VIGENTE_VERIFIED",str(result_rec))
   self.assertEqual((pre_rec["padre_filas"],pre_rec["hija_filas"],pre_rec["version_max"]),(1,1,1))
   self.assertEqual((post_rec["padre_filas"],post_rec["hija_filas"],post_rec["version_max"]),(1,2,2))
   self.assertEqual((final_rec["padre_filas"],final_rec["hija_filas"],final_rec["version_max"]),(1,1,1))
   self.assertEqual(pre_rec["sha_padre"],REAL_LF_ROW_SHA)
   self.assertNotEqual(post_rec["sha_padre"],REAL_LF_ROW_SHA)
   self.assertEqual(final_rec["sha_padre"],REAL_LF_ROW_SHA)
   self.assertEqual(sql("SELECT count(*) FROM public.lf_ig_owner_decision_v2 WHERE rule_code='B2B-RULE-AUTH-001';"),"0")
   self.assertEqual(sql(INVARIANT),"0")
   print("B07_LF_REAL_RULE_ROLLBACK_"+image.replace(":","_")+" "+json.dumps({
     "codigo":real_code,"id":real_id,"decision_status":result_rec["status"],
     "antes":pre_rec,"dentro_tx":post_rec,"despues_rollback":final_rec},
     sort_keys=True,ensure_ascii=False),flush=True)
   sql("""INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id)
     SELECT id,999992 FROM lf_ops.reglas WHERE codigo='LF-B07-TEST-0002';""")
   target="LF-B07-TEST-0002"
   execution="EXEC-PROFILE-GATE2-B07FINALIZER0002"
   patch={"rule_code":target,"change_kind":"DOCUMENTARY_ONLY",
      "changes":{"descripcion":"B07 V2 governed correction"}}
   initial=sql("SELECT public.lf_asset_snapshot_sha_v1('REGLA',"+q(target)+");")
   PG18RealSQL.parent(execution,patch)
   decision=json.loads(PG18RealSQL.owner_decide(execution,initial,rule=target).splitlines()[-1])
   self.assertEqual(decision.get("status"),"APPROVED_AND_VIGENTE_VERIFIED",str(decision))
   self.assertEqual(sql(INVARIANT),"0")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas_versiones_b07 WHERE rule_id=-90002;"),"2")
   child=decision["child_execution_id"]
   replay=json.loads(sql("SELECT public.lf_ig_rule_finalize_v2("+q(child)+")::text;"))
   self.assertTrue(replay.get("replay") is True,str(replay))
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas_versiones_b07 WHERE rule_id=-90002;"),"2")
   created="LF-B07-V2-CREATE-NEW"
   patchnew={"rule_code":created,"change_kind":"CREATE","changes":{
     "categoria":"TEST","titulo":"B07 LF new","descripcion":"New governed rule",
     "razon":"CI only","es_transversal":False,"valor_config":{},"origen":"B07_CI_ONLY"}}
   createpre=sql("SELECT encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||"+q(created)+",'UTF8'),'sha256'),'hex');")
   PG18RealSQL.parent("EXEC-PROFILE-GATE2-B07CREATE0003",patchnew)
   created_result=json.loads(PG18RealSQL.owner_decide("EXEC-PROFILE-GATE2-B07CREATE0003",createpre,rule=created).splitlines()[-1])
   self.assertEqual(created_result.get("status"),"APPROVED_AND_VIGENTE_VERIFIED",str(created_result))
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas_versiones_b07 WHERE rule_id=(SELECT id FROM lf_ops.reglas WHERE codigo="+q(created)+") AND version_no=1 AND origin='GOVERNED_APPEND';"),"1")
   self.assertEqual(sql(INVARIANT),"0")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO';"),"166")
   print("PASS_B07_LF_V2_CORRECT_CREATE_REPLAY_"+image.replace(":","_"),flush=True)
   parents_sha=sql(PARENTS); history_sha=sql(HISTORY)
   dump=subprocess.run(["docker","exec",cid,"pg_dump","-Fc","-U","postgres",
      "--no-owner","--no-privileges","-d","postgres"],capture_output=True,timeout=400)
   self.assertEqual(dump.returncode,0,dump.stderr.decode("utf-8","replace")[-2000:])
   archive_sha=hashlib.sha256(dump.stdout).hexdigest()
   sql("CREATE DATABASE lf_b07_restored;")
   restored=subprocess.run(["docker","exec","-i",cid,"pg_restore",
     "-U","postgres","--no-owner","--no-privileges","-d","lf_b07_restored"],
     input=dump.stdout,capture_output=True,timeout=420)
   self.assertEqual(restored.returncode,0,restored.stderr.decode("utf-8","replace")[-3000:])
   self.assertEqual(sql(PARENTS,dbname="lf_b07_restored"),parents_sha)
   self.assertEqual(sql(HISTORY,dbname="lf_b07_restored"),history_sha)
   self.assertEqual(sql(INVARIANT,dbname="lf_b07_restored"),"0")
   self.assertEqual(sql("SELECT to_regclass('saly.reglas_versiones_b07') IS NULL;",dbname="lf_b07_restored"),"t")
   print("PASS_B07_LF_DUMP_RESTORE_CI_"+image.replace(":","_")+" ARCHIVE_SHA="+archive_sha,flush=True)
  finally:
   subprocess.run(["docker","rm","-f",cid],capture_output=True,text=True,timeout=60)
 def test_pg17_6(self): self.run_pg("postgres:17.6","170006")
 def test_pg18_7(self): self.run_pg("postgres:18.7","180007")

if __name__=="__main__": unittest.main()
