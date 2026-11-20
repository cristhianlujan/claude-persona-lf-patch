"""LF additive family reference inheritance: PG17.6/18.7 BEGIN/ROLLBACK.
Uses exact live source preimages for the five Step60/45/70/80 routines.
Semantic judge results and rule fixtures are SYNTHETIC, never live approvals.
"""
from pathlib import Path
import subprocess
import shutil
import time
import unittest
import uuid
ROOT=Path(__file__).resolve().parents[3]
M=list((ROOT/"supabase/migrations").glob("*_lf_input_family_inheritance_reference_v1.sql"))
SRC=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/fixtures/lf_family_reference_runtime_source_preimages_20261114.sql"
IDS=[
 ("API_DATA_CONTRACT",179),("ASSETS_ICONS",362),("AUDIT",416),
 ("DESIGN_SYSTEM",387),("LOADING_EMPTY_ERROR_STATES",199),("OBSERVABILITY",412),
 ("PRIVACY_PII",411),("SECURITY",396),("TESTING_OBLIGATIONS",424),
 ("VALIDATIONS",25),("VISUAL_EVIDENCE",370)]
BASE=r"""
CREATE ROLE service_role; CREATE ROLE anon; CREATE ROLE authenticated;
CREATE SCHEMA programacion; CREATE SCHEMA lf_ops;
CREATE SCHEMA private; CREATE SCHEMA extensions;
CREATE TABLE lf_ops.pantallas(
  id integer PRIMARY KEY,codigo text UNIQUE,module_id bigint,
  module_code text,activa boolean);
CREATE TABLE lf_ops.modulos(module_id bigint PRIMARY KEY,module_code text,app_shell_code text);
INSERT INTO lf_ops.modulos VALUES(1,'B2B_CARGAS','B2B_APP_SHELL'),(3,'B2B_AUTENTICACION','B2B_APP_SHELL');
INSERT INTO lf_ops.pantallas VALUES(44,'B2B-CARGA-002',1,'B2B_CARGAS',true),
  (51,'B2B-AUTH-001',3,'B2B_AUTENTICACION',true);
CREATE TABLE lf_ops.reglas(
 id integer PRIMARY KEY,codigo text UNIQUE,estado text,es_transversal boolean,
 titulo text,descripcion text,valor_config jsonb DEFAULT '{}'::jsonb);
CREATE TABLE lf_ops.reglas_pantallas(regla_id integer,pantalla_id integer);
CREATE TABLE lf_ops.politicas_rate_limit(
 rate_limit_policy_id bigint PRIMARY KEY,policy_code text,status text,resource_code text);
CREATE TABLE lf_ops.politicas_timeout(
 timeout_policy_id bigint PRIMARY KEY,policy_code text,status text,operation_code text);
CREATE TABLE lf_ops.politicas_sesion(
 session_policy_id bigint PRIMARY KEY,policy_code text,status text,scope_code text);
CREATE TABLE lf_ops.politicas_seguridad(
 security_policy_id bigint PRIMARY KEY,policy_code text,status text,description text);
INSERT INTO lf_ops.politicas_rate_limit VALUES(2,'RATE-B2B-UPLOAD','CANDIDATO','FILE_UPLOAD');
INSERT INTO lf_ops.politicas_timeout VALUES(2,'TIMEOUT-B2B-UPLOAD','CANDIDATO','FILE_UPLOAD');
INSERT INTO lf_ops.politicas_sesion VALUES(1,'SESSION-B2B-DEFAULT','VIGENTE','B2B_APP_SHELL');
INSERT INTO lf_ops.politicas_seguridad VALUES(9,'SEC-B2B-IDEMPOTENCY','CANDIDATO','key');
CREATE TABLE programacion.input_family_reuse_map_v1(
 source_run_id bigint,resolution_path text,transversal_regla_id integer,policy_kind text,policy_code text);
CREATE TABLE programacion.input_family_assessments(id bigint,run_id bigint,coverage_status text);
INSERT INTO programacion.input_family_assessments
 SELECT n,956,CASE WHEN n<=17 THEN 'PARTIAL' ELSE 'COMPLETE' END FROM generate_series(1,47) n;
CREATE FUNCTION public.lf_input_family_reuse_before_propose_v1(integer,text,bigint)
 RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text,target_type text,target_code text,
 status text,manifest jsonb);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text,step_order integer,step_id text,status text,
 evidence_ref text,evidence_payload jsonb);
CREATE TABLE public.lf_operation_step_judge_bindings(
 operation_code text,step_id text,status text,clean_result_value text);
CREATE TABLE public.lf_activos(codigo_activo text,tipo_activo text,archived_at timestamptz,metadata jsonb);
CREATE TABLE public.lf_eventos(id bigint,created_by_execution_id text,payload jsonb);
CREATE TABLE private.lf_context_budget_events_v2(
 id bigint,execution_id text,evidence_event_id bigint,context_status text);
CREATE FUNCTION programacion.fn_t_remed_scope_judge_v1(numeric)
 RETURNS TABLE(regla_id bigint,regla_codigo text,categoria text,real_shells integer,
 category_shells integer,pendiente boolean,verdict text,reason text)
 LANGUAGE sql AS $$SELECT NULL::bigint,NULL::text,NULL::text,NULL::int,
 NULL::int,NULL::boolean,NULL::text,NULL::text WHERE false$$;
CREATE FUNCTION programacion.fn_t_remed_global_rules_v1(numeric)
 RETURNS TABLE(regla_id bigint,regla_codigo text,regla_estado text,screens integer,share numeric,basis text)
 LANGUAGE sql AS $$SELECT NULL::bigint,NULL::text,NULL::text,NULL::int,NULL::numeric,NULL::text WHERE false$$;
CREATE FUNCTION programacion.fn_t_remed_inherited_rules_v1(integer,numeric,boolean)
 RETURNS TABLE(regla_id bigint,regla_codigo text,regla_estado text,share numeric,neighbor_count integer)
 LANGUAGE sql AS $$SELECT NULL::bigint,NULL::text,NULL::text,NULL::numeric,NULL::int WHERE false$$;
CREATE FUNCTION programacion.fn_t_remed_effective_rules_v1(integer,numeric)
 RETURNS TABLE(regla_id bigint,origin text)
 LANGUAGE sql AS $$SELECT NULL::bigint,NULL::text WHERE false$$;
CREATE FUNCTION programacion.fn_input_effective_rule_links_v1(integer,text)
 RETURNS TABLE(pantalla_id integer,regla_id integer,binding_source text)
 LANGUAGE sql AS $$SELECT NULL::int,NULL::int,NULL::text WHERE false$$;
INSERT INTO public.lf_operation_execution VALUES
 ('EXEC-PROFILE-GATE2-FIXTURE44','EJECUCION_PERFIL_LF','PERFIL',
  'PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS','{}'::jsonb);
INSERT INTO public.lf_operation_execution_steps VALUES
 ('EXEC-PROFILE-GATE2-FIXTURE44',40,'input_validate',
 'STEP_PASS_WITH_EVIDENCE','source://40',
 '{"resolved_scope":{"resolved_screen_code":"B2B-CARGA-002"}}'::jsonb);
"""

