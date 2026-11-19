-- Familia B PG17 reversible. Sólo pruebas contractuales de RUN nativo Step50/60, source-bound SHA.
-- Sin alterar lf_ops.reglas ni configuración; backend E2E NOT_TESTED.
BEGIN;
CREATE TEMP TABLE ig_b_probe (codigo text PRIMARY KEY,payload jsonb) ON COMMIT DROP;
INSERT INTO ig_b_probe SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo IN ('REG_UI_008');
CREATE TEMP TABLE ig_b_cfg AS SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE config_key IN ('COMPONENT_TRANSITION_MIN_MS','COMPONENT_TRANSITION_MAX_MS','SCREEN_FADE_MS','SKELETON_FADE_MS') AND scope IN ('ALERTAS','OBSERVABILIDAD','UX');

DO $pre_regui008$
DECLARE v_patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-6D315138FF77DF279C38CFC6' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_probe WHERE codigo='REG_UI_008')<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_UI_008' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_UI_008' AND r.estado='VIGENTE' AND p.codigo='ONB_001')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-6D315138FF77DF279C38CFC6' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-6D315138FF77DF279C38CFC6' AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE' AND evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_UI_008') IS DISTINCT FROM 'ef6ff49a04347a530d31a3f3cd00f66d51e20cc647cff151431cfd3cd26c6a9a'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_UI_008') IS DISTINCT FROM 'ef6ff49a04347a530d31a3f3cd00f66d51e20cc647cff151431cfd3cd26c6a9a'
 OR v_patch->>'rule_code' IS DISTINCT FROM 'REG_UI_008' OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '4f22edc299d458849d0c34e2a09df968cd654d4367d842e44a18982b4b7d986e'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='UX' AND config_key='COMPONENT_TRANSITION_MIN_MS' AND config_value='150' AND value_type='INTEGER' AND value_status='REAL')
 OR v_patch#>>'{changes,valor_config,transicion_componente_ms,min_config_ref,scope}' IS DISTINCT FROM 'UX'
 OR v_patch#>>'{changes,valor_config,transicion_componente_ms,min_config_ref,config_key}' IS DISTINCT FROM 'COMPONENT_TRANSITION_MIN_MS'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='UX' AND config_key='COMPONENT_TRANSITION_MAX_MS' AND config_value='300' AND value_type='INTEGER' AND value_status='REAL')
 OR v_patch#>>'{changes,valor_config,transicion_componente_ms,max_config_ref,scope}' IS DISTINCT FROM 'UX'
 OR v_patch#>>'{changes,valor_config,transicion_componente_ms,max_config_ref,config_key}' IS DISTINCT FROM 'COMPONENT_TRANSITION_MAX_MS'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='UX' AND config_key='SCREEN_FADE_MS' AND config_value='200' AND value_type='INTEGER' AND value_status='REAL')
 OR v_patch#>>'{changes,valor_config,cambio_pantalla_ms_config_ref,scope}' IS DISTINCT FROM 'UX'
 OR v_patch#>>'{changes,valor_config,cambio_pantalla_ms_config_ref,config_key}' IS DISTINCT FROM 'SCREEN_FADE_MS'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='UX' AND config_key='SKELETON_FADE_MS' AND config_value='300' AND value_type='INTEGER' AND value_status='REAL')
 OR v_patch#>>'{changes,valor_config,skeleton_fade_ms_config_ref,scope}' IS DISTINCT FROM 'UX'
 OR v_patch#>>'{changes,valor_config,skeleton_fade_ms_config_ref,config_key}' IS DISTINCT FROM 'SKELETON_FADE_MS'
 OR (v_patch#>'{changes,valor_config}') ? 'skeleton_fade_ms'
 OR (v_patch#>'{changes,valor_config}') ? 'cambio_pantalla_ms'
 
 OR position('transiciones CSS' in v_patch#>>'{changes,descripcion}')=0
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-6D315138FF77DF279C38CFC6' AND rule_code='REG_UI_008')
 THEN RAISE EXCEPTION 'IG_B_REG_UI_008_PREIMAGE_OR_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_REG_UI_008_PREIMAGE_SOURCE_PROFILE_CONFIG_PASS';
END $pre_regui008$;
SAVEPOINT ig_regui008_positive;
UPDATE ig_b_probe b SET payload=b.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-6D315138FF77DF279C38CFC6' AND s.step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-6D315138FF77DF279C38CFC6' AND s.step_id='execute_profile')
) WHERE codigo='REG_UI_008';
DO $positive_regui008$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_UI_008') IS DISTINCT FROM '47d0f9c85314abd6419ffad776252f5b143163deeb789789ad0d938332da4a98'
 THEN RAISE EXCEPTION 'IG_B_REG_UI_008_CANDIDATE_SHA_FAILED'; END IF;
 RAISE NOTICE 'IG_B_REG_UI_008_CANDIDATE_PASS';
END $positive_regui008$;
ROLLBACK TO SAVEPOINT ig_regui008_positive;
RELEASE SAVEPOINT ig_regui008_positive;
DO $rb1_regui008$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_UI_008') IS DISTINCT FROM 'ef6ff49a04347a530d31a3f3cd00f66d51e20cc647cff151431cfd3cd26c6a9a'
 THEN RAISE EXCEPTION 'IG_B_REG_UI_008_POSITIVE_ROLLBACK_FAILED'; END IF;
END $rb1_regui008$;
SAVEPOINT ig_regui008_negative;
UPDATE ig_b_probe SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb) WHERE codigo='REG_UI_008';
DELETE FROM ig_b_cfg WHERE scope='UX' AND config_key='COMPONENT_TRANSITION_MIN_MS';
DO $negative_regui008$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_UI_008')='ef6ff49a04347a530d31a3f3cd00f66d51e20cc647cff151431cfd3cd26c6a9a'
 OR EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='UX' AND config_key='COMPONENT_TRANSITION_MIN_MS')
 THEN RAISE EXCEPTION 'IG_B_REG_UI_008_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_REG_UI_008_NEGATIVE_DRIFT_AND_CONFIG_ABSENCE_PASS';
END $negative_regui008$;
ROLLBACK TO SAVEPOINT ig_regui008_negative;
RELEASE SAVEPOINT ig_regui008_negative;
DO $post_regui008$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_UI_008') IS DISTINCT FROM 'ef6ff49a04347a530d31a3f3cd00f66d51e20cc647cff151431cfd3cd26c6a9a'
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_UI_008') IS DISTINCT FROM 'ef6ff49a04347a530d31a3f3cd00f66d51e20cc647cff151431cfd3cd26c6a9a'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='UX' AND config_key='COMPONENT_TRANSITION_MIN_MS' AND config_value='150' AND value_type='INTEGER' AND value_status='REAL')
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='UX' AND config_key='COMPONENT_TRANSITION_MAX_MS' AND config_value='300' AND value_type='INTEGER' AND value_status='REAL')
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='UX' AND config_key='SCREEN_FADE_MS' AND config_value='200' AND value_type='INTEGER' AND value_status='REAL')
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='UX' AND config_key='SKELETON_FADE_MS' AND config_value='300' AND value_type='INTEGER' AND value_status='REAL')
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-6D315138FF77DF279C38CFC6' AND rule_code='REG_UI_008')
 THEN RAISE EXCEPTION 'IG_B_REG_UI_008_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'IG_B_REG_UI_008_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $post_regui008$;
COMMIT;
