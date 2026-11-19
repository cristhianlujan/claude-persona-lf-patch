-- Familia B REG_OBS_005: PG17 contractual reversible. No modifica reglas ni autoridad.
BEGIN;
CREATE TEMP TABLE ig_b_obs005_probe (codigo text PRIMARY KEY,payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_b_obs005_config AS SELECT scope,config_key,config_value,value_type,value_status
 FROM public.lf_global_config WHERE scope='OBSERVABILIDAD' AND config_key='OTP_DELIVERY_P95_SECONDS_MAX';
INSERT INTO ig_b_obs005_probe SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_OBS_005';
DO $pre$
DECLARE patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch FROM public.lf_operation_execution_steps
 WHERE execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_obs005_probe)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas s ON s.id=rp.pantalla_id
  WHERE r.codigo='REG_OBS_005' AND r.estado='VIGENTE' AND s.codigo='ONB_002')
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_OBS_005' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76'
  AND e.operation_code='EJECUCION_PERFIL_LF' AND e.status='IN_PROGRESS'
  AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002'
  AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76'
  AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_obs005_probe)<>'8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_OBS_005')<>'8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'
 OR (SELECT payload#>>'{valor_config,p95_segundos}' FROM ig_b_obs005_probe)<>'30'
 OR (SELECT count(*) FROM ig_b_obs005_config WHERE scope='OBSERVABILIDAD'
  AND config_key='OTP_DELIVERY_P95_SECONDS_MAX' AND config_value='30'
  AND value_type='INTEGER' AND value_status='REAL')<>1
 OR patch->>'rule_code'<>'REG_OBS_005' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'08561b6c4b43a00e5c92fe790ac21478afa679dbab1c08eea871889d7cc43fc4'
 OR patch#>>'{changes,valor_config,p95_segundos_config_ref,scope}'<>'OBSERVABILIDAD'
 OR patch#>>'{changes,valor_config,p95_segundos_config_ref,config_key}'<>'OTP_DELIVERY_P95_SECONDS_MAX'
 OR (patch#>'{changes,valor_config}')?'p95_segundos'
 OR patch#>>'{changes,valor_config,metrica}'<>'tiempo_entrega_otp'
 OR patch#>>'{changes,valor_config,alerta_si_supera}'<>'true'
 OR position('otp_sent y otp_verified' in patch#>>'{changes,descripcion}')=0
 OR position('percentil p95 supera' in patch#>>'{changes,descripcion}')=0
 OR (patch#>>'{changes,descripcion}') LIKE '%30 segundos%'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76' AND rule_code='REG_OBS_005')
 THEN RAISE EXCEPTION 'IG_B_OBS005_PREIMAGE_OR_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_OBS005_NATIVE_SOURCE_CONFIG_SHA_PASS';
END $pre$;
SAVEPOINT ig_b_obs005_positive;
UPDATE ig_b_obs005_probe t SET payload=t.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76' AND step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76' AND step_id='execute_profile')
) WHERE codigo='REG_OBS_005';
DO $post_positive$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_obs005_probe)<>'87c4d828d3a0edd7c4be27efb273e23133facec9d311fe0eb004c54f40373a2e'
 THEN RAISE EXCEPTION 'IG_B_OBS005_CANDIDATE_SHA_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_OBS005_POSITIVE_CANDIDATE_SHA_PASS';
END $post_positive$;
ROLLBACK TO SAVEPOINT ig_b_obs005_positive;
RELEASE SAVEPOINT ig_b_obs005_positive;
DO $readback_positive$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_obs005_probe)<>'8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'
 THEN RAISE EXCEPTION 'IG_B_OBS005_POSITIVE_ROLLBACK_FAILED'; END IF;
END $readback_positive$;
SAVEPOINT ig_b_obs005_negative;
UPDATE ig_b_obs005_probe SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb);
DELETE FROM ig_b_obs005_config WHERE config_key='OTP_DELIVERY_P95_SECONDS_MAX';
DO $negative$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_obs005_probe)='8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'
 OR EXISTS(SELECT 1 FROM ig_b_obs005_config WHERE config_key='OTP_DELIVERY_P95_SECONDS_MAX')
 THEN RAISE EXCEPTION 'IG_B_OBS005_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_OBS005_NEGATIVE_DRIFT_DETECTED';
END $negative$;
ROLLBACK TO SAVEPOINT ig_b_obs005_negative;
RELEASE SAVEPOINT ig_b_obs005_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_obs005_probe)<>'8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_OBS_005')<>'8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'
 OR (SELECT count(*) FROM ig_b_obs005_config WHERE config_value='30' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76' AND rule_code='REG_OBS_005')
 THEN RAISE EXCEPTION 'IG_B_OBS005_INDEPENDENT_SELECT_FAILED'; END IF;
 RAISE NOTICE 'IG_B_OBS005_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;
