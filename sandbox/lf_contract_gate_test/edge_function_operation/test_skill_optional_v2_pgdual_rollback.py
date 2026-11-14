"""Exact sandbox pg_get_functiondef preimages -> governed optional skill migration.
Disposable PostgreSQL 17.6 and 18.7; executes real BEGIN/ROLLBACK, no Supabase writes.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIX = ROOT / "sandbox/lf_contract_gate_test/edge_function_operation/fixture_skill_optional_v2_preimage_pgdual.sql"
MIG = ROOT / "supabase/migrations/20261114195000_lf_skill_selection_optional_run_context_names_v1.sql"

CHECK = r"""
DO $assert$
DECLARE r record; plan jsonb; ctx jsonb; decision jsonb; v jsonb; count_checked int:=0;
  old_hash text;
BEGIN
  SELECT md5(pg_get_functiondef('public.lf_profile_skill_selection_prepare_v1(text,text,jsonb)'::regprocedure)) INTO old_hash;
  IF old_hash='24850ec585cecca9a54fe87e3d1ad2da'
  THEN RAISE EXCEPTION 'OLD_SELECTOR_WAS_NOT_REPLACED';END IF;
  IF (SELECT count(*) FROM public.lf_skill_selector_policy_v1
    WHERE enabled AND skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
      AND applicability_contract ? 'selection_required')<>0
  THEN RAISE EXCEPTION 'IG_SELECTION_REQUIRED_NOT_REMOVED';END IF;

  FOR r IN SELECT p.profile_code,p.channels[1] AS channel
    FROM public.lf_profile_selector_policy_v1 p ORDER BY p.profile_code
  LOOP
    plan:=public.lf_profile_skill_selection_prepare_v2(r.profile_code,r.channel,NULL,NULL);
    IF plan->>'status'<>'READY'
       OR jsonb_array_length(plan->'skills')<>0
       OR plan->>'finding_code'<>'SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED'
       OR plan->>'finding_status'<>'SKILL_SELECTION_PENDING_FINDING'
       OR plan->>'next_action'<>'SUBMIT_SKILL_SELECTION'
       OR plan->>'continuation_allowed'<>'true'
       OR jsonb_typeof(plan->'skill_candidates')<>'array'
    THEN RAISE EXCEPTION 'FAIL_OPEN_NOT_PRESERVED:%,%',r.profile_code,plan;END IF;
    count_checked:=count_checked+1;
  END LOOP;
  IF count_checked<>10 THEN RAISE EXCEPTION 'PROFILE_COVERAGE_WRONG:%',count_checked;END IF;

  ctx:=jsonb_build_object(
    'execution_id','EXEC-PROFILE-GATE2-15B9B3F0FA7D6B7C3BFC037A',
    'request_text','Revisar reglas de carga masiva B2B',
    'profile_code','PERFIL-PRODUCT-DIRECTOR-LF',
    'channel','PRODUCTO','step_id','input_validate','consumer','CONTEXT_PACK',
    'scope',jsonb_build_object('resolution_status','RESOLVED','resolved_screen_code','B2B-CARGA-002'),
    'pantalla_codigo','B2B-CARGA-002','legacy_run',true);
  plan:=public.lf_profile_skill_selection_prepare_v2('PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',NULL,ctx);
  IF plan->>'status'<>'READY' OR jsonb_array_length(plan->'skill_candidates')<>2
     OR jsonb_array_length(plan->'skills')<>0
     OR plan->>'finding_status'<>'SKILL_SELECTION_PENDING_FINDING'
  THEN RAISE EXCEPTION 'TWO_ELIGIBLE_MUST_FAIL_OPEN:%',plan;END IF;

  decision:=jsonb_build_object('selected_skill_codes','[]'::jsonb,
    'reason','Se omiten ambas skills opcionales en este RUN');
  plan:=public.lf_profile_skill_selection_prepare_v2('PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',decision,ctx);
  IF plan->>'status'<>'READY' OR jsonb_array_length(plan->'skills')<>0
  THEN RAISE EXCEPTION 'NONE_SELECTION_DENIED:%',plan;END IF;
  decision:=jsonb_build_object('selected_skill_codes',jsonb_build_array('ninguna'),
    'reason','ninguna skill corresponde');
  plan:=public.lf_profile_skill_selection_prepare_v2('PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',decision,ctx);
  IF plan->>'status'<>'READY' OR jsonb_array_length(plan->'skills')<>0
  THEN RAISE EXCEPTION 'NINGUNA_SELECTION_DENIED:%',plan;END IF;

  decision:=jsonb_build_object('selected_skill_codes',
      jsonb_build_array('INPUT_GOVERNANCE_CONTEXT_PACK','SCREEN_RULES_SNAPSHOT'),
      'reason','La revisión usa ambas fuentes vigentes de entrada',
      'review_mode','CURRENT_CONTEXT_REVIEW',
      'evidence_refs',jsonb_build_array(jsonb_build_object('source_ref','lf://screen/44')),
      'descriptor_revisions',jsonb_build_object(
        'INPUT_GOVERNANCE_CONTEXT_PACK','sha256:25dd30f67ed5759209b11a7e7d993d7766bd3c5cedf5f79a61976e25362980dc',
        'SCREEN_RULES_SNAPSHOT','sha256:e1d9545da14de1f43ebab0a803624c79fdac46f2f33b42ff4ce95a9ca849ddb4'));
  plan:=public.lf_profile_skill_selection_prepare_v2('PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',decision,ctx);
  IF plan->>'status'<>'READY' OR jsonb_array_length(plan->'skills')<>2
  THEN RAISE EXCEPTION 'TWO_SKILLS_NOT_SELECTED:%',plan;END IF;
  plan:=public.lf_profile_skill_selection_prepare_v2('PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',
    decision||jsonb_build_object('selected_skill_codes',
     jsonb_build_array('INPUT_GOVERNANCE_CONTEXT_PACK','SCREEN_RULES_SNAPSHOT','PROFILE_UPDATE_APPLY')),ctx);
  IF plan->>'status'<>'BLOCKED' OR plan->>'blocking_code'<>'SKILL_SELECTION_CARDINALITY_INVALID'
  THEN RAISE EXCEPTION 'THREE_SKILLS_NOT_REJECTED:%',plan;END IF;

  ctx:=ctx||jsonb_build_object('profile_code','ACT-0051');
  plan:=public.lf_profile_skill_selection_prepare_v2('ACT-0051','PRODUCTO',NULL,ctx);
  IF plan->>'status'<>'READY' OR jsonb_array_length(plan->'skills')<>1
     OR plan#>>'{skills,0,selection_mode}'<>'DETERMINISTIC_SINGLE_ELIGIBLE_READ_ONLY'
     OR plan->>'finding_status'<>'SKILL_AUTO_SELECTED'
  THEN RAISE EXCEPTION 'SINGLE_SKILL_MUST_AUTOPICK:%',plan;END IF;

  ctx:=ctx||jsonb_build_object('consumer','FORGED_CONSUMER');
  plan:=public.lf_profile_skill_selection_prepare_v2('ACT-0051','PRODUCTO',NULL,ctx);
  IF plan->>'status'<>'READY' OR jsonb_array_length(plan->'skills')<>0
  THEN RAISE EXCEPTION 'INPUT_REQUIRED_NOT_FILTERED:%',plan;END IF;

  FOR r IN SELECT execution_id FROM public.lf_operation_execution
    WHERE execution_id IN (
     'EXEC-PROFILE-GATE2-0248912F0BB40220F116168D',
     'EXEC-PROFILE-GATE2-15B9B3F0FA7D6B7C3BFC037A',
     'EXEC-PROFILE-GATE2-C506666157F990238F37B2C1') ORDER BY execution_id
  LOOP
    plan:=public.lf_profile_execution_plan_for_run_v1(r.execution_id,NULL);
    IF plan->>'status'<>'READY'
       OR jsonb_array_length(plan->'steps')<>11
       OR plan->>'finding_status'<>'SKILL_SELECTION_PENDING_FINDING'
       OR plan->>'continuation_allowed'<>'true'
    THEN RAISE EXCEPTION 'EXISTING_RUN_NOT_RESUMABLE:%,%',r.execution_id,plan;END IF;
  END LOOP;

  FOR r IN SELECT p.proname,pg_get_functiondef(p.oid) AS src
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
    WHERE n.nspname='public' AND p.proname IN (
      'lf_router_pipeline_context_profile_semantic_prepare_v2',
      'lf_router_pipeline_context_profile_semantic_submit_v2',
      'lf_router_pipeline_profile_semantic_prepare_v1',
      'lf_router_pipeline_profile_semantic_submit_v1')
  LOOP
    IF position('PROFILE_SELECTION_REQUESTED' IN r.src)=0
    THEN RAISE EXCEPTION 'PROFILE_VOCAB_NOT_UPDATED:%',r.proname;END IF;
    IF r.proname LIKE '%_prepare_%'
       AND position('PROFILE_SEMANTIC_SELECTION_REQUIRED' IN r.src)>0
    THEN RAISE EXCEPTION 'LEGACY_PROFILE_NAME_OUTSIDE_COMPAT:%',r.proname;END IF;
  END LOOP;
  IF position('TOO_MANY_FORMAS' IN pg_get_functiondef(
    'public.lf_router_stage1_validate_v2(jsonb)'::regprocedure))=0
  THEN RAISE EXCEPTION 'OVERFLOW_FINDING_LOST';END IF;
