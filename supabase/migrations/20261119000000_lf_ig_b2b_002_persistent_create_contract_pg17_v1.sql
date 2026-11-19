-- LF IG Fase 2, preflight: contract-bound proof for NEW Product Director RUN.
-- Signed REAL Merge Train evidence consumed by Step70/owner V2 in follow-up PR.
-- This stage makes NO persistent rule changes. BEGIN/ROLLBACK PG17.
BEGIN;
DO $ig_b2b_002_contract$
DECLARE
 v_run constant text:='EXEC-PROFILE-GATE2-258A773626E5527875866440';
 v_new constant text:='B2B-RULE-VALIDATION-VALID-ONLY-002';
 v_old constant text:='B2B-RULE-VALIDATION-VALID-ONLY-001';
 v_expected_sha constant text:='f08fc4166cddd37b8d4c17157cb09b45039264a7ab0bb0da162f75cbffe51e9a';
 v_patch jsonb;
 v_before_rules text;v_after_rules text;v_before_hist text;v_after_hist text;
 v_old_config jsonb;v_new_config jsonb;v_source_sha text;
BEGIN
 IF current_setting('server_version_num')::int / 10000<>17
 THEN RAISE EXCEPTION 'LF_IG_B2B_002_PG17_REQUIRED'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas)<>586 OR (SELECT count(*) FROM lf_ops.reglas_versiones)<>586
 THEN RAISE EXCEPTION 'LF_IG_B2B_002_BASELINE_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_new)
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE rule_code=v_new)
 OR EXISTS(SELECT 1 FROM public.lf_ig_rule_change_v2 WHERE rule_code=v_new)
 THEN RAISE EXCEPTION 'LF_IG_B2B_002_NOT_ABSENT'; END IF;
 SELECT valor_config INTO STRICT v_old_config FROM lf_ops.reglas WHERE codigo=v_old AND estado='VIGENTE';
 IF (SELECT array_agg(pantalla_id ORDER BY pantalla_id) FROM lf_ops.reglas_pantallas WHERE regla_id=(SELECT id FROM lf_ops.reglas WHERE codigo=v_old))
  IS DISTINCT FROM ARRAY[44,66,67]::int[]
 OR (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_old)<>1
 OR (SELECT count(*) FROM lf_ops.reglas r WHERE r.codigo<>v_old AND r.valor_config::text LIKE '%'||v_old||'%')<>3
 THEN RAISE EXCEPTION 'LF_IG_B2B_002_OLD_DEPENDENCIES_DRIFT'; END IF;
 SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}'
 INTO STRICT v_patch FROM public.lf_operation_execution_steps s
 JOIN public.lf_operation_execution p ON p.execution_id=s.execution_id
 WHERE s.execution_id=v_run AND s.step_id='execute_profile' AND s.status='STEP_PASS_WITH_EVIDENCE'
  AND p.operation_code='EJECUCION_PERFIL_LF' AND p.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
  AND p.status='IN_PROGRESS' AND p.manifest->>'read_only'='true' AND p.manifest->>'no_write'='true'
  AND p.manifest#>>'{screen_selection_result,selected_screen_code}'='B2B-CARGA-002'
  AND s.evidence_payload#>>'{profile_output,deliverable_created,product_decision,proposed_by}'='PERFIL-PRODUCT-DIRECTOR-LF';
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id=v_run
 AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE'
 AND s.evidence_payload->>'output_contract_result'='PASS')
 THEN RAISE EXCEPTION 'LF_IG_B2B_002_STEP60_MISSING'; END IF;
 v_source_sha:=encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||v_new,'UTF8'),'sha256'),'hex');
 IF v_source_sha IS DISTINCT FROM 'bd8c5508b511132662ae23149ca5603ec3f6807edf19c165f7399a1d1700c3bf'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM v_expected_sha
 OR v_patch->>'rule_code' IS DISTINCT FROM v_new
 OR v_patch->>'change_kind' IS DISTINCT FROM 'CREATE'
 OR v_patch#>>'{changes,valor_config,lf_rule_scope}' IS DISTINCT FROM 'PANTALLA'
 OR v_patch#>'{changes,valor_config,lf_screen_ids}' IS DISTINCT FROM '[44,66,67]'::jsonb
 OR v_patch#>>'{changes,es_transversal}' IS DISTINCT FROM 'false'
 OR v_patch#>>'{changes,valor_config,lf_replaces_rule_code}' IS DISTINCT FROM v_old
 THEN RAISE EXCEPTION 'LF_IG_B2B_002_SOURCE_PATCH_OR_SCOPE_DRIFT'; END IF;
 v_new_config:=v_patch#>'{changes,valor_config}';
 IF (v_new_config - 'lf_rule_scope' - 'lf_screen_ids' - 'lf_applicability' - 'lf_replaces_rule_code' - 'lf_promotion_authorized') IS DISTINCT FROM v_old_config
 THEN RAISE EXCEPTION 'LF_IG_B2B_002_CONFIG_LOSS'; END IF;
 IF (v_patch#>>'{changes,descripcion}') NOT ILIKE '%Condicion:%'
 OR (v_patch#>>'{changes,descripcion}') NOT ILIKE '%Alcance:%'
 OR (v_patch#>>'{changes,descripcion}') NOT ILIKE '%Resultado:%'
 OR nullif(v_patch#>>'{changes,razon}','') IS NULL
 OR nullif(v_patch#>>'{changes,origen}','') IS NULL
 THEN RAISE EXCEPTION 'LF_IG_B2B_002_RULE_QUALITY_INCOMPLETE'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]')) INTO v_before_rules FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo,r.version)::text,'[]')) INTO v_before_hist FROM lf_ops.reglas_versiones r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]')) INTO v_after_rules FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo,r.version)::text,'[]')) INTO v_after_hist FROM lf_ops.reglas_versiones r;
 IF v_before_rules IS DISTINCT FROM v_after_rules OR v_before_hist IS DISTINCT FROM v_after_hist
 THEN RAISE EXCEPTION 'LF_IG_B2B_002_PREFLIGHT_MUTATED_CANONICAL'; END IF;
 RAISE NOTICE 'LF_IG_B2B_002_CONTRACT_PASS:profile_run=%:source_sha=%:patch_sha=%:old=VIGENTE:new=ABSENT:3screens:1test:3cites:CONFIG_EXACT',
 v_run,v_source_sha,v_expected_sha;
END;
$ig_b2b_002_contract$;
ROLLBACK;
