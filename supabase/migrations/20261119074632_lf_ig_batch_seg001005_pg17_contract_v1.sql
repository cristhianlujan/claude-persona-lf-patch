-- REG_SEG_001 and REG_SEG_005: independent real PG17 positive/negative SAVEPOINT probes.
-- Only TEMP tables are mutated. NOT an E2E implementation test. No authoritative writes.
BEGIN;
CREATE TEMP TABLE ig_seg_probe(code text PRIMARY KEY,payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_seg_cfg(scope text,config_key text,config_value text,value_type text,value_status text) ON COMMIT DROP;
INSERT INTO ig_seg_probe SELECT r.codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE r.codigo IN ('REG_SEG_001','REG_SEG_005');
INSERT INTO ig_seg_cfg SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='AUTH' AND config_key IN ('OTP_MAX_ATTEMPTS','OTP_EXHAUSTION_COOLDOWN_SECONDS','PHONE_UPDATE_MAX_PER_SESSION');

DO $pre_seg001$
DECLARE patch jsonb;
BEGIN
SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-C706A2286CCBC25C2E77DC35' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_seg_probe WHERE code='REG_SEG_001')<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas s ON s.id=rp.pantalla_id WHERE r.codigo='REG_SEG_001' AND r.estado='VIGENTE' AND s.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-C706A2286CCBC25C2E77DC35' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.status='IN_PROGRESS' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps e WHERE e.execution_id='EXEC-PROFILE-GATE2-C706A2286CCBC25C2E77DC35' AND e.step_id='output_validate' AND e.status='STEP_PASS_WITH_EVIDENCE' AND e.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_SEG_001')<>'5d58a022181c4d82d131822420431fb0f44d9b465ebd3e2d860c611642d0c988'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg_probe WHERE code='REG_SEG_001')<>'5d58a022181c4d82d131822420431fb0f44d9b465ebd3e2d860c611642d0c988'
 OR (SELECT payload#>>'{valor_config,otp_max_attempts}' FROM ig_seg_probe WHERE code='REG_SEG_001')<>'5'
 OR (SELECT payload#>>'{valor_config,bloqueo_minutos}' FROM ig_seg_probe WHERE code='REG_SEG_001')<>'2'
 OR (SELECT payload#>>'{valor_config,source_decision_number}' FROM ig_seg_probe WHERE code='REG_SEG_001')<>'87'
 OR (SELECT payload#>>'{valor_config,invalidar_otp_actual}' FROM ig_seg_probe WHERE code='REG_SEG_001')<>'true'
 OR (SELECT payload#>>'{valor_config,bloqueo_permanente_en_primer_ciclo}' FROM ig_seg_probe WHERE code='REG_SEG_001')<>'false'
 OR (SELECT count(*) FROM ig_seg_cfg WHERE scope='AUTH' AND config_key='OTP_MAX_ATTEMPTS' AND config_value='5' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('OTP_MAX_ATTEMPTS')<>5
 OR (SELECT count(*) FROM ig_seg_cfg WHERE scope='AUTH' AND config_key='OTP_EXHAUSTION_COOLDOWN_SECONDS' AND config_value='120' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('OTP_EXHAUSTION_COOLDOWN_SECONDS')<>120
 OR patch->>'rule_code'<>'REG_SEG_001' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'486bf26c582a68b35c9951d9af1e772d070c9ade05e494195a99f9eba8b85a99'
 OR patch#>>'{changes,valor_config,otp_max_attempts_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,otp_max_attempts_config,config_key}'<>'OTP_MAX_ATTEMPTS'
 OR patch#>>'{changes,valor_config,cooldown_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,cooldown_config,config_key}'<>'OTP_EXHAUSTION_COOLDOWN_SECONDS'
 OR (patch#>'{changes,valor_config}')?'otp_max_attempts'
 OR (patch#>'{changes,valor_config}')?'bloqueo_minutos'
 OR patch#>>'{changes,valor_config,cooldown_config,unit}'<>'SECONDS'
 OR patch#>>'{changes,valor_config,invalidar_otp_actual}'<>'true'
 OR patch#>>'{changes,valor_config,bloqueo_permanente_en_primer_ciclo}'<>'false'
 OR patch#>>'{changes,valor_config,source_decision_number}'<>'87'
 OR 2*60<>public.lf_auth_config_integer_v1('OTP_EXHAUSTION_COOLDOWN_SECONDS')
THEN RAISE EXCEPTION 'IG_SEG001_PG17_PREIMAGE_PROFILE_OR_POLICY_DRIFT'; END IF;
RAISE NOTICE 'SEG001_PG17_SOURCE_PROFILE_CONFIG_PASS';
END $pre_seg001$;
SAVEPOINT ig_seg001_positive;
UPDATE ig_seg_probe t SET payload=t.payload||jsonb_build_object('descripcion',(SELECT e.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps e WHERE e.execution_id='EXEC-PROFILE-GATE2-C706A2286CCBC25C2E77DC35' AND e.step_id='execute_profile'),'valor_config',(SELECT e.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps e WHERE e.execution_id='EXEC-PROFILE-GATE2-C706A2286CCBC25C2E77DC35' AND e.step_id='execute_profile')) WHERE t.code='REG_SEG_001';
DO $positive_seg001$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg_probe WHERE code='REG_SEG_001')<>'5edd255554d2fbf513f3731d96f004ad76a91b4529cf2cfa39e6562571f919ed' THEN RAISE EXCEPTION 'IG_SEG001_CANDIDATE_SHA_FAIL'; END IF;
RAISE NOTICE 'SEG001_CANDIDATE_PASS';
END $positive_seg001$;
ROLLBACK TO SAVEPOINT ig_seg001_positive;
RELEASE SAVEPOINT ig_seg001_positive;
DO $back_seg001$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg_probe WHERE code='REG_SEG_001')<>'5d58a022181c4d82d131822420431fb0f44d9b465ebd3e2d860c611642d0c988' THEN RAISE EXCEPTION 'IG_SEG001_POSITIVE_ROLLBACK_FAIL'; END IF;
END $back_seg001$;
SAVEPOINT ig_seg001_negative;
UPDATE ig_seg_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb) WHERE code='REG_SEG_001';
DELETE FROM ig_seg_cfg WHERE config_key='OTP_MAX_ATTEMPTS';
DO $neg_seg001$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg_probe WHERE code='REG_SEG_001')='5d58a022181c4d82d131822420431fb0f44d9b465ebd3e2d860c611642d0c988' OR EXISTS(SELECT 1 FROM ig_seg_cfg WHERE config_key='OTP_MAX_ATTEMPTS') THEN RAISE EXCEPTION 'IG_SEG001_NEGATIVE_NOT_DETECTED'; END IF;
RAISE NOTICE 'SEG001_NEGATIVE_DRIFT_DETECTED';
END $neg_seg001$;
ROLLBACK TO SAVEPOINT ig_seg001_negative;
RELEASE SAVEPOINT ig_seg001_negative;
DO $final_seg001$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg_probe WHERE code='REG_SEG_001')<>'5d58a022181c4d82d131822420431fb0f44d9b465ebd3e2d860c611642d0c988' OR NOT EXISTS(SELECT 1 FROM ig_seg_cfg WHERE scope='AUTH' AND config_key='OTP_MAX_ATTEMPTS' AND config_value='5') OR public.lf_asset_snapshot_sha_v1('REGLA','REG_SEG_001')<>'5d58a022181c4d82d131822420431fb0f44d9b465ebd3e2d860c611642d0c988' OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-C706A2286CCBC25C2E77DC35' AND rule_code='REG_SEG_001') THEN RAISE EXCEPTION 'IG_SEG001_INDEPENDENT_SELECT_FAIL'; END IF;
RAISE NOTICE 'SEG001_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_SELECT_PASS; BACKEND_E2E_NOT_TESTED';
END $final_seg001$;

DO $pre_seg005$
DECLARE patch jsonb;
BEGIN
SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-AC0832BB7C7B76EDAFB26747' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_seg_probe WHERE code='REG_SEG_005')<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas s ON s.id=rp.pantalla_id WHERE r.codigo='REG_SEG_005' AND r.estado='VIGENTE' AND s.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-AC0832BB7C7B76EDAFB26747' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.status='IN_PROGRESS' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps e WHERE e.execution_id='EXEC-PROFILE-GATE2-AC0832BB7C7B76EDAFB26747' AND e.step_id='output_validate' AND e.status='STEP_PASS_WITH_EVIDENCE' AND e.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_SEG_005')<>'e4f9dca010db525c44f334a818fb9ab51557fd9f05346d0b4e849163b8431b1b'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg_probe WHERE code='REG_SEG_005')<>'e4f9dca010db525c44f334a818fb9ab51557fd9f05346d0b4e849163b8431b1b'
 OR (SELECT payload#>>'{valor_config,max_cambios}' FROM ig_seg_probe WHERE code='REG_SEG_005')<>'3'
 OR (SELECT payload#>>'{valor_config,accion}' FROM ig_seg_probe WHERE code='REG_SEG_005')<>'bloquear_campo_y_sesion'
 OR (SELECT count(*) FROM ig_seg_cfg WHERE scope='AUTH' AND config_key='PHONE_UPDATE_MAX_PER_SESSION' AND config_value='3' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('PHONE_UPDATE_MAX_PER_SESSION')<>3
 OR patch->>'rule_code'<>'REG_SEG_005' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'ecb3ff3d555ec6fb320f4853c94fa005aa9c807f2c183aaa9643fcfe2222fbde'
 OR patch#>>'{changes,valor_config,max_cambios_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,max_cambios_config,config_key}'<>'PHONE_UPDATE_MAX_PER_SESSION'
 OR (patch#>'{changes,valor_config}')?'max_cambios'
 OR patch#>>'{changes,valor_config,accion}'<>'bloquear_campo_y_sesion'
 OR position('Al alcanzar el límite' in patch#>>'{changes,descripcion}')=0
THEN RAISE EXCEPTION 'IG_SEG005_PG17_PREIMAGE_PROFILE_OR_POLICY_DRIFT'; END IF;
RAISE NOTICE 'SEG005_PG17_SOURCE_PROFILE_CONFIG_PASS';
END $pre_seg005$;
SAVEPOINT ig_seg005_positive;
UPDATE ig_seg_probe t SET payload=t.payload||jsonb_build_object('descripcion',(SELECT e.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps e WHERE e.execution_id='EXEC-PROFILE-GATE2-AC0832BB7C7B76EDAFB26747' AND e.step_id='execute_profile'),'valor_config',(SELECT e.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps e WHERE e.execution_id='EXEC-PROFILE-GATE2-AC0832BB7C7B76EDAFB26747' AND e.step_id='execute_profile')) WHERE t.code='REG_SEG_005';
DO $positive_seg005$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg_probe WHERE code='REG_SEG_005')<>'22c248eeb7997e7d6dcd058bb0afd2e7e90c00a6475efca3342cbe676e6d5244' THEN RAISE EXCEPTION 'IG_SEG005_CANDIDATE_SHA_FAIL'; END IF;
RAISE NOTICE 'SEG005_CANDIDATE_PASS';
END $positive_seg005$;
ROLLBACK TO SAVEPOINT ig_seg005_positive;
RELEASE SAVEPOINT ig_seg005_positive;
DO $back_seg005$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg_probe WHERE code='REG_SEG_005')<>'e4f9dca010db525c44f334a818fb9ab51557fd9f05346d0b4e849163b8431b1b' THEN RAISE EXCEPTION 'IG_SEG005_POSITIVE_ROLLBACK_FAIL'; END IF;
END $back_seg005$;
SAVEPOINT ig_seg005_negative;
UPDATE ig_seg_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb) WHERE code='REG_SEG_005';
DELETE FROM ig_seg_cfg WHERE config_key='PHONE_UPDATE_MAX_PER_SESSION';
DO $neg_seg005$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg_probe WHERE code='REG_SEG_005')='e4f9dca010db525c44f334a818fb9ab51557fd9f05346d0b4e849163b8431b1b' OR EXISTS(SELECT 1 FROM ig_seg_cfg WHERE config_key='PHONE_UPDATE_MAX_PER_SESSION') THEN RAISE EXCEPTION 'IG_SEG005_NEGATIVE_NOT_DETECTED'; END IF;
RAISE NOTICE 'SEG005_NEGATIVE_DRIFT_DETECTED';
END $neg_seg005$;
ROLLBACK TO SAVEPOINT ig_seg005_negative;
RELEASE SAVEPOINT ig_seg005_negative;
DO $final_seg005$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_seg_probe WHERE code='REG_SEG_005')<>'e4f9dca010db525c44f334a818fb9ab51557fd9f05346d0b4e849163b8431b1b' OR NOT EXISTS(SELECT 1 FROM ig_seg_cfg WHERE scope='AUTH' AND config_key='PHONE_UPDATE_MAX_PER_SESSION' AND config_value='3') OR public.lf_asset_snapshot_sha_v1('REGLA','REG_SEG_005')<>'e4f9dca010db525c44f334a818fb9ab51557fd9f05346d0b4e849163b8431b1b' OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-AC0832BB7C7B76EDAFB26747' AND rule_code='REG_SEG_005') THEN RAISE EXCEPTION 'IG_SEG005_INDEPENDENT_SELECT_FAIL'; END IF;
RAISE NOTICE 'SEG005_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_SELECT_PASS; BACKEND_E2E_NOT_TESTED';
END $final_seg005$;
COMMIT;
