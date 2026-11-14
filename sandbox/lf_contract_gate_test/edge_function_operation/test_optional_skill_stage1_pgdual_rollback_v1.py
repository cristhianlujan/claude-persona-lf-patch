"""LF 2026-11-14: PG17.6/18.7 ten-profile optional skill, 0..2 choices,
run-sticky input, Stage1 5->4, renamed statuses, real ROLLBACK.
Does not invoke production or write to Supabase; test DB is disposable.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIGRATION=ROOT/"supabase/migrations/20261114195500_lf_skill_optional_context_sticky_stage1_bounded_v1.sql"
FIXTURE=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/fixture_optional_skills_stage1_live_preimage_v1.sql"
RUN="EXEC-PROFILE-GATE2-0248912F0BB40220F116168D"
PROFILE="PERFIL-PRODUCT-DIRECTOR-LF"
CONTEXT=lambda profile,step,have_screen: ("jsonb_build_object('profile_code','"+profile+
 "', 'channel',(SELECT channels[1] FROM public.lf_profile_selector_policy_v1 WHERE profile_code='"+
 profile+"'),'step','"+str(step)+"','request_text','Revisar carga masiva B2B',"+
 "'intent','SCREEN_RULES_REVIEW','input_summary',jsonb_build_object('screen_code','B2B-CARGA-002'),"+
 "'input',jsonb_build_object('execution_id','"+RUN+
 "','request_text','Revisar carga masiva B2B','profile_code','"+profile+
 "','consumer','CONTEXT_PACK'"+(
 ",'scope',jsonb_build_object('resolved_screen_code','B2B-CARGA-002'),'pantalla_codigo','B2B-CARGA-002'"
 if have_screen else "")+"))")

class PgOptionalSkillStage1Rollback(unittest.TestCase):
 def check(self,image,version):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_UNAVAILABLE")
  container="lf-skill-optional-"+uuid.uuid4().hex[:11]
  start=subprocess.run(["docker","run","--rm","-d","--name",container,
    "-e","POSTGRES_PASSWORD=postgres",image],capture_output=True,text=True,timeout=180)
  self.assertEqual(start.returncode,0,start.stderr[-1300:])
  try:
   for _ in range(100):
    test=subprocess.run(["docker","exec",container,"pg_isready","-U","postgres"],
      capture_output=True,timeout=5)
    if test.returncode==0:break
    time.sleep(.8)
   else:self.fail("PG_READY_TIMEOUT")
   def run(sql,expect_error=None):
    p=subprocess.run(["docker","exec","-i",container,"psql","-X","-Atq",
      "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
      input=sql,text=True,capture_output=True,timeout=150)
    if expect_error:
      self.assertNotEqual(p.returncode,0,p.stdout[-1100:])
      self.assertIn(expect_error,p.stderr[-5500:])
    else:self.assertEqual(p.returncode,0,p.stderr[-7800:])
    return p.stdout.strip()
   self.assertTrue(run("SHOW server_version_num;").startswith(version))
   run(FIXTURE.read_text(encoding="utf-8"))
   src=MIGRATION.read_text(encoding="utf-8")
   self.assertIn("SKILL_SELECTION_PENDING_FINDING",src)
   self.assertIn("TOO_MANY_FORMAS",src)
   inner=src.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;\n",1)[0]
   seed_count=run("SELECT count(*) FROM public.lf_skill_selector_policy_v1 WHERE enabled AND selection_mode='SEMANTIC_OPTIONAL';")
   self.assertEqual(seed_count,"18")
   test_sql="BEGIN;\n"+inner+"\n"
   # All ten profiles: step30 has insufficient required inputs -> READY without skills.
   test_sql+="""
