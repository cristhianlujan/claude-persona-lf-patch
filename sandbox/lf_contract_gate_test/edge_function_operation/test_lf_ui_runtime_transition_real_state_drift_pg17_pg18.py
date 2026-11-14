#!/usr/bin/env python3
"""Exact governed runtime transition SQL: real-state FAIL-CLOSED and hypothetical source PASS, rollback in disposable PG."""
from __future__ import annotations
import json,os,shutil,subprocess,time,unittest,uuid
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
READBACK=HERE/"fixtures/lf_ui_runtime_transition_2255_preflight_real_state_20261113.json"
STUB=ROOT/"sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_transition_route_v1_stub.sql"
MIG=ROOT/"supabase/migrations/20261105060000_lf_profile_runtime_transition_route_v1.sql"
STATE="""jsonb_build_object('estado_original',r.estado_original,'estado_documental',r.estado_documental,
 'estado_operativo',r.estado_operativo,'nivel_control',r.nivel_control,
 'runtime_estado',r.runtime_estado,'impacto_automatico',r.impacto_automatico)"""
SHA="encode(sha256(convert_to(("+STATE+")::text,'UTF8')),'hex')"
SEL="SELECT "+SHA+" FROM public.lf_activos r WHERE r.codigo_activo='PERFIL-UI-ARCHITECT';"
SCHEMA="TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF"

