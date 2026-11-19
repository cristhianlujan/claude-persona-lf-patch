-- Familia B OBS003 + DAT003. PG17 native V2 source-bound, TEMP only and reversible.
-- Two independent proofs under the existing OBS+TEC+DAT+MOD test group.
BEGIN;
CREATE TEMP TABLE ig_b_odd_probe (code text PRIMARY KEY,payload jsonb NOT NULL) ON COMMIT DROP;
INSERT INTO ig_b_odd_probe SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo IN ('REG_OBS_003','REG_DAT_003');
CREATE TEMP TABLE ig_b_odd_cfg AS SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config
WHERE (scope='ALERTAS' AND config_key='PASO1_SUBMIT_ERROR_RATE_MAX') OR (scope='UX' AND config_key='SELECTION_RECALC_MAX_LATENCY_MS');

DO $pre_regobs003$
DECLARE p jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO p
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-4EB598CC54DA31538C309B33' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_odd_probe WHERE code='REG_OBS_003')<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_OBS_003' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas sc ON sc.id=rp.pantalla_id WHERE r.codigo='REG_OBS_003' AND r.estado='VIGENTE' AND sc.codigo='ONB_001')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-4EB598CC54DA31538C309B33' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-4EB598CC54DA31538C309B33' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_OBS_003') IS DISTINCT FROM '95728aa2994d42ac14873ac66a280287b38e11893d87b725530413112c017b51'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_odd_probe WHERE code='REG_OBS_003') IS DISTINCT FROM '95728aa2994d42ac14873ac66a280287b38e11893d87b725530413112c017b51'
 OR NOT EXISTS(SELECT 1 FROM ig_b_odd_cfg WHERE scope='ALERTAS' AND config_key='PASO1_SUBMIT_ERROR_RATE_MAX' AND config_value='0.05' AND value_type='DECIMAL' AND value_status='REAL')
 OR p->>'rule_code' IS DISTINCT FROM 'REG_OBS_003'
 OR p->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(p::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM 'fecd54d5d0b799352ae35c5d9e65ad0d4e012939f3483136ec38db1e3e18313b'
 OR p#>>'{changes,valor_config,paso1_submit_error_rate_config_ref,scope}' IS DISTINCT FROM 'ALERTAS'
 OR p#>>'{changes,valor_config,paso1_submit_error_rate_config_ref,config_key}' IS DISTINCT FROM 'PASO1_SUBMIT_ERROR_RATE_MAX'
 OR (p#>>'{changes,descripcion}') NOT LIKE '%public.lf_global_config%'
 OR position('Sentry debe alertar inmediatamente' in p#>>'{changes,descripcion}')=0
 OR NOT ((p#>>'{changes,valor_config,paso1_submit_error_comparador}')='MAYOR_QUE' AND (p#>'{changes,valor_config,alertas_criticas}')='["otp_whatsapp_send_failed","home_variant_cruce_timeout","paso1_submit_error_rate","paso3_load_failed"]'::jsonb)
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-4EB598CC54DA31538C309B33' AND rule_code='REG_OBS_003')
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_003_PG17_PREIMAGE_OR_NATIVE_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_003_PREIMAGE_PATCH_CONFIG_PASS';
END $pre_regobs003$;
SAVEPOINT ig_regobs003_positive;
UPDATE ig_b_odd_probe b SET payload=b.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-4EB598CC54DA31538C309B33' AND step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-4EB598CC54DA31538C309B33' AND step_id='execute_profile')
) WHERE code='REG_OBS_003';
DO $positive_regobs003$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_odd_probe WHERE code='REG_OBS_003') IS DISTINCT FROM '95a02202cc7697ee5b0468f0ebfa4831839c2d6a3e979c9ba1af6fe3e3f9b676' THEN RAISE EXCEPTION 'IG_B_REG_OBS_003_CANDIDATE_SHA_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_003_CANDIDATE_PASS';
END $positive_regobs003$;
ROLLBACK TO SAVEPOINT ig_regobs003_positive;
RELEASE SAVEPOINT ig_regobs003_positive;
DO $rb_regobs003$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_odd_probe WHERE code='REG_OBS_003') IS DISTINCT FROM '95728aa2994d42ac14873ac66a280287b38e11893d87b725530413112c017b51' THEN RAISE EXCEPTION 'IG_B_REG_OBS_003_POSITIVE_ROLLBACK_FAIL'; END IF;
END $rb_regobs003$;
SAVEPOINT ig_regobs003_negative;
UPDATE ig_b_odd_probe SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb) WHERE code='REG_OBS_003';
DELETE FROM ig_b_odd_cfg WHERE scope='ALERTAS' AND config_key='PASO1_SUBMIT_ERROR_RATE_MAX';
DO $neg_regobs003$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_odd_probe WHERE code='REG_OBS_003')='95728aa2994d42ac14873ac66a280287b38e11893d87b725530413112c017b51'
 OR EXISTS(SELECT 1 FROM ig_b_odd_cfg WHERE scope='ALERTAS' AND config_key='PASO1_SUBMIT_ERROR_RATE_MAX')
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_003_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_003_NEGATIVE_DRIFT_PASS';
END $neg_regobs003$;
ROLLBACK TO SAVEPOINT ig_regobs003_negative;
RELEASE SAVEPOINT ig_regobs003_negative;
DO $final_regobs003$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_odd_probe WHERE code='REG_OBS_003') IS DISTINCT FROM '95728aa2994d42ac14873ac66a280287b38e11893d87b725530413112c017b51'
 OR NOT EXISTS(SELECT 1 FROM ig_b_odd_cfg WHERE scope='ALERTAS' AND config_key='PASO1_SUBMIT_ERROR_RATE_MAX' AND config_value='0.05' AND value_type='DECIMAL' AND value_status='REAL')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_OBS_003') IS DISTINCT FROM '95728aa2994d42ac14873ac66a280287b38e11893d87b725530413112c017b51'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-4EB598CC54DA31538C309B33' AND rule_code='REG_OBS_003')
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_003_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_003_REAL_PG17_PROOF_COMPLETE; BOTH_ROLLBACK_PASS; INDEPENDENT_SELECT_PASS; BACKEND_E2E_NOT_TESTED';
END $final_regobs003$;

