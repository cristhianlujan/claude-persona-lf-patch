-- Familia B PG17 reversible. Sólo pruebas contractuales de RUN nativo Step50/60, source-bound SHA.
-- Sin alterar lf_ops.reglas ni configuración; backend E2E NOT_TESTED.
BEGIN;
CREATE TEMP TABLE ig_b_probe (codigo text PRIMARY KEY,payload jsonb) ON COMMIT DROP;
INSERT INTO ig_b_probe SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo IN ('REG_ALR_005');
CREATE TEMP TABLE ig_b_cfg AS SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE config_key IN ('LCP_ALERT_THRESHOLD_MS','LCP_ALERT_SESSIONS_RATIO','LCP_ALERT_WINDOW_HOURS') AND scope IN ('ALERTAS','OBSERVABILIDAD','UX');

DO $pre_regalr005$
DECLARE v_patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-D043BA968CE82F0E527F2A53' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_probe WHERE codigo='REG_ALR_005')<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_ALR_005' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_ALR_005' AND r.estado='VIGENTE' AND p.codigo='ONB_001')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-D043BA968CE82F0E527F2A53' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-D043BA968CE82F0E527F2A53' AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE' AND evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ALR_005') IS DISTINCT FROM '4b2d32422b36f65637cdf5901f93570fe60aa4abf1528f47cd301e5b43f38b72'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_ALR_005') IS DISTINCT FROM '4b2d32422b36f65637cdf5901f93570fe60aa4abf1528f47cd301e5b43f38b72'
 OR v_patch->>'rule_code' IS DISTINCT FROM 'REG_ALR_005' OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '295bc0232b0926e6b3119b64b5bb3822f0377efe77725251e61a2ee3cce42a90'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='ALERTAS' AND config_key='LCP_ALERT_THRESHOLD_MS' AND config_value='4000' AND value_type='INTEGER' AND value_status='REAL')
 OR v_patch#>>'{changes,valor_config,umbral_ms_config_ref,scope}' IS DISTINCT FROM 'ALERTAS'
 OR v_patch#>>'{changes,valor_config,umbral_ms_config_ref,config_key}' IS DISTINCT FROM 'LCP_ALERT_THRESHOLD_MS'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='ALERTAS' AND config_key='LCP_ALERT_SESSIONS_RATIO' AND config_value='0.2' AND value_type='DECIMAL' AND value_status='REAL')
 OR v_patch#>>'{changes,valor_config,porcentaje_sesiones_config_ref,scope}' IS DISTINCT FROM 'ALERTAS'
 OR v_patch#>>'{changes,valor_config,porcentaje_sesiones_config_ref,config_key}' IS DISTINCT FROM 'LCP_ALERT_SESSIONS_RATIO'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='ALERTAS' AND config_key='LCP_ALERT_WINDOW_HOURS' AND config_value='1' AND value_type='INTEGER' AND value_status='REAL')
 OR v_patch#>>'{changes,valor_config,ventana_horas_config_ref,scope}' IS DISTINCT FROM 'ALERTAS'
 OR v_patch#>>'{changes,valor_config,ventana_horas_config_ref,config_key}' IS DISTINCT FROM 'LCP_ALERT_WINDOW_HOURS'
 OR (v_patch#>'{changes,valor_config}') ? 'umbral_ms'
 OR (v_patch#>'{changes,valor_config}') ? 'porcentaje_sesiones'
 OR (v_patch#>'{changes,valor_config}') ? 'ventana_horas'
 OR v_patch#>>'{changes,valor_config,metrica}' IS DISTINCT FROM 'LCP'
 OR v_patch#>>'{changes,valor_config,canal_alerta}' IS DISTINCT FROM 'slack_tecnico'
 OR position('alerta a técnico y producto' in v_patch#>>'{changes,descripcion}')=0
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-D043BA968CE82F0E527F2A53' AND rule_code='REG_ALR_005')
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_005_PREIMAGE_OR_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_REG_ALR_005_PREIMAGE_SOURCE_PROFILE_CONFIG_PASS';
END $pre_regalr005$;
SAVEPOINT ig_regalr005_positive;
UPDATE ig_b_probe b SET payload=b.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-D043BA968CE82F0E527F2A53' AND s.step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-D043BA968CE82F0E527F2A53' AND s.step_id='execute_profile')
) WHERE codigo='REG_ALR_005';
DO $positive_regalr005$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_ALR_005') IS DISTINCT FROM '783ff5a8ef6af0c78bce343a7a9f0017587e5566c174807852205b3622b96f8f'
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_005_CANDIDATE_SHA_FAILED'; END IF;
 RAISE NOTICE 'IG_B_REG_ALR_005_CANDIDATE_PASS';
END $positive_regalr005$;
ROLLBACK TO SAVEPOINT ig_regalr005_positive;
RELEASE SAVEPOINT ig_regalr005_positive;
DO $rb1_regalr005$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_ALR_005') IS DISTINCT FROM '4b2d32422b36f65637cdf5901f93570fe60aa4abf1528f47cd301e5b43f38b72'
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_005_POSITIVE_ROLLBACK_FAILED'; END IF;
END $rb1_regalr005$;
SAVEPOINT ig_regalr005_negative;
UPDATE ig_b_probe SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb) WHERE codigo='REG_ALR_005';
DELETE FROM ig_b_cfg WHERE scope='ALERTAS' AND config_key='LCP_ALERT_THRESHOLD_MS';
DO $negative_regalr005$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_ALR_005')='4b2d32422b36f65637cdf5901f93570fe60aa4abf1528f47cd301e5b43f38b72'
 OR EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='ALERTAS' AND config_key='LCP_ALERT_THRESHOLD_MS')
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_005_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_REG_ALR_005_NEGATIVE_DRIFT_AND_CONFIG_ABSENCE_PASS';
END $negative_regalr005$;
ROLLBACK TO SAVEPOINT ig_regalr005_negative;
RELEASE SAVEPOINT ig_regalr005_negative;
DO $post_regalr005$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_ALR_005') IS DISTINCT FROM '4b2d32422b36f65637cdf5901f93570fe60aa4abf1528f47cd301e5b43f38b72'
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ALR_005') IS DISTINCT FROM '4b2d32422b36f65637cdf5901f93570fe60aa4abf1528f47cd301e5b43f38b72'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='ALERTAS' AND config_key='LCP_ALERT_THRESHOLD_MS' AND config_value='4000' AND value_type='INTEGER' AND value_status='REAL')
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='ALERTAS' AND config_key='LCP_ALERT_SESSIONS_RATIO' AND config_value='0.2' AND value_type='DECIMAL' AND value_status='REAL')
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='ALERTAS' AND config_key='LCP_ALERT_WINDOW_HOURS' AND config_value='1' AND value_type='INTEGER' AND value_status='REAL')
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-D043BA968CE82F0E527F2A53' AND rule_code='REG_ALR_005')
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_005_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'IG_B_REG_ALR_005_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $post_regalr005$;
COMMIT;