class TestOfficialRuntimeTransition(unittest.TestCase):
 def run_pg(self,image,num):
  src=json.loads(READBACK.read_text(encoding="utf8"))
  real=src["profile"]
  self.assertEqual(real["runtime_estado"],"CANDIDATE_READ_ONLY")
  self.assertEqual(real["estado_original"],"CANDIDATO_CONTROLADO_READ_ONLY")
  self.assertEqual(real["nivel_control"],"CONTROLADO")
  self.assertEqual(real["impacto_automatico"],"BLOQUEADO")
  self.assertEqual(real["metadata_runtime_enabled"],"false")
  self.assertTrue(src["no_live_write"])
  self.assertEqual(src["source_precheck_outcome"],"TRANSITION_SOURCE_STATE_DRIFT")
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  self.assertTrue(STUB.exists() and MIG.exists())
  cid="lf-ui-runtime-"+uuid.uuid4().hex[:9]
  r=subprocess.run(["docker","run","-d","--rm","--name",cid,
    "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
    text=True,capture_output=True,timeout=240)
  self.assertEqual(r.returncode,0,r.stderr[-1000:])
  try:
   def sql(s):
    p=subprocess.run(["docker","exec","-i",cid,"psql","-X","-q","-t","-A",
      "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
      input=s,text=True,capture_output=True,timeout=300)
    self.assertEqual(p.returncode,0,"SQL_FAILED:"+p.stderr[-4000:])
    return [x.strip() for x in p.stdout.splitlines() if x.strip()]
   for _ in range(90):
    if subprocess.run(["docker","exec",cid,"pg_isready","-U","postgres"],capture_output=True,timeout=10).returncode==0:break
    time.sleep(1)
   else:self.fail("PG_NOT_READY")
   self.assertEqual(sql("SHOW server_version_num;"),[num])
   sql(STUB.read_text(encoding="utf8"))
   sql("ALTER TABLE public.lf_activos ADD COLUMN metadata jsonb NOT NULL DEFAULT "+
      """'{"runtime_enabled":false,"post_merge_next_gate":"PROFILE_RUNTIME_REFRESH_REQUIRED"}'::jsonb;""")
   sql(MIG.read_text(encoding="utf8"))
   # Exact real SELECT state transferred to local stub, no live row modified.
   fields=["codigo_activo","tipo_activo","estado_original","estado_documental","estado_operativo",
    "nivel_control","runtime_estado","impacto_automatico"]
   vals=[real["codigo_activo"],"PERFIL",real["estado_original"],real["estado_documental"],
     real["estado_operativo"],real["nivel_control"],real["runtime_estado"],real["impacto_automatico"]]
   def q(v):return "'"+str(v).replace("'","''")+"'"
   sql("INSERT INTO public.lf_activos("+",".join(fields)+") VALUES ("+
     ",".join(map(q,vals))+");")
   self.assertEqual(sql(SEL),[real["state_sha"]],"CANONICAL_SOURCE_TUPLE_SHA_MISMATCH")
   self.assertEqual(sql("SELECT (metadata->>'runtime_enabled') FROM public.lf_activos WHERE codigo_activo='PERFIL-UI-ARCHITECT';"),["false"])
   # This synthetic request is for the lab, NOT a user-authorized live invocation.
   req="""jsonb_build_object(
      'profile_code','PERFIL-UI-ARCHITECT',
      'requested_by','gpt',
      'request_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/issues/9999',
      'owner_authorization',jsonb_build_object(
       'mode','OWNER_CHAT_CONFORMITY_ONE_SHOT',
       'profile_code','PERFIL-UI-ARCHITECT',
       'statement','LAB ONLY NOT AN OWNER AUTHORIZATION FOR LIVE CHANGE',
       'authorized_at',now()))"""
   sql("""CREATE FUNCTION public.lf_try_transition_lab(req jsonb) RETURNS text LANGUAGE plpgsql AS $$
    BEGIN PERFORM public.lf_profile_runtime_transition_v1(req); RETURN 'PASS';
    EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $$;""")
   before=sql(SEL)[0]
   tx=["BEGIN;","SELECT 'BEFORE|'||"+SHA+" FROM public.lf_activos r WHERE r.codigo_activo='PERFIL-UI-ARCHITECT';",
        "SELECT 'GUARD|'||public.lf_try_transition_lab("+req+");",
        "SELECT 'DURING|'||"+SHA+" FROM public.lf_activos r WHERE r.codigo_activo='PERFIL-UI-ARCHITECT';",
        "SELECT 'RECEIPT_IN|'||count(*) FROM public.lf_profile_runtime_transition_receipt_v1;",
        "ROLLBACK;",
        "SELECT 'AFTER|'||"+SHA+" FROM public.lf_activos r WHERE r.codigo_activo='PERFIL-UI-ARCHITECT';",
        "SELECT 'RECEIPT_OUT|'||count(*) FROM public.lf_profile_runtime_transition_receipt_v1;"]
   lines=sql("\n".join(tx))
   results={k:v for k,v in (x.split("|",1) for x in lines if "|" in x)}
   self.assertEqual(results["GUARD"],"TRANSITION_SOURCE_STATE_DRIFT")
   self.assertEqual(results["BEFORE"],before)
   self.assertEqual(results["DURING"],before)
   self.assertEqual(results["AFTER"],before)
   self.assertEqual(results["RECEIPT_IN"],"0")
   self.assertEqual(results["RECEIPT_OUT"],"0")
   print("LF_UI_RUNTIME_REAL_GUARD|"+image+"|"+before+"|"+before+"|"+before+
       "|TRANSITION_SOURCE_STATE_DRIFT|PASS",flush=True)
   # Distinct hypothetical lab-only source ensures the official function itself works;
   # NEVER normalize real state backward to force this transition.
   sql("""UPDATE public.lf_activos SET estado_original='CANDIDATE_READ_ONLY',
     nivel_control='PROFILE_REGISTRY',runtime_estado='NO_HABILITADO'
     WHERE codigo_activo='PERFIL-UI-ARCHITECT';""")
   source=sql(SEL)[0]
   self.assertNotEqual(source,before)
   tx2=["BEGIN;",
        "SELECT 'BEFORE|'||"+SHA+" FROM public.lf_activos r WHERE r.codigo_activo='PERFIL-UI-ARCHITECT';",
        "SELECT 'RESULT|'||(public.lf_profile_runtime_transition_v1("+req+")->>'status');",
        "SELECT 'DURING|'||"+SHA+" FROM public.lf_activos r WHERE r.codigo_activo='PERFIL-UI-ARCHITECT';",
        "SELECT 'RECEIPT_IN|'||count(*) FROM public.lf_profile_runtime_transition_receipt_v1;",
        "SELECT 'STATUS|'||runtime_estado||'|'||impacto_automatico||'|'||metadata->>'runtime_enabled' FROM public.lf_activos WHERE codigo_activo='PERFIL-UI-ARCHITECT';",
        "ROLLBACK;",
        "SELECT 'AFTER|'||"+SHA+" FROM public.lf_activos r WHERE r.codigo_activo='PERFIL-UI-ARCHITECT';",
        "SELECT 'RECEIPT_OUT|'||count(*) FROM public.lf_profile_runtime_transition_receipt_v1;"]
   lines=sql("\n".join(tx2))
   r2={k:v for k,v in (x.split("|",1) for x in lines if "|" in x)}
   self.assertEqual(r2["RESULT"],"PASS_TRANSITION")
   self.assertEqual(r2["STATUS"],"CANDIDATE_READ_ONLY|BLOQUEADO|false")
   self.assertEqual(r2["BEFORE"],source)
   self.assertEqual(r2["DURING"],before)
   self.assertEqual(r2["AFTER"],source)
   self.assertEqual(r2["RECEIPT_IN"],"1")
   self.assertEqual(r2["RECEIPT_OUT"],"0")
   print("LF_UI_RUNTIME_HYPOTHETICAL_VALID|"+image+"|"+source+"|"+before+"|"+source+
       "|PASS_TRANSITION_ROLLBACK|PASS",flush=True)
   print("PASS_UI_RUNTIME_TRANSITION_CLOSED_SCOPE_"+image.replace(":","_"),flush=True)
   if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf8") as out:
     out.write("\n### UI runtime transition "+image+" (LAB ONLY, no live request)\n\n")
     out.write("| Scenario | SHA before | SHA in transaction | SHA after rollback | Result |\n")
     out.write("|---|---|---|---|---|\n")
     out.write("| REAL_SOURCE_FAIL_CLOSED | "+before+" | "+before+" | "+before+" | TRANSITION_SOURCE_STATE_DRIFT PASS |\n")
     out.write("| HYPOTHETICAL_NO_HABILITADO | "+source+" | "+before+" | "+source+" | PASS_TRANSITION ROLLBACK |\n")
  finally:
   subprocess.run(["docker","rm","-f",cid],text=True,capture_output=True,timeout=45)
 def test_pg_17_6(self):self.run_pg("postgres:17.6","170006")
 def test_pg_18_7(self):self.run_pg("postgres:18.7","180007")
if __name__=="__main__":unittest.main()