END $assert$;

WITH v AS (
 SELECT public.lf_router_stage1_validate_v2(
  '{"schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Entra por el router y revisa las reglas de carga masiva del b2b",
    "es_operacion":true,"ambiguo":false,"respuesta_directa":false,
    "sujeto":"reglas de carga masiva B2B",
    "accion":"revisar reglas de carga masiva B2B",
    "formas_busqueda":["B2B_CARGAS","B2B-CARGA-002","lf_ops.reglas","reglas_pantallas","B2B-RULE-LOAD"],
    "alternativas":[],"correcciones":[],"downstream_execution_allowed":false,
    "canal_candidato":"PRODUCTO","negocio_codigo":"LF",
    "razon_seleccion":"Revisión de reglas funcionales B2B",
    "alcance":{"target_type":"PANTALLA","target_hint":"B2B-CARGA-002","resolution_status":"UNRESOLVED"}}'::jsonb) x
)
SELECT CASE WHEN x->>'valid'='true'
  AND x#>>'{findings,0,finding_code}'='TOO_MANY_FORMAS'
  AND jsonb_array_length(x#>'{normalized_stage1,formas_busqueda}')=4
 THEN 'PASS_ROUTER_TOO_MANY_FORMAS_TRUNCATED_FINDING'
 ELSE 'FAIL_ROUTER_STAGE1_OVERFLOW' END FROM v;
SELECT 'PASS_SKILL_OPTIONAL_TEN_PROFILES_THREE_EXISTING_RUNS' AS marker;
