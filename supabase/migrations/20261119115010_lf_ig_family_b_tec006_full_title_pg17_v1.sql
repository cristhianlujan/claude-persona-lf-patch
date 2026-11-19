-- Familia B REG_TEC_006: PG17 real contract-only, test full titulo/descripcion/valor_config.
-- Source immutable snapshot + native RUN Step50/60 hash + single central config REAL; rollback.
BEGIN;
CREATE TEMP TABLE ig_b_tec006_probe (code text PRIMARY KEY,payload jsonb NOT NULL) ON COMMIT DROP;
INSERT INTO ig_b_tec006_probe SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_TEC_006';
CREATE TEMP TABLE ig_b_tec006_cfg AS SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='UX' AND config_key='SKELETON_SHOW_AFTER_MS';
DO $pre$
DECLARE v_patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-4D03709FFC87BCA208DE907B' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_tec006_probe)<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_TEC_006' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_TEC_006' AND r.estado='VIGENTE' AND p.codigo='PASO3_MULTI_OFERTA')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-4D03709FFC87BCA208DE907B' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='PASO3_MULTI_OFERTA' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-4D03709FFC87BCA208DE907B' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_tec006_probe)<>'6eb5b8ce6cd5f618f8106a987919172a643ea70cc87fb1801528ee154471c53f'
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_TEC_006')<>'6eb5b8ce6cd5f618f8106a987919172a643ea70cc87fb1801528ee154471c53f'
 OR (SELECT count(*) FROM ig_b_tec006_cfg WHERE scope='UX' AND config_key='SKELETON_SHOW_AFTER_MS' AND config_value='300' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR v_patch->>'rule_code'<>'REG_TEC_006' OR v_patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex')<>'218915573546e4128847d0e1a9ab2e0ea6739228d1a60d18ee9cc043c1b5e207'
 OR v_patch#>>'{changes,valor_config,umbral_ms_config_ref,scope}'<>'UX'
 OR v_patch#>>'{changes,valor_config,umbral_ms_config_ref,config_key}'<>'SKELETON_SHOW_AFTER_MS'
 OR (v_patch#>'{changes,valor_config}')?'umbral_ms'
 OR v_patch#>>'{changes,valor_config,tipo}'<>'skeleton_screen'
 OR v_patch#>'{changes,valor_config,aplica_a}' IS DISTINCT FROM '["carga_paso3","cruce_dni","carga_ofertas"]'::jsonb
 OR (v_patch#>>'{changes,titulo}') NOT LIKE '%public.lf_global_config%'
 OR (v_patch#>>'{changes,titulo}') NOT LIKE '%UX/SKELETON_SHOW_AFTER_MS%'
 OR (v_patch#>>'{changes,titulo}') ~ '[0-9]+[[:space:]]*ms'
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%skeleton screen contextual%'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-4D03709FFC87BCA208DE907B' AND rule_code='REG_TEC_006')
 THEN RAISE EXCEPTION 'IG_B_TEC006_TITLE_NATIVE_OR_SOURCE_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_TEC006_PREIMAGE_FULL_TITLE_RUN_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_tec006_positive;
UPDATE ig_b_tec006_probe t SET payload=t.payload||jsonb_build_object(
 'titulo',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,titulo}' FROM public.lf_operation_execution_steps s WHERE execution_id='EXEC-PROFILE-GATE2-4D03709FFC87BCA208DE907B' AND step_id='execute_profile'),
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE execution_id='EXEC-PROFILE-GATE2-4D03709FFC87BCA208DE907B' AND step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE execution_id='EXEC-PROFILE-GATE2-4D03709FFC87BCA208DE907B' AND step_id='execute_profile')
) WHERE code='REG_TEC_006';
DO $positive$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_tec006_probe)<>'80691c1fb7b780693eb9f568df6dcccf1879b7643eaa41dec2ef72fc774a65fa'
 THEN RAISE EXCEPTION 'IG_B_TEC006_CANDIDATE_SHA_MISMATCH'; END IF;
 RAISE NOTICE 'IG_B_TEC006_FULL_CANDIDATE_PASS';
END $positive$;
ROLLBACK TO SAVEPOINT ig_tec006_positive;
RELEASE SAVEPOINT ig_tec006_positive;
DO $rb$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_tec006_probe)<>'6eb5b8ce6cd5f618f8106a987919172a643ea70cc87fb1801528ee154471c53f'
 THEN RAISE EXCEPTION 'IG_B_TEC006_POSITIVE_ROLLBACK_FAILED'; END IF;
END $rb$;
SAVEPOINT ig_tec006_negative;
UPDATE ig_b_tec006_probe SET payload=jsonb_set(payload,'{titulo}','"SOURCE_DRIFT"'::jsonb) WHERE code='REG_TEC_006';
DELETE FROM ig_b_tec006_cfg WHERE config_key='SKELETON_SHOW_AFTER_MS';
DO $neg$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_tec006_probe)='6eb5b8ce6cd5f618f8106a987919172a643ea70cc87fb1801528ee154471c53f'
 OR EXISTS(SELECT 1 FROM ig_b_tec006_cfg WHERE config_key='SKELETON_SHOW_AFTER_MS')
 THEN RAISE EXCEPTION 'IG_B_TEC006_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_TEC006_NEGATIVE_SOURCE_AND_CONFIG_ABSENCE_DETECTED';
END $neg$;
ROLLBACK TO SAVEPOINT ig_tec006_negative;
RELEASE SAVEPOINT ig_tec006_negative;
DO $post$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_tec006_probe)<>'6eb5b8ce6cd5f618f8106a987919172a643ea70cc87fb1801528ee154471c53f'
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_TEC_006')<>'6eb5b8ce6cd5f618f8106a987919172a643ea70cc87fb1801528ee154471c53f'
 OR (SELECT count(*) FROM ig_b_tec006_cfg WHERE config_value='300' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-4D03709FFC87BCA208DE907B' AND rule_code='REG_TEC_006')
 THEN RAISE EXCEPTION 'IG_B_TEC006_INDEPENDENT_SELECT_FAILED'; END IF;
 RAISE NOTICE 'IG_B_TEC006_TITLE_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_SELECT_PASS; BACKEND_E2E_NOT_TESTED';
END $post$;
COMMIT;
