-- Familia B REG_ALR_004, PG17 contractual reversible, sin autoridad de escritura de reglas.
BEGIN;
CREATE TEMP TABLE ig_b_alr004_probe (code text PRIMARY KEY, payload jsonb NOT NULL) ON COMMIT DROP;
INSERT INTO ig_b_alr004_probe SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_ALR_004';
CREATE TEMP TABLE ig_b_alr004_cfg AS
SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='ALERTAS'
AND config_key IN ('PASO1_SUBMIT_ERROR_RATE_MAX','PASO1_SUBMIT_ERROR_WINDOW_MINUTES');
DO $pre$
DECLARE v_patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch FROM public.lf_operation_execution_steps
 WHERE execution_id='EXEC-PROFILE-GATE2-99B22D985DF43A73CD6BF946' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_alr004_probe)<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_ALR_004' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_ALR_004' AND r.estado='VIGENTE' AND p.codigo='ONB_001')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-99B22D985DF43A73CD6BF946' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-99B22D985DF43A73CD6BF946' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ALR_004')<>'aaa2aed1bb7ce2697b814dab5909cd151f642c5a89032a9f3763db8ce5011505'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr004_probe)<>'aaa2aed1bb7ce2697b814dab5909cd151f642c5a89032a9f3763db8ce5011505'
 OR NOT EXISTS(SELECT 1 FROM ig_b_alr004_cfg WHERE scope='ALERTAS' AND config_key='PASO1_SUBMIT_ERROR_RATE_MAX' AND config_value='0.05' AND value_type='DECIMAL' AND value_status='REAL')
 OR NOT EXISTS(SELECT 1 FROM ig_b_alr004_cfg WHERE scope='ALERTAS' AND config_key='PASO1_SUBMIT_ERROR_WINDOW_MINUTES' AND config_value='15' AND value_type='INTEGER' AND value_status='REAL')
 OR v_patch->>'rule_code'<>'REG_ALR_004' OR v_patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex')<>'e260217b2689834fb124e1e41d53d36bc42bf8df7b6f0613c72eb192c5384e2b'
 OR v_patch#>>'{changes,valor_config,umbral_maximo_config_ref,scope}'<>'ALERTAS'
 OR v_patch#>>'{changes,valor_config,umbral_maximo_config_ref,config_key}'<>'PASO1_SUBMIT_ERROR_RATE_MAX'
 OR v_patch#>>'{changes,valor_config,ventana_minutos_config_ref,scope}'<>'ALERTAS'
 OR v_patch#>>'{changes,valor_config,ventana_minutos_config_ref,config_key}'<>'PASO1_SUBMIT_ERROR_WINDOW_MINUTES'
 OR (v_patch#>'{changes,valor_config}')?'umbral_maximo'
 OR (v_patch#>'{changes,valor_config}')?'ventana_minutos'
 OR v_patch#>>'{changes,valor_config,metrica}'<>'paso1_submit_error_rate'
 OR v_patch#>>'{changes,valor_config,canal_alerta}'<>'slack_tecnico'
 OR position('alerta al equipo técnico' in v_patch#>>'{changes,descripcion}')=0
 OR position('public.lf_global_config' in v_patch#>>'{changes,descripcion}')=0
 OR (v_patch#>>'{changes,descripcion}') LIKE '%5%'
 OR (v_patch#>>'{changes,descripcion}') LIKE '%15 minutos%'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-99B22D985DF43A73CD6BF946' AND rule_code='REG_ALR_004')
 THEN RAISE EXCEPTION 'IG_B_ALR004_PROFILE_SOURCE_SHA_OR_CONFIG_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_ALR004_PREIMAGE_NATIVE_PROFILE_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_b_alr004_positive;
UPDATE ig_b_alr004_probe p SET payload=p.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE execution_id='EXEC-PROFILE-GATE2-99B22D985DF43A73CD6BF946' AND step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE execution_id='EXEC-PROFILE-GATE2-99B22D985DF43A73CD6BF946' AND step_id='execute_profile')
) WHERE code='REG_ALR_004';
DO $positive$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr004_probe)<>'4d84a561e71b37c9821f80be4a4851eac71a3c4bdad7ef38ac61d5f8bd66a775'
 THEN RAISE EXCEPTION 'IG_B_ALR004_CANDIDATE_SHA_MISMATCH'; END IF;
 RAISE NOTICE 'IG_B_ALR004_CANDIDATE_POSITIVE_PASS';
END $positive$;
ROLLBACK TO SAVEPOINT ig_b_alr004_positive;
RELEASE SAVEPOINT ig_b_alr004_positive;
DO $rbpositive$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr004_probe)<>'aaa2aed1bb7ce2697b814dab5909cd151f642c5a89032a9f3763db8ce5011505'
 THEN RAISE EXCEPTION 'IG_B_ALR004_POSITIVE_ROLLBACK_FAIL'; END IF;
END $rbpositive$;
SAVEPOINT ig_b_alr004_negative;
UPDATE ig_b_alr004_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb) WHERE code='REG_ALR_004';
DELETE FROM ig_b_alr004_cfg WHERE config_key='PASO1_SUBMIT_ERROR_RATE_MAX';
DO $negative$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr004_probe)='aaa2aed1bb7ce2697b814dab5909cd151f642c5a89032a9f3763db8ce5011505'
 OR EXISTS(SELECT 1 FROM ig_b_alr004_cfg WHERE config_key='PASO1_SUBMIT_ERROR_RATE_MAX')
 THEN RAISE EXCEPTION 'IG_B_ALR004_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_ALR004_NEGATIVE_DRIFT_AND_CONFIG_ABSENCE_PASS';
END $negative$;
ROLLBACK TO SAVEPOINT ig_b_alr004_negative;
RELEASE SAVEPOINT ig_b_alr004_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr004_probe)<>'aaa2aed1bb7ce2697b814dab5909cd151f642c5a89032a9f3763db8ce5011505'
 OR (SELECT count(*) FROM ig_b_alr004_cfg WHERE scope='ALERTAS' AND value_status='REAL')<>2
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ALR_004')<>'aaa2aed1bb7ce2697b814dab5909cd151f642c5a89032a9f3763db8ce5011505'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-99B22D985DF43A73CD6BF946' AND rule_code='REG_ALR_004')
 THEN RAISE EXCEPTION 'IG_B_ALR004_INDEPENDENT_READBACK_FAILED'; END IF;
 RAISE NOTICE 'IG_B_ALR004_PG17_REAL_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;
