#!/usr/bin/env python3
"""B07 PADRE/HIJA candidate: REAL isolated PG17.6 & PG18.7.

No production credentials, no Supabase writes, no real human signatures.
LF baseline is an existing live-object schema slice populated with 578
synthetic rules (412 VIGENTE + 166 CANDIDATO). SALY fixture has the
14 observed rule codes/states/decision IDs but SYNTHETIC rule bodies.
"""
from __future__ import annotations
import json
import hashlib
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
DIR=ROOT/"sandbox/lf_contract_gate_test/input_governance_lifecycle"
BASE=DIR/"pg18_live_object_slice_baseline.sql"
MIG=ROOT/"supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"
SALY=DIR/"b07_saly_14_rows_fixture.sql"
UP=DIR/"b07_parent_child_candidate_up.sql"
DOWN=DIR/"b07_parent_child_candidate_down.sql"
BRIDGE=DIR/"b07_parent_child_v2_finalizer_integration_candidate.sql"
SALY_WRITER=DIR/"b07_saly_official_writer_candidate_v1.sql"

def q(x):return "'"+str(x).replace("'","''")+"'"
def j(x):return q(json.dumps(x,separators=(',',':'),ensure_ascii=False))+"::jsonb"

PARENTS_SHA="""SELECT encode(extensions.digest(convert_to(
 jsonb_build_object(
  'lf',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.id),'[]'::jsonb)
          FROM lf_ops.reglas r),
  'saly',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.id),'[]'::jsonb)
          FROM saly.reglas r),
  'lf_cols',(SELECT count(*) FROM information_schema.columns
             WHERE table_schema='lf_ops' AND table_name='reglas'),
  'saly_cols',(SELECT count(*) FROM information_schema.columns
             WHERE table_schema='saly' AND table_name='reglas')
 )::text,'UTF8'),'sha256'),'hex');"""

INVARIANT="""SELECT
 (SELECT count(*) FROM lf_ops.reglas r WHERE
   to_jsonb(r) IS DISTINCT FROM
   (SELECT h.snapshot FROM lf_ops.reglas_versiones_b07 h
      WHERE h.rule_id=r.id ORDER BY h.version_no DESC LIMIT 1))
 +(SELECT count(*) FROM saly.reglas r WHERE
   to_jsonb(r) IS DISTINCT FROM
   (SELECT h.snapshot FROM saly.reglas_versiones_b07 h
      WHERE h.rule_id=r.id ORDER BY h.version_no DESC LIMIT 1));"""