DO $pre_regdat003$
DECLARE p jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO p
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-CD293DC8600BC2C9390C7106' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_odd_probe WHERE code='REG_DAT_003')<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_DAT_003' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas sc ON sc.id=rp.pantalla_id WHERE r.codigo='REG_DAT_003' AND r.estado='VIGENTE' AND sc.codigo='PASO3_MULTI_OFERTA')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-CD293DC8600BC2C9390C7106' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='PASO3_MULTI_OFERTA' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-CD293DC8600BC2C9390C7106' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_DAT_003') IS DISTINCT FROM 'f75ae3f8cd8cf6f96759d70aa0a30d3a9d552d1b2bda7f89020b73f5bb955f32'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_odd_probe WHERE code='REG_DAT_003') IS DISTINCT FROM 'f75ae3f8cd8cf6f96759d70aa0a30d3a9d552d1b2bda7f89020b73f5bb955f32'
 OR NOT EXISTS(SELECT 1 FROM ig_b_odd_cfg WHERE scope='UX' AND config_key='SELECTION_RECALC_MAX_LATENCY_MS' AND config_value='100' AND value_type='INTEGER' AND value_status='REAL')
 OR p->>'rule_code' IS DISTINCT FROM 'REG_DAT_003'
 OR p->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(p::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM 'd70efdb141043803e5808fd887f884667da3924a3e01229c7ca0f759b2a1915c'
 OR p#>>'{changes,valor_config,latencia_maxima_ms_config_ref,scope}' IS DISTINCT FROM 'UX'
 OR p#>>'{changes,valor_config,latencia_maxima_ms_config_ref,config_key}' IS DISTINCT FROM 'SELECTION_RECALC_MAX_LATENCY_MS'
 OR (p#>>'{changes,descripcion}') NOT LIKE '%public.lf_global_config%'
 OR position('sin confirmar ni recargar' in p#>>'{changes,descripcion}')=0
 OR NOT ((p#>>'{changes,valor_config,trigger}')='on_change_seleccion_o_modalidad' AND (p#>'{changes,valor_config,campos_recalculados}')='["lista_ofertas","total_hoy","ahorro_total","contador_seleccionadas"]'::jsonb)
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-CD293DC8600BC2C9390C7106' AND rule_code='REG_DAT_003')
 THEN RAISE EXCEPTION 'IG_B_REG_DAT_003_PG17_PREIMAGE_OR_NATIVE_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_REG_DAT_003_PREIMAGE_PATCH_CONFIG_PASS';
END $pre_regdat003$;
SAVEPOINT ig_regdat003_positive;
UPDATE ig_b_odd_probe b SET payload=b.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-CD293DC8600BC2C9390C7106' AND step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-CD293DC8600BC2C9390C7106' AND step_id='execute_profile')
) WHERE code='REG_DAT_003';
DO $positive_regdat003$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_odd_probe WHERE code='REG_DAT_003') IS DISTINCT FROM '83566314a625392a95af9c88481058c4e6d7ceeeae4406bf0ab15c462ed32ebe' THEN RAISE EXCEPTION 'IG_B_REG_DAT_003_CANDIDATE_SHA_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_REG_DAT_003_CANDIDATE_PASS';
END $positive_regdat003$;
ROLLBACK TO SAVEPOINT ig_regdat003_positive;
RELEASE SAVEPOINT ig_regdat003_positive;
DO $rb_regdat003$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_odd_probe WHERE code='REG_DAT_003') IS DISTINCT FROM 'f75ae3f8cd8cf6f96759d70aa0a30d3a9d552d1b2bda7f89020b73f5bb955f32' THEN RAISE EXCEPTION 'IG_B_REG_DAT_003_POSITIVE_ROLLBACK_FAIL'; END IF;
END $rb_regdat003$;
SAVEPOINT ig_regdat003_negative;
UPDATE ig_b_odd_probe SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb) WHERE code='REG_DAT_003';
DELETE FROM ig_b_odd_cfg WHERE scope='UX' AND config_key='SELECTION_RECALC_MAX_LATENCY_MS';
DO $neg_regdat003$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_odd_probe WHERE code='REG_DAT_003')='f75ae3f8cd8cf6f96759d70aa0a30d3a9d552d1b2bda7f89020b73f5bb955f32'
 OR EXISTS(SELECT 1 FROM ig_b_odd_cfg WHERE scope='UX' AND config_key='SELECTION_RECALC_MAX_LATENCY_MS')
 THEN RAISE EXCEPTION 'IG_B_REG_DAT_003_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_REG_DAT_003_NEGATIVE_DRIFT_PASS';
END $neg_regdat003$;
ROLLBACK TO SAVEPOINT ig_regdat003_negative;
RELEASE SAVEPOINT ig_regdat003_negative;
DO $final_regdat003$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_odd_probe WHERE code='REG_DAT_003') IS DISTINCT FROM 'f75ae3f8cd8cf6f96759d70aa0a30d3a9d552d1b2bda7f89020b73f5bb955f32'
 OR NOT EXISTS(SELECT 1 FROM ig_b_odd_cfg WHERE scope='UX' AND config_key='SELECTION_RECALC_MAX_LATENCY_MS' AND config_value='100' AND value_type='INTEGER' AND value_status='REAL')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_DAT_003') IS DISTINCT FROM 'f75ae3f8cd8cf6f96759d70aa0a30d3a9d552d1b2bda7f89020b73f5bb955f32'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-CD293DC8600BC2C9390C7106' AND rule_code='REG_DAT_003')
 THEN RAISE EXCEPTION 'IG_B_REG_DAT_003_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'IG_B_REG_DAT_003_REAL_PG17_PROOF_COMPLETE; BOTH_ROLLBACK_PASS; INDEPENDENT_SELECT_PASS; BACKEND_E2E_NOT_TESTED';
END $final_regdat003$;
COMMIT;
