-- Familia B grupo ALR, PG17 contrato real reversible REG_ALR_002 y REG_ALR_003.
-- Dos RUN Product Director independientes con pantalla, STEP50/60, SHA origen/propuesta/candidato.
-- SOLO TEMP, ninguna actualización de lf_ops.reglas ni evidencia de Owner V2.
BEGIN;
CREATE TEMP TABLE ig_b_alr_specs(
 code text PRIMARY KEY,run text NOT NULL,screen text NOT NULL,
 source_sha text NOT NULL,proposal_sha text NOT NULL,candidate_sha text NOT NULL) ON COMMIT DROP;
INSERT INTO ig_b_alr_specs VALUES
('REG_ALR_002','EXEC-PROFILE-GATE2-FB1C9E73E8958751D06E5867','ONB_001','a2c84d4b00d18000b81911271ed6f40716a18ca58962e1f2289b63313994d250','91a337d9f591ea9fba5b67ca511dc2cca8467dc91e05e9da01b1eff44a65381f','c0188bafcfd6f251e57a07af3924110c3ccf89be276b8eb26902354e4cdad844'),
('REG_ALR_003','EXEC-PROFILE-GATE2-ACF582BDC22926C64B5E415A','ONB_002','2f303845e7ed4986b5bf9a44374386e870ab9d367cfda53d0258c5bbe3741d92','87318579c4c22ebcd7be365cba80347c7d261d2067eb49ddbc781245fa75c737','c87bb0afe1217a950eb3be2e6632dbdbb19546e2f9e06abdfaa7a11b0bd5ba6c');
CREATE TEMP TABLE ig_b_alr_cfg_req(
 code text NOT NULL,scope text NOT NULL,config_key text NOT NULL,
 expected_value text NOT NULL,value_type text NOT NULL) ON COMMIT DROP;