class FamilyRefPgDual(unittest.TestCase):
 def test_reference_catalog_and_native_bridge_contract(self):
  self.assertEqual(len(M),1)
  self.assertEqual(M[0].name,"20261114224412_lf_input_family_inheritance_reference_v1.sql")
  self.assertTrue(SRC.exists())
  self.assertIsNotNone(shutil.which("docker"),"CI_REQUIRES_DOCKER")
  migration=M[0].read_text("utf8")
  self.assertEqual(migration.count("CREATE OR REPLACE FUNCTION public.lf_input_family_reuse_before_propose_v1"),1)
  self.assertTrue(migration.startswith("-- LF: additive"))
  for banned in ("INSERT INTO lf_ops.reglas","UPDATE lf_ops.reglas",
     "INSERT INTO lf_ops.reglas_pantallas","UPDATE lf_ops.reglas_pantallas",
     "INSERT INTO lf_ops.pantallas_politicas","UPDATE lf_ops.pantallas_politicas",
     "UPDATE programacion.input_family_assessments"):
   self.assertNotIn(banned,migration)
  self.assertEqual(migration.count("SEMANTIC_SELECTION_REQUIRED"),0)
  for fn in ("fn_t_remed_global_rules_v1","fn_t_remed_inherited_rules_v1",
    "fn_t_remed_effective_rules_v1","fn_input_effective_rule_links_v1",
    "fn_t_remed_scope_judge_v1"):
   self.assertIn(fn,migration,"V must consume all five legacy READ-ONLY sources")
  for expected in ("LF_FAMILY_REFERENCE_SOURCE_NOT_VIGENTE","V1_SOURCE_NOT_VIGENTE_OR_SCOPE_OR_HASH",
    "V2_REFERENCE_ONLY_NO_COPIED_CONTENT","V3_DUPLICATE_POLICY_PARAMETERS",
    "V4_EXISTING_HERITABLE_SOURCE_USE_REFERENCE",
    "V5_GAP_SOLUTION_CASES_OR_OWNER_QUESTION_REQUIRED",
    "LF_FAMILY_REUSE_INDEPENDENT_JUDGE_V1","family_source_receipts"):
   self.assertIn(expected,migration)
  assert "\nBEGIN;\n" in migration and migration.endswith("COMMIT;\n")
  inner=migration.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;\n",1)[0]
  seed=BASE
  for family,rid in IDS:
   seed+=(f"INSERT INTO lf_ops.reglas(id,codigo,estado,es_transversal,titulo) VALUES "
       f"({rid},'SOURCE_{rid}','VIGENTE',true,'{family}');\n")
   seed+=(f"INSERT INTO programacion.input_family_reuse_map_v1 VALUES "
       f"(956,'HEREDAR',{rid},NULL,NULL);\n")
  seed+="INSERT INTO lf_ops.reglas(id,codigo,estado,es_transversal,titulo) VALUES (390,'THEME-002','CANDIDATO',true,'Gate night');\n"
  for kind,code in (("SECURITY","SEC-B2B-IDEMPOTENCY"),("RATE_LIMIT","RATE-B2B-UPLOAD"),
      ("SESSION","SESSION-B2B-DEFAULT"),("TIMEOUT","TIMEOUT-B2B-UPLOAD")):
   seed+=("INSERT INTO programacion.input_family_reuse_map_v1 "
          f"VALUES (956,'ATAR_POLITICA',NULL,'{kind}','{code}');\n")
  check=r"""
SELECT 'CATALOG_TOTAL='||count(*) FROM programacion.input_family_inheritable_sources_v1;
SELECT 'RULE_SOURCES='||count(*) FROM programacion.input_family_inheritable_sources_v1 WHERE source_kind='RULE';
SELECT 'POLICY_SOURCES='||count(*) FROM programacion.input_family_inheritable_sources_v1 WHERE source_kind='POLICY';
SELECT 'MEMBERS='||count(*) FROM programacion.input_family_inheritable_members_v1;
SELECT 'CANDIDATE_SOURCES='||count(*) FROM programacion.input_family_inheritable_sources_v1 c
 JOIN lf_ops.reglas r ON r.id=c.rule_id WHERE r.estado='CANDIDATO';
SELECT 'VIEW_CURRENT_44='||count(*) FROM public.v_lf_input_family_coverage_by_screen_v1
 WHERE pantalla_id=44 AND scope_applies AND freshness='CURRENT';
SELECT 'VIEW_CURRENT_51='||count(*) FROM public.v_lf_input_family_coverage_by_screen_v1
 WHERE pantalla_id=51 AND scope_applies AND freshness='CURRENT';
SELECT 'POLICY_RATE_ABSENT='||count(*) FROM public.v_lf_input_family_coverage_by_screen_v1
 WHERE family_code='RATE_LIMIT';
SELECT 'REUSE_AUDIT='||(public.lf_input_family_reuse_before_propose_v1(44,'AUDIT',956)->>'status');
SELECT 'REUSE_SESSION='||(public.lf_input_family_reuse_before_propose_v1(44,'SESSION',956)->>'status');
SELECT 'REUSE_RATE='||(public.lf_input_family_reuse_before_propose_v1(44,'RATE_LIMIT',956)->>'status');
SELECT 'RUN_INDEPENDENT='||(public.lf_input_family_reuse_before_propose_v1(51,'SESSION',NULL)->>'run_independent');
SELECT 'STEP45_SOURCE_COUNT='||(public.lf_input_family_catalog_context_for_run_v1('EXEC-PROFILE-GATE2-FIXTURE44')->>'source_count');
SELECT 'STEP45_CATALOG_SHA='||(
 (public.lf_input_family_catalog_context_for_run_v1('EXEC-PROFILE-GATE2-FIXTURE44')->>'snapshot_sha256') ~ '^[a-f0-9]{64}$')::text;
SELECT 'NO_ASSESSMENT_WRITES='||count(*) FROM programacion.input_family_assessments;
SELECT 'ANON_NO_EXEC='||NOT has_function_privilege('anon',
 'public.lf_input_family_reuse_claims_gate_v1(integer,jsonb)','EXECUTE');
SELECT 'SERVICE_EXEC='||has_function_privilege('service_role',
 'public.lf_input_family_reuse_claims_gate_v1(integer,jsonb)','EXECUTE');
CREATE TEMP TABLE fixture_assertions(name text PRIMARY KEY, status text);
DO $test$
DECLARE h text; x bigint; o jsonb;j jsonb;
        v_initial integer; v_message text; v_sqlstate text;
        v_positive_source_id bigint; v_previous_description text;
        v_source_hash text; v_current_hash text;
BEGIN
 SELECT count(*) INTO v_initial FROM programacion.input_family_inheritable_sources_v1;
 IF v_initial<>12 THEN RAISE EXCEPTION 'TEST_INITIAL_CATALOG_NOT_12:%',v_initial; END IF;
 SELECT source_hash,source_id INTO h,x
 FROM programacion.input_family_inheritable_sources_v1
 WHERE family_code='AUDIT';
 o:=public.lf_input_family_reuse_claims_gate_v1(44,
 jsonb_build_array(jsonb_build_object('family_code','AUDIT',
 'action','REUSE_REFERENCE','source_catalog_id',x,'source_hash',h)));
 IF o->>'status'<>'REFERENCE_CLAIMS_READY_FOR_INDEPENDENT_REVIEW'
 THEN RAISE EXCEPTION 'POSITIVE_RULE_REUSE_REJECTED:%',o; END IF;
 INSERT INTO fixture_assertions VALUES('V1_VALID_RULE','PASS');
 o:=public.lf_input_family_reuse_claims_gate_v1(44,
 jsonb_build_array(jsonb_build_object('family_code','AUDIT',
 'action','REUSE_REFERENCE','source_catalog_id',x,'source_hash',h,
 'rule_text','COPIED_FORBIDDEN')));
 IF o->'findings'->0->>'code'<>'V2_REFERENCE_ONLY_NO_COPIED_CONTENT'
 THEN RAISE EXCEPTION 'V2_COPY_NOT_REJECTED:%',o; END IF;
 INSERT INTO fixture_assertions VALUES('V2_NO_CONTENT_COPY','PASS');
 o:=public.lf_input_family_reuse_claims_gate_v1(44,
 jsonb_build_array(jsonb_build_object('family_code','AUDIT','action','PROPOSE_RULE',
 'solution','duplicate rejected')));
 IF o->'findings'->0->>'code'<>'V4_EXISTING_HERITABLE_SOURCE_USE_REFERENCE'
 THEN RAISE EXCEPTION 'V4_DUPLICATE_NOT_REJECTED:%',o; END IF;
 INSERT INTO fixture_assertions VALUES('V4_NO_DUPLICATE_RULE','PASS');
 o:=public.lf_input_family_reuse_claims_gate_v1(44,
 '[{"family_code":"MISSING_FAMILY","action":"GAP"}]'::jsonb);
 IF o->'findings'->0->>'code'<>'V5_GAP_SOLUTION_CASES_OR_OWNER_QUESTION_REQUIRED'
 THEN RAISE EXCEPTION 'V5_RETURN_TO_WORKER_MISSING:%',o; END IF;
 INSERT INTO fixture_assertions VALUES('V5_RETURN_TO_WORKER','PASS');
 o:=public.lf_input_family_reuse_claims_gate_v1(44,
 '[{"family_code":"MISSING_FAMILY","action":"GAP","cases":[{"when":"no source","result":"ask curator"}]}]'::jsonb);
 IF o->>'status'<>'REFERENCE_CLAIMS_READY_FOR_INDEPENDENT_REVIEW'
 THEN RAISE EXCEPTION 'V5_CASES_REJECTED:%',o; END IF;
 INSERT INTO fixture_assertions VALUES('V5_CASES_PROVIDED','PASS');
 o:=public.lf_input_family_reuse_claims_gate_v1(44,
 '[{"family_code":"MISSING_FAMILY","action":"GAP",
 "owner_question":{"question":"Select option","recommended_option":"A"}}]'::jsonb);
 IF o->>'status'<>'RETURN_TO_WORKER' THEN
   RAISE EXCEPTION 'OPEN_QUESTION_FALSELY_ACCEPTED:%',o; END IF;
 INSERT INTO fixture_assertions VALUES('V5_OPEN_QUESTION_REJECTED','PASS');
 o:=public.lf_input_family_reuse_claims_gate_v1(44,
 '[{"family_code":"MISSING_FAMILY","action":"GAP",
 "owner_question":{"question":"Select option","options":["A","B"],
 "recommended_option":"A"}}]'::jsonb);
 IF o->>'status'<>'REFERENCE_CLAIMS_READY_FOR_INDEPENDENT_REVIEW' THEN
   RAISE EXCEPTION 'CLOSED_QUESTION_NOT_ACCEPTED:%',o; END IF;
 INSERT INTO fixture_assertions VALUES('V5_CLOSED_QUESTION_VALID','PASS');
 SELECT source_hash,source_id INTO h,x FROM programacion.input_family_inheritable_sources_v1
 WHERE family_code='SESSION';
 o:=public.lf_input_family_reuse_claims_gate_v1(44,
 jsonb_build_array(jsonb_build_object('family_code','SESSION',
 'action','REUSE_REFERENCE','source_catalog_id',x,'source_hash',h,
 'parameter_values',jsonb_build_object('timeout',42))));
 IF o->'findings'->0->>'code'<>'V3_DUPLICATE_POLICY_PARAMETERS'
 THEN RAISE EXCEPTION 'V3_PARAMS_COPY_NOT_REJECTED:%',o; END IF;
 INSERT INTO fixture_assertions VALUES('V3_NO_POLICY_PARAMS_COPY','PASS');
 -- Negative 1: CANDIDATO must raise the exact guarded error.
 BEGIN
  INSERT INTO programacion.input_family_inheritable_sources_v1(
  family_code,source_kind,rule_id,scope_kind,source_hash,
  semantic_equivalence,semantic_transferability,semantic_evidence_ref,semantic_reason_code)
  SELECT 'THEME_LIGHT_DARK_SYSTEM','RULE',390,'GLOBAL',
  encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),
  'EQUIVALENT_COMPONENT','TRANSFERABLE',
  'supabase://lf_ops.reglas/390#source_hash','UNAPPROVED_THEME'
  FROM lf_ops.reglas r WHERE r.id=390;
  RAISE EXCEPTION 'CANDIDATE_WAS_INSERTED';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT,v_sqlstate=RETURNED_SQLSTATE;
  IF v_sqlstate<>'P0001'
     OR v_message<>'LF_FAMILY_REFERENCE_SOURCE_NOT_VIGENTE:THEME_LIGHT_DARK_SYSTEM,RULE'
  THEN RAISE EXCEPTION 'CANDIDATE_WRONG_ERROR:%,%',v_sqlstate,v_message; END IF;
  RAISE NOTICE 'CASE_CANDIDATO_SQLERRM=%',v_message;
 END;
 IF (SELECT count(*) FROM programacion.input_family_inheritable_sources_v1)<>v_initial
 THEN RAISE EXCEPTION 'CANDIDATE_CATALOG_COUNT_DRIFT'; END IF;
 INSERT INTO fixture_assertions VALUES('CANDIDATO_SOURCE_REJECTED','PASS');

 -- Two independent fixture rules exist only inside the enclosing ROLLBACK.
 INSERT INTO lf_ops.reglas(id,codigo,estado,es_transversal,titulo)
 VALUES (6,'TEST_NONTRANSVERSAL','VIGENTE',false,'Nontransversal fixture'),
        (21,'TEST_TRANSVERSAL','VIGENTE',true,'Transversal fixture');

 -- Negative 2: VIGENTE non-transversal is rejected even with matching SHA.
 BEGIN
  INSERT INTO programacion.input_family_inheritable_sources_v1(
  family_code,source_kind,rule_id,scope_kind,source_hash,
  semantic_equivalence,semantic_transferability,semantic_evidence_ref,semantic_reason_code)
  SELECT 'TEST_NONTRANSVERSAL','RULE',r.id,'GLOBAL',
   encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),
   'EQUIVALENT_COMPONENT','TRANSFERABLE',
   'fixture://nontransversal-6','NONTRANSVERSAL_NEGATIVE'
  FROM lf_ops.reglas r WHERE r.id=6;
  RAISE EXCEPTION 'NONTRANSVERSAL_WAS_INSERTED';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT,v_sqlstate=RETURNED_SQLSTATE;
  IF v_sqlstate<>'P0001'
    OR v_message<>'LF_FAMILY_REFERENCE_SOURCE_NOT_VIGENTE:TEST_NONTRANSVERSAL,RULE'
  THEN RAISE EXCEPTION 'NONTRANSVERSAL_WRONG_ERROR:%,%',v_sqlstate,v_message; END IF;
  RAISE NOTICE 'CASE_NONTRANSVERSAL_SQLERRM=%',v_message;
 END;
 IF (SELECT count(*) FROM programacion.input_family_inheritable_sources_v1)<>v_initial
 THEN RAISE EXCEPTION 'NONTRANSVERSAL_CATALOG_COUNT_DRIFT'; END IF;
 INSERT INTO fixture_assertions VALUES('NONTRANSVERSAL_SOURCE_REJECTED','PASS');

 -- Negative 3: VIGENTE/transversal with an incorrect 64-character SHA.
 BEGIN
  INSERT INTO programacion.input_family_inheritable_sources_v1(
  family_code,source_kind,rule_id,scope_kind,source_hash,
  semantic_equivalence,semantic_transferability,semantic_evidence_ref,semantic_reason_code)
  SELECT 'TEST_HASH_MISMATCH','RULE',r.id,'GLOBAL',repeat('0',64),
   'PARTIAL_BASE','TRANSFERABLE',
   'fixture://hash-mismatch-179','SOURCE_SHA_NEGATIVE'
  FROM lf_ops.reglas r WHERE r.id=179;
  RAISE EXCEPTION 'SHA_MISMATCH_WAS_INSERTED';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT,v_sqlstate=RETURNED_SQLSTATE;
  IF v_sqlstate<>'P0001'
    OR v_message<>'LF_FAMILY_REFERENCE_SOURCE_SHA_MISMATCH:TEST_HASH_MISMATCH'
  THEN RAISE EXCEPTION 'SHA_MISMATCH_WRONG_ERROR:%,%',v_sqlstate,v_message; END IF;
  RAISE NOTICE 'CASE_SHA_MISMATCH_SQLERRM=%',v_message;
 END;
 IF (SELECT count(*) FROM programacion.input_family_inheritable_sources_v1)<>v_initial
 THEN RAISE EXCEPTION 'SHA_MISMATCH_CATALOG_COUNT_DRIFT'; END IF;
 INSERT INTO fixture_assertions VALUES('SOURCE_SHA_MISMATCH_REJECTED','PASS');

 -- Positive 4: matching SHA for a VIGENTE transversal source passes the guard.
 INSERT INTO programacion.input_family_inheritable_sources_v1(
  family_code,source_kind,rule_id,scope_kind,source_hash,
  semantic_equivalence,semantic_transferability,semantic_evidence_ref,semantic_reason_code)
 SELECT 'TEST_VALID_TRANSVERSAL','RULE',r.id,'GLOBAL',
  encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),
  'EQUIVALENT_COMPONENT','TRANSFERABLE',
  'fixture://positive-transversal-21','SOURCE_VIGENTE_TRANSVERSAL'
 FROM lf_ops.reglas r WHERE r.id=21
 RETURNING source_id INTO v_positive_source_id;
 IF v_positive_source_id IS NULL OR
   (SELECT count(*) FROM programacion.input_family_inheritable_sources_v1)<>v_initial+1
 THEN RAISE EXCEPTION 'VALID_TRANSVERSAL_INSERT_NOT_ACCEPTED'; END IF;
 DELETE FROM programacion.input_family_inheritable_sources_v1
 WHERE source_id=v_positive_source_id;
 IF (SELECT count(*) FROM programacion.input_family_inheritable_sources_v1)<>v_initial
 THEN RAISE EXCEPTION 'VALID_TRANSVERSAL_CATALOG_COUNT_DRIFT'; END IF;
 RAISE NOTICE 'CASE_VALID_TRANSVERSAL_SQLERRM=NONE';
 INSERT INTO fixture_assertions VALUES('VIGENTE_TRANSVERSAL_SOURCE_ACCEPTED','PASS');
 -- Independent judge schema and references (fixture, no real model).
 SELECT source_hash,source_id INTO h,x FROM programacion.input_family_inheritable_sources_v1
 WHERE family_code='AUDIT';
 j:=jsonb_build_object('schema_version','LF_FAMILY_REUSE_INDEPENDENT_JUDGE_V1',
 'reviews',jsonb_build_array(jsonb_build_object('family_code','AUDIT',
 'action','REUSE_REFERENCE','source_catalog_id',x,'source_hash',h,
 'equivalence','EQUIVALENT_COMPONENT','transferability','TRANSFERABLE',
 'reason','Source component matches append-only audit only',
 'source_refs',jsonb_build_array('supabase://lf_ops.reglas/416'))));
 o:=public.lf_input_family_semantic_transfer_eval_v1(44,
 jsonb_build_array(jsonb_build_object('family_code','AUDIT',
 'action','REUSE_REFERENCE','source_catalog_id',x,'source_hash',h)),j);
 IF o->>'status'<>'JUDGE_EVIDENCE_VALIDATED' OR
 o->>'actual_independent_receipt_required'<>'true' THEN
 RAISE EXCEPTION 'SEMANTIC_SCHEMA_POSITIVE_FAILED:%',o; END IF;
 INSERT INTO fixture_assertions VALUES('70_JUDGE_SCHEMA_OWN','PASS');
 SELECT source_hash,source_id INTO h,x FROM programacion.input_family_inheritable_sources_v1
 WHERE family_code='ASSETS_ICONS';
 j:=jsonb_build_object('schema_version','LF_FAMILY_REUSE_INDEPENDENT_JUDGE_V1',
 'reviews',jsonb_build_array(jsonb_build_object('family_code','ASSETS_ICONS',
 'action','REUSE_REFERENCE','source_catalog_id',x,'source_hash',h,
 'equivalence','EQUIVALENT_COMPONENT','transferability','TRANSFERABLE',
 'reason','Synthetic false upgrade of asset provenance to full icons coverage',
 'source_refs',jsonb_build_array('fixture://fake'))));
 o:=public.lf_input_family_semantic_transfer_eval_v1(44,
 jsonb_build_array(jsonb_build_object('family_code','ASSETS_ICONS',
 'action','REUSE_REFERENCE','source_catalog_id',x,'source_hash',h)),j);
 IF o->>'status'<>'RETURN_TO_WORKER' OR
   o->'findings'->0->>'code'<>'INDEPENDENT_SEMANTIC_EQUIVALENCE_OR_TRANSFERABILITY_CONTRADICTS_SOURCE'
 THEN RAISE EXCEPTION 'JUDGE_FALSE_EQUIVALENCE_ALLOWED:%',o; END IF;
 INSERT INTO fixture_assertions VALUES('70_SOURCE_SEMANTIC_DRIFT_REJECTED','PASS');
 o:=public.lf_input_family_semantic_transfer_eval_v1(44,
 jsonb_build_array(jsonb_build_object('family_code','AUDIT',
 'action','REUSE_REFERENCE','source_catalog_id',x,'source_hash',h)),NULL);
 IF o->>'status'<>'RETURN_TO_WORKER' THEN RAISE EXCEPTION 'JUDGE_MISSING_FALSE_PASS'; END IF;
 INSERT INTO fixture_assertions VALUES('70_MISSING_JUDGE_NOT_PASS','PASS');
 -- Positive 5: change a non-status source field; read-time hash must become STALE.
 SELECT descripcion INTO v_previous_description FROM lf_ops.reglas WHERE id=416;
 SELECT source_hash INTO v_source_hash
 FROM programacion.input_family_inheritable_sources_v1 WHERE rule_id=416;
 IF (SELECT freshness FROM public.v_lf_input_family_coverage_by_screen_v1
     WHERE pantalla_id=44 AND family_code='AUDIT')<>'CURRENT'
 THEN RAISE EXCEPTION 'STALE_PRECONDITION_NOT_CURRENT'; END IF;
 UPDATE lf_ops.reglas SET descripcion='SOURCE_HASH_CHANGED_IN_ROLLBACK' WHERE id=416;
 SELECT current_source_hash INTO v_current_hash
 FROM public.v_lf_input_family_coverage_by_screen_v1
 WHERE pantalla_id=44 AND family_code='AUDIT';
 IF v_current_hash IS NOT DISTINCT FROM v_source_hash
   OR (SELECT estado FROM lf_ops.reglas WHERE id=416)<>'VIGENTE'
   OR (SELECT freshness FROM public.v_lf_input_family_coverage_by_screen_v1
       WHERE pantalla_id=44 AND family_code='AUDIT')<>'STALE'
 THEN RAISE EXCEPTION 'STALE_HASH_READTIME_NOT_RECOGNIZED'; END IF;
 IF (public.lf_input_family_reuse_before_propose_v1(44,'AUDIT',956)->>'status')
   <>'STALE_SOURCE_REVIEW' THEN RAISE EXCEPTION 'STALE_WRAPPER_INVALID'; END IF;
 UPDATE lf_ops.reglas SET descripcion=v_previous_description WHERE id=416;
 IF (SELECT freshness FROM public.v_lf_input_family_coverage_by_screen_v1
       WHERE pantalla_id=44 AND family_code='AUDIT')<>'CURRENT'
 THEN RAISE EXCEPTION 'STALE_RESTORE_NOT_CURRENT'; END IF;
 IF (SELECT count(*) FROM programacion.input_family_inheritable_sources_v1)<>v_initial
 THEN RAISE EXCEPTION 'STALE_CATALOG_COUNT_DRIFT'; END IF;
 RAISE NOTICE 'CASE_STALE_SOURCE_FIELD_SQLERRM=NONE,FRESHNESS=STALE';
 INSERT INTO fixture_assertions VALUES('STALE_SOURCE_READTIME','PASS');
 -- 80: REF+HASH only, never content/parameters.
 SELECT jsonb_agg(jsonb_build_object('family_code',c.family_code,'action','REUSE_REFERENCE',
   'source_catalog_id',c.source_id,'source_hash',c.source_hash))
   INTO j FROM programacion.input_family_inheritable_sources_v1 c
 WHERE c.family_code='SESSION';
 INSERT INTO public.lf_operation_execution_steps VALUES
 ('EXEC-PROFILE-GATE2-FIXTURE44',50,'execute_profile','STEP_PASS_WITH_EVIDENCE','fixture://50',
 jsonb_build_object('profile_output',jsonb_build_object('traceability',
 jsonb_build_object('family_reuse_claims',j))));
 IF jsonb_array_length(public.lf_input_family_catalog_receipts_for_run_v1(
  'EXEC-PROFILE-GATE2-FIXTURE44'))<>1 THEN RAISE EXCEPTION 'STEP80_REF_HASH_MISSING'; END IF;
 INSERT INTO fixture_assertions VALUES('80_REF_HASH_ONLY','PASS');
 IF (SELECT count(*) FROM programacion.input_family_inheritable_sources_v1)<>v_initial
 THEN RAISE EXCEPTION 'FINAL_CATALOG_COUNT_DRIFT'; END IF;
END $test$;
SELECT 'ASSERTIONS='||count(*) FROM fixture_assertions WHERE status='PASS';
SELECT 'POST_ASSERT_CATALOG='||count(*) FROM programacion.input_family_inheritable_sources_v1;
SELECT 'POST_ASSERT_CANDIDATE_SOURCE='||count(*) FROM programacion.input_family_inheritable_sources_v1 WHERE rule_id=390;
"""
  for image in ("17.6","18.7"):
   with self.subTest(postgres=image):
    name="lf-family-ref-"+uuid.uuid4().hex[:10]
    started=subprocess.run(["docker","run","-d","--rm","--name",name,
       "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+image],
      capture_output=True,text=True,timeout=180)
    self.assertEqual(started.returncode,0,started.stderr)
    try:
     rdy=None
     for _ in range(120):
      rdy=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
       capture_output=True,timeout=8)
      log=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=8)
      if rdy.returncode==0 and "PostgreSQL init process complete; ready for start up." in (log.stdout+log.stderr):
       break
      time.sleep(.7)
     self.assertEqual(rdy.returncode,0)
     def psql(text):
      return subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq",
       "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
       input=text,capture_output=True,text=True,timeout=140)
     fixture=psql(seed+"\nSET check_function_bodies=off;\n"+SRC.read_text("utf-8"))
     self.assertEqual(fixture.returncode,0,fixture.stderr[-5200:])
     txn="BEGIN;\n"+inner+"\n"+check+"\nROLLBACK;\n"
     txn+="SELECT 'ROLLED_BACK='||(to_regclass('programacion.input_family_inheritable_sources_v1') IS NULL)::text;\n"
     txn+="SELECT 'BASE_RULES_UNCHANGED='||count(*) FROM lf_ops.reglas WHERE estado='VIGENTE';\n"
     txn+="SELECT 'BASE_ASSESSMENTS_UNCHANGED='||count(*) FROM programacion.input_family_assessments;\n"
     rr=psql(txn)
     self.assertEqual(rr.returncode,0,rr.stderr[-8500:])
     expect=["CATALOG_TOTAL=12","RULE_SOURCES=11","POLICY_SOURCES=1",
       "MEMBERS=0","CANDIDATE_SOURCES=0","VIEW_CURRENT_44=12",
       "VIEW_CURRENT_51=12","POLICY_RATE_ABSENT=0",
       "REUSE_AUDIT=REFERENCE_REUSE_AVAILABLE_WITH_FINDINGS",
       "REUSE_SESSION=REFERENCE_REUSE_AVAILABLE_WITH_FINDINGS",
       "REUSE_RATE=RETURN_TO_WORKER","RUN_INDEPENDENT=true",
       "STEP45_SOURCE_COUNT=12","STEP45_CATALOG_SHA=true",
       "NO_ASSESSMENT_WRITES=47","ANON_NO_EXEC=true","SERVICE_EXEC=true",
       "ASSERTIONS=17","POST_ASSERT_CATALOG=12",
       "POST_ASSERT_CANDIDATE_SOURCE=0","ROLLED_BACK=true",
       "BASE_RULES_UNCHANGED=11","BASE_ASSESSMENTS_UNCHANGED=47"]
     for wanted in expect:
      self.assertIn(wanted,rr.stdout,wanted+"\n"+rr.stdout[-5500:])
     expected_case_markers=[
       "CASE_CANDIDATO_SQLERRM=LF_FAMILY_REFERENCE_SOURCE_NOT_VIGENTE:THEME_LIGHT_DARK_SYSTEM,RULE",
       "CASE_NONTRANSVERSAL_SQLERRM=LF_FAMILY_REFERENCE_SOURCE_NOT_VIGENTE:TEST_NONTRANSVERSAL,RULE",
       "CASE_SHA_MISMATCH_SQLERRM=LF_FAMILY_REFERENCE_SOURCE_SHA_MISMATCH:TEST_HASH_MISMATCH",
       "CASE_VALID_TRANSVERSAL_SQLERRM=NONE",
       "CASE_STALE_SOURCE_FIELD_SQLERRM=NONE,FRESHNESS=STALE",
     ]
     for marker in expected_case_markers:
      self.assertIn(marker,rr.stderr,marker+"\\n"+rr.stderr[-5000:])
      print(marker)
     print("PASS_LF_FAMILY_REFERENCE_PG"+image+
       "_12_SOURCES_CANDIDATE_REJECT_V1_V5_STEP45_60_70_80_ROLLBACK_TRUE")
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
