-- IG Familia B ALR 002+003: PG17 reversible, source/RAW/SHA bound; no production E2E.
BEGIN;
CREATE TEMP TABLE ig_b_alr23 (code text PRIMARY KEY,payload jsonb NOT NULL) ON COMMIT DROP;
INSERT INTO ig_b_alr23 SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo IN ('REG_ALR_002','REG_ALR_003');
CREATE TEMP TABLE ig_b_alr23_cfg AS SELECT scope,config_key,config_value,value_type,value_status
FROM public.lf_global_config WHERE scope='ALERTAS' AND config_key IN
('PASO1_ABANDON_RATE_MAX','PASO1_ABANDON_WINDOW_HOURS','OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT');

-- REG_ALR_002: native RUN original, screen and candidate controlled by Step50/60.
DO $pre_regalr002$
DECLARE patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-FB1C9E73E8958751D06E5867'
 AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_alr23 WHERE code='REG_ALR_002')<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON r.id=rp.regla_id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_ALR_002' AND r.estado='VIGENTE' AND p.codigo='ONB_001')
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_ALR_002' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-FB1C9E73E8958751D06E5867' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-FB1C9E73E8958751D06E5867' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ALR_002') IS DISTINCT FROM 'a2c84d4b00d18000b81911271ed6f40716a18ca58962e1f2289b63313994d250'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr23 WHERE code='REG_ALR_002') IS DISTINCT FROM 'a2c84d4b00d18000b81911271ed6f40716a18ca58962e1f2289b63313994d250'
 OR NOT (EXISTS(SELECT 1 FROM ig_b_alr23_cfg WHERE scope='ALERTAS' AND config_key='PASO1_ABANDON_RATE_MAX' AND config_value='0.8' AND value_type='DECIMAL' AND value_status='REAL') AND EXISTS(SELECT 1 FROM ig_b_alr23_cfg WHERE scope='ALERTAS' AND config_key='PASO1_ABANDON_WINDOW_HOURS' AND config_value='1' AND value_type='INTEGER' AND value_status='REAL'))
 OR patch->>'rule_code' IS DISTINCT FROM 'REG_ALR_002'
 OR patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '91a337d9f591ea9fba5b67ca511dc2cca8467dc91e05e9da01b1eff44a65381f'
 OR patch#>>'{changes,valor_config,umbral_maximo_config_ref,scope}' IS DISTINCT FROM 'ALERTAS'
 OR patch#>>'{changes,valor_config,umbral_maximo_config_ref,config_key}' IS DISTINCT FROM 'PASO1_ABANDON_RATE_MAX'
 OR patch#>>'{changes,valor_config,ventana_horas_config_ref,scope}' IS DISTINCT FROM 'ALERTAS'
 OR patch#>>'{changes,valor_config,ventana_horas_config_ref,config_key}' IS DISTINCT FROM 'PASO1_ABANDON_WINDOW_HOURS'
 OR (patch#>'{changes,valor_config}') ? 'umbral_maximo'
 OR (patch#>'{changes,valor_config}') ? 'ventana_horas'
 OR patch#>>'{changes,valor_config,metrica}' IS DISTINCT FROM 'paso1_abandono_rate'
 OR position('se activa alerta a producto' in patch#>>'{changes,descripcion}')=0
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-FB1C9E73E8958751D06E5867' AND rule_code='REG_ALR_002')
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_002_PG17_PREIMAGE_OR_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_REG_ALR_002_PROFILE_CONFIG_SHA_PASS';
END $pre_regalr002$;
SAVEPOINT regalr002_positive;
UPDATE ig_b_alr23 t SET payload=t.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-FB1C9E73E8958751D06E5867' AND step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-FB1C9E73E8958751D06E5867' AND step_id='execute_profile')
) WHERE code='REG_ALR_002';
DO $candidate_regalr002$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr23 WHERE code='REG_ALR_002') IS DISTINCT FROM 'c0188bafcfd6f251e57a07af3924110c3ccf89be276b8eb26902354e4cdad844'
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_002_CANDIDATE_SHA_FAILED'; END IF;
 RAISE NOTICE 'IG_B_REG_ALR_002_CANDIDATE_POSITIVE_PASS';
