-- Independent PG17 reversible probes for remaining Family-A candidates.
-- Each profile has its own RUN and source/candidate SHA; NO persistent writes, no E2E claim.
BEGIN;
CREATE TEMP TABLE ig_remaining_probe(code text PRIMARY KEY,payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_remaining_cfg(scope text,config_key text,config_value text,value_type text,value_status text) ON COMMIT DROP;
INSERT INTO ig_remaining_probe SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo IN ('REG_RATE_005','REG_RL_001','REG_RL_003','REG_TEC_009');
INSERT INTO ig_remaining_cfg SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='AUTH' AND config_key IN ('OTP_ORDINARY_RESEND_TIMER_SECONDS','OTP_EXHAUSTION_COOLDOWN_SECONDS','OTP_MAX_ATTEMPTS','PHONE_UPDATE_MAX_PER_SESSION','IDEMPOTENCY_KEY_VALIDITY_MINUTES');
INSERT INTO ig_remaining_probe SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_SEG_002';
INSERT INTO ig_remaining_cfg SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='AUTH' AND config_key='OTP_MAX_RESENDS';
INSERT INTO ig_remaining_probe SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_RL_002';
INSERT INTO ig_remaining_cfg SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='AUTH' AND config_key='OTP_RESEND_LIMIT_COOLDOWN_MINUTES';
DO $pre_r005$
DECLARE patch jsonb;
BEGIN
 SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-598A9BB7E5319458332274A9' AND s.step_id='execute_profile' AND s.status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17 OR (SELECT count(*) FROM ig_remaining_probe WHERE code='REG_RATE_005')<>1
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-598A9BB7E5319458332274A9' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_RATE_005' AND r.estado='VIGENTE' AND p.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-598A9BB7E5319458332274A9' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RATE_005')<>'a48b19db1fbbc7c84a1f21bb51827b99389fb8f4c6068762c1009edad052c426'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RATE_005')<>'a48b19db1fbbc7c84a1f21bb51827b99389fb8f4c6068762c1009edad052c426'
  OR (SELECT payload#>>'{valor_config,cooldown_segundos}' FROM ig_remaining_probe WHERE code='REG_RATE_005')<>'45'
 OR (SELECT payload#>>'{valor_config,cooldown_agotamiento_segundos}' FROM ig_remaining_probe WHERE code='REG_RATE_005')<>'120'
 OR (SELECT payload#>>'{valor_config,campo_timer}' FROM ig_remaining_probe WHERE code='REG_RATE_005')<>'otp_last_sent_at'
 OR (SELECT payload#>>'{valor_config,precedencia_si_intentos_agotados}' FROM ig_remaining_probe WHERE code='REG_RATE_005')<>'REG_SEG_001'
  OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_ORDINARY_RESEND_TIMER_SECONDS' AND config_value='45' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('OTP_ORDINARY_RESEND_TIMER_SECONDS')<>45
 OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_EXHAUSTION_COOLDOWN_SECONDS' AND config_value='120' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('OTP_EXHAUSTION_COOLDOWN_SECONDS')<>120
 OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_MAX_ATTEMPTS' AND config_value='5' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('OTP_MAX_ATTEMPTS')<>5
 OR patch->>'rule_code'<>'REG_RATE_005' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'6b85bc091b2b0026247d9893fd85f918205c9c23ddadc0a6d057b2bfc59a4847'
  OR patch#>>'{changes,valor_config,cooldown_segundos_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,cooldown_segundos_config,config_key}'<>'OTP_ORDINARY_RESEND_TIMER_SECONDS'
 OR patch#>>'{changes,valor_config,cooldown_agotamiento_segundos_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,cooldown_agotamiento_segundos_config,config_key}'<>'OTP_EXHAUSTION_COOLDOWN_SECONDS'
 OR patch#>>'{changes,valor_config,otp_max_attempts_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,otp_max_attempts_config,config_key}'<>'OTP_MAX_ATTEMPTS'
  OR (patch#>'{changes,valor_config}')?'cooldown_segundos'
 OR (patch#>'{changes,valor_config}')?'cooldown_agotamiento_segundos'
  OR patch#>>'{changes,valor_config,campo_timer}'<>'otp_last_sent_at' OR patch#>>'{changes,valor_config,precedencia_si_intentos_agotados}'<>'REG_SEG_001'
 THEN RAISE EXCEPTION 'R005_PG17_SOURCE_CONFIG_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'R005_PG17_SOURCE_CONFIG_PROFILE_PASS';
END $pre_r005$;
SAVEPOINT ig_r005_positive;
UPDATE ig_remaining_probe t SET payload=t.payload||jsonb_build_object('descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-598A9BB7E5319458332274A9' AND s.step_id='execute_profile'),'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-598A9BB7E5319458332274A9' AND s.step_id='execute_profile')) WHERE t.code='REG_RATE_005';
DO $positive_r005$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RATE_005')<>'0e127096d2923d27679a991cf8bb2e5147f3ee57cc479f78b620adfafabe781d' THEN RAISE EXCEPTION 'R005_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'R005_CANDIDATE_SHA_PASS';
END $positive_r005$;
ROLLBACK TO SAVEPOINT ig_r005_positive;
RELEASE SAVEPOINT ig_r005_positive;
DO $back_r005$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RATE_005')<>'a48b19db1fbbc7c84a1f21bb51827b99389fb8f4c6068762c1009edad052c426' THEN RAISE EXCEPTION 'R005_POSITIVE_ROLLBACK_FAILED'; END IF;
END $back_r005$;
SAVEPOINT ig_r005_negative;
UPDATE ig_remaining_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb) WHERE code='REG_RATE_005';
DELETE FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_ORDINARY_RESEND_TIMER_SECONDS';
DO $negative_r005$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RATE_005')='a48b19db1fbbc7c84a1f21bb51827b99389fb8f4c6068762c1009edad052c426' OR EXISTS(SELECT 1 FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_ORDINARY_RESEND_TIMER_SECONDS') THEN RAISE EXCEPTION 'R005_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'R005_NEGATIVE_DRIFT_DETECTED';
END $negative_r005$;
ROLLBACK TO SAVEPOINT ig_r005_negative;
RELEASE SAVEPOINT ig_r005_negative;
DO $final_r005$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RATE_005')<>'a48b19db1fbbc7c84a1f21bb51827b99389fb8f4c6068762c1009edad052c426' OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_ORDINARY_RESEND_TIMER_SECONDS' AND config_value='45')<>1 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RATE_005')<>'a48b19db1fbbc7c84a1f21bb51827b99389fb8f4c6068762c1009edad052c426' OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-598A9BB7E5319458332274A9' AND rule_code='REG_RATE_005') THEN RAISE EXCEPTION 'R005_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'R005_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_SELECT_PASS; BACKEND_E2E_NOT_TESTED';
END $final_r005$;
DO $pre_rl001$
DECLARE patch jsonb;
BEGIN
 SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-DE56B1A1683A7108F86E258E' AND s.step_id='execute_profile' AND s.status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17 OR (SELECT count(*) FROM ig_remaining_probe WHERE code='REG_RL_001')<>1
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-DE56B1A1683A7108F86E258E' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_RL_001' AND r.estado='VIGENTE' AND p.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-DE56B1A1683A7108F86E258E' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RL_001')<>'9b22ae5b0649c4f8cd09b13565eb50e1909419c4e1753aa28578e4310914ffd2'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_001')<>'9b22ae5b0649c4f8cd09b13565eb50e1909419c4e1753aa28578e4310914ffd2'
  OR (SELECT payload#>>'{valor_config,cooldown_segundos}' FROM ig_remaining_probe WHERE code='REG_RL_001')<>'45'
  OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_ORDINARY_RESEND_TIMER_SECONDS' AND config_value='45' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('OTP_ORDINARY_RESEND_TIMER_SECONDS')<>45
 OR patch->>'rule_code'<>'REG_RL_001' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'a06cd5e771ff3ec2335d7e733325fab03e5c3d7a0a5fd863fa79ed1804a4c06f'
  OR patch#>>'{changes,valor_config,cooldown_segundos_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,cooldown_segundos_config,config_key}'<>'OTP_ORDINARY_RESEND_TIMER_SECONDS'
  OR (patch#>'{changes,valor_config}')?'cooldown_segundos'
 
 THEN RAISE EXCEPTION 'RL001_PG17_SOURCE_CONFIG_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'RL001_PG17_SOURCE_CONFIG_PROFILE_PASS';
END $pre_rl001$;
SAVEPOINT ig_rl001_positive;
UPDATE ig_remaining_probe t SET payload=t.payload||jsonb_build_object('descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-DE56B1A1683A7108F86E258E' AND s.step_id='execute_profile'),'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-DE56B1A1683A7108F86E258E' AND s.step_id='execute_profile')) WHERE t.code='REG_RL_001';
DO $positive_rl001$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_001')<>'0385dfe8242fe3223869606fa27528b0be83d83e2a43c4e2644d5dac9231da8a' THEN RAISE EXCEPTION 'RL001_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'RL001_CANDIDATE_SHA_PASS';
END $positive_rl001$;
ROLLBACK TO SAVEPOINT ig_rl001_positive;
RELEASE SAVEPOINT ig_rl001_positive;
DO $back_rl001$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_001')<>'9b22ae5b0649c4f8cd09b13565eb50e1909419c4e1753aa28578e4310914ffd2' THEN RAISE EXCEPTION 'RL001_POSITIVE_ROLLBACK_FAILED'; END IF;
END $back_rl001$;
SAVEPOINT ig_rl001_negative;
UPDATE ig_remaining_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb) WHERE code='REG_RL_001';
DELETE FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_ORDINARY_RESEND_TIMER_SECONDS';
DO $negative_rl001$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_001')='9b22ae5b0649c4f8cd09b13565eb50e1909419c4e1753aa28578e4310914ffd2' OR EXISTS(SELECT 1 FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_ORDINARY_RESEND_TIMER_SECONDS') THEN RAISE EXCEPTION 'RL001_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'RL001_NEGATIVE_DRIFT_DETECTED';
END $negative_rl001$;
ROLLBACK TO SAVEPOINT ig_rl001_negative;
RELEASE SAVEPOINT ig_rl001_negative;
DO $final_rl001$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_001')<>'9b22ae5b0649c4f8cd09b13565eb50e1909419c4e1753aa28578e4310914ffd2' OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_ORDINARY_RESEND_TIMER_SECONDS' AND config_value='45')<>1 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RL_001')<>'9b22ae5b0649c4f8cd09b13565eb50e1909419c4e1753aa28578e4310914ffd2' OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-DE56B1A1683A7108F86E258E' AND rule_code='REG_RL_001') THEN RAISE EXCEPTION 'RL001_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'RL001_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_SELECT_PASS; BACKEND_E2E_NOT_TESTED';
END $final_rl001$;
DO $pre_rl003$
DECLARE patch jsonb;
BEGIN
 SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-8E808BBF541AA2D178E15290' AND s.step_id='execute_profile' AND s.status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17 OR (SELECT count(*) FROM ig_remaining_probe WHERE code='REG_RL_003')<>1
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-8E808BBF541AA2D178E15290' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='HOME_001' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_RL_003' AND r.estado='VIGENTE' AND p.codigo='HOME_001')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-8E808BBF541AA2D178E15290' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RL_003')<>'1692d7c9282c162ab2271471d5e8999d58478345fb692914f7fc9ee413c7a50c'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_003')<>'1692d7c9282c162ab2271471d5e8999d58478345fb692914f7fc9ee413c7a50c'
  OR (SELECT payload#>>'{valor_config,max_cambios}' FROM ig_remaining_probe WHERE code='REG_RL_003')<>'3'
 OR (SELECT payload#>>'{valor_config,scope}' FROM ig_remaining_probe WHERE code='REG_RL_003')<>'session_id'
 OR (SELECT payload#>>'{valor_config,accion}' FROM ig_remaining_probe WHERE code='REG_RL_003')<>'mostrar_soporte'
  OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='PHONE_UPDATE_MAX_PER_SESSION' AND config_value='3' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('PHONE_UPDATE_MAX_PER_SESSION')<>3
 OR patch->>'rule_code'<>'REG_RL_003' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'16adbaf32f5ab383d21af511032811a1343a2489830e97b46be1e7c2278269e1'
  OR patch#>>'{changes,valor_config,max_cambios_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,max_cambios_config,config_key}'<>'PHONE_UPDATE_MAX_PER_SESSION'
  OR (patch#>'{changes,valor_config}')?'max_cambios'
  OR patch#>>'{changes,valor_config,scope}'<>'session_id' OR patch#>>'{changes,valor_config,accion}'<>'mostrar_soporte' OR position('Al superar' in patch#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'RL003_PG17_SOURCE_CONFIG_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'RL003_PG17_SOURCE_CONFIG_PROFILE_PASS';
END $pre_rl003$;
SAVEPOINT ig_rl003_positive;
UPDATE ig_remaining_probe t SET payload=t.payload||jsonb_build_object('descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-8E808BBF541AA2D178E15290' AND s.step_id='execute_profile'),'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-8E808BBF541AA2D178E15290' AND s.step_id='execute_profile')) WHERE t.code='REG_RL_003';
DO $positive_rl003$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_003')<>'eb03479ff355b65cf28d245f32c545a171132646e8c94f4de3ac6dc4fda9577d' THEN RAISE EXCEPTION 'RL003_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'RL003_CANDIDATE_SHA_PASS';
END $positive_rl003$;
ROLLBACK TO SAVEPOINT ig_rl003_positive;
RELEASE SAVEPOINT ig_rl003_positive;
DO $back_rl003$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_003')<>'1692d7c9282c162ab2271471d5e8999d58478345fb692914f7fc9ee413c7a50c' THEN RAISE EXCEPTION 'RL003_POSITIVE_ROLLBACK_FAILED'; END IF;
END $back_rl003$;
SAVEPOINT ig_rl003_negative;
UPDATE ig_remaining_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb) WHERE code='REG_RL_003';
DELETE FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='PHONE_UPDATE_MAX_PER_SESSION';
DO $negative_rl003$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_003')='1692d7c9282c162ab2271471d5e8999d58478345fb692914f7fc9ee413c7a50c' OR EXISTS(SELECT 1 FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='PHONE_UPDATE_MAX_PER_SESSION') THEN RAISE EXCEPTION 'RL003_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'RL003_NEGATIVE_DRIFT_DETECTED';
END $negative_rl003$;
ROLLBACK TO SAVEPOINT ig_rl003_negative;
RELEASE SAVEPOINT ig_rl003_negative;
DO $final_rl003$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_003')<>'1692d7c9282c162ab2271471d5e8999d58478345fb692914f7fc9ee413c7a50c' OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='PHONE_UPDATE_MAX_PER_SESSION' AND config_value='3')<>1 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RL_003')<>'1692d7c9282c162ab2271471d5e8999d58478345fb692914f7fc9ee413c7a50c' OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-8E808BBF541AA2D178E15290' AND rule_code='REG_RL_003') THEN RAISE EXCEPTION 'RL003_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'RL003_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_SELECT_PASS; BACKEND_E2E_NOT_TESTED';
END $final_rl003$;
DO $pre_tec009$
DECLARE patch jsonb;
BEGIN
 SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-6161468F545B3653396DE9CB' AND s.step_id='execute_profile' AND s.status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17 OR (SELECT count(*) FROM ig_remaining_probe WHERE code='REG_TEC_009')<>1
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-6161468F545B3653396DE9CB' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_TEC_009' AND r.estado='VIGENTE' AND p.codigo='ONB_001')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-6161468F545B3653396DE9CB' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_TEC_009')<>'ab9e546d3324dcca8286810f28fc18a60ce29373435033cd934eb4436be67709'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_TEC_009')<>'ab9e546d3324dcca8286810f28fc18a60ce29373435033cd934eb4436be67709'
  OR (SELECT payload#>>'{valor_config,ventana_validez_minutos}' FROM ig_remaining_probe WHERE code='REG_TEC_009')<>'5'
 OR (SELECT payload#>>'{valor_config,generacion}' FROM ig_remaining_probe WHERE code='REG_TEC_009')<>'uuid_v4_en_cliente'
 OR (SELECT payload#>>'{valor_config,header}' FROM ig_remaining_probe WHERE code='REG_TEC_009')<>'X-Idempotency-Key'
  OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='IDEMPOTENCY_KEY_VALIDITY_MINUTES' AND config_value='5' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('IDEMPOTENCY_KEY_VALIDITY_MINUTES')<>5
 OR patch->>'rule_code'<>'REG_TEC_009' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'e10506f6a809c52f25b8ea442c9f5a3b705034f53f5293274345ebb5e5f6f05a'
  OR patch#>>'{changes,valor_config,ventana_validez_minutos_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,ventana_validez_minutos_config,config_key}'<>'IDEMPOTENCY_KEY_VALIDITY_MINUTES'
  OR (patch#>'{changes,valor_config}')?'ventana_validez_minutos'
  OR patch#>>'{changes,valor_config,header}'<>'X-Idempotency-Key' OR patch#>>'{changes,valor_config,generacion}'<>'uuid_v4_en_cliente' OR NOT (patch#>'{changes,valor_config,aplica_a}')@>'["submit_paso1","checkout"]'::jsonb
 THEN RAISE EXCEPTION 'TEC009_PG17_SOURCE_CONFIG_PROFILE_DRIFT'; END IF;
 RAISE NOTICE 'TEC009_PG17_SOURCE_CONFIG_PROFILE_PASS';
END $pre_tec009$;
SAVEPOINT ig_tec009_positive;
UPDATE ig_remaining_probe t SET payload=t.payload||jsonb_build_object('descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-6161468F545B3653396DE9CB' AND s.step_id='execute_profile'),'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-6161468F545B3653396DE9CB' AND s.step_id='execute_profile')) WHERE t.code='REG_TEC_009';
DO $positive_tec009$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_TEC_009')<>'9d326e934d57a16ab7f0bed7d8569b7d6b5a45aa402fb765121b44871e0e5cb2' THEN RAISE EXCEPTION 'TEC009_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'TEC009_CANDIDATE_SHA_PASS';
END $positive_tec009$;
ROLLBACK TO SAVEPOINT ig_tec009_positive;
RELEASE SAVEPOINT ig_tec009_positive;
DO $back_tec009$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_TEC_009')<>'ab9e546d3324dcca8286810f28fc18a60ce29373435033cd934eb4436be67709' THEN RAISE EXCEPTION 'TEC009_POSITIVE_ROLLBACK_FAILED'; END IF;
END $back_tec009$;
SAVEPOINT ig_tec009_negative;
UPDATE ig_remaining_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb) WHERE code='REG_TEC_009';
DELETE FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='IDEMPOTENCY_KEY_VALIDITY_MINUTES';
DO $negative_tec009$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_TEC_009')='ab9e546d3324dcca8286810f28fc18a60ce29373435033cd934eb4436be67709' OR EXISTS(SELECT 1 FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='IDEMPOTENCY_KEY_VALIDITY_MINUTES') THEN RAISE EXCEPTION 'TEC009_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'TEC009_NEGATIVE_DRIFT_DETECTED';
END $negative_tec009$;
ROLLBACK TO SAVEPOINT ig_tec009_negative;
RELEASE SAVEPOINT ig_tec009_negative;
DO $final_tec009$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_TEC_009')<>'ab9e546d3324dcca8286810f28fc18a60ce29373435033cd934eb4436be67709' OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='IDEMPOTENCY_KEY_VALIDITY_MINUTES' AND config_value='5')<>1 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_TEC_009')<>'ab9e546d3324dcca8286810f28fc18a60ce29373435033cd934eb4436be67709' OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-6161468F545B3653396DE9CB' AND rule_code='REG_TEC_009') THEN RAISE EXCEPTION 'TEC009_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'TEC009_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_SELECT_PASS; BACKEND_E2E_NOT_TESTED';
END $final_tec009$;
DO $pre_seg002$
DECLARE patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-3317DC878265B05840704DA9' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_remaining_probe WHERE code='REG_SEG_002')<>1
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-3317DC878265B05840704DA9' AND e.status='IN_PROGRESS'
  AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
  AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002'
  AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
  JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_SEG_002' AND r.estado='VIGENTE' AND p.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-3317DC878265B05840704DA9'
  AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE'
  AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_SEG_002')<>'d328b7165cda5974850193365ebc84865c73fec28e9a1bfdb4cf8b6d6d9d31f4'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
  FROM ig_remaining_probe WHERE code='REG_SEG_002')<>'d328b7165cda5974850193365ebc84865c73fec28e9a1bfdb4cf8b6d6d9d31f4'
 OR (SELECT payload#>>'{valor_config,otp_resend_max}' FROM ig_remaining_probe WHERE code='REG_SEG_002')<>'3'
 OR (SELECT payload#>>'{valor_config,otp_max_attempts_por_codigo}' FROM ig_remaining_probe WHERE code='REG_SEG_002')<>'5'
 OR (SELECT payload#>>'{valor_config,accion_usuario}' FROM ig_remaining_probe WHERE code='REG_SEG_002')<>'RESTART_ONBOARDING_FROM_ONB_001'
 OR (SELECT payload#>>'{valor_config,estado_resultado}' FROM ig_remaining_probe WHERE code='REG_SEG_002')<>'BLOCKED'
 OR (SELECT payload#>>'{valor_config,requiere_soporte}' FROM ig_remaining_probe WHERE code='REG_SEG_002')<>'false'
 OR (SELECT payload#>>'{valor_config,source_decision_number}' FROM ig_remaining_probe WHERE code='REG_SEG_002')<>'87'
 OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_MAX_RESENDS' AND config_value='3' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_MAX_ATTEMPTS' AND config_value='5' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('OTP_MAX_RESENDS')<>3
 OR public.lf_auth_config_integer_v1('OTP_MAX_ATTEMPTS')<>5
 OR patch->>'rule_code'<>'REG_SEG_002' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'b81d58ccb62138de3703f479613ccac6774477b80e70690bc99fac0438e8924b'
 OR patch#>>'{changes,valor_config,otp_resend_max_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,otp_resend_max_config,config_key}'<>'OTP_MAX_RESENDS'
 OR patch#>>'{changes,valor_config,otp_max_attempts_por_codigo_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,otp_max_attempts_por_codigo_config,config_key}'<>'OTP_MAX_ATTEMPTS'
 OR patch#>>'{changes,valor_config,accion_usuario}'<>'RESTART_ONBOARDING_FROM_ONB_001'
 OR patch#>>'{changes,valor_config,estado_resultado}'<>'BLOCKED'
 OR patch#>>'{changes,valor_config,requiere_soporte}'<>'false'
 OR patch#>>'{changes,valor_config,source_decision_number}'<>'87'
 OR (patch#>'{changes,valor_config}')?'otp_resend_max'
 OR (patch#>'{changes,valor_config}')?'otp_max_attempts_por_codigo'
 THEN RAISE EXCEPTION 'SEG002_PG17_SOURCE_PROFILE_CONFIG_DRIFT'; END IF;
 RAISE NOTICE 'SEG002_PG17_SOURCE_PROFILE_CONFIG_PASS';
END $pre_seg002$;
SAVEPOINT ig_seg002_positive;
UPDATE ig_remaining_probe t SET payload=t.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-3317DC878265B05840704DA9' AND s.step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-3317DC878265B05840704DA9' AND s.step_id='execute_profile'))
 WHERE code='REG_SEG_002';
DO $pos_seg002$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_SEG_002')<>'f567aef479fdeacb8f03d19498246a315139b1cd42a6410cd85a13fcab073715'
 THEN RAISE EXCEPTION 'SEG002_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'SEG002_CANDIDATE_SHA_PASS';
END $pos_seg002$;
ROLLBACK TO SAVEPOINT ig_seg002_positive;
RELEASE SAVEPOINT ig_seg002_positive;
DO $back_seg002$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_SEG_002')<>'d328b7165cda5974850193365ebc84865c73fec28e9a1bfdb4cf8b6d6d9d31f4'
 THEN RAISE EXCEPTION 'SEG002_POSITIVE_ROLLBACK_FAIL'; END IF;
END $back_seg002$;
SAVEPOINT ig_seg002_negative;
UPDATE ig_remaining_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb) WHERE code='REG_SEG_002';
DELETE FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_MAX_RESENDS';
DO $neg_seg002$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_SEG_002')='d328b7165cda5974850193365ebc84865c73fec28e9a1bfdb4cf8b6d6d9d31f4'
 OR EXISTS(SELECT 1 FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_MAX_RESENDS')
 THEN RAISE EXCEPTION 'SEG002_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'SEG002_NEGATIVE_DRIFT_DETECTED';
END $neg_seg002$;
ROLLBACK TO SAVEPOINT ig_seg002_negative;
RELEASE SAVEPOINT ig_seg002_negative;
DO $final_seg002$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_SEG_002')<>'d328b7165cda5974850193365ebc84865c73fec28e9a1bfdb4cf8b6d6d9d31f4'
 OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_MAX_RESENDS' AND config_value='3')<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_SEG_002')<>'d328b7165cda5974850193365ebc84865c73fec28e9a1bfdb4cf8b6d6d9d31f4'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-3317DC878265B05840704DA9' AND rule_code='REG_SEG_002')
 THEN RAISE EXCEPTION 'SEG002_INDEPENDENT_SELECT_FAIL'; END IF;
 RAISE NOTICE 'SEG002_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_SELECT_PASS; BACKEND_E2E_NOT_TESTED';
END $final_seg002$;
DO $pre_rl002$
DECLARE patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-9A0B8F4245D22E90E0C12383' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_remaining_probe WHERE code='REG_RL_002')<>1
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-9A0B8F4245D22E90E0C12383' AND e.status='IN_PROGRESS'
  AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
  AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_RL_002' AND r.estado='VIGENTE' AND p.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-9A0B8F4245D22E90E0C12383'
  AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RL_002')<>'d6966fb26db3ef0249bfe479e1920834e279d8b31432738746ee9d965b2e5a80'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_002')<>'d6966fb26db3ef0249bfe479e1920834e279d8b31432738746ee9d965b2e5a80'
 OR (SELECT payload#>>'{valor_config,scope}' FROM ig_remaining_probe WHERE code='REG_RL_002')<>'session_id'
 OR (SELECT payload#>>'{valor_config,bloqueo_minutos}' FROM ig_remaining_probe WHERE code='REG_RL_002')<>'2'
 OR position('los 3 reenvíos' in (SELECT payload->>'descripcion' FROM ig_remaining_probe WHERE code='REG_RL_002'))=0
 OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_MAX_RESENDS' AND config_value='3' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_RESEND_LIMIT_COOLDOWN_MINUTES' AND config_value='2' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('OTP_MAX_RESENDS')<>3
 OR public.lf_auth_config_integer_v1('OTP_RESEND_LIMIT_COOLDOWN_MINUTES')<>2
 OR patch->>'rule_code'<>'REG_RL_002' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'95e0c9c9c1f6834d5cfca09913e2ba3ee805cd605629656f92bd9cc9c7cf067b'
 OR patch#>>'{changes,valor_config,scope}'<>'session_id'
 OR patch#>>'{changes,valor_config,max_reenvios_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,max_reenvios_config,config_key}'<>'OTP_MAX_RESENDS'
 OR patch#>>'{changes,valor_config,bloqueo_minutos_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,bloqueo_minutos_config,config_key}'<>'OTP_RESEND_LIMIT_COOLDOWN_MINUTES'
 OR (patch#>'{changes,valor_config}')?'bloqueo_minutos'
 OR position('bloquea temporalmente' in patch#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'RL002_PG17_SOURCE_PROFILE_CONFIG_DRIFT'; END IF;
 RAISE NOTICE 'RL002_PG17_SOURCE_PROFILE_CONFIG_PASS';
END $pre_rl002$;
SAVEPOINT ig_rl002_positive;
UPDATE ig_remaining_probe t SET payload=t.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-9A0B8F4245D22E90E0C12383' AND s.step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-9A0B8F4245D22E90E0C12383' AND s.step_id='execute_profile'))
 WHERE code='REG_RL_002';
DO $positive_rl002$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_002')<>'d0e61eebd5f645cff6e61a605bf3060459a0036506c3691baa629cc904eb73c4'
 THEN RAISE EXCEPTION 'RL002_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'RL002_CANDIDATE_SHA_PASS';
END $positive_rl002$;
ROLLBACK TO SAVEPOINT ig_rl002_positive;
RELEASE SAVEPOINT ig_rl002_positive;
DO $back_rl002$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_002')<>'d6966fb26db3ef0249bfe479e1920834e279d8b31432738746ee9d965b2e5a80'
 THEN RAISE EXCEPTION 'RL002_POSITIVE_ROLLBACK_FAIL'; END IF;
END $back_rl002$;
SAVEPOINT ig_rl002_negative;
UPDATE ig_remaining_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb) WHERE code='REG_RL_002';
DELETE FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_RESEND_LIMIT_COOLDOWN_MINUTES';
DO $negative_rl002$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_002')='d6966fb26db3ef0249bfe479e1920834e279d8b31432738746ee9d965b2e5a80'
 OR EXISTS(SELECT 1 FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_RESEND_LIMIT_COOLDOWN_MINUTES')
 THEN RAISE EXCEPTION 'RL002_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'RL002_NEGATIVE_DRIFT_DETECTED';
END $negative_rl002$;
ROLLBACK TO SAVEPOINT ig_rl002_negative;
RELEASE SAVEPOINT ig_rl002_negative;
DO $final_rl002$ BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_remaining_probe WHERE code='REG_RL_002')<>'d6966fb26db3ef0249bfe479e1920834e279d8b31432738746ee9d965b2e5a80'
 OR (SELECT count(*) FROM ig_remaining_cfg WHERE scope='AUTH' AND config_key='OTP_RESEND_LIMIT_COOLDOWN_MINUTES' AND config_value='2')<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RL_002')<>'d6966fb26db3ef0249bfe479e1920834e279d8b31432738746ee9d965b2e5a80'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-9A0B8F4245D22E90E0C12383' AND rule_code='REG_RL_002')
 THEN RAISE EXCEPTION 'RL002_INDEPENDENT_SELECT_FAIL'; END IF;
 RAISE NOTICE 'RL002_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_SELECT_PASS; BACKEND_E2E_NOT_TESTED';
END $final_rl002$;
COMMIT;