DO $test$
DECLARE r record;ctx jsonb;v jsonb;cnt int:=0;selected jsonb;none_dec jsonb;
BEGIN
 FOR r IN SELECT profile_code,channels[1] AS channel FROM public.lf_profile_selector_policy_v1 ORDER BY profile_code LOOP
  ctx:=jsonb_build_object('profile_code',r.profile_code,'channel',r.channel,
   'step','30','request_text','Entra por el router y revisa las reglas de carga masiva del b2b',
   'intent','SCREEN_RULES_REVIEW','input_summary','{}'::jsonb,
   'input',jsonb_build_object('execution_id','EXEC-TEST-STEP30','profile_code',r.profile_code,
     'request_text','Entra por el router y revisa las reglas de carga masiva del b2b','consumer','CONTEXT_PACK'));
  v:=public.lf_profile_skill_selection_prepare_context_v1(r.profile_code,r.channel,NULL,ctx);
  IF v->>'status'<>'READY' OR jsonb_array_length(v->'skills')<>0 OR
     v#>>'{content_findings,0,finding_code}'<>'SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED' THEN
     RAISE EXCEPTION 'OPTIONAL_SKILL_STEP30_BLOCKS:%,%',r.profile_code,v;
  END IF;
  cnt:=cnt+1;
 END LOOP;
 IF cnt<>10 THEN RAISE EXCEPTION 'PROFILE_COUNT_WRONG:%',cnt; END IF;
 ctx:=jsonb_build_object('profile_code','PERFIL-PRODUCT-DIRECTOR-LF','channel','PRODUCTO',
   'step','40','request_text','Entra por el router y revisa las reglas de carga masiva del b2b',
   'intent','SCREEN_RULES_REVIEW','input_summary',jsonb_build_object('screen_code','B2B-CARGA-002'),
   'input',jsonb_build_object('execution_id','EXEC-TEST-40',
      'request_text','Entra por el router y revisa las reglas de carga masiva del b2b',
      'profile_code','PERFIL-PRODUCT-DIRECTOR-LF','consumer','CONTEXT_PACK',
      'scope',jsonb_build_object('resolved_screen_code','B2B-CARGA-002'),
      'pantalla_codigo','B2B-CARGA-002'));
 v:=public.lf_profile_skill_selection_prepare_context_v1('PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',NULL,ctx);
 IF v->>'status'<>'READY' OR jsonb_array_length(v->'skill_candidates')<>2
    OR jsonb_array_length(v->'skills')<>0 OR
    v#>>'{skill_candidates,0,selection_context,step}'<>'40' OR
    v#>>'{content_findings,0,finding_alias}'<>'SKILL_SELECTION_PENDING_FINDING' THEN
   RAISE EXCEPTION 'AMBIGUOUS_SKILL_NO_FAILOPEN:%',v; END IF;
 none_dec:=jsonb_build_object('selected_skill_codes','[]'::jsonb,'reason','Ninguna aplica con evidencia suficiente');
 v:=public.lf_profile_skill_selection_prepare_context_v1('PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',none_dec,ctx);
 IF v->>'status'<>'READY' OR jsonb_array_length(v->'skills')<>0
  OR v#>>'{content_findings,0,finding_code}'<>'SKILL_EXPLICIT_NONE' THEN
    RAISE EXCEPTION 'NONE_SKILL_REJECTED:%',v; END IF;
 selected:=jsonb_build_object('selected_skill_codes',jsonb_build_array(
      'INPUT_GOVERNANCE_CONTEXT_PACK','SCREEN_RULES_SNAPSHOT'),
   'reason','Two read-only skill inputs are present',
   'review_mode','CURRENT_CONTEXT_REVIEW',
   'evidence_refs',jsonb_build_array(jsonb_build_object('kind','RUN_INPUT')),
   'descriptor_revisions',jsonb_build_object(
      'INPUT_GOVERNANCE_CONTEXT_PACK','sha256:25dd30f67ed5759209b11a7e7d993d7766bd3c5cedf5f79a61976e25362980dc',
      'SCREEN_RULES_SNAPSHOT','sha256:e1d9545da14de1f43ebab0a803624c79fdac46f2f33b42ff4ce95a9ca849ddb4'));
 v:=public.lf_profile_skill_selection_prepare_context_v1('PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',selected,ctx);
 IF v->>'status'<>'READY' OR jsonb_array_length(v->'skills')<>2 THEN
   RAISE EXCEPTION 'TWO_SKILLS_NOT_ALLOWED:%',v; END IF;
 selected:=selected||jsonb_build_object('selected_skill_codes',
   jsonb_build_array('INPUT_GOVERNANCE_CONTEXT_PACK','SCREEN_RULES_SNAPSHOT','FAKE_THIRD'));
 v:=public.lf_profile_skill_selection_prepare_context_v1('PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',selected,ctx);
 IF v->>'blocking_code'<>'SKILL_SELECTION_TICKET_LIMIT_EXCEEDED' THEN
   RAISE EXCEPTION 'THIRD_SKILL_NOT_REJECTED:%',v; END IF;
END $test$;
SELECT 'PASS_SKILL_OPTIONAL_TEN_PROFILES_0_2_AND_JUDGE_CONTEXT';
"""
   # Existing original execution id stays identical (no insert from resume).
   test_sql+="""
