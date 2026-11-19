-- IG Familia A REG_ATQ_012, PostgreSQL17 real, source-bound,
-- TEMP-only reversible positive/negative probes + independent SELECT after ROLLBACK.
BEGIN;
CREATE TEMP TABLE ig_atq012_probe(payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_atq012_cfg(scope text,config_key text,config_value text,value_type text,value_status text) ON COMMIT DROP;
INSERT INTO ig_atq012_probe SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_ATQ_012';
INSERT INTO ig_atq012_cfg SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config
WHERE scope='AUTH' AND config_key IN ('OTP_MAX_ATTEMPTS','OTP_MAX_RESENDS','OTP_EXHAUSTION_COOLDOWN_SECONDS');
DO $pre$
DECLARE
 old constant text:='35e94c0b94e65e7d45c44774904a11ccb7055134ce31a8a903cd4c5903c9728b'; prop constant text:='e3eca6e95c1de1d8a921ecf4f32796d373bec538be7de590de8de90731352620';
 p constant text:='EXEC-PROFILE-GATE2-D1C98DA906710AE386EEA8C9'; patch jsonb;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_atq012_probe)<>1
 OR (SELECT count(*) FROM public.lf_operation_execution e WHERE e.execution_id=p
  AND e.operation_code='EJECUCION_PERFIL_LF' AND e.status='IN_PROGRESS' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
  AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002'
  AND e.manifest->>'no_write'='true')<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
  JOIN lf_ops.pantallas s ON s.id=rp.pantalla_id
  WHERE r.codigo='REG_ATQ_012' AND r.estado='VIGENTE' AND s.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps WHERE execution_id=p AND step_id='output_validate'
  AND status='STEP_PASS_WITH_EVIDENCE' AND evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ATQ_012') IS DISTINCT FROM old
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_atq012_probe)<>old
 THEN RAISE EXCEPTION 'ATQ012_REAL_PG17_PARENT_OR_SOURCE_DRIFT'; END IF;
 IF (SELECT count(*) FROM ig_atq012_cfg
  WHERE (config_key='OTP_MAX_ATTEMPTS' AND config_value='5' OR config_key='OTP_MAX_RESENDS' AND config_value='3'
   OR config_key='OTP_EXHAUSTION_COOLDOWN_SECONDS' AND config_value='120')
  AND value_type='INTEGER' AND value_status='REAL' AND scope='AUTH')<>3
 OR public.lf_auth_config_integer_v1('OTP_MAX_ATTEMPTS')<>5
 OR public.lf_auth_config_integer_v1('OTP_MAX_RESENDS')<>3
 OR public.lf_auth_config_integer_v1('OTP_EXHAUSTION_COOLDOWN_SECONDS')<>120
 OR (SELECT payload#>>'{valor_config,max_attempts_per_otp}' FROM ig_atq012_probe) IS DISTINCT FROM '5'
 OR (SELECT payload#>>'{valor_config,max_resends}' FROM ig_atq012_probe) IS DISTINCT FROM '3'
 OR (SELECT payload#>>'{valor_config,cooldown_after_exhaustion_seconds}' FROM ig_atq012_probe) IS DISTINCT FROM '120'
 THEN RAISE EXCEPTION 'ATQ012_REAL_PG17_CONFIG_SOURCE_DRIFT'; END IF;
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch
 FROM public.lf_operation_execution_steps WHERE execution_id=p AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF patch->>'rule_code'<>'REG_ATQ_012' OR patch->>'change_kind'<>'FUNCTIONAL'
  OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>prop
  OR patch#>>'{changes,valor_config,max_attempts_per_otp_config,config_key}'<>'OTP_MAX_ATTEMPTS'
  OR patch#>>'{changes,valor_config,max_resends_config,config_key}'<>'OTP_MAX_RESENDS'
  OR patch#>>'{changes,valor_config,cooldown_after_exhaustion_config,config_key}'<>'OTP_EXHAUSTION_COOLDOWN_SECONDS'
  OR (patch#>'{changes,valor_config}')?'max_attempts_per_otp'
  OR (patch#>'{changes,valor_config}')?'max_resends'
  OR (patch#>'{changes,valor_config}')?'cooldown_after_exhaustion_seconds'
  OR patch#>>'{changes,valor_config,source_decision_number}'<>'87'
  OR patch#>>'{changes,valor_config,estado_final}'<>'BLOCKED'
  OR position('no se bloquea permanentemente' in patch#>>'{changes,descripcion}')=0
  OR position('último reenvío permitido' in patch#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'ATQ012_REAL_PG17_PATCH_SEMANTICS_CHANGED'; END IF;
 RAISE NOTICE 'IG_ATQ012_PG17_PRE_SOURCE_PROFILE_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_atq012_positive;
UPDATE ig_atq012_probe t SET payload=t.payload||jsonb_build_object(
 'descripcion',(SELECT evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}'
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-D1C98DA906710AE386EEA8C9' AND step_id='execute_profile'),
 'valor_config',(SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}'
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-D1C98DA906710AE386EEA8C9' AND step_id='execute_profile'));
DO $candidate$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_atq012_probe)
  IS DISTINCT FROM 'b7c7bcd16df6996fdc0f6e8fce9fe24f43f153db6d0da69a07fd63a92481f5e4' THEN RAISE EXCEPTION 'ATQ012_PG17_CANDIDATE_MISMATCH'; END IF;
 RAISE NOTICE 'IG_ATQ012_PG17_POSITIVE_CANDIDATE_PASS';
END $candidate$;
ROLLBACK TO SAVEPOINT ig_atq012_positive;
RELEASE SAVEPOINT ig_atq012_positive;
DO $positive_readback$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_atq012_probe) <> '35e94c0b94e65e7d45c44774904a11ccb7055134ce31a8a903cd4c5903c9728b'
 THEN RAISE EXCEPTION 'ATQ012_PG17_POSITIVE_ROLLBACK_FAILED'; END IF;
 RAISE NOTICE 'IG_ATQ012_PG17_POSITIVE_ROLLBACK_PASS';
END $positive_readback$;
SAVEPOINT ig_atq012_negative;
UPDATE ig_atq012_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb);
DELETE FROM ig_atq012_cfg WHERE config_key='OTP_MAX_RESENDS';
DO $negative$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_atq012_probe)='35e94c0b94e65e7d45c44774904a11ccb7055134ce31a8a903cd4c5903c9728b'
 OR EXISTS(SELECT 1 FROM ig_atq012_cfg WHERE config_key='OTP_MAX_RESENDS')
 THEN RAISE EXCEPTION 'ATQ012_PG17_NEGATIVE_GUARD_FAIL'; END IF;
 RAISE NOTICE 'IG_ATQ012_PG17_NEGATIVE_SOURCE_DRIFT_AND_MISSING_CONFIG_DETECTED';
END $negative$;
ROLLBACK TO SAVEPOINT ig_atq012_negative;
RELEASE SAVEPOINT ig_atq012_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_atq012_probe) <> '35e94c0b94e65e7d45c44774904a11ccb7055134ce31a8a903cd4c5903c9728b'
 OR (SELECT count(*) FROM ig_atq012_cfg)<>3
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ATQ_012')<>'35e94c0b94e65e7d45c44774904a11ccb7055134ce31a8a903cd4c5903c9728b'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-D1C98DA906710AE386EEA8C9' AND rule_code='REG_ATQ_012')
 THEN RAISE EXCEPTION 'ATQ012_PG17_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'IG_ATQ012_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;