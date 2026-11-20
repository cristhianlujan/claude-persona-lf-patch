-- IG Familia B, REG_ALR_001. PG17 contract level; REAL reversible only, no DML on authority.
-- Source-bound native Product Director RUN / screen / Step50+60, original SHA, proposal SHA, candidate SHA.
-- Positive and negative SAVEPOINT/ROLLBACK, subsequent independent SELECT.
-- No backend E2E assertion.
BEGIN;
CREATE TEMP TABLE ig_b_alr001_probe (code text PRIMARY KEY,payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_b_alr001_config (scope text NOT NULL,config_key text NOT NULL,config_value text NOT NULL,value_type text NOT NULL,value_status text NOT NULL) ON COMMIT DROP;
INSERT INTO ig_b_alr001_probe SELECT r.codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_ALR_001';
INSERT INTO ig_b_alr001_config
 SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config
 WHERE scope='ALERTAS' AND config_key IN ('OTP_VERIFICATION_MIN_RATE','OTP_VERIFICATION_WINDOW_MINUTES');
DO $pre$
DECLARE v_patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch
 FROM public.lf_operation_execution_steps
 WHERE execution_id='EXEC-PROFILE-GATE2-A5639FC053BB74DE9AFD2273' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_alr001_probe)<>1
 OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo='REG_ALR_001' AND estado='VIGENTE')<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_ALR_001' AND es_actual)<>1
 OR NOT EXISTS(
  SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
  JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_ALR_001' AND p.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE
  e.execution_id='EXEC-PROFILE-GATE2-A5639FC053BB74DE9AFD2273' AND e.operation_code='EJECUCION_PERFIL_LF'
  AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS'
  AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002'
  AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE
  s.execution_id='EXEC-PROFILE-GATE2-A5639FC053BB74DE9AFD2273' AND s.step_id='output_validate'
  AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ALR_001')<>'041953d0ab76dffd9a250f528bfeb40220435f82f3aa5d39b293501129beac06'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
     FROM ig_b_alr001_probe)<>'041953d0ab76dffd9a250f528bfeb40220435f82f3aa5d39b293501129beac06'
 OR (SELECT payload#>>'{valor_config,umbral_minimo}' FROM ig_b_alr001_probe)<>'0.60'
 OR (SELECT payload#>>'{valor_config,ventana_minutos}' FROM ig_b_alr001_probe)<>'30'
 OR (SELECT count(*) FROM ig_b_alr001_config
  WHERE (config_key='OTP_VERIFICATION_MIN_RATE' AND config_value='0.6' AND value_type='DECIMAL' AND value_status='REAL')
   OR (config_key='OTP_VERIFICATION_WINDOW_MINUTES' AND config_value='30' AND value_type='INTEGER' AND value_status='REAL'))<>2
 OR v_patch->>'rule_code'<>'REG_ALR_001'
 OR v_patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex')<>'bb7e79c1e32339b17130f249b692c9f5d7dfbefa5964dd16fdb2852e5a300bef'
 OR v_patch#>>'{changes,valor_config,umbral_minimo_config_ref,scope}'<>'ALERTAS'
 OR v_patch#>>'{changes,valor_config,umbral_minimo_config_ref,config_key}'<>'OTP_VERIFICATION_MIN_RATE'
 OR v_patch#>>'{changes,valor_config,ventana_minutos_config_ref,scope}'<>'ALERTAS'
 OR v_patch#>>'{changes,valor_config,ventana_minutos_config_ref,config_key}'<>'OTP_VERIFICATION_WINDOW_MINUTES'
 OR (v_patch#>'{changes,valor_config}') ? 'umbral_minimo'
 OR (v_patch#>'{changes,valor_config}') ? 'ventana_minutos'
 OR v_patch#>>'{changes,valor_config,metrica}'<>'otp_verification_rate'
 OR v_patch#>>'{changes,valor_config,canal_alerta}'<>'slack_tecnico'
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%otp_verified / otp_sent%'
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%alerta inmediata al equipo técnico%'
 OR (v_patch#>>'{changes,descripcion}') LIKE '%60%'
 OR (v_patch#>>'{changes,descripcion}') LIKE '%30 minutos%'
 OR EXISTS (SELECT 1 FROM public.lf_ig_owner_decision_v2
  WHERE parent_execution_id='EXEC-PROFILE-GATE2-A5639FC053BB74DE9AFD2273' AND rule_code='REG_ALR_001')
 THEN RAISE EXCEPTION 'IG_B_ALR001_SOURCE_PROFILE_OR_CONFIG_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_ALR001_PREIMAGE_PROFILE_SHA_REAL_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_b_alr001_positive;
UPDATE ig_b_alr001_probe t
 SET payload=t.payload||jsonb_build_object(
  'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-A5639FC053BB74DE9AFD2273' AND s.step_id='execute_profile'),
  'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-A5639FC053BB74DE9AFD2273' AND s.step_id='execute_profile')
 ) WHERE code='REG_ALR_001';
DO $pos$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr001_probe)<>'add7b3ad0e58be063c37a76337263ab6649c18b0a0149ab05899f044bc58271e'
 OR (SELECT payload->>'estado' FROM ig_b_alr001_probe)<>'VIGENTE'
 OR (SELECT payload->>'razon' FROM ig_b_alr001_probe) IS DISTINCT FROM
 (SELECT razon FROM lf_ops.reglas WHERE codigo='REG_ALR_001')
 THEN RAISE EXCEPTION 'IG_B_ALR001_CANDIDATE_SHA_OR_SEMANTICS_FAIL'; END IF;
 RAISE NOTICE 'IG_B_ALR001_CANDIDATE_SHA_POSITIVE_PASS';
END $pos$;
ROLLBACK TO SAVEPOINT ig_b_alr001_positive;
RELEASE SAVEPOINT ig_b_alr001_positive;
DO $rb1$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr001_probe)<>'041953d0ab76dffd9a250f528bfeb40220435f82f3aa5d39b293501129beac06'
 THEN RAISE EXCEPTION 'IG_B_ALR001_POSITIVE_ROLLBACK_FAIL'; END IF;
END $rb1$;
SAVEPOINT ig_b_alr001_negative;
UPDATE ig_b_alr001_probe SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb);
DELETE FROM ig_b_alr001_config WHERE config_key='OTP_VERIFICATION_MIN_RATE';
DO $neg$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr001_probe)='041953d0ab76dffd9a250f528bfeb40220435f82f3aa5d39b293501129beac06'
 OR (SELECT count(*) FROM ig_b_alr001_config)<>1
 THEN RAISE EXCEPTION 'IG_B_ALR001_NEGATIVE_DRIFT_UNDETECTED'; END IF;
 RAISE NOTICE 'IG_B_ALR001_NEGATIVE_DRIFT_AND_MISSING_CONFIG_DETECTED';
END $neg$;
ROLLBACK TO SAVEPOINT ig_b_alr001_negative;
RELEASE SAVEPOINT ig_b_alr001_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr001_probe)<>'041953d0ab76dffd9a250f528bfeb40220435f82f3aa5d39b293501129beac06'
 OR (SELECT count(*) FROM ig_b_alr001_config)<>2
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ALR_001')<>'041953d0ab76dffd9a250f528bfeb40220435f82f3aa5d39b293501129beac06'
 OR EXISTS (SELECT 1 FROM public.lf_ig_owner_decision_v2
  WHERE parent_execution_id='EXEC-PROFILE-GATE2-A5639FC053BB74DE9AFD2273' AND rule_code='REG_ALR_001')
 THEN RAISE EXCEPTION 'IG_B_ALR001_INDEPENDENT_SELECT_OR_NO_WRITE_FAIL'; END IF;
 RAISE NOTICE 'IG_B_ALR001_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;
