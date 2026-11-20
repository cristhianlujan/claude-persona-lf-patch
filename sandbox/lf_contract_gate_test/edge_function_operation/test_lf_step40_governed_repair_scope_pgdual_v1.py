"""PG17.6/PG18.7: LIVE prepatch bridge function definitions, exact migration,
three real Step40 prepare cases and an actual Step80 report admission path.
BEGIN/ROLLBACK. Negative source-drift patch MUST reject.
"""
import shutil, subprocess, time, unittest, uuid, re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIGS=list((ROOT/"supabase/migrations").glob("*_lf_step40_governed_repair_scope_v1.sql"))
SOURCE=Path(__file__).resolve().parent/"fixtures/lf_step40_prepatch_live_functions_v1.sql"
assert len(MIGS)==1, "LF_STEP40_MIGRATION_SOURCE_AMBIGUOUS"
SCHEMA=r"""
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY,operation_code text NOT NULL,target_type text NOT NULL,
 target_code text NOT NULL,status text NOT NULL,manifest jsonb NOT NULL,
 target_repo text,target_path text);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text NOT NULL,step_id text NOT NULL,status text NOT NULL,
 evidence_payload jsonb NOT NULL DEFAULT '{}'::jsonb,step_order integer,
 observed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(execution_id,step_id));
CREATE TABLE public.lf_activos(
 codigo_activo text PRIMARY KEY,tipo_activo text,archived_at timestamptz,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb);
CREATE OR REPLACE FUNCTION public.lf_input_family_catalog_receipts_for_run_v1(text)
RETURNS jsonb LANGUAGE sql AS $family$ SELECT '[]'::jsonb $family$;
CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"valid":true}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"READY","resolved_scope":{}}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_for_run_v1(text,jsonb)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"READY","skills":[]}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_profile_skill_reconcile_late_v1(text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"BLOCKED","blocking_code":"TEST_STOP_AFTER_STEP40"}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
RETURNS jsonb LANGUAGE plpgsql AS $record$
BEGIN
 INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload)
 VALUES($1,$2,'STEP_PASS_WITH_EVIDENCE',$4);
 RETURN '{"status":"STEP_PASS_WITH_EVIDENCE"}'::jsonb;
END $record$;
INSERT INTO public.lf_activos(codigo_activo,tipo_activo,metadata)
 VALUES ('PERFIL-PRODUCT-DIRECTOR-LF','PERFIL','{"profile_slug":"product_director_lf"}');
"""
RUNS=r"""
INSERT INTO public.lf_operation_execution(
 execution_id,operation_code,target_type,target_code,status,manifest,target_repo,target_path)
SELECT r.id,'EJECUCION_PERFIL_LF','PERFIL','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS',
 jsonb_build_object('executor_mode','GPT_NATIVE','executor_provider','OPENAI_CHATGPT_NATIVE',
  'router_profile_handoff',jsonb_build_object('literal_request','test cases','channel','issue'))
 ||r.g, 'cristhianlujan/claude-persona-lf-patch','profiles/product_director_lf/PROFILE.md'
FROM (VALUES('GOV','{"governed_repair_write":true}'::jsonb),
 ('RO','{"governed_repair_write":false}'::jsonb),
 ('NONE','{}'::jsonb)) AS r(id,g);
SELECT 'CALL='||execution_id||':'||
 (public.lf_profile_native_bridge_prepare_v1(execution_id,repeat('a',40),
  'sha256:'||repeat('b',64),execution_id)->>'blocking_code')
FROM public.lf_operation_execution ORDER BY execution_id;
SELECT 'READBACK='||execution_id||':'||
 (evidence_payload->>'analysis_scope')||':'||
 (evidence_payload#>>'{input_governance,analysis_scope}')||':'||
 (evidence_payload->>'mutation_authorized')
FROM public.lf_operation_execution_steps
WHERE step_id='input_validate' ORDER BY execution_id;
-- Report must no longer reject GOVERNED_REPAIR with BLOCK_REPORT_IG_FINDINGS_WRITE_SCOPE.
UPDATE public.lf_operation_execution_steps
 SET evidence_payload=jsonb_set(evidence_payload,'{input_governance,status}','"BLOCKED"',true)
 WHERE execution_id='GOV' AND step_id='input_validate';
INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload)
VALUES ('GOV','semantic_judge','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('semantic_judge_result',jsonb_build_object(
 'candidate_sha256',repeat('c',64),'scope_packet_sha256',repeat('d',64))));
SELECT 'REPORT_GOV='||(public.lf_profile_native_bridge_record_report_v1(
 'GOV','supabase://test/profile/evidence','GOV')->>'blocking_code');
"""
class Step40GovernedRepairPGDual(unittest.TestCase):
 def test_live_bridge_source_migration_patch_and_scenarios(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  src=re.sub(r"(\$function\$)(\s+)(?=CREATE OR REPLACE FUNCTION)",r"\1;\2",SOURCE.read_text(encoding="utf-8")).rstrip()+";\n"
  migration=MIGS[0].read_text(encoding="utf-8")
  self.assertIn("lf_profile_native_bridge_prepare_v1",src)
  self.assertIn("lf_profile_native_bridge_record_report_v1",src)
  self.assertIn("LF_STEP40_PATCH_A_NOT_APPLIED",migration)
  self.assertIn("LF_STEP40_PATCH_B_NOT_APPLIED",migration)
  # Negative: downgrade prepare body, proving the EXACT migration refuses source drift.
  negative=r"""
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1(
 p_execution_id text,p_source_revision text,p_source_digest text,
 p_actor_execution_id text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql AS $break$
BEGIN RETURN '{}'::jsonb; END $break$;
"""
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-e12-step40-"+uuid.uuid4().hex[:9]
    run=subprocess.run(["docker","run","-d","--rm","--name",name,
      "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
      capture_output=True,text=True,timeout=180)
    self.assertEqual(run.returncode,0,run.stderr[-1200:])
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
       capture_output=True,text=True,timeout=10)
      if ready.returncode==0:
       logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     def sql(inp,expected=0):
      p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
          "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
         input=inp,capture_output=True,text=True,timeout=160)
      if expected==0:self.assertEqual(p.returncode,0,p.stderr[-4500:]+"\n"+p.stdout[-3300:])
      else:self.assertNotEqual(p.returncode,0,"EXPECTED SQL ERROR; "+p.stdout[-1000:])
      return p.stdout,p.stderr
     # All schema, live function definitions, and writes in transaction.
     sql("BEGIN;\n"+SCHEMA+"\n"+src+"\n"+negative+
         "\nCOMMIT;")
     out,err=sql(migration,expected=1)
     self.assertIn("LF_STEP40_PATCH_A_NOT_APPLIED",err)
     # Restore actual LIVE prepatch source via CREATE OR REPLACE (not a dummy).
     # The real regression reads output in same SQL session, before ROLLBACK.
     out,err=sql("BEGIN;\n"+src+"\n"+
        migration.split("BEGIN;",1)[1].rsplit("COMMIT;",1)[0]+"\n"+
        RUNS+"\nROLLBACK;\nSELECT 'RESIDUE='||count(*) FROM public.lf_operation_execution;\n")
     for marker in (
        "READBACK=GOV:GOVERNED_REPAIR:GOVERNED_REPAIR:true",
        "READBACK=RO:READ_ONLY_PROFILE_VALIDATION:READ_ONLY_PROFILE_VALIDATION:false",
        "READBACK=NONE:READ_ONLY_PROFILE_VALIDATION:READ_ONLY_PROFILE_VALIDATION:false",
        "REPORT_GOV=BLOCK_PROFILE_NATIVE_REPORT_COMPLETION_NOT_CLEAN",
        "RESIDUE=0"):
      self.assertIn(marker,out,marker+"\n"+out[-2200:])
     self.assertNotIn("REPORT_GOV=BLOCK_REPORT_IG_FINDINGS_WRITE_SCOPE",out)
     print("PASS_E12_STEP40_GOVERNED_REPAIR_PG"+pg+"_LIVE_FUNCTIONS_NEGATIVE_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":
 unittest.main()