SELECT CASE WHEN
 (SELECT count(*) FROM public.lf_operation_execution
   WHERE execution_id IN
    ('EXEC-PROFILE-GATE2-0248912F0BB40220F116168D',
     'EXEC-PROFILE-GATE2-15B9B3F0FA7D6B7C3BFC037A',
     'EXEC-PROFILE-GATE2-C506666157F990238F37B2C1'))=3
 AND public.lf_profile_execution_plan_for_run_v1(
   'EXEC-PROFILE-GATE2-0248912F0BB40220F116168D',NULL)->>'status'='READY'
 AND public.lf_profile_execution_plan_for_run_v1(
   'EXEC-PROFILE-GATE2-15B9B3F0FA7D6B7C3BFC037A',NULL)->>'status'='READY'
 AND public.lf_profile_execution_plan_for_run_v1(
   'EXEC-PROFILE-GATE2-C506666157F990238F37B2C1',NULL)->>'status'='READY'
 THEN 'PASS_RESUME_EXISTING_IDS_WITHOUT_SKILL_BLOCK' ELSE 'FAIL_RESUME_IDS' END;
"""
   # Stage1 must truncate first four, preserve order, and carry a content finding.
   test_sql+="""
SELECT CASE WHEN
 v->>'valid'='true'
 AND jsonb_array_length(v->'effective_stage1'->'formas_busqueda')=4
 AND v#>>'{content_findings,0,finding_code}'='TOO_MANY_FORMAS'
 AND v#>>'{content_findings,0,continuation_allowed}'='true'
 THEN 'PASS_STAGE1_FIVE_TO_FOUR_WITH_CONTENT_FINDING'
 ELSE 'FAIL_STAGE1_FIVE_TO_FOUR' END
FROM (SELECT public.lf_router_stage1_validate_v2(jsonb_build_object(
 'schema_version','LF_ROUTER_STAGE1_V2',
 'texto_original','Entra por el router y revisa las reglas de carga masiva del b2b',
 'es_operacion',true,'ambiguo',false,
 'formas_busqueda',jsonb_build_array('busqueda 1','busqueda 2','busqueda 3','busqueda 4','busqueda 5'),
 'alternativas','[]'::jsonb,'canal','PRODUCTO','negocio','LF',
 'razon_seleccion','El usuario pide una revisión de reglas',
 'sujeto','B2B-CARGA-002','accion','revisar')) AS v) test;
"""
   # inspect code presence only after actual migration, not from copied source.
   test_sql+="""
SELECT CASE WHEN
 (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
  WHERE n.nspname='public'
   AND p.proname IN ('lf_profile_skill_selection_prepare_v1',
    'lf_profile_skill_runtime_ticket_issue_v1','lf_profile_skill_invoke_selected_v1',
    'lf_profile_native_bridge_prepare_v1',
    'lf_router_pipeline_context_profile_semantic_prepare_v2',
    'lf_router_pipeline_context_profile_semantic_submit_v2',
    'lf_router_pipeline_profile_semantic_prepare_v1',
    'lf_router_pipeline_profile_semantic_submit_v1')
   AND position('SEMANTIC_SELECTION_REQUIRED' in p.prosrc)>0)=0
 AND (SELECT count(*) FROM public.lf_skill_selector_policy_v1
  WHERE applicability_contract ? 'selection_required')=0
 THEN 'PASS_NAMING_NO_OLD_EXCEPT_COMPAT_AND_POLICY'
 ELSE 'FAIL_SKILL_NAMING' END;
ROLLBACK;
SELECT count(*) FILTER(WHERE applicability_contract ? 'selection_required')
 FROM public.lf_skill_selector_policy_v1;
SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
 WHERE n.nspname='public' AND p.proname='lf_profile_skill_selection_prepare_context_v1';
"""
   output=run(test_sql).splitlines()
   for marker in ("PASS_SKILL_OPTIONAL_TEN_PROFILES_0_2_AND_JUDGE_CONTEXT",
     "PASS_RESUME_EXISTING_IDS_WITHOUT_SKILL_BLOCK",
     "PASS_NAMING_NO_OLD_EXCEPT_COMPAT_AND_POLICY","10","0"):
     self.assertIn(marker,output,output)
   # Check content finding in stdout; might fail validity on stub business.
   self.assertIn("PASS_STAGE1_FIVE_TO_FOUR_WITH_CONTENT_FINDING",output,output)
   self.assertEqual(output[-1],"0")
   print("PASS_LF_SKILL_OPTIONAL_STAGE1_ROLLBACK_"+image,flush=True)
  finally:
   subprocess.run(["docker","rm","-f",container],capture_output=True,text=True,timeout=60)
 def test_pg176(self):self.check("postgres:17.6","170006")
 def test_pg187(self):self.check("postgres:18.7","180007")

if __name__=="__main__":unittest.main()
