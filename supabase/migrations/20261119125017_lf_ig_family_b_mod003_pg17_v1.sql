-- Familia B REG_MOD_003 native V2 PG17 source-bound, TEMP only with positive/negative rollback.
BEGIN;
CREATE TEMP TABLE ig_b_regmod003_probe(code text PRIMARY KEY,payload jsonb NOT NULL) ON COMMIT DROP;
INSERT INTO ig_b_regmod003_probe SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_MOD_003';
CREATE TEMP TABLE ig_b_regmod003_cfg AS SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='UX' AND config_key='MODAL_APPLY_MAX_LATENCY_MS';
DO $pre$
DECLARE v_patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-3CA86C4FE2EE0164FFCCF3C8' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_regmod003_probe)<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_MOD_003' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_MOD_003' AND r.estado='VIGENTE' AND p.codigo='PASO3_OFERTA_UNICA_CUOTAS_V2')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-3CA86C4FE2EE0164FFCCF3C8' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='PASO3_OFERTA_UNICA_CUOTAS_V2' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-3CA86C4FE2EE0164FFCCF3C8' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_regmod003_probe)<>'d803f5d1393157141072cc91959fb722489aa04575ea27fb79b1d461cdf7d876'
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_MOD_003')<>'d803f5d1393157141072cc91959fb722489aa04575ea27fb79b1d461cdf7d876'
 OR (SELECT count(*) FROM ig_b_regmod003_cfg WHERE scope='UX' AND config_key='MODAL_APPLY_MAX_LATENCY_MS' AND config_value='100' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR v_patch->>'rule_code'<>'REG_MOD_003' OR v_patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex')<>'40ce435fee84c56672bb87328655de463b17b6ee5cbb427e66f4265497245e60'
 OR v_patch#>>'{changes,valor_config,latencia_maxima_ms_config_ref,scope}'<>'UX'
 OR v_patch#>>'{changes,valor_config,latencia_maxima_ms_config_ref,config_key}'<>'MODAL_APPLY_MAX_LATENCY_MS'
 OR (v_patch#>'{changes,valor_config}')?'latencia_maxima_ms'
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%public.lf_global_config%'
 OR (v_patch#>'{changes}')?'titulo'
  OR v_patch#>'{changes,valor_config,acciones_al_aplicar}' IS DISTINCT FROM '["cerrar_modal","actualizar_card","recalcular_resumen"]'::jsonb
 OR position('Tu selección actual' in v_patch#>>'{changes,descripcion}')=0
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-3CA86C4FE2EE0164FFCCF3C8' AND rule_code='REG_MOD_003')
 THEN RAISE EXCEPTION 'IG_B_regmod003_SOURCE_NATIVE_SHA_CONFIG_FAIL'; END IF;
 RAISE NOTICE 'IG_B_regmod003_SOURCE_PROFILE_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_b_regmod003_positive;
UPDATE ig_b_regmod003_probe t SET payload=t.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE execution_id='EXEC-PROFILE-GATE2-3CA86C4FE2EE0164FFCCF3C8' AND step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE execution_id='EXEC-PROFILE-GATE2-3CA86C4FE2EE0164FFCCF3C8' AND step_id='execute_profile')
) WHERE code='REG_MOD_003';
DO $pos$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_regmod003_probe)<>'4f04e3ab48cf720cba5c349e7a9c6e54bc4889063e31aafd0404a07d6ab30f9a'
 THEN RAISE EXCEPTION 'IG_B_regmod003_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'IG_B_regmod003_CANDIDATE_PASS';
END $pos$;
ROLLBACK TO SAVEPOINT ig_b_regmod003_positive;
RELEASE SAVEPOINT ig_b_regmod003_positive;
DO $rb$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_regmod003_probe)<>'d803f5d1393157141072cc91959fb722489aa04575ea27fb79b1d461cdf7d876'
 THEN RAISE EXCEPTION 'IG_B_regmod003_POSITIVE_ROLLBACK_FAIL'; END IF;
END $rb$;
SAVEPOINT ig_b_regmod003_negative;
UPDATE ig_b_regmod003_probe SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb) WHERE code='REG_MOD_003';
DELETE FROM ig_b_regmod003_cfg WHERE config_key='MODAL_APPLY_MAX_LATENCY_MS';
DO $neg$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_regmod003_probe)='d803f5d1393157141072cc91959fb722489aa04575ea27fb79b1d461cdf7d876'
 OR EXISTS(SELECT 1 FROM ig_b_regmod003_cfg WHERE config_key='MODAL_APPLY_MAX_LATENCY_MS')
 THEN RAISE EXCEPTION 'IG_B_regmod003_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_regmod003_NEGATIVE_DRIFT_AND_MISSING_CONFIG_PASS';
END $neg$;
ROLLBACK TO SAVEPOINT ig_b_regmod003_negative;
RELEASE SAVEPOINT ig_b_regmod003_negative;
DO $post$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_regmod003_probe)<>'d803f5d1393157141072cc91959fb722489aa04575ea27fb79b1d461cdf7d876'
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_MOD_003')<>'d803f5d1393157141072cc91959fb722489aa04575ea27fb79b1d461cdf7d876'
 OR (SELECT count(*) FROM ig_b_regmod003_cfg WHERE config_value='100' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-3CA86C4FE2EE0164FFCCF3C8' AND rule_code='REG_MOD_003')
 THEN RAISE EXCEPTION 'IG_B_regmod003_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'IG_B_regmod003_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $post$;
COMMIT;
