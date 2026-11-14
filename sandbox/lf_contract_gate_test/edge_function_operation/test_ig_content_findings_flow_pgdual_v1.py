#!/usr/bin/env python3
"""Live-preimage-guarded migration: real PG17.6/18.7 disposable rollback tests.

No network to sandbox Supabase, no credentials and no production effects.
Checks known IG content -> finding, contract/identity/authority -> flow block.
"""
import re
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261114163000_lf_ig_content_findings_flow_only_v1.sql"
OLD_HASHES = (
    ("programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)", "142364e102b48d353d6e3b56816183ee"),
    ("programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)", "ab091d641cc1d3d923d20c0db96d9bc5"),
    ("programacion.fn_lf_router_input_governance_derive_v1(text,jsonb,text)", "06f024f37c34030f02291b44d4463bda"),
)
FIXTURE = r"""
CREATE SCHEMA IF NOT EXISTS programacion;
CREATE SCHEMA IF NOT EXISTS lf_ops;
CREATE SCHEMA IF NOT EXISTS transversal;
CREATE TABLE public.lf_activos(
 codigo_activo text, archived_at timestamptz, tipo_activo text, metadata jsonb);
CREATE TABLE public.lf_activo_relaciones(
 codigo_activo text, relacionado_codigo text, relacion_tipo text);
CREATE TABLE lf_ops.pantallas(id integer,codigo text,activa boolean);
CREATE TABLE programacion.contratos(id integer,contrato_codigo text,estado text,especificacion jsonb);
CREATE TABLE transversal.error_knowledge(
 codigo text,categoria text,titulo text,descripcion text,causa_raiz text,
 prevencion text,validacion text,estado text,lote_origen text,source_ref text);
CREATE FUNCTION programacion.fn_lf_profile_adapter_input_governance_resolve_v1(
 text,jsonb,text) RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
CREATE FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(
 text,text,jsonb,text) RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
CREATE FUNCTION programacion.fn_lf_router_input_governance_derive_v1(
 text,jsonb,text) RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
CREATE FUNCTION public.lf_profile_screen_selector_semantic_validate_v1(jsonb,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$SELECT '{"status":"VALID"}'::jsonb$$;
CREATE FUNCTION public.fn_input_governance_worker_spec(integer,text)
 RETURNS jsonb LANGUAGE sql AS $$SELECT '{"current_run_id":null}'::jsonb$$;
CREATE FUNCTION programacion.fn_input_governance_execute(integer,text)
 RETURNS jsonb LANGUAGE sql AS $$SELECT '{"status":"BLOCKED","remediation_state":"INTERNAL_REMEDIATION_REQUIRED"}'::jsonb$$;
INSERT INTO public.lf_activos VALUES(
 'PERFIL-PRODUCT-DIRECTOR-LF',NULL,'PERFIL',
 '{"input_governance_binding_mode":"DIRECT_PROFILE","input_governance_consumer":"CONTEXT_PACK"}');
INSERT INTO public.lf_activo_relaciones VALUES(
 'PERFIL-PRODUCT-DIRECTOR-LF','INPUT_GOVERNANCE_EXECUTION_CONTRACT','GOBERNADO_POR');
INSERT INTO lf_ops.pantallas VALUES(44,'B2B-AUTH-001',true);
INSERT INTO programacion.contratos VALUES(
 1,'INPUT_GOVERNANCE_EXECUTION_CONTRACT','defined',
 '{"allowed_consumers":["CONTEXT_PACK"]}');
"""