END $candidate_regalr002$;
ROLLBACK TO SAVEPOINT regalr002_positive;
RELEASE SAVEPOINT regalr002_positive;
DO $restore_regalr002$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr23 WHERE code='REG_ALR_002') IS DISTINCT FROM 'a2c84d4b00d18000b81911271ed6f40716a18ca58962e1f2289b63313994d250'
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_002_POSITIVE_ROLLBACK_FAILED'; END IF;
END $restore_regalr002$;
SAVEPOINT regalr002_negative;
UPDATE ig_b_alr23 SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb) WHERE code='REG_ALR_002';
DELETE FROM ig_b_alr23_cfg WHERE config_key='PASO1_ABANDON_RATE_MAX';
DO $negative_regalr002$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr23 WHERE code='REG_ALR_002')='a2c84d4b00d18000b81911271ed6f40716a18ca58962e1f2289b63313994d250'
 OR EXISTS(SELECT 1 FROM ig_b_alr23_cfg WHERE config_key='PASO1_ABANDON_RATE_MAX')
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_002_NEGATIVE_UNDETECTED'; END IF;
 RAISE NOTICE 'IG_B_REG_ALR_002_NEGATIVE_SOURCE_AND_CONFIG_DRIFT_DETECTED';
END $negative_regalr002$;
ROLLBACK TO SAVEPOINT regalr002_negative;
RELEASE SAVEPOINT regalr002_negative;
DO $final_regalr002$
BEGIN
 IF public.lf_asset_snapshot_sha_v1('REGLA','REG_ALR_002') IS DISTINCT FROM 'a2c84d4b00d18000b81911271ed6f40716a18ca58962e1f2289b63313994d250'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr23 WHERE code='REG_ALR_002') IS DISTINCT FROM 'a2c84d4b00d18000b81911271ed6f40716a18ca58962e1f2289b63313994d250'
 OR NOT (EXISTS(SELECT 1 FROM ig_b_alr23_cfg WHERE scope='ALERTAS' AND config_key='PASO1_ABANDON_RATE_MAX' AND config_value='0.8' AND value_type='DECIMAL' AND value_status='REAL') AND EXISTS(SELECT 1 FROM ig_b_alr23_cfg WHERE scope='ALERTAS' AND config_key='PASO1_ABANDON_WINDOW_HOURS' AND config_value='1' AND value_type='INTEGER' AND value_status='REAL'))
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-FB1C9E73E8958751D06E5867' AND rule_code='REG_ALR_002')
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_002_INDEPENDENT_READBACK_FAILED'; END IF;
 RAISE NOTICE 'IG_B_REG_ALR_002_PG17_REAL_PROOF_PASS; POSITIVE_AND_NEGATIVE_ROLLBACK_PASS; SELECT_PASS; E2E_NOT_TESTED';
END $final_regalr002$;