INSERT INTO ig_b_alr_cfg_req VALUES
('REG_ALR_002','ALERTAS','PASO1_ABANDON_RATE_MAX','0.8','DECIMAL'),
('REG_ALR_002','ALERTAS','PASO1_ABANDON_WINDOW_HOURS','1','INTEGER'),
('REG_ALR_003','ALERTAS','OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT','3','INTEGER');
CREATE TEMP TABLE ig_b_alr_probe AS SELECT r.codigo code,to_jsonb(r) payload FROM lf_ops.reglas r JOIN ig_b_alr_specs s ON s.code=r.codigo;
CREATE TEMP TABLE ig_b_alr_config AS SELECT g.* FROM public.lf_global_config g JOIN ig_b_alr_cfg_req m ON m.scope=g.scope AND m.config_key=g.config_key;
DO $pre$
DECLARE row_i record; patch_i jsonb; old_i jsonb;
BEGIN
 IF current_setting('server_version_num')::integer/10000<>17
 OR (SELECT count(*) FROM ig_b_alr_specs)<>2
 OR (SELECT count(*) FROM ig_b_alr_probe)<>2
 OR (SELECT count(*) FROM ig_b_alr_cfg_req)<>3
 OR (SELECT count(*) FROM ig_b_alr_config)<>3
 OR EXISTS(SELECT 1 FROM ig_b_alr_cfg_req m LEFT JOIN ig_b_alr_config g USING(scope,config_key)
           WHERE g.scope IS NULL OR g.value_status<>'REAL' OR g.value_type<>m.value_type OR g.config_value<>m.expected_value)
 THEN RAISE EXCEPTION 'IG_B_ALR002003_SOURCE_CONFIG_COUNT_DRIFT'; END IF;
 FOR row_i IN SELECT * FROM ig_b_alr_specs ORDER BY code LOOP
 SELECT p.payload-'created_at'-'updated_at' INTO old_i FROM ig_b_alr_probe p WHERE p.code=row_i.code;
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch_i
 FROM public.lf_operation_execution_steps WHERE execution_id=row_i.run AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF (SELECT count(*) FROM lf_ops.reglas WHERE codigo=row_i.code AND estado='VIGENTE')<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=row_i.code AND es_actual)<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA',row_i.code)<>row_i.source_sha
 OR encode(extensions.digest(convert_to(old_i::text,'UTF8'),'sha256'),'hex')<>row_i.source_sha
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo=row_i.code AND p.codigo=row_i.screen)
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=row_i.run AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'=row_i.screen AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps st WHERE st.execution_id=row_i.run AND st.step_id='output_validate' AND st.status='STEP_PASS_WITH_EVIDENCE' AND st.evidence_payload->>'output_contract_result'='PASS')
 OR patch_i->>'rule_code'<>row_i.code
 OR patch_i->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch_i::text,'UTF8'),'sha256'),'hex')<>row_i.proposal_sha
 OR (patch_i#>>'{changes,descripcion}') NOT LIKE '%public.lf_global_config%'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id=row_i.run AND rule_code=row_i.code)
 THEN RAISE EXCEPTION 'IG_B_ALR_SOURCE_PROFILE_SHA_OR_SCREEN_DRIFT:%',row_i.code; END IF;
 IF row_i.code='REG_ALR_002' AND (
     patch_i#>>'{changes,valor_config,umbral_maximo_config_ref,scope}'<>'ALERTAS'
  OR patch_i#>>'{changes,valor_config,umbral_maximo_config_ref,config_key}'<>'PASO1_ABANDON_RATE_MAX'
  OR patch_i#>>'{changes,valor_config,ventana_horas_config_ref,scope}'<>'ALERTAS'
  OR patch_i#>>'{changes,valor_config,ventana_horas_config_ref,config_key}'<>'PASO1_ABANDON_WINDOW_HOURS'
  OR (patch_i#>'{changes,valor_config}')?'umbral_maximo'
  OR (patch_i#>'{changes,valor_config}')?'ventana_horas'
  OR patch_i#>>'{changes,valor_config,metrica}'<>'paso1_abandono_rate'
  OR patch_i#>>'{changes,valor_config,canal_alerta}'<>'slack_producto'
 ) THEN RAISE EXCEPTION 'IG_B_ALR002_PATCH_SEMANTIC_DRIFT'; END IF;
 IF row_i.code='REG_ALR_003' AND (
    patch_i#>>'{changes,valor_config,condicion_max_config_ref,scope}'<>'ALERTAS'
 OR patch_i#>>'{changes,valor_config,condicion_max_config_ref,config_key}'<>'OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT'
 OR (patch_i#>'{changes,valor_config}')?'condicion'
 OR patch_i#>>'{changes,valor_config,condicion_tipo}'<>'fallos_consecutivos_webhook_otp'
 OR patch_i#>>'{changes,valor_config,severidad}'<>'critica'
 OR patch_i#>>'{changes,valor_config,accion_inmediata}'<>'activar_fallback_sms'
 OR patch_i#>'{changes,valor_config,canal_alerta}' IS DISTINCT FROM '["slack_tecnico","email_responsable"]'::jsonb
 ) THEN RAISE EXCEPTION 'IG_B_ALR003_PATCH_SEMANTIC_DRIFT'; END IF;
 END LOOP;
 RAISE NOTICE 'IG_B_ALR002003_PREIMAGE_CONFIG_NATIVE_SHA_PASS';
END $pre$;
SAVEPOINT ig_b_alr_positive;
UPDATE ig_b_alr_probe t SET payload=t.payload||jsonb_build_object(
 'descripcion',s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}',
 'valor_config',s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}')
 FROM ig_b_alr_specs x JOIN public.lf_operation_execution_steps s ON s.execution_id=x.run AND s.step_id='execute_profile' WHERE t.code=x.code;
DO $positive$
BEGIN
 IF EXISTS(SELECT 1 FROM ig_b_alr_specs s JOIN ig_b_alr_probe p ON p.code=s.code
 WHERE encode(extensions.digest(convert_to((p.payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')<>s.candidate_sha)
 THEN RAISE EXCEPTION 'IG_B_ALR002003_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'IG_B_ALR002003_CANDIDATE_SHA_POSITIVE_PASS';
END $positive$;
ROLLBACK TO SAVEPOINT ig_b_alr_positive;
RELEASE SAVEPOINT ig_b_alr_positive;
DO $rb1$
BEGIN
 IF EXISTS(SELECT 1 FROM ig_b_alr_specs s JOIN ig_b_alr_probe p ON p.code=s.code
 WHERE encode(extensions.digest(convert_to((p.payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')<>s.source_sha)
 THEN RAISE EXCEPTION 'IG_B_ALR002003_POSITIVE_ROLLBACK_FAIL'; END IF;
END $rb1$;
SAVEPOINT ig_b_alr_negative;
UPDATE ig_b_alr_probe SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb) WHERE code='REG_ALR_002';
DELETE FROM ig_b_alr_config WHERE scope='ALERTAS' AND config_key='OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT';
DO $negative$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_alr_probe WHERE code='REG_ALR_002')=
    (SELECT source_sha FROM ig_b_alr_specs WHERE code='REG_ALR_002')
 OR EXISTS(SELECT 1 FROM ig_b_alr_config WHERE config_key='OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT')
 THEN RAISE EXCEPTION 'IG_B_ALR002003_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_ALR002003_NEGATIVE_SOURCE_AND_CONFIG_DRIFT_DETECTED';
END $negative$;
ROLLBACK TO SAVEPOINT ig_b_alr_negative;
RELEASE SAVEPOINT ig_b_alr_negative;
DO $final$
BEGIN
 IF EXISTS(SELECT 1 FROM ig_b_alr_specs s JOIN ig_b_alr_probe p ON p.code=s.code
 WHERE encode(extensions.digest(convert_to((p.payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')<>s.source_sha
 OR public.lf_asset_snapshot_sha_v1('REGLA',s.code)<>s.source_sha)
 OR (SELECT count(*) FROM ig_b_alr_config)<>3
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 d JOIN ig_b_alr_specs x ON x.run=d.parent_execution_id AND x.code=d.rule_code)
 THEN RAISE EXCEPTION 'IG_B_ALR002003_INDEPENDENT_SELECT_FAILED'; END IF;
 RAISE NOTICE 'IG_B_ALR002003_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;