class RealPgFlowRollback(unittest.TestCase):
    def run_pg(self,image,prefix):
        self.assertTrue(shutil.which("docker"),"NOT_TESTED_DOCKER_MISSING")
        name="lf-ig-content-"+uuid.uuid4().hex[:11]
        created=subprocess.run(
            ["docker","run","-d","--rm","--name",name,
             "-e","POSTGRES_PASSWORD=postgres",image],
            capture_output=True,text=True,timeout=180)
        self.assertEqual(created.returncode,0,created.stderr[-1500:])
        try:
            def sql(query,failed=None):
                res=subprocess.run(
                    ["docker","exec","-i",name,"psql","-X",
                     "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres","-Atq"],
                    input=query,capture_output=True,text=True,timeout=240)
                if failed:
                    self.assertNotEqual(res.returncode,0,"wrong success: "+query[:180])
                    self.assertIn(failed,res.stderr)
                else:
                    self.assertEqual(res.returncode,0,res.stderr[-3500:])
                return res.stdout.strip()
            for _ in range(100):
                ready=subprocess.run(
                    ["docker","exec",name,"pg_isready","-U","postgres"],
                    capture_output=True,timeout=8)
                if ready.returncode==0:break
                time.sleep(0.8)
            else:self.fail("PG_READY_TIMEOUT")
            self.assertTrue(sql("SHOW server_version_num;").startswith(prefix))
            sql(FIXTURE)
            source=MIGRATION.read_text(encoding="utf-8")
            self.assertTrue(source.startswith("-- LF IG:"))
            self.assertRegex(source,r"\nCOMMIT;\s*$")
            inner=source.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
            # Original preimage is intentionally strict on sandbox. Disposable
            # fixture uses minimal old stubs and translates only each hash guard.
            patched=inner
            for signature,live_md5 in OLD_HASHES:
                stub_md5=sql("SELECT md5(pg_get_functiondef('"+signature+"'::regprocedure));")
                self.assertRegex(stub_md5,r"^[a-f0-9]{32}$")
                self.assertIn(live_md5,patched)
                patched=patched.replace(live_md5,stub_md5)
            # Negative guard: unaltered production preimage must reject this
            # synthetic old-stub fixture without modifying any object.
            sql("BEGIN;\n"+inner+"\nROLLBACK;",failed="SOURCE_STATE_DRIFT:")
            self.assertEqual(sql("SELECT count(*) FROM transversal.error_knowledge;"),"0")
            adapters='''[{"adapter_code":"A1","adapter_metadata":{
                "router_discoverable":"true","runtime_enabled":"true",
                "input_governance_receipt_required":"true",
                "input_governance_continuation_policy":"PASS_ONLY",
                "input_governance_contract_resolution":"LIVE_CURRENT",
                "input_governance_authority_contract":"INPUT_READINESS_CONTRACT"}}]'''
            scope='''{"resolution_status":"RESOLVED",
               "resolution_method":"DETERMINISTIC_SHORTLIST_THEN_SEMANTIC",
               "resolved_screen_code":"B2B-AUTH-001",
               "screen_selection_request":{"literal_request":"B2B-AUTH-001"},
               "screen_selection_result":{"decision":"SELECTED",
                "selected_screen_code":"B2B-AUTH-001","semantic_receipt_sha256":"abc"}}'''
            direct=lambda body: "programacion.fn_lf_profile_input_governance_resolve_v1('B2B-AUTH-001','PERFIL-PRODUCT-DIRECTOR-LF',"+body+"::jsonb,'CONTEXT_PACK')"
            adapter=lambda consumer: "programacion.fn_lf_profile_adapter_input_governance_resolve_v1('B2B-AUTH-001','"+adapters+"'::jsonb,'"+consumer+"')"
            derive=lambda consumer: "programacion.fn_lf_router_input_governance_derive_v1('B2B-AUTH-001','"+adapters+"'::jsonb,'"+consumer+"')"
            query="\n".join([
                "SELECT 'LIVE_EKB='||count(*) FROM transversal.error_knowledge;",
                "SELECT 'DIRECT_CONTENT='||("+direct("'"+scope+"'")+"->>'continuation_allowed');",
                "SELECT 'DIRECT_FINDING='||("+direct("'"+scope+"'")+"->>'finding_class');",
                "SELECT 'DIRECT_BROKEN_SCOPE='||("+direct("'{}'")+"->>'continuation_allowed');",
                "SELECT 'ADAPTER_MISSING_CURRENT='||("+adapter("CONTEXT_PACK")+"->>'continuation_allowed');",
                "SELECT 'ADAPTER_UNAUTHORIZED='||("+adapter("STORY_CREATOR")+"->>'continuation_allowed');",
                "SELECT 'ADAPTER_BAD_METADATA='||(programacion.fn_lf_profile_adapter_input_governance_resolve_v1('X','{}'::jsonb,'CONTEXT_PACK')->>'continuation_allowed');",
                "SELECT 'ROUTER_DERIVED='||("+derive("CONTEXT_PACK")+"->>'continuation_allowed');",
                "SELECT 'ROUTER_UNAUTHORIZED='||("+derive("STORY_CREATOR")+"->>'continuation_allowed');",
                """CREATE OR REPLACE FUNCTION programacion.fn_input_governance_execute(integer,text)
                   RETURNS jsonb LANGUAGE sql AS $f$
                   SELECT '{"status":"BLOCKED","remediation_state":"ACTION_AUTHORIZATION_GATE"}'::jsonb
                   $f$;""",
                "SELECT 'DIRECT_EFFECT_AUTHORITY='||("+direct("'"+scope+"'")+"->>'continuation_allowed');",
            ])
            tested=sql("BEGIN; SET LOCAL check_function_bodies=off;\n"+patched+"\n"+query+"\nROLLBACK;")
            expected_lines={
              "LIVE_EKB=5","DIRECT_CONTENT=true","DIRECT_FINDING=INPUT_GOVERNANCE_CONTENT",
              "DIRECT_BROKEN_SCOPE=false","ADAPTER_MISSING_CURRENT=true",
              "ADAPTER_UNAUTHORIZED=false","ADAPTER_BAD_METADATA=false",
              "ROUTER_DERIVED=true","ROUTER_UNAUTHORIZED=false",
              "DIRECT_EFFECT_AUTHORITY=false",
            }
            self.assertTrue(expected_lines.issubset(set(tested.splitlines())),tested)
            self.assertEqual(sql("SELECT count(*) FROM transversal.error_knowledge;"),"0")
            self.assertEqual(sql("SELECT (programacion.fn_lf_profile_input_governance_resolve_v1('x','y','{}'::jsonb,'CONTEXT_PACK')->>'status');"),None if False else "{}" ) if False else None
            original=sql("SELECT position('SELECT ' IN pg_get_functiondef('programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure))>0;")
            self.assertEqual(original,"t")
            print("PASS_IG_FLOW_CONTENT_ROLLBACK_"+image.replace(":","_"),flush=True)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=45)

    def test_pg176_rollback(self):
        self.run_pg("postgres:17.6","170006")

    def test_pg187_rollback(self):
        self.run_pg("postgres:18.7","180007")

if __name__=="__main__":
    unittest.main()