-- REG_ALR_003: native RUN original, screen and candidate controlled by Step50/60.
DO $pre_regalr003$
DECLARE patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-ACF582BDC22926C64B5E415A'
 AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_alr23 WHERE code='REG_ALR_003')<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON r.id=rp.regla_id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_ALR_003' AND r.estado='VIGENTE' AND p.codigo='ONB_002')
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_ALR_003' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-ACF582BDC22926C64B5E415A' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-ACF582BDC22926C64B5E415A' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ALR_003') IS DISTINCT FROM '2f303845e7ed4986b5bf9a44374386e870ab9d367cfda53d0258c5bbe3741d92'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr23 WHERE code='REG_ALR_003') IS DISTINCT FROM '2f303845e7ed4986b5bf9a44374386e870ab9d367cfda53d0258c5bbe3741d92'
 OR NOT (EXISTS(SELECT 1 FROM ig_b_alr23_cfg WHERE scope='ALERTAS' AND config_key='OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT' AND config_value='3' AND value_type='INTEGER' AND value_status='REAL'))
 OR patch->>'rule_code' IS DISTINCT FROM 'REG_ALR_003'
 OR patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '87318579c4c22ebcd7be365cba80347c7d261d2067eb49ddbc781245fa75c737'
 OR patch#>>'{changes,valor_config,condicion_max_config_ref,scope}' IS DISTINCT FROM 'ALERTAS'
 OR patch#>>'{changes,valor_config,condicion_max_config_ref,config_key}' IS DISTINCT FROM 'OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT'
 OR (patch#>'{changes,valor_config}') ? 'condicion'
 
 OR patch#>>'{changes,valor_config,accion_inmediata}' IS DISTINCT FROM 'activar_fallback_sms'
 OR position('alerta crítica inmediata' in patch#>>'{changes,descripcion}')=0
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-ACF582BDC22926C64B5E415A' AND rule_code='REG_ALR_003')
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_003_PG17_PREIMAGE_OR_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_REG_ALR_003_PROFILE_CONFIG_SHA_PASS';
END $pre_regalr003$;
SAVEPOINT regalr003_positive;
UPDATE ig_b_alr23 t SET payload=t.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-ACF582BDC22926C64B5E415A' AND step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-ACF582BDC22926C64B5E415A' AND step_id='execute_profile')
) WHERE code='REG_ALR_003';
DO $candidate_regalr003$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr23 WHERE code='REG_ALR_003') IS DISTINCT FROM 'c87bb0afe1217a950eb3be2e6632dbdbb19546e2f9e06abdfaa7a11b0bd5ba6c'
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_003_CANDIDATE_SHA_FAILED'; END IF;
 RAISE NOTICE 'IG_B_REG_ALR_003_CANDIDATE_POSITIVE_PASS';
END $candidate_regalr003$;
ROLLBACK TO SAVEPOINT regalr003_positive;
RELEASE SAVEPOINT regalr003_positive;
DO $restore_regalr003$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr23 WHERE code='REG_ALR_003') IS DISTINCT FROM '2f303845e7ed4986b5bf9a44374386e870ab9d367cfda53d0258c5bbe3741d92'
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_003_POSITIVE_ROLLBACK_FAILED'; END IF;
END $restore_regalr003$;
SAVEPOINT regalr003_negative;
UPDATE ig_b_alr23 SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb) WHERE code='REG_ALR_003';
DELETE FROM ig_b_alr23_cfg WHERE config_key='OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT';
DO $negative_regalr003$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr23 WHERE code='REG_ALR_003')='2f303845e7ed4986b5bf9a44374386e870ab9d367cfda53d0258c5bbe3741d92'
 OR EXISTS(SELECT 1 FROM ig_b_alr23_cfg WHERE config_key='OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT')
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_003_NEGATIVE_UNDETECTED'; END IF;
 RAISE NOTICE 'IG_B_REG_ALR_003_NEGATIVE_SOURCE_AND_CONFIG_DRIFT_DETECTED';
END $negative_regalr003$;
ROLLBACK TO SAVEPOINT regalr003_negative;
RELEASE SAVEPOINT regalr003_negative;
DO $final_regalr003$
BEGIN
 IF public.lf_asset_snapshot_sha_v1('REGLA','REG_ALR_003') IS DISTINCT FROM '2f303845e7ed4986b5bf9a44374386e870ab9d367cfda53d0258c5bbe3741d92'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr23 WHERE code='REG_ALR_003') IS DISTINCT FROM '2f303845e7ed4986b5bf9a44374386e870ab9d367cfda53d0258c5bbe3741d92'
 OR NOT (EXISTS(SELECT 1 FROM ig_b_alr23_cfg WHERE scope='ALERTAS' AND config_key='OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT' AND config_value='3' AND value_type='INTEGER' AND value_status='REAL'))
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-ACF582BDC22926C64B5E415A' AND rule_code='REG_ALR_003')
 THEN RAISE EXCEPTION 'IG_B_REG_ALR_003_INDEPENDENT_READBACK_FAILED'; END IF;
 RAISE NOTICE 'IG_B_REG_ALR_003_PG17_REAL_PROOF_PASS; POSITIVE_AND_NEGATIVE_ROLLBACK_PASS; SELECT_PASS; E2E_NOT_TESTED';
END $final_regalr003$;
COMMIT;
