#!/usr/bin/env python3
"""B07 official single-file Train candidate: isolated PostgreSQL 17.6 / 18.7.
Only synthetic SALY op/owner/profile. NEVER a Supabase/Auth registration.
"""
from __future__ import annotations
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DIR = ROOT / "sandbox/lf_contract_gate_test/input_governance_lifecycle"
BASE = DIR / "pg18_live_object_slice_baseline.sql"
V2 = ROOT / "supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"
SALY = DIR / "b07_saly_14_rows_fixture.sql"
B07 = ROOT / "supabase/migrations/20261113180000_lf_ig_b07_parent_child_atomic_v1.sql"

def q(v):
    return "'" + str(v).replace("'", "''") + "'"

def j(v):
    return q(json.dumps(v, separators=(",", ":"))) + "::jsonb"

class B07OfficialAtomicTrainTest(unittest.TestCase):
    def verify(self, image, pg_num):
        self.assertIsNotNone(shutil.which("docker"), "DOCKER_REQUIRED")
        for p in (BASE,V2,SALY,B07):
            self.assertTrue(p.is_file(), "B07_SOURCE_MISSING:" + str(p))
        src=B07.read_text(encoding="utf-8")
        self.assertEqual(src.count("\nBEGIN;\n"),1,"B07_ATOMIC_BEGIN_COUNT")
        self.assertEqual(src.count("\nCOMMIT;\n"),1,"B07_ATOMIC_COMMIT_COUNT")
        self.assertIn("B07_SALY_OFFICIAL_OPERATION_NOT_REGISTERED",src)
        self.assertIn("B07_SALY_OWNER_AND_PROFILE_GOVERNED_REQUIRED",src)
        cid="lf-b07-atomic-"+uuid.uuid4().hex[:12]
        start=subprocess.run(["docker","run","-d","--rm","--name",cid,
          "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
          capture_output=True,text=True,timeout=240)
        self.assertEqual(start.returncode,0,start.stderr)
        try:
            def sql(s,fail=None,timeout=420):
                res=subprocess.run(["docker","exec","-i",cid,"psql","-X","-q","-t","-A",
                  "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                  input=s,capture_output=True,text=True,timeout=timeout)
                if fail:
                    self.assertNotEqual(res.returncode,0,"NEGATIVE_ACCEPTED:"+fail)
                    self.assertIn(fail,res.stderr[-5000:],res.stderr[-5000:])
                    return res.stderr.strip()
                self.assertEqual(res.returncode,0,"SQL_FAILURE:"+res.stderr[-5000:])
                return res.stdout.strip()
            for _ in range(90):
                ready=subprocess.run(["docker","exec",cid,"pg_isready","-U","postgres","-d","postgres"],capture_output=True,text=True,timeout=10)
                if ready.returncode==0: break
                time.sleep(1)
            else: self.fail("PG_NOT_READY")
            self.assertEqual(sql("SHOW server_version_num;"),pg_num)
            sql(BASE.read_text(encoding="utf-8"))
            code="20261113030000_lf_ig_rule_lifecycle_writer_v2"
            train_id="43379990001"
            train_execution="EXEC-DB-TRAIN-PR3803-20261113030000-R"+train_id
            manifest={"producer":"lf-migration-merge-train","pr":3803,
              "train_run_id":train_id,"head_sha":"e"*40,
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
                VALUES({q(train_execution)},'ACTUALIZACION_DB_LF','MIGRATION',
                {q(code)},'cristhianlujan/claude-persona-lf-patch',
                {q("supabase/migrations/"+code+".sql")},'IN_PROGRESS',{q("f"*64)},
                {j(manifest)},{q("train:20261113030000:"+"e"*40)},
                'LF-MIGRATION-TRAIN-RUN-43379990001');""")
            sql(V2.read_text(encoding="utf-8"))
            sql(SALY.read_text(encoding="utf-8"))
            sql("""DO $seed$
            DECLARE have int; active int; pending int;
            BEGIN
              SELECT count(*),count(*) FILTER(WHERE estado='VIGENTE'),
                count(*) FILTER(WHERE estado='CANDIDATO')
                INTO have,active,pending FROM lf_ops.reglas;
              IF have>578 OR active>412 OR pending>166 OR have<>active+pending
              THEN RAISE EXCEPTION 'B07_ATOMIC_BASELINE_MISMATCH'; END IF;
              INSERT INTO lf_ops.reglas(id,codigo,categoria,titulo,descripcion,estado)
              SELECT -90000-g, 'LF-B07-TEST-'||lpad(g::text,4,'0'),
                'B07_FIXTURE','Synthetic row '||g,'Synthetic content',
                CASE WHEN g<=412-active THEN 'VIGENTE' ELSE 'CANDIDATO' END
              FROM generate_series(1,578-have) g;
            END $seed$;""")
            sql("""CREATE TABLE saly.decisiones (
               id bigint PRIMARY KEY,codigo text NOT NULL,estado text NOT NULL,
               vigente boolean NOT NULL DEFAULT true);
               INSERT INTO saly.decisiones(id,codigo,estado)
               SELECT DISTINCT decision_id,'CI-SALY-DEC-'||decision_id,'VALIDADO'
               FROM saly.reglas WHERE decision_id IS NOT NULL;""")
            self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas;"),"578")
            self.assertEqual(sql("SELECT count(*) FROM saly.reglas WHERE estado='VALIDADO';"),"14")
            before=sql("""SELECT encode(extensions.digest(convert_to(
              jsonb_build_object('lf',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM lf_ops.reglas x),
              'saly',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM saly.reglas x))::text,
              'UTF8'),'sha256'),'hex');""")
            sql(src,fail="B07_SALY_OFFICIAL_OPERATION_NOT_REGISTERED")
            self.assertEqual(sql("SELECT to_regclass('lf_ops.reglas_versiones_b07') IS NULL;"),"t")
            sql("""INSERT INTO public.lf_operation_execution(
                execution_id,operation_code,target_type,target_code,status,manifest,created_by_execution_id)
                VALUES('EXEC-B07-TEST-SALY-BOOT','VULNERABILITY_COVERAGE_REPAIR_LF',
                  'OPERATION','ACTUALIZACION_REGLA_SALY','IN_PROGRESS',
                  '{"governance_bootstrap":true,"bootstrap_operation_code":"ACTUALIZACION_REGLA_SALY","bootstrap_status_ceiling":"SANDBOX_ACTIVE","test_only":true,"candidate_only":true,"production_allowed":false,"runtime_activation":false}'::jsonb,'EXEC-B07-TEST-SALY-BOOT');
                INSERT INTO public.lf_operation_registry(
                operation_code,version,status,source_model,source_repo,source_paths,
                lifecycle_state_code,created_by_execution_id)
                VALUES('ACTUALIZACION_REGLA_SALY','v0.1','SANDBOX_ACTIVE',
                'GIT_FIRST_YAML','cristhianlujan/claude-persona-lf-patch',
                '[]'::jsonb,'OP_CANDIDATE','EXEC-B07-TEST-SALY-BOOT');""")
            sql(src,fail="B07_SALY_OWNER_AND_PROFILE_GOVERNED_REQUIRED")
            sql("""INSERT INTO public.lf_ig_project_owner_v2(
                project_code,owner_sub,owner_name,owner_profile_code,
                authority_receipt_sha256,status,source_execution_id)
                VALUES('SALY','00000000-0000-4000-8000-000000000111',
                'Cristhian Luján','PERFIL-SALY-CI-ONLY',
                repeat('f',64),'TEMP_DOCUMENTARY_ACTIVE','EXEC-B07-TEST-SALY-BOOT');""")
            sql(src,fail="B07_SALY_OWNER_AND_PROFILE_GOVERNED_REQUIRED")
            sql("""INSERT INTO public.lf_activos(
                id,codigo_activo,nombre_canonico,tipo_activo,estado_documental,
                estado_operativo,source_spreadsheet_id,source_spreadsheet_title,
                source_sheet_name,source_row_number,migration_batch_id)
                VALUES(-777777,'PERFIL-SALY-CI-ONLY','CI ONLY SALY PROFILE','PERFIL',
                'CANDIDATO','READ_ONLY','CI_SYNTHETIC','CI_SYNTHETIC','CI_ONLY',
                1,'00000000-0000-4000-8000-000000000111'::uuid);""")
            sql(src,timeout=600)
            self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas_versiones_b07;"),"578")
            self.assertEqual(sql("SELECT count(*) FROM saly.reglas_versiones_b07;"),"14")
            self.assertEqual(sql("""SELECT
              (SELECT count(*) FROM lf_ops.reglas x WHERE to_jsonb(x) IS DISTINCT FROM
                (SELECT h.snapshot FROM lf_ops.reglas_versiones_b07 h
                  WHERE h.rule_id=x.id ORDER BY version_no DESC LIMIT 1))+
              (SELECT count(*) FROM saly.reglas x WHERE to_jsonb(x) IS DISTINCT FROM
                (SELECT h.snapshot FROM saly.reglas_versiones_b07 h
                  WHERE h.rule_id=x.id ORDER BY version_no DESC LIMIT 1));"""),"0")
            self.assertEqual(sql("SELECT to_regprocedure('public.lf_ig_saly_rule_finalize_b07_v1(text)') IS NOT NULL;"),"t")
            self.assertEqual(sql("SELECT has_function_privilege('service_role','public.lf_ig_saly_rule_finalize_b07_v1(text)','EXECUTE');"),"t")
            self.assertEqual(sql("SELECT has_function_privilege('authenticated','public.lf_ig_saly_rule_finalize_b07_v1(text)','EXECUTE');"),"f")
            self.assertEqual(sql("SELECT has_table_privilege('service_role','saly.reglas_versiones_b07','INSERT');"),"f")
            after=sql("""SELECT encode(extensions.digest(convert_to(
              jsonb_build_object('lf',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM lf_ops.reglas x),
              'saly',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM saly.reglas x))::text,
              'UTF8'),'sha256'),'hex');""")
            self.assertEqual(before,after,"B07_PARENT_PREIMAGE_CHANGED_DURING_MIGRATION")
            print("PASS_B07_ATOMIC_OFFICIAL_MIGRATION_"+image.replace(":","_"),flush=True)
        finally:
            subprocess.run(["docker","rm","-f",cid],capture_output=True,text=True,timeout=30)

    def test_pg176_atomic(self): self.verify("postgres:17.6","170006")
    def test_pg187_atomic(self): self.verify("postgres:18.7","180007")

if __name__=="__main__":
    unittest.main()
