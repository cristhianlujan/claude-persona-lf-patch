-- Familia B PG17 reversible. Sólo pruebas contractuales de RUN nativo Step50/60, source-bound SHA.
-- Sin alterar lf_ops.reglas ni configuración; backend E2E NOT_TESTED.
BEGIN;
CREATE TEMP TABLE ig_b_probe (codigo text PRIMARY KEY,payload jsonb) ON COMMIT DROP;
INSERT INTO ig_b_probe SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo IN ('REG_OBS_004','REG_TEC_006');
CREATE TEMP TABLE ig_b_cfg AS SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE config_key IN ('CORE_WEB_VITALS_ALERT_SESSIONS_PERCENT','SKELETON_SHOW_AFTER_MS') AND scope IN ('ALERTAS','OBSERVABILIDAD','UX');

DO $pre_regobs004$
DECLARE v_patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_probe WHERE codigo='REG_OBS_004')<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_OBS_004' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_OBS_004' AND r.estado='VIGENTE' AND p.codigo='ONB_001')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D' AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE' AND evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_OBS_004') IS DISTINCT FROM '7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_OBS_004') IS DISTINCT FROM '7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660'
 OR v_patch->>'rule_code' IS DISTINCT FROM 'REG_OBS_004' OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM 'd7455e46f17701b8acd6eb937c1fcab15d62aa44ab8cfa8e5d06f8d3c04cd0af'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='OBSERVABILIDAD' AND config_key='CORE_WEB_VITALS_ALERT_SESSIONS_PERCENT' AND config_value='10' AND value_type='INTEGER' AND value_status='REAL')
 OR v_patch#>>'{changes,valor_config,alerta_porcentaje_sesiones_config_ref,scope}' IS DISTINCT FROM 'OBSERVABILIDAD'
 OR v_patch#>>'{changes,valor_config,alerta_porcentaje_sesiones_config_ref,config_key}' IS DISTINCT FROM 'CORE_WEB_VITALS_ALERT_SESSIONS_PERCENT'
 OR (v_patch#>'{changes,valor_config}') ? 'alerta_porcentaje_sesiones'
 
 OR position('Core Web Vitals' in v_patch#>>'{changes,descripcion}')=0
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D' AND rule_code='REG_OBS_004')
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_004_PREIMAGE_OR_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_004_PREIMAGE_SOURCE_PROFILE_CONFIG_PASS';
END $pre_regobs004$;
SAVEPOINT ig_regobs004_positive;
UPDATE ig_b_probe b SET payload=b.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D' AND s.step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D' AND s.step_id='execute_profile')
) WHERE codigo='REG_OBS_004';
DO $positive_regobs004$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_OBS_004') IS DISTINCT FROM '36d040466e485e57abcc68175ea7a553f8d8d24a741f7c627daaadf6d3306e44'
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_004_CANDIDATE_SHA_FAILED'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_004_CANDIDATE_PASS';
END $positive_regobs004$;
ROLLBACK TO SAVEPOINT ig_regobs004_positive;
RELEASE SAVEPOINT ig_regobs004_positive;
DO $rb1_regobs004$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_OBS_004') IS DISTINCT FROM '7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660'
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_004_POSITIVE_ROLLBACK_FAILED'; END IF;
END $rb1_regobs004$;
SAVEPOINT ig_regobs004_negative;
UPDATE ig_b_probe SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb) WHERE codigo='REG_OBS_004';
DELETE FROM ig_b_cfg WHERE scope='OBSERVABILIDAD' AND config_key='CORE_WEB_VITALS_ALERT_SESSIONS_PERCENT';
DO $negative_regobs004$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_OBS_004')='7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660'
 OR EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='OBSERVABILIDAD' AND config_key='CORE_WEB_VITALS_ALERT_SESSIONS_PERCENT')
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_004_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_004_NEGATIVE_DRIFT_AND_CONFIG_ABSENCE_PASS';
END $negative_regobs004$;
ROLLBACK TO SAVEPOINT ig_regobs004_negative;
RELEASE SAVEPOINT ig_regobs004_negative;
DO $post_regobs004$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_OBS_004') IS DISTINCT FROM '7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660'
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_OBS_004') IS DISTINCT FROM '7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='OBSERVABILIDAD' AND config_key='CORE_WEB_VITALS_ALERT_SESSIONS_PERCENT' AND config_value='10' AND value_type='INTEGER' AND value_status='REAL')
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D' AND rule_code='REG_OBS_004')
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_004_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_004_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $post_regobs004$;

