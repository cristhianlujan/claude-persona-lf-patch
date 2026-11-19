-- Familia B ALR004+005 title-complete native RUN V2 PG17 reversible contract.
-- One PR, one migration. No target rule write. Backend E2E NOT_TESTED.
BEGIN;
CREATE TEMP TABLE ig_b_alr45_specs(code text PRIMARY KEY,run text,screen text,source_sha text,patch_sha text,candidate_sha text) ON COMMIT DROP;
INSERT INTO ig_b_alr45_specs VALUES
('REG_ALR_004','EXEC-PROFILE-GATE2-E20D2C0F25D8B32CF9CD6EA3','ONB_001','aaa2aed1bb7ce2697b814dab5909cd151f642c5a89032a9f3763db8ce5011505','fe5dd29eec29d98db3053c8bb7a6a3c4e283ae1b3821de9900cff09478ee63f5','bb60d95cbc9aacba740aa4a490759d8d4079770878047324b89a909df552321c'),
('REG_ALR_005','EXEC-PROFILE-GATE2-5ABE133CA01BE0AD525073E0','ONB_001','4b2d32422b36f65637cdf5901f93570fe60aa4abf1528f47cd301e5b43f38b72','206ce6e62e928c6b29dbca57fc672b06bfecb21b1ea0a343ba7780577ae0c369','27b73cdf590967e30f6968f11b33e34bdd41c87d589e0d472a75e232095aa8a3');
CREATE TEMP TABLE ig_b_alr45_probe AS SELECT r.codigo AS code,to_jsonb(r) payload FROM lf_ops.reglas r WHERE r.codigo IN('REG_ALR_004','REG_ALR_005');
CREATE TEMP TABLE ig_b_alr45_config AS SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='ALERTAS' AND config_key IN('PASO1_SUBMIT_ERROR_RATE_MAX','PASO1_SUBMIT_ERROR_WINDOW_MINUTES','LCP_ALERT_THRESHOLD_MS','LCP_ALERT_SESSIONS_RATIO','LCP_ALERT_WINDOW_HOURS');
DO $pre$
DECLARE x record;v_patch jsonb;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17 OR (SELECT count(*) FROM ig_b_alr45_specs)<>2 OR (SELECT count(*) FROM ig_b_alr45_probe)<>2
 OR (SELECT count(*) FROM ig_b_alr45_config c WHERE c.value_status='REAL' AND
 ((c.config_key='PASO1_SUBMIT_ERROR_RATE_MAX' AND c.config_value='0.05' AND c.value_type='DECIMAL')
 OR (c.config_key='PASO1_SUBMIT_ERROR_WINDOW_MINUTES' AND c.config_value='15' AND c.value_type='INTEGER')
 OR (c.config_key='LCP_ALERT_THRESHOLD_MS' AND c.config_value='4000' AND c.value_type='INTEGER')
 OR (c.config_key='LCP_ALERT_SESSIONS_RATIO' AND c.config_value='0.2' AND c.value_type='DECIMAL')
 OR (c.config_key='LCP_ALERT_WINDOW_HOURS' AND c.config_value='1' AND c.value_type='INTEGER')))<>5
 THEN RAISE EXCEPTION 'IG_B_ALR45_PG17_CONFIG_OR_SERVER_DRIFT'; END IF;
 FOR x IN SELECT * FROM ig_b_alr45_specs ORDER BY code LOOP
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch
 FROM public.lf_operation_execution_steps WHERE execution_id=x.run AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=x.code AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo=x.code AND r.estado='VIGENTE' AND p.codigo=x.screen)
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=x.run AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'=x.screen AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id=x.run AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA',x.code) IS DISTINCT FROM x.source_sha
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr45_probe WHERE code=x.code) IS DISTINCT FROM x.source_sha
 OR v_patch->>'rule_code' IS DISTINCT FROM x.code OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM x.patch_sha
 OR position('public.lf_global_config' in v_patch#>>'{changes,titulo}')=0
 OR position('public.lf_global_config' in v_patch#>>'{changes,descripcion}')=0
 OR (v_patch#>>'{changes,titulo}') ~ '[0-9]+[[:space:]]*(%|ms|segundos)'
 OR (v_patch#>'{changes,valor_config}') ? 'umbral_maximo'
 OR (v_patch#>'{changes,valor_config}') ? 'umbral_ms'
 OR (v_patch#>'{changes,valor_config}') ? 'porcentaje_sesiones'
 OR (v_patch#>'{changes,valor_config}') ? 'ventana_minutos'
 OR (v_patch#>'{changes,valor_config}') ? 'ventana_horas'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id=x.run AND rule_code=x.code)
 THEN RAISE EXCEPTION 'IG_B_ALR45_PROFILE_SHA_SOURCE_OR_SCOPE_DRIFT:%',x.code; END IF;
 IF x.code='REG_ALR_004' AND (
 v_patch#>>'{changes,valor_config,umbral_maximo_config_ref,config_key}' IS DISTINCT FROM 'PASO1_SUBMIT_ERROR_RATE_MAX'
 OR v_patch#>>'{changes,valor_config,ventana_minutos_config_ref,config_key}' IS DISTINCT FROM 'PASO1_SUBMIT_ERROR_WINDOW_MINUTES'
 OR v_patch#>>'{changes,valor_config,canal_alerta}' IS DISTINCT FROM 'slack_tecnico'
 OR v_patch#>>'{changes,valor_config,metrica}' IS DISTINCT FROM 'paso1_submit_error_rate') THEN RAISE EXCEPTION 'IG_B_ALR004_FUNCTIONAL_DRIFT'; END IF;
 IF x.code='REG_ALR_005' AND (
 v_patch#>>'{changes,valor_config,umbral_ms_config_ref,config_key}' IS DISTINCT FROM 'LCP_ALERT_THRESHOLD_MS'
 OR v_patch#>>'{changes,valor_config,porcentaje_sesiones_config_ref,config_key}' IS DISTINCT FROM 'LCP_ALERT_SESSIONS_RATIO'
 OR v_patch#>>'{changes,valor_config,ventana_horas_config_ref,config_key}' IS DISTINCT FROM 'LCP_ALERT_WINDOW_HOURS'
 OR v_patch#>>'{changes,valor_config,metrica}' IS DISTINCT FROM 'LCP') THEN RAISE EXCEPTION 'IG_B_ALR005_FUNCTIONAL_DRIFT'; END IF;
 END LOOP;
 RAISE NOTICE 'IG_B_ALR45_FULL_TITLE_NATIVE_PREIMAGE_SHA_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_b_alr45_positive;
UPDATE ig_b_alr45_probe t SET payload=t.payload||jsonb_build_object(
 'titulo',s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,titulo}',
 'descripcion',s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}',
 'valor_config',s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}')
 FROM ig_b_alr45_specs x JOIN public.lf_operation_execution_steps s ON s.execution_id=x.run AND s.step_id='execute_profile'
 WHERE t.code=x.code;
DO $positive$
BEGIN
 IF EXISTS(SELECT 1 FROM ig_b_alr45_probe t JOIN ig_b_alr45_specs x ON x.code=t.code WHERE encode(extensions.digest(convert_to((t.payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM x.candidate_sha)
 THEN RAISE EXCEPTION 'IG_B_ALR45_CANDIDATE_SHA_INVALID'; END IF;
 RAISE NOTICE 'IG_B_ALR45_CANDIDATE_SHA_PASS';
END $positive$;
ROLLBACK TO SAVEPOINT ig_b_alr45_positive;
RELEASE SAVEPOINT ig_b_alr45_positive;
DO $rollback$
BEGIN
 IF EXISTS(SELECT 1 FROM ig_b_alr45_probe t JOIN ig_b_alr45_specs x ON x.code=t.code WHERE encode(extensions.digest(convert_to((t.payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM x.source_sha)
 THEN RAISE EXCEPTION 'IG_B_ALR45_POSITIVE_ROLLBACK_FAILED'; END IF;
END $rollback$;
SAVEPOINT ig_b_alr45_negative;
UPDATE ig_b_alr45_probe SET payload=jsonb_set(payload,'{titulo}','"SOURCE_DRIFT"'::jsonb);
DELETE FROM ig_b_alr45_config WHERE config_key='LCP_ALERT_THRESHOLD_MS';
DO $negative$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM ig_b_alr45_probe t JOIN ig_b_alr45_specs x ON x.code=t.code WHERE encode(extensions.digest(convert_to((t.payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM x.source_sha)
 OR EXISTS(SELECT 1 FROM ig_b_alr45_config WHERE config_key='LCP_ALERT_THRESHOLD_MS') THEN RAISE EXCEPTION 'IG_B_ALR45_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_ALR45_NEGATIVE_SOURCE_AND_MISSING_CONFIG_PASS';
END $negative$;
ROLLBACK TO SAVEPOINT ig_b_alr45_negative;
RELEASE SAVEPOINT ig_b_alr45_negative;
DO $post$
BEGIN
 IF (SELECT count(*) FROM ig_b_alr45_config)<>5
 OR EXISTS(SELECT 1 FROM ig_b_alr45_probe t JOIN ig_b_alr45_specs x ON x.code=t.code WHERE encode(extensions.digest(convert_to((t.payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM x.source_sha OR public.lf_asset_snapshot_sha_v1('REGLA',x.code) IS DISTINCT FROM x.source_sha)
 THEN RAISE EXCEPTION 'IG_B_ALR45_INDEPENDENT_READBACK_FAILED'; END IF;
 RAISE NOTICE 'IG_B_ALR45_FULL_TITLE_REAL_PG17_PROOF_COMPLETE; 2_RULES; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_SELECT_PASS; BACKEND_E2E_NOT_TESTED';
END $post$;
COMMIT;
