-- Evidence-only source-bound contract check, Product Director Step50/60 RAW.
-- Precedes Step70 TRAIN_EVIDENCE_AUTOMATICO and actual owner V2 CREATE.
-- Does not simulate or register a human decision, skill invocation, or promotion.
BEGIN;
DO $ig_pg17_create_contract$
DECLARE
 v_run constant text := 'EXEC-PROFILE-GATE2-103AA9E9039805D81315B92F';
 v_rule constant text := 'IG-PG17-SCREEN-CREATE-001';
 v_patch jsonb; v_src text; v_old_rules text; v_new_rules text;
 v_old_history text; v_new_history text; v_proposal_sha text;
 v_missing_scope jsonb; v_missing_screen jsonb; v_screen integer;
BEGIN
 IF current_setting('server_version_num')::int / 10000<>17 THEN
  RAISE EXCEPTION 'LF_IG_PG17_EXACT_VERSION_REQUIRED';
 END IF;
 SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}',
 s.evidence_payload#>>'{profile_output,deliverable_created,product_decision,proposed_by}'
 INTO STRICT v_patch,v_src
 FROM public.lf_operation_execution_steps s
 JOIN public.lf_operation_execution e ON e.execution_id=s.execution_id
 WHERE s.execution_id=v_run AND s.step_id='execute_profile'
 AND s.status='STEP_PASS_WITH_EVIDENCE'
 AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF'
 AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
 AND e.manifest->>'read_only'='true'
 AND e.manifest->>'no_write'='true'
 AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='B2B-CARGA-002';
 SELECT id INTO STRICT v_screen FROM lf_ops.pantallas
 WHERE codigo='B2B-CARGA-002' AND activa;
 IF v_src IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF'
 OR v_patch->>'rule_code'<>v_rule
 OR v_patch->>'change_kind'<>'CREATE'
 OR v_patch#>>'{changes,valor_config,lf_rule_scope}'<>'PANTALLA'
 OR v_patch#>'{changes,valor_config,lf_screen_ids}' IS DISTINCT FROM jsonb_build_array(v_screen)
 OR v_patch#>>'{changes,valor_config,production_authorized}'<>'false'
 OR v_patch#>>'{changes,es_transversal}'<>'false'
 OR nullif(v_patch#>>'{changes,razon}','') IS NULL
 OR nullif(v_patch#>>'{changes,origen}','') IS NULL
 OR v_patch#>>'{changes,descripcion}' NOT ILIKE '%Condicion:%'
 OR v_patch#>>'{changes,descripcion}' NOT ILIKE '%Alcance:%'
 OR v_patch#>>'{changes,descripcion}' NOT ILIKE '%Resultado:%'
 THEN RAISE EXCEPTION 'LF_IG_PG17_PATCH_FIELDS_OR_SCOPE_INVALID'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution_steps
 WHERE execution_id=v_run AND step_id='output_validate'
 AND status='STEP_PASS_WITH_EVIDENCE'
 AND evidence_payload->>'output_contract_result'='PASS') THEN
   RAISE EXCEPTION 'LF_IG_PG17_STEP60_INVALID';
 END IF;
 v_proposal_sha:=encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex');
 IF v_proposal_sha<>'d122d6cbf21d15954701b0bd90be8fed1e176f0a7b7c861b3336d36845d925ca'
 OR encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||v_rule,'UTF8'),'sha256'),'hex')<>'4b652b2dc6f5082d8c571c6e573d4fe4684101922f531aa4cbbfbe92f7822986'
 THEN RAISE EXCEPTION 'LF_IG_PG17_PATCH_SHA_OR_SOURCE_DRIFT'; END IF;
 IF EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo=v_rule)
 OR EXISTS (SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE rule_code=v_rule)
 THEN RAISE EXCEPTION 'LF_IG_PG17_PREMATURE_RULE_OR_OWNER'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]')) INTO v_old_rules
 FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(h) ORDER BY codigo,version)::text,'[]')) INTO v_old_history
 FROM lf_ops.reglas_versiones h;

 -- These are deliberately NOT claims of runtime writer acceptance/rejection:
 -- objective-only contract checks of malformed versus corrected JSON inputs.
 v_missing_scope:=v_patch#>'{changes,valor_config}'-'lf_rule_scope';
 v_missing_screen:=jsonb_set(v_patch#>'{changes,valor_config}','{lf_screen_ids}','[]'::jsonb);
 IF v_missing_scope ? 'lf_rule_scope'
 OR v_missing_screen->'lf_screen_ids' IS DISTINCT FROM '[]'::jsonb
 OR (v_patch#>'{changes,valor_config}')->>'lf_rule_scope'<>'PANTALLA'
 OR (v_patch#>'{changes,valor_config}')->'lf_screen_ids' IS DISTINCT FROM jsonb_build_array(v_screen)
 THEN RAISE EXCEPTION 'LF_IG_PG17_NEGATIVE_POSITIVE_CONTRACT_PAIR_FAILED'; END IF;
 IF position('LF_RULE_CREATE_SCOPE_REQUIRED' in
    pg_get_functiondef('public.lf_regla_candidate_write_v1(text,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure))=0
 OR position('LF_RULE_CREATE_SCREEN_REQUIRED' in
    pg_get_functiondef('public.lf_regla_candidate_write_v1(text,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure))=0
 OR position('LF_RULE_CREATE_IG_V2_REQUIRED' in
    pg_get_functiondef('public.lf_regla_candidate_write_v1(text,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'LF_IG_PG17_WRITER_MESSAGES_NOT_PRESENT'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]')) INTO v_new_rules
 FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(h) ORDER BY codigo,version)::text,'[]')) INTO v_new_history
 FROM lf_ops.reglas_versiones h;
 IF v_new_rules IS DISTINCT FROM v_old_rules OR v_new_history IS DISTINCT FROM v_old_history
 THEN RAISE EXCEPTION 'LF_IG_PG17_CANONICAL_MUTATION_UNEXPECTED'; END IF;
 RAISE NOTICE 'LF_IG_PG17_RULE_CONTRACT_LEVEL_PASS:rule=%:sha=%:screen=%:negative_variants=2:positive_spec=1:writer_invocations=0:owner_decisions=0',
 v_rule,v_proposal_sha,v_screen;
END;
$ig_pg17_create_contract$;
ROLLBACK;