DO $pre_regtec006$
DECLARE v_patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-DE04AB9C1965131FFA6CA9BC' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_probe WHERE codigo='REG_TEC_006')<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_TEC_006' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_TEC_006' AND r.estado='VIGENTE' AND p.codigo='PASO3_MULTI_OFERTA')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-DE04AB9C1965131FFA6CA9BC' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='PASO3_MULTI_OFERTA' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-DE04AB9C1965131FFA6CA9BC' AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE' AND evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_TEC_006') IS DISTINCT FROM '6eb5b8ce6cd5f618f8106a987919172a643ea70cc87fb1801528ee154471c53f'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_TEC_006') IS DISTINCT FROM '6eb5b8ce6cd5f618f8106a987919172a643ea70cc87fb1801528ee154471c53f'
 OR v_patch->>'rule_code' IS DISTINCT FROM 'REG_TEC_006' OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM 'bca7668723a904ec9796ea9ae2754806c9e6a6b5857b3524e445426f8856dccf'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='UX' AND config_key='SKELETON_SHOW_AFTER_MS' AND config_value='300' AND value_type='INTEGER' AND value_status='REAL')
 OR v_patch#>>'{changes,valor_config,umbral_ms_config_ref,scope}' IS DISTINCT FROM 'UX'
 OR v_patch#>>'{changes,valor_config,umbral_ms_config_ref,config_key}' IS DISTINCT FROM 'SKELETON_SHOW_AFTER_MS'
 OR (v_patch#>'{changes,valor_config}') ? 'umbral_ms'
 OR v_patch#>>'{changes,valor_config,tipo}' IS DISTINCT FROM 'skeleton_screen'
 OR position('skeleton screen' in v_patch#>>'{changes,descripcion}')=0
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-DE04AB9C1965131FFA6CA9BC' AND rule_code='REG_TEC_006')
 THEN RAISE EXCEPTION 'IG_B_REG_TEC_006_PREIMAGE_OR_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_REG_TEC_006_PREIMAGE_SOURCE_PROFILE_CONFIG_PASS';
END $pre_regtec006$;
SAVEPOINT ig_regtec006_positive;
UPDATE ig_b_probe b SET payload=b.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-DE04AB9C1965131FFA6CA9BC' AND s.step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-DE04AB9C1965131FFA6CA9BC' AND s.step_id='execute_profile')
) WHERE codigo='REG_TEC_006';
DO $positive_regtec006$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_TEC_006') IS DISTINCT FROM '37d00c79127762101bebbbd015fe29cd6c26ffbe01bbc1066be01386a6fca23a'
 THEN RAISE EXCEPTION 'IG_B_REG_TEC_006_CANDIDATE_SHA_FAILED'; END IF;
 RAISE NOTICE 'IG_B_REG_TEC_006_CANDIDATE_PASS';
END $positive_regtec006$;
ROLLBACK TO SAVEPOINT ig_regtec006_positive;
RELEASE SAVEPOINT ig_regtec006_positive;
DO $rb1_regtec006$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_TEC_006') IS DISTINCT FROM '6eb5b8ce6cd5f618f8106a987919172a643ea70cc87fb1801528ee154471c53f'
 THEN RAISE EXCEPTION 'IG_B_REG_TEC_006_POSITIVE_ROLLBACK_FAILED'; END IF;
END $rb1_regtec006$;
SAVEPOINT ig_regtec006_negative;
UPDATE ig_b_probe SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb) WHERE codigo='REG_TEC_006';
DELETE FROM ig_b_cfg WHERE scope='UX' AND config_key='SKELETON_SHOW_AFTER_MS';
DO $negative_regtec006$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_TEC_006')='6eb5b8ce6cd5f618f8106a987919172a643ea70cc87fb1801528ee154471c53f'
 OR EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='UX' AND config_key='SKELETON_SHOW_AFTER_MS')
 THEN RAISE EXCEPTION 'IG_B_REG_TEC_006_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_REG_TEC_006_NEGATIVE_DRIFT_AND_CONFIG_ABSENCE_PASS';
END $negative_regtec006$;
ROLLBACK TO SAVEPOINT ig_regtec006_negative;
RELEASE SAVEPOINT ig_regtec006_negative;
DO $post_regtec006$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_probe WHERE codigo='REG_TEC_006') IS DISTINCT FROM '6eb5b8ce6cd5f618f8106a987919172a643ea70cc87fb1801528ee154471c53f'
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_TEC_006') IS DISTINCT FROM '6eb5b8ce6cd5f618f8106a987919172a643ea70cc87fb1801528ee154471c53f'
 OR NOT EXISTS(SELECT 1 FROM ig_b_cfg WHERE scope='UX' AND config_key='SKELETON_SHOW_AFTER_MS' AND config_value='300' AND value_type='INTEGER' AND value_status='REAL')
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-DE04AB9C1965131FFA6CA9BC' AND rule_code='REG_TEC_006')
 THEN RAISE EXCEPTION 'IG_B_REG_TEC_006_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'IG_B_REG_TEC_006_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $post_regtec006$;
COMMIT;