class B07ParentChildPG(unittest.TestCase):
 def run_pg(self,image,version):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  for f in (BASE,MIG,SALY,UP,DOWN,BRIDGE,SALY_WRITER):self.assertTrue(f.is_file(),"SOURCE_MISSING "+str(f))
  cid="lf-b07-pc-"+uuid.uuid4().hex[:12]
  p=subprocess.run(["docker","run","-d","--rm","--name",cid,
    "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
    text=True,capture_output=True,timeout=240)
  self.assertEqual(p.returncode,0,p.stderr)
  try:
   def sql(statement,fail=None,timeout=420,dbname="postgres"):
    r=subprocess.run(["docker","exec","-i",cid,"psql","-X","-q","-t","-A",
      "-v","ON_ERROR_STOP=1","-U","postgres","-d",dbname],
      input=statement,capture_output=True,text=True,timeout=timeout)
    if fail:
     self.assertNotEqual(r.returncode,0,"NEGATIVE_DID_NOT_FAIL:"+fail)
     self.assertIn(fail,r.stderr[-4500:],r.stderr[-4500:])
     return r.stderr.strip()
    self.assertEqual(r.returncode,0,"SQL_FAILURE "+r.stderr[-4500:]+"\n"+statement[:700])
    return r.stdout.strip()
   for _ in range(80):
    r=subprocess.run(["docker","exec",cid,"pg_isready","-U","postgres","-d","postgres"],
      capture_output=True,text=True,timeout=10)
    if r.returncode==0:break
    time.sleep(1)
   else:self.fail("PG_NOT_READY")
   self.assertEqual(sql("SHOW server_version_num;").splitlines()[-1],version)

   sql(BASE.read_text(encoding="utf-8"))
   code="20261113030000_lf_ig_rule_lifecycle_writer_v2"
   target="supabase/migrations/"+code+".sql"
   repo="cristhianlujan/claude-persona-lf-patch"
   train_run_id="43379990001"
   train_execution="EXEC-DB-TRAIN-PR3803-20261113030000-R"+train_run_id
   manifest={"producer":"lf-migration-merge-train","pr":3803,
      "train_run_id":train_run_id,"head_sha":"e"*40,
      "router_authority_receipt":{
        "schema_version":"LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
        "operation_code":"ACTUALIZACION_DB_LF","target_repo":repo,
        "target_code":code,"target_path":target,
        "route_eligibility_only":True,"scope_attested":False}}
   sql(f"""INSERT INTO public.lf_operation_execution(
     execution_id,operation_code,target_type,target_code,target_repo,
     target_path,status,request_sha256,manifest,idempotency_key,created_by_execution_id)
     VALUES({q(train_execution)},'ACTUALIZACION_DB_LF','MIGRATION',
     {q(code)},{q(repo)},{q(target)},'IN_PROGRESS',{q('f'*64)},
     {j(manifest)},{q('train:20261113030000:'+'e'*40)},
     'LF-MIGRATION-TRAIN-RUN-43379990001');""")
   sql(MIG.read_text(encoding="utf-8"))
   self.assertEqual(sql("SELECT to_regprocedure('public.lf_ig_rule_finalize_v2(text)') IS NOT NULL;"),"t")
   # SALY test fixture also includes two LF samples; load before LF top-up.
   sql(SALY.read_text(encoding="utf-8"))
   # These are synthetic LF row values: not copies of personal/customer contents.
   sql("""DO $seed_lf$
      DECLARE have int; active int; pending int;
      BEGIN
        SELECT count(*),count(*) FILTER(WHERE estado='VIGENTE'),
         count(*) FILTER(WHERE estado='CANDIDATO')
        INTO have,active,pending FROM lf_ops.reglas;
        IF have>578 OR active>412 OR pending>166 OR have<>active+pending
        THEN RAISE EXCEPTION 'B07_LF_BASE_FIXTURE_UNEXPECTED_STATE'; END IF;
        INSERT INTO lf_ops.reglas(id,codigo,categoria,titulo,descripcion,estado)
        SELECT -90000-g, 'LF-B07-TEST-'||lpad(g::text,4,'0'), 'B07_FIXTURE',
         'Synthetic row '||g,'Synthetic content',
         CASE WHEN g<=412-active THEN 'VIGENTE' ELSE 'CANDIDATO' END
        FROM generate_series(1,578-have) AS g;
      END $seed_lf$;""")
   # SALY legacy decision rows reconstructed for isolated FK/receipt fixture.
   sql("""CREATE TABLE saly.decisiones (
        id bigint PRIMARY KEY, codigo text NOT NULL, estado text NOT NULL, vigente boolean NOT NULL DEFAULT true);
      INSERT INTO saly.decisiones(id,codigo,estado)
      SELECT DISTINCT decision_id, 'CI-SALY-DEC-'||decision_id,'VALIDADO'
      FROM saly.reglas WHERE decision_id IS NOT NULL;""")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas;"),"578")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE';"),"412")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas WHERE estado='VALIDADO';"),"14")
   first_sha=sql(PARENTS_SHA)
   self.assertEqual(len(first_sha),64)
   source=UP.read_text(encoding="utf-8")
   self.assertEqual(source.count("\nBEGIN;\n"),1)
   self.assertEqual(source.count("\nCOMMIT;\n"),1)
   inner=source.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
   sql("BEGIN;\n"+inner+"\nROLLBACK;",timeout=420)
   self.assertEqual(first_sha,sql(PARENTS_SHA),"PRECOMMIT_ROLLBACK_CHANGED_PARENT")
   self.assertEqual(sql("SELECT to_regclass('lf_ops.reglas_versiones_b07') IS NULL;"),"t")
   self.assertEqual(sql("SELECT to_regclass('saly.reglas_versiones_b07') IS NULL;"),"t")
   print("PASS_B07_PRECOMMIT_ROLLBACK_"+image.replace(":","_")+" SHA="+first_sha,flush=True)

   sql(source,timeout=420)
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas_versiones_b07;"),"578")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas_versiones_b07;"),"14")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas_versiones_b07 WHERE origin='BASELINE_CURRENT_ONLY' AND decisor IS NULL;"),"578")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas_versiones_b07 WHERE origin='BASELINE_CURRENT_ONLY' AND decisor IS NULL;"),"14")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas WHERE estado='VALIDADO';"),"14")
   self.assertEqual(sql(INVARIANT),"0")
   self.assertEqual(sql("""SELECT count(*) FROM information_schema.columns
     WHERE (table_schema='lf_ops' AND table_name='reglas'
       OR table_schema='saly' AND table_name='reglas')
       AND column_name LIKE 'lifecycle_%';"""),"0")
   self.assertEqual(first_sha,sql(PARENTS_SHA),"BACKFILL_CHANGED_PARENT")
   print("PASS_B07_BASELINE_BACKFILL_578_LF_14_SALY_"+image.replace(":","_"),flush=True)

   # Reject forged, stale or unlinked writes; tests only, no real human receipt.
   lf_code="LF-B07-TEST-0001"; saly_code="SALY-RGL-001"
   lf_first=sql("SELECT snapshot_sha256 FROM lf_ops.reglas_versiones_b07 WHERE rule_id=-90001;")
   saly_first=sql("SELECT snapshot_sha256 FROM saly.reglas_versiones_b07 WHERE rule_id=1;")
   sql("""BEGIN; UPDATE lf_ops.reglas SET titulo='NON_GOVERNED_CHANGE'
      WHERE codigo='LF-B07-TEST-0001'; COMMIT;""",fail="B07_PARENT_LATEST_MISMATCH")
   self.assertEqual(sql(INVARIANT),"0")
   sql("""BEGIN; UPDATE saly.reglas SET titulo='NON_GOVERNED_CHANGE'
      WHERE codigo='SALY-RGL-001'; COMMIT;""",fail="B07_PARENT_LATEST_MISMATCH")
   self.assertEqual(sql(INVARIANT),"0")

   # Even service_role direct DML or anon RPC invocation cannot bypass.
   sql("""BEGIN; SET LOCAL ROLE anon;
     SELECT public.lf_b07_append_version_candidate_v1(
      'LF','LF-B07-TEST-0001',repeat('0',64),'x','fake',repeat('a',64),
      now(),'EXEC-TEST'); ROLLBACK;""",fail="permission denied for function")
   sql(f"""SELECT public.lf_b07_append_version_candidate_v1(
     'LF',{q(lf_code)},{q('0'*64)},'x','fake',{q('a'*64)},
     now(),'EXEC-TEST');""",fail="B07_LF_OWNER_DECISION_RECEIPT_MISSING")

   # Documentary-only fake receipt is inserted ONLY inside a disposable PG DB.
   # It is explicitly NOT an authenticated human decision.
   doc_id=sql(f"""INSERT INTO public.lf_ig_owner_decision_v2(
     project_code,owner_sub,decisor,proponente,decision_date,literal_phrase,
     decision_record,decision_record_sha256,identity_mode,parent_execution_id,
     rule_code,kind,source_sha256,proposal_sha256,verdict,approved_patch)
     VALUES('LF',
      (SELECT owner_sub FROM public.lf_ig_project_owner_v2 WHERE project_code='LF'),
      'Cristhian Luján','CI_MACHINE_ONLY',now(),'CI SYNTHETIC NOT APPROVED',
      '{{}}'::jsonb,repeat('a',64),'UNVERIFIED_CHAT_DECLARATION',
      'EXEC-CI-B07-ONLY', {q(lf_code)},'CORRECT_VIGENTE',repeat('b',64),
      repeat('c',64),'APROBAR','{{}}'::jsonb)
     RETURNING decision_id;""").splitlines()[-1]
   self.assertEqual(len(doc_id),36)
   sql(f"""SELECT public.lf_b07_append_version_candidate_v1(
     'LF',{q(lf_code)},{q('0'*64)},{q(doc_id)},
     'Cristhian Luján',repeat('a',64),now(),'EXEC-CI-ONLY');""",
     fail="B07_STALE_PARENT_HASH")
   sql(f"""SELECT public.lf_b07_append_version_candidate_v1(
     'LF',{q(lf_code)},{q(lf_first)},{q(doc_id)},
     'Cristhian Luján','bad-hash',now(),'EXEC-CI-ONLY');""",
     fail="B07_DECISION_EVIDENCE_INCOMPLETE")

   # Two parent changes and version appends in the *same transaction*.
   # The production V2 finalizer must eventually call this hook atomically.
   lf_action=f"""BEGIN;
      UPDATE lf_ops.reglas SET titulo='CI governed replacement' WHERE codigo={q(lf_code)};
      SET LOCAL ROLE service_role;
      SELECT public.lf_b07_append_version_candidate_v1(
        'LF',{q(lf_code)},{q(lf_first)},{q(doc_id)},
        'Cristhian Luján',repeat('a',64),now(),'EXEC-CI-ONLY');
      RESET ROLE; COMMIT;"""
   sql(lf_action)
   saly_action=f"""BEGIN;
      UPDATE saly.reglas SET titulo='CI governed replacement' WHERE codigo={q(saly_code)};
      SET LOCAL ROLE service_role;
      SELECT public.lf_b07_append_version_candidate_v1(
        'SALY',{q(saly_code)},{q(saly_first)},'51',
        'CI_UNVERIFIED_DECISOR',repeat('d',64),now(),'EXEC-CI-ONLY');
      RESET ROLE; COMMIT;"""
   sql(saly_action)
   self.assertEqual(sql(INVARIANT),"0")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas_versiones_b07;"),"579")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas_versiones_b07;"),"15")
   self.assertEqual(sql("SELECT estado FROM saly.reglas WHERE codigo='SALY-RGL-001';"),"VALIDADO")
   self.assertEqual(sql("""SELECT count(*) FROM lf_ops.reglas_versiones_b07
     WHERE origin='GOVERNED_APPEND' AND previous_sha256 IS NOT NULL
       AND identity_verified=false;"""),"1")
   sql(f"""SELECT public.lf_b07_append_version_candidate_v1(
     'LF',{q(lf_code)},{q(lf_first)},{q(doc_id)},
     'Cristhian Luján',repeat('a',64),now(),'EXEC-CI-ONLY');""",
     fail="B07_STALE_PARENT_HASH")
   sql("""UPDATE lf_ops.reglas_versiones_b07 SET snapshot='{}'::jsonb
     WHERE version_no=1;""",fail="B07_HISTORY_IMMUTABLE")
   sql("""DELETE FROM saly.reglas_versiones_b07 WHERE version_no=1;""",
      fail="B07_HISTORY_IMMUTABLE")
   sql("""TRUNCATE saly.reglas_versiones_b07;""",
      fail="B07_HISTORY_TRUNCATE_BLOCKED")
   sql(DOWN.read_text(encoding="utf-8"),fail="B07_DOWN_HISTORY_ROWS_PRESENT")
   self.assertEqual(sql(INVARIANT),"0")
   print("PASS_B07_ATOMIC_PARENT_CHILD_AND_NEGATIVE_GATES_"+image.replace(":","_"),flush=True)
   print("PASS_B07_DOWN_FAIL_CLOSED_WITH_HISTORY_"+image.replace(":","_"),flush=True)
   # Official LF V2 bridge only: candidate helper cannot be called directly
   # by service_role after this step. Child writes occur inside V2 FINALIZE.
   sql(BRIDGE.read_text(encoding="utf-8"))
   self.assertEqual(sql("""SELECT strpos(pg_get_functiondef(
     'public.lf_ig_rule_finalize_v2(text)'::regprocedure),
     'PERFORM public.lf_b07_append_after_finalize_v1(p_child);')>0;"""),"t")
   sql("""BEGIN; SET LOCAL ROLE service_role;
     SELECT public.lf_b07_append_version_candidate_v1(
       'LF','LF-B07-TEST-0001',repeat('a',64),'x','fake',repeat('a',64),
       now(),'EXEC-DIRECT'); ROLLBACK;""",fail="permission denied for function")
   self.assertEqual(sql("""SELECT has_function_privilege('service_role',
      'public.lf_b07_append_after_finalize_v1(text)','EXECUTE');"""),"f")
   self.assertEqual(sql("""SELECT count(*) FROM public.lf_b07_rules_current_v1;"""),"412")
   self.assertEqual(sql("""SELECT count(*) FROM public.saly_b07_rules_current_v1;"""),"14")
   self.assertEqual(sql("""SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO';"""),"166")
   sql("""BEGIN; SET LOCAL ROLE anon;
      SELECT count(*) FROM public.lf_b07_rules_current_v1; ROLLBACK;""",
      fail="permission denied for view")
   sql("""BEGIN; SET LOCAL ROLE service_role;
      SELECT count(*) FROM public.lf_b07_rules_current_v1;
      SELECT count(*) FROM public.saly_b07_rules_current_v1;
      SELECT count(*) FROM lf_ops.reglas_versiones_b07; ROLLBACK;""")
   sql("""BEGIN; SET LOCAL ROLE service_role;
      DELETE FROM lf_ops.reglas_versiones_b07 WHERE version_no=1; ROLLBACK;""",
      fail="permission denied for table")
   print("PASS_B07_PERMISSIONS_RLS_AND_EFFECTIVE_CONSUMERS_"+image.replace(":","_"),flush=True)

   # Invoke GENUINE V2 owner_decide → skill → child 7-step → V2 finalize.
   # All authority receipts and profiles in this CI database are synthetic,
   # NOT real owner signatures or live model invocations.
   from test_ig_rule_lifecycle_pg18 import PG18RealSQL
   PG18RealSQL.docker=cid
   target_code="LF-B07-TEST-0002"
   execution="EXEC-PROFILE-GATE2-B07FINALIZER0002"
   sql("""INSERT INTO lf_ops.pantallas(id,codigo,nombre,estado)
       VALUES(999992,'LF-PG18-SCREEN','B07 sandbox','ACTIVA');
       INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id)
       SELECT id,999992 FROM lf_ops.reglas
       WHERE codigo='LF-B07-TEST-0002';""")
   patch={"rule_code":target_code,"change_kind":"DOCUMENTARY_ONLY",
      "changes":{"descripcion":"B07 V2 official governed correction"}}
   before_versions=sql("""SELECT count(*) FROM lf_ops.reglas_versiones_b07
       WHERE rule_id=(SELECT id FROM lf_ops.reglas WHERE codigo='LF-B07-TEST-0002');""")
   self.assertEqual(before_versions,"1")
   original_hash=sql("SELECT public.lf_asset_snapshot_sha_v1('REGLA',"+q(target_code)+");")
   self.assertEqual(len(original_hash),64)
   PG18RealSQL.parent(execution,patch)
   decision=json.loads(PG18RealSQL.owner_decide(execution,original_hash,
      rule=target_code).splitlines()[-1])
   self.assertEqual(decision.get("status"),"APPROVED_AND_VIGENTE_VERIFIED",str(decision))
   self.assertEqual(sql(INVARIANT),"0")
   self.assertEqual(sql("""SELECT count(*) FROM lf_ops.reglas_versiones_b07
      WHERE rule_id=(SELECT id FROM lf_ops.reglas WHERE codigo='LF-B07-TEST-0002');"""),"2")
   child=decision["child_execution_id"]
   replay=json.loads(sql("SELECT public.lf_ig_rule_finalize_v2("+q(child)+")::text;"))
   self.assertTrue(replay.get("replay") is True,str(replay))
   self.assertEqual(sql("""SELECT count(*) FROM lf_ops.reglas_versiones_b07
      WHERE rule_id=(SELECT id FROM lf_ops.reglas WHERE codigo='LF-B07-TEST-0002');"""),"2")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO';"),"166")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas WHERE estado='VALIDADO';"),"14")
   sql("""BEGIN; UPDATE lf_ops.reglas SET descripcion='UNAUTHORIZED'
      WHERE codigo='LF-B07-TEST-0002'; COMMIT;""",fail="B07_PARENT_LATEST_MISMATCH")
   self.assertEqual(sql(INVARIANT),"0")
   print("PASS_B07_REAL_V2_FINALIZER_ATOMIC_APPEND_AND_REPLAY_"+image.replace(":","_"),flush=True)

   # Additional real V2 channels: CREATE and approved CANDIDATO -> VIGENTE.
   # Neither must promote or alter the 166 existing candidates.
   created_code="LF-B07-V2-CREATE-NEW"
   created_parent="EXEC-PROFILE-GATE2-B07CREATE0003"
   created_patch={"rule_code":created_code,"change_kind":"CREATE","changes":{
      "categoria":"TEST","titulo":"B07 prueba alta V2",
      "descripcion":"Nueva regla gobernada por V2, PG aislado",
      "razon":"B07 prueba adicional","es_transversal":False,
      "valor_config":{},"origen":"B07_CI_ONLY"}}
   create_pre=sql("SELECT encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||"+
       q(created_code)+",'UTF8'),'sha256'),'hex');")
   PG18RealSQL.parent(created_parent,created_patch)
   created_result=json.loads(PG18RealSQL.owner_decide(created_parent,create_pre,
      rule=created_code).splitlines()[-1])
   self.assertEqual(created_result.get("status"),"APPROVED_AND_VIGENTE_VERIFIED",str(created_result))
   self.assertEqual(sql("SELECT estado FROM lf_ops.reglas WHERE codigo="+q(created_code)+";"),"VIGENTE")
   self.assertEqual(sql("""SELECT count(*) FROM lf_ops.reglas_versiones_b07
      WHERE rule_id=(SELECT id FROM lf_ops.reglas WHERE codigo='LF-B07-V2-CREATE-NEW')
      AND version_no=1 AND previous_sha256 IS NULL
      AND origin='GOVERNED_APPEND' AND decision_ref IS NOT NULL;"""),"1")
   self.assertEqual(sql(INVARIANT),"0")
   print("PASS_B07_OFFICIAL_V2_CREATE_NEW_RULE_WITH_VERSION_1_"+image.replace(":","_"),flush=True)

   candidate_code="LF-B07-V2-CANDIDATE-NEW"
   candidate_parent="EXEC-PROFILE-GATE2-B07CAND0004"
   sql("""BEGIN;
      INSERT INTO lf_ops.reglas(codigo,categoria,titulo,descripcion,estado,
        pendiente_decision,es_transversal,created_by)
      VALUES('LF-B07-V2-CANDIDATE-NEW','B07_TEST','Candidata nueva B07',
        'Candidato aislado','CANDIDATO',true,false,
        'EXEC-PROFILE-GATE2-B07CAND0004');
      INSERT INTO lf_ops.reglas_versiones_b07(rule_id,version_no,snapshot,snapshot_sha256,origin)
      SELECT r.id,1,to_jsonb(r),
       encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex'),
       'BASELINE_CURRENT_ONLY'
      FROM lf_ops.reglas r WHERE codigo='LF-B07-V2-CANDIDATE-NEW';
      INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id)
      SELECT id,999992 FROM lf_ops.reglas WHERE codigo='LF-B07-V2-CANDIDATE-NEW';
      COMMIT;""")
   candidate_pre=sql("SELECT public.lf_asset_snapshot_sha_v1('REGLA',"+q(candidate_code)+");")
   candidate_patch={"rule_code":candidate_code,"change_kind":"DOCUMENTARY_ONLY",
      "changes":{"descripcion":"Candidata nueva promovida tras decisión V2"}}
   PG18RealSQL.parent(candidate_parent,candidate_patch)
   candidate_result=json.loads(PG18RealSQL.owner_decide(candidate_parent,candidate_pre,
      rule=candidate_code).splitlines()[-1])
   self.assertEqual(candidate_result.get("status"),"APPROVED_AND_VIGENTE_VERIFIED",
       str(candidate_result))
   self.assertEqual(sql("SELECT estado FROM lf_ops.reglas WHERE codigo="+q(candidate_code)+";"),"VIGENTE")
   self.assertEqual(sql("""SELECT count(*) FROM lf_ops.reglas_versiones_b07
      WHERE rule_id=(SELECT id FROM lf_ops.reglas WHERE codigo='LF-B07-V2-CANDIDATE-NEW');"""),"2")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO';"),"166")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas WHERE estado='VALIDADO';"),"14")
   self.assertEqual(sql(INVARIANT),"0")
   print("PASS_B07_OFFICIAL_V2_CANDIDATE_PROMOTION_WITH_HISTORY_"+image.replace(":","_"),flush=True)

   # Native SALY candidate: provenance bootstrapped ONLY in a disposable PG DB.
   # Neither the SALY owner nor ACTUALIZACION_REGLA_SALY is live today.
   sql(SALY_WRITER.read_text(encoding="utf-8"))
   self.assertEqual(sql("""SELECT has_function_privilege('authenticated',
      'public.lf_ig_saly_rule_finalize_b07_v1(text)','EXECUTE');"""),"f")
   self.assertEqual(sql("""SELECT has_function_privilege('service_role',
      'public.lf_ig_saly_rule_finalize_b07_v1(text)','EXECUTE');"""),"t")
   self.assertEqual(sql("""SELECT has_table_privilege('service_role',
      'saly.reglas_versiones_b07','INSERT');"""),"f")
   sql("""BEGIN; SET LOCAL ROLE authenticated;
      SELECT public.lf_ig_saly_rule_finalize_b07_v1('NO_CHILD'); COMMIT;""",
      fail="permission denied for function")
   sql("""INSERT INTO public.lf_operation_execution(
      execution_id,operation_code,target_type,target_code,status,
      manifest,created_by_execution_id)
      VALUES('EXEC-B07-SALY-BOOT','VULNERABILITY_COVERAGE_REPAIR_LF',
      'OPERATION','ACTUALIZACION_REGLA_SALY','IN_PROGRESS',
      '{"governance_bootstrap":true,"bootstrap_operation_code":"ACTUALIZACION_REGLA_SALY",
      "bootstrap_status_ceiling":"SANDBOX_ACTIVE"}'::jsonb,'EXEC-B07-SALY-BOOT');""")
   sql("""INSERT INTO public.lf_operation_registry(
      operation_code,version,status,source_model,source_repo,source_paths,
      lifecycle_state_code,created_by_execution_id)
      VALUES('ACTUALIZACION_REGLA_SALY','v0.1','SANDBOX_ACTIVE',
      'GIT_FIRST_YAML','cristhianlujan/claude-persona-lf-patch',
      '[]'::jsonb,'OP_CANDIDATE','EXEC-B07-SALY-BOOT');""")
   sql("""INSERT INTO public.lf_ig_project_owner_v2(
      project_code,owner_sub,owner_name,owner_profile_code,
      authority_receipt_sha256,status,source_execution_id)
      VALUES('SALY','00000000-0000-4000-8000-000000000111',
      'Cristhian Luján','PERFIL-PRODUCT-DIRECTOR-LF',
      repeat('f',64),'TEMP_DOCUMENTARY_ACTIVE','EXEC-B07-SALY-BOOT');""")
   sp="EXEC-PROFILE-GATE2-B07SALYPARENT0001"
   sc="EXEC-B07-SALY-CHILD-0001"
   code="SALY-RGL-002"
   PG18RealSQL.parent(sp,{"rule_code":code,"change_kind":"DOCUMENTARY_ONLY",
      "changes":{"titulo":"Synthetic SALY proposal"}})
   sql("UPDATE public.lf_operation_execution SET manifest=manifest||"+
       j({"project_code":"SALY"})+" WHERE execution_id="+q(sp)+";")
   sql(f"""INSERT INTO public.lf_operation_execution(
      execution_id,operation_code,target_type,target_code,status,
      created_by_execution_id)
      VALUES({q(sc)},'ACTUALIZACION_REGLA_SALY','REGLA',
      {q(code)},'COMPLETED',{q(sp)});""")
   sql(f"""INSERT INTO public.lf_operation_execution_steps(
      execution_id,step_order,step_id,status,evidence_payload,
      created_by_execution_id)
      SELECT {q(sc)},g,'governed_step_'||g,'PASS_CLEAN',
      jsonb_build_object('proof','CI_ONLY_SYNTHETIC','step',g),
      {q(sc)} FROM generate_series(1,7) AS g;""")
   sql(f"""BEGIN; SET LOCAL ROLE service_role;
      SELECT public.lf_ig_saly_rule_finalize_b07_v1({q(sc)}); COMMIT;""",
      fail="B07_SALY_V2_OWNER_DECISION_REQUIRED")
   src=sql("""SELECT snapshot_sha256 FROM saly.reglas_versiones_b07
      WHERE rule_id=2 ORDER BY version_no DESC LIMIT 1;""")
   doc={"saly_decision_id":"53","rule_code":code,"source_sha256":src}
   patch={"change_kind":"DOCUMENTARY_ONLY",
          "changes":{"titulo":"SALY versionada por escritor oficial CI"}}
   sql(f"""INSERT INTO public.lf_ig_owner_decision_v2(
      project_code,owner_sub,decisor,proponente,decision_date,
      literal_phrase,decision_record,decision_record_sha256,identity_mode,
      parent_execution_id,rule_code,kind,source_sha256,proposal_sha256,
      verdict,approved_patch)
      VALUES('SALY','00000000-0000-4000-8000-000000000111',
      'Cristhian Luján','CI_SALY_ARCHITECT',now(),
      'CI_ONLY_APPROVAL_DOCUMENTARY_UNVERIFIED',{j(doc)},
      encode(extensions.digest(convert_to({j(doc)}::text,'UTF8'),'sha256'),'hex'),
      'UNVERIFIED_CHAT_DECLARATION',{q(sp)},{q(code)},'CORRECT_VIGENTE',
      {q(src)},
      encode(extensions.digest(convert_to({j(patch)}::text,'UTF8'),'sha256'),'hex'),
      'APROBAR',{j(patch)});""")
   did=sql("""SELECT decision_id FROM public.lf_ig_owner_decision_v2
      WHERE project_code='SALY' AND rule_code='SALY-RGL-002';""")
   self.assertEqual(len(did),36)
   wrong_doc={"saly_decision_id":"53","rule_code":code,"source_sha256":"0"*64}
   sql(f"""BEGIN;
      UPDATE public.lf_ig_owner_decision_v2 SET source_sha256=repeat('0',64),
      decision_record={j(wrong_doc)},
      decision_record_sha256=encode(extensions.digest(convert_to(
      {j(wrong_doc)}::text,'UTF8'),'sha256'),'hex')
      WHERE decision_id={q(did)}::uuid;
      SET LOCAL ROLE service_role;
      SELECT public.lf_ig_saly_rule_finalize_b07_v1({q(sc)}); COMMIT;""",
      fail="B07_SALY_STALE_PARENT_HASH")
   sql(f"""BEGIN;
      UPDATE public.lf_ig_owner_decision_v2 SET decision_record_sha256=repeat('0',64)
      WHERE decision_id={q(did)}::uuid;
      SET LOCAL ROLE service_role;
      SELECT public.lf_ig_saly_rule_finalize_b07_v1({q(sc)}); COMMIT;""",
      fail="B07_SALY_DECISION_EVIDENCE_INCOMPLETE")
   badpatch={"change_kind":"DOCUMENTARY_ONLY","changes":{"estado":"VIGENTE"}}
   sql(f"""BEGIN;
      UPDATE public.lf_ig_owner_decision_v2 SET approved_patch={j(badpatch)},
      proposal_sha256=encode(extensions.digest(convert_to(
      {j(badpatch)}::text,'UTF8'),'sha256'),'hex')
      WHERE decision_id={q(did)}::uuid;
      SET LOCAL ROLE service_role;
      SELECT public.lf_ig_saly_rule_finalize_b07_v1({q(sc)}); COMMIT;""",
      fail="B07_SALY_DOCUMENTARY_ONLY_SCOPE")
   pre=sql(PARENTS_SHA)
   sql(f"""BEGIN; SET LOCAL ROLE service_role;
      SELECT public.lf_ig_saly_rule_finalize_b07_v1({q(sc)})::text;
      ROLLBACK;""")
   self.assertEqual(sql(PARENTS_SHA),pre)
   self.assertEqual(sql("SELECT count(*) FROM public.lf_b07_saly_finalization_receipt_v1;"),"0")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas_versiones_b07 WHERE rule_id=2;"),"1")
   answer=json.loads(sql(f"""BEGIN; SET LOCAL ROLE service_role;
      SELECT public.lf_ig_saly_rule_finalize_b07_v1({q(sc)})::text;
      COMMIT;""").splitlines()[-1])
   self.assertEqual(answer["status"],"VALIDADO_VERIFIED",str(answer))
   self.assertFalse(answer["identity_verified"])
   self.assertFalse(answer["replay"])
   self.assertEqual(sql(INVARIANT),"0")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas WHERE estado='VALIDADO';"),"14")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas_versiones_b07 WHERE rule_id=2;"),"2")
   self.assertEqual(sql("SELECT count(*) FROM public.lf_b07_saly_finalization_receipt_v1;"),"1")
   replay=json.loads(sql(f"""BEGIN; SET LOCAL ROLE service_role;
      SELECT public.lf_ig_saly_rule_finalize_b07_v1({q(sc)})::text;
      COMMIT;""").splitlines()[-1])
   self.assertTrue(replay["replay"])
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas_versiones_b07 WHERE rule_id=2;"),"2")
   sql("""BEGIN; SET LOCAL ROLE service_role;
      INSERT INTO saly.reglas_versiones_b07(rule_id,version_no,snapshot,
      snapshot_sha256,origin) VALUES(2,99,'{}'::jsonb,repeat('a',64),
      'BASELINE_CURRENT_ONLY'); COMMIT;""",fail="permission denied for schema saly")
   sql("""BEGIN; UPDATE saly.reglas SET estado='VIGENTE'
      WHERE codigo='SALY-RGL-002'; COMMIT;""",fail="B07_PARENT_LATEST_MISMATCH")
   self.assertEqual(sql("SELECT estado FROM saly.reglas WHERE codigo='SALY-RGL-002';"),"VALIDADO")
   print("PASS_B07_SALY_WRITER_GOVERNED_ATOMIC_ROLLBACK_HASH_EVIDENCE_REPLAY_"+image.replace(":","_"),flush=True)

   # Real PostgreSQL physical backup/restore AFTER migration AND committed
   # history data. No deleting history to game fail-closed DOWN.
   history_digest="""SELECT encode(extensions.digest(convert_to(
      jsonb_build_object(
       'lf',(SELECT jsonb_agg(to_jsonb(h) ORDER BY version_id)
           FROM lf_ops.reglas_versiones_b07 h),
       'saly',(SELECT jsonb_agg(to_jsonb(h) ORDER BY version_id)
           FROM saly.reglas_versiones_b07 h))::text,
      'UTF8'),'sha256'),'hex');"""
   snapshot_sha=sql(PARENTS_SHA)
   history_sha=sql(history_digest)
   dump=subprocess.run(["docker","exec",cid,"pg_dump","-Fc","-U","postgres",
      "--no-owner","--no-privileges","-d","postgres"],
      capture_output=True,timeout=400)
   self.assertEqual(dump.returncode,0,dump.stderr.decode("utf-8","replace")[-2500:])
   self.assertGreater(len(dump.stdout),1000)
   dump_sha=hashlib.sha256(dump.stdout).hexdigest()
   sql("CREATE DATABASE b07_restored;")
   restored=subprocess.run(["docker","exec","-i",cid,"pg_restore",
      "-U","postgres","--no-owner","--no-privileges","-d","b07_restored"],
      input=dump.stdout,capture_output=True,timeout=420)
   self.assertEqual(restored.returncode,0,restored.stderr.decode("utf-8","replace")[-4000:])
   self.assertEqual(sql(PARENTS_SHA,dbname="b07_restored"),snapshot_sha)
   self.assertEqual(sql(history_digest,dbname="b07_restored"),history_sha)
   self.assertEqual(sql(INVARIANT,dbname="b07_restored"),"0")
   self.assertEqual(sql("SELECT count(*) FROM public.lf_b07_saly_finalization_receipt_v1;",dbname="b07_restored"),"1")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas_versiones_b07;",dbname="b07_restored"),"583")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas_versiones_b07;",dbname="b07_restored"),"16")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas WHERE estado='VALIDADO';",dbname="b07_restored"),"14")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO';",dbname="b07_restored"),"166")
   self.assertEqual(sql("""SELECT strpos(pg_get_functiondef(
     'public.lf_ig_rule_finalize_v2(text)'::regprocedure),
     'PERFORM public.lf_b07_append_after_finalize_v1(p_child);')>0;""",
      dbname="b07_restored"),"t")
   sql("""BEGIN; UPDATE saly.reglas SET titulo='WRONG'
      WHERE codigo='SALY-RGL-001'; COMMIT;""",
      fail="B07_PARENT_LATEST_MISMATCH",dbname="b07_restored")
   print("PASS_B07_PG_DUMP_RESTORE_POST_COMMITTED_HISTORY_"+image.replace(":","_")+
       " PARENTS_SHA="+snapshot_sha+" HISTORY_SHA="+history_sha+
       " ARCHIVE_SHA="+dump_sha,flush=True)
   print("B07_SALY_OFFICIAL_WRITER_NOT_YET_INSTALLED_NO_LIVE_DEPLOY",flush=True)

  finally:
   subprocess.run(["docker","rm","-f",cid],text=True,capture_output=True,timeout=90)
 def test_pg17_6(self): self.run_pg("postgres:17.6","170006")
 def test_pg18_7(self): self.run_pg("postgres:18.7","180007")
if __name__=="__main__":unittest.main()
