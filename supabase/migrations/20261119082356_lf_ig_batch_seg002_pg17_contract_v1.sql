-- REG_SEG_002 standalone real PG17 positive/negative rollback contract proof.
-- No persistent mutation of lf_ops.reglas or lf_global_config. Backend E2E NOT_TESTED.
BEGIN;
CREATE TEMP TABLE ig_seg002_probe(payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_seg002_config(scope text, config_key text, config_value text, value_type text, value_status text) ON COMMIT DROP;
INSERT INTO ig_seg002_probe SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE r.codigo='REG_SEG_002';
INSERT INTO ig_seg002_config SELECT scope,config_key,config_value,value_type,value_status
 FROM public.lf_global_config WHERE scope='AUTH' AND config_key IN ('OTP_MAX_RESENDS','OTP_MAX_ATTEMPTS');
DO $seg002_pre$
DECLARE patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-3317DC878265B05840704DA9' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::integer / 10000<>17
 OR (SELECT count(*) FROM ig_seg002_probe)<>1
 OR (SELECT count(*) FROM ig_seg002_config WHERE scope='AUTH' AND value_type='INTEGER' AND value_status='REAL'
 AND ((config_key='OTP_MAX_RESENDS' AND config_value='3') OR (config_key='OTP_MAX_ATTEMPTS' AND config_value='5')))<>2
 OR public.lf_auth_config_integer_v1('OTP_MAX_RESENDS')<>3
 OR public.lf_auth_config_integer_v1('OTP_MAX_ATTEMPTS')<>5
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_SEG_002')<>'d328b7165cda5974850193365ebc84865c73fec28e9a1bfdb4cf8b6d6d9d31f4'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg002_probe)<>'d328b7165cda5974850193365ebc84865c73fec28e9a1bfdb4cf8b6d6d9d31f4'
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas screen ON screen.id=rp.pantalla_id WHERE r.codigo='REG_SEG_002' AND r.estado='VIGENTE' AND screen.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-3317DC878265B05840704DA9' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.status='IN_PROGRESS' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002' AND e.manifest->>'read_only'='true' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-3317DC878265B05840704DA9' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR (SELECT payload#>>'{valor_config,otp_resend_max}' FROM ig_seg002_probe)<>'3'
 OR (SELECT payload#>>'{valor_config,otp_max_attempts_por_codigo}' FROM ig_seg002_probe)<>'5'
 OR (SELECT payload#>>'{valor_config,source_decision_number}' FROM ig_seg002_probe)<>'87'
 OR (SELECT payload#>>'{valor_config,accion_usuario}' FROM ig_seg002_probe)<>'RESTART_ONBOARDING_FROM_ONB_001'
 OR (SELECT payload#>>'{valor_config,estado_resultado}' FROM ig_seg002_probe)<>'BLOCKED'
 OR (SELECT payload#>>'{valor_config,requiere_soporte}' FROM ig_seg002_probe)<>'false'
 OR patch->>'rule_code'<>'REG_SEG_002' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'b81d58ccb62138de3703f479613ccac6774477b80e70690bc99fac0438e8924b'
 OR patch#>>'{changes,valor_config,otp_resend_max_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,otp_resend_max_config,config_key}'<>'OTP_MAX_RESENDS'
 OR patch#>>'{changes,valor_config,otp_max_attempts_por_codigo_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,otp_max_attempts_por_codigo_config,config_key}'<>'OTP_MAX_ATTEMPTS'
 OR patch#>>'{changes,valor_config,source_decision_number}'<>'87'
 OR patch#>>'{changes,valor_config,accion_usuario}'<>'RESTART_ONBOARDING_FROM_ONB_001'
 OR patch#>>'{changes,valor_config,estado_resultado}'<>'BLOCKED'
 OR patch#>>'{changes,valor_config,requiere_soporte}'<>'false'
 OR (patch#>'{changes,valor_config}')?'otp_resend_max'
 OR (patch#>'{changes,valor_config}')?'otp_max_attempts_por_codigo'
 OR position('último reenvío permitido' IN patch#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'SEG002_REAL_PG17_SOURCE_PROFILE_CONFIG_OR_SEMANTIC_DRIFT'; END IF;
 RAISE NOTICE 'SEG002_PG17_SOURCE_PROFILE_CONFIG_PASS';
END $seg002_pre$;
SAVEPOINT ig_seg002_positive;
UPDATE ig_seg002_probe p SET payload=p.payload||jsonb_build_object(
 'descripcion',(SELECT evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-3317DC878265B05840704DA9' AND step_id='execute_profile'),
 'valor_config',(SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-3317DC878265B05840704DA9' AND step_id='execute_profile'));
DO $seg002_pos$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg002_probe)<>'f567aef479fdeacb8f03d19498246a315139b1cd42a6410cd85a13fcab073715'
 THEN RAISE EXCEPTION 'SEG002_REAL_PG17_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'SEG002_REAL_PG17_CANDIDATE_SHA_PASS';
END $seg002_pos$;
ROLLBACK TO SAVEPOINT ig_seg002_positive;
RELEASE SAVEPOINT ig_seg002_positive;
DO $seg002_back$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg002_probe)<>'d328b7165cda5974850193365ebc84865c73fec28e9a1bfdb4cf8b6d6d9d31f4'
 THEN RAISE EXCEPTION 'SEG002_REAL_PG17_POSITIVE_ROLLBACK_FAILED'; END IF;
 RAISE NOTICE 'SEG002_REAL_PG17_POSITIVE_ROLLBACK_READBACK_PASS';
END $seg002_back$;
SAVEPOINT ig_seg002_negative;
UPDATE ig_seg002_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb);
DELETE FROM ig_seg002_config WHERE scope='AUTH' AND config_key='OTP_MAX_RESENDS';
DO $seg002_negative$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg002_probe)='d328b7165cda5974850193365ebc84865c73fec28e9a1bfdb4cf8b6d6d9d31f4'
 OR EXISTS(SELECT 1 FROM ig_seg002_config WHERE config_key='OTP_MAX_RESENDS')
 THEN RAISE EXCEPTION 'SEG002_REAL_PG17_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'SEG002_REAL_PG17_NEGATIVE_SOURCE_CONFIG_DRIFT_DETECTED';
END $seg002_negative$;
ROLLBACK TO SAVEPOINT ig_seg002_negative;
RELEASE SAVEPOINT ig_seg002_negative;
DO $seg002_final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg002_probe)<>'d328b7165cda5974850193365ebc84865c73fec28e9a1bfdb4cf8b6d6d9d31f4'
 OR (SELECT count(*) FROM ig_seg002_config)<>2
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_SEG_002')<>'d328b7165cda5974850193365ebc84865c73fec28e9a1bfdb4cf8b6d6d9d31f4'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-3317DC878265B05840704DA9' AND rule_code='REG_SEG_002')
 THEN RAISE EXCEPTION 'SEG002_REAL_PG17_INDEPENDENT_READBACK_FAILED'; END IF;
 RAISE NOTICE 'SEG002_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $seg002_final$;
COMMIT;
