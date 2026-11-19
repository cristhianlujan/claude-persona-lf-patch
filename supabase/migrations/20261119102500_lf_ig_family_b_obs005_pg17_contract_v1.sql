-- IG Familia B / REG_OBS_005. PG17 source-bound reversible, sin escrituras en reglas.
BEGIN;
CREATE TEMP TABLE ig_b_test_rule (payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_b_test_cfg (config_key text PRIMARY KEY,expected_value text NOT NULL,value_type text NOT NULL) ON COMMIT DROP;
INSERT INTO ig_b_test_rule SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE r.codigo='REG_OBS_005';
INSERT INTO ig_b_test_cfg VALUES
('OTP_DELIVERY_P95_SECONDS_MAX','30','INTEGER');
DO $pre$
DECLARE v_patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76'
 AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_test_rule)<>1
 OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo='REG_OBS_005' AND estado='VIGENTE')<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_OBS_005' AND es_actual)<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_OBS_005')<>'8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_test_rule)<>'8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_OBS_005' AND p.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76' AND e.status='IN_PROGRESS'
 AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
 AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002'
 AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps e WHERE e.execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76'
 AND e.step_id='output_validate' AND e.status='STEP_PASS_WITH_EVIDENCE' AND e.evidence_payload->>'output_contract_result'='PASS')
 OR (SELECT count(*) FROM ig_b_test_cfg)<>1
 OR EXISTS(SELECT 1 FROM ig_b_test_cfg t LEFT JOIN public.lf_global_config g ON g.scope='OBSERVABILIDAD' AND g.config_key=t.config_key
 WHERE g.scope IS NULL OR g.config_value<>t.expected_value OR g.value_type<>t.value_type OR g.value_status<>'REAL')
 OR v_patch->>'rule_code' IS DISTINCT FROM 'REG_OBS_005'
 OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex')<>'08561b6c4b43a00e5c92fe790ac21478afa679dbab1c08eea871889d7cc43fc4'
 OR v_patch#>>'{changes,descripcion}' NOT LIKE '%public.lf_global_config%'
  OR v_patch#>>'{changes,valor_config,p95_segundos_config_ref,scope}' IS DISTINCT FROM 'OBSERVABILIDAD'
 OR v_patch#>>'{changes,valor_config,p95_segundos_config_ref,config_key}' IS DISTINCT FROM 'OTP_DELIVERY_P95_SECONDS_MAX'
 OR (v_patch#>'{changes,valor_config}')?'p95_segundos'
 OR v_patch#>>'{changes,valor_config,metrica}' IS DISTINCT FROM 'tiempo_entrega_otp'
 OR (v_patch#>>'{changes,valor_config,alerta_si_supera}')::boolean IS DISTINCT FROM true
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%p95%'
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%otp_sent y otp_verified%'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76' AND rule_code='REG_OBS_005')
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_005_PREIMAGE_RUN_CONFIG_OR_PATCH_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_005_PG17_SOURCE_NATIVE_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_b_positive;
UPDATE ig_b_test_rule SET payload=payload||jsonb_build_object(
 'descripcion',(SELECT evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76' AND step_id='execute_profile'),
 'valor_config',(SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76' AND step_id='execute_profile'));
DO $pos$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_test_rule)<>'87c4d828d3a0edd7c4be27efb273e23133facec9d311fe0eb004c54f40373a2e'
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_005_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_005_POSITIVE_PASS';
END $pos$;
ROLLBACK TO SAVEPOINT ig_b_positive;
RELEASE SAVEPOINT ig_b_positive;
DO $rb1$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_test_rule)<>'8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_005_ROLLBACK_POSITIVE_FAILED'; END IF;
END $rb1$;
SAVEPOINT ig_b_negative;
UPDATE ig_b_test_rule SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb);
DELETE FROM ig_b_test_cfg WHERE config_key='OTP_DELIVERY_P95_SECONDS_MAX';
DO $neg$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_test_rule)='8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'
 OR (SELECT count(*) FROM ig_b_test_cfg)<>0
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_005_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_005_NEGATIVE_SOURCE_AND_CONFIG_DRIFT_DETECTED';
END $neg$;
ROLLBACK TO SAVEPOINT ig_b_negative;
RELEASE SAVEPOINT ig_b_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_test_rule)<>'8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'
 OR (SELECT count(*) FROM ig_b_test_cfg)<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_OBS_005')<>'8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76' AND rule_code='REG_OBS_005')
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_005_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_005_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;
