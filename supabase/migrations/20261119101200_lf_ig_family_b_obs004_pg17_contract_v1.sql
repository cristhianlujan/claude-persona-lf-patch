-- IG Familia B / REG_OBS_004. PG17 source-bound reversible, sin escrituras en reglas.
BEGIN;
CREATE TEMP TABLE ig_b_test_rule (payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_b_test_cfg (config_key text PRIMARY KEY,expected_value text NOT NULL,value_type text NOT NULL) ON COMMIT DROP;
INSERT INTO ig_b_test_rule SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE r.codigo='REG_OBS_004';
INSERT INTO ig_b_test_cfg VALUES
('CORE_WEB_VITALS_ALERT_SESSIONS_PERCENT','10','INTEGER');
DO $pre$
DECLARE v_patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D'
 AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_test_rule)<>1
 OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo='REG_OBS_004' AND estado='VIGENTE')<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_OBS_004' AND es_actual)<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_OBS_004')<>'7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_test_rule)<>'7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660'
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_OBS_004' AND p.codigo='ONB_001')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D' AND e.status='IN_PROGRESS'
 AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
 AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001'
 AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps e WHERE e.execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D'
 AND e.step_id='output_validate' AND e.status='STEP_PASS_WITH_EVIDENCE' AND e.evidence_payload->>'output_contract_result'='PASS')
 OR (SELECT count(*) FROM ig_b_test_cfg)<>1
 OR EXISTS(SELECT 1 FROM ig_b_test_cfg t LEFT JOIN public.lf_global_config g ON g.scope='OBSERVABILIDAD' AND g.config_key=t.config_key
 WHERE g.scope IS NULL OR g.config_value<>t.expected_value OR g.value_type<>t.value_type OR g.value_status<>'REAL')
 OR v_patch->>'rule_code' IS DISTINCT FROM 'REG_OBS_004'
 OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex')<>'d7455e46f17701b8acd6eb937c1fcab15d62aa44ab8cfa8e5d06f8d3c04cd0af'
 OR v_patch#>>'{changes,descripcion}' NOT LIKE '%public.lf_global_config%'
  OR v_patch#>>'{changes,valor_config,alerta_porcentaje_sesiones_config_ref,scope}' IS DISTINCT FROM 'OBSERVABILIDAD'
 OR v_patch#>>'{changes,valor_config,alerta_porcentaje_sesiones_config_ref,config_key}' IS DISTINCT FROM 'CORE_WEB_VITALS_ALERT_SESSIONS_PERCENT'
  OR (v_patch#>'{changes,valor_config}')?'alerta_porcentaje_sesiones'
 OR (v_patch#>>'{changes,valor_config,cls}')::numeric<>0.1
 OR (v_patch#>>'{changes,valor_config,fid_ms}')::integer<>100
 OR (v_patch#>>'{changes,valor_config,lcp_ms}')::integer<>2500
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%LCP < 2.5s%'
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%CLS < 0.1%'
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%FID < 100ms%'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D' AND rule_code='REG_OBS_004')
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_004_PREIMAGE_RUN_CONFIG_OR_PATCH_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_004_PG17_SOURCE_NATIVE_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_b_positive;
UPDATE ig_b_test_rule SET payload=payload||jsonb_build_object(
 'descripcion',(SELECT evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D' AND step_id='execute_profile'),
 'valor_config',(SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D' AND step_id='execute_profile'));
DO $pos$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_test_rule)<>'36d040466e485e57abcc68175ea7a553f8d8d24a741f7c627daaadf6d3306e44'
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_004_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_004_POSITIVE_PASS';
END $pos$;
ROLLBACK TO SAVEPOINT ig_b_positive;
RELEASE SAVEPOINT ig_b_positive;
DO $rb1$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_test_rule)<>'7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660'
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_004_ROLLBACK_POSITIVE_FAILED'; END IF;
END $rb1$;
SAVEPOINT ig_b_negative;
UPDATE ig_b_test_rule SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb);
DELETE FROM ig_b_test_cfg WHERE config_key='CORE_WEB_VITALS_ALERT_SESSIONS_PERCENT';
DO $neg$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_test_rule)='7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660'
 OR (SELECT count(*) FROM ig_b_test_cfg)<>0
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_004_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_004_NEGATIVE_SOURCE_AND_CONFIG_DRIFT_DETECTED';
END $neg$;
ROLLBACK TO SAVEPOINT ig_b_negative;
RELEASE SAVEPOINT ig_b_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_test_rule)<>'7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660'
 OR (SELECT count(*) FROM ig_b_test_cfg)<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_OBS_004')<>'7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D' AND rule_code='REG_OBS_004')
 THEN RAISE EXCEPTION 'IG_B_REG_OBS_004_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'IG_B_REG_OBS_004_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;
