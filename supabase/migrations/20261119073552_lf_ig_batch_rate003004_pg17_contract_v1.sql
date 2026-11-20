-- PG17 contract probes for RATE group: source-bound per-rule RUN / SHA / config and rollback.
-- Does not UPDATE lf_ops.reglas or public.lf_global_config. Backend E2E NOT_TESTED.
BEGIN;
CREATE TEMP TABLE ig_rate_probe(code text PRIMARY KEY,payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_rate_config(scope text,config_key text,config_value text,value_type text,value_status text) ON COMMIT DROP;
INSERT INTO ig_rate_probe SELECT r.codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE r.codigo IN ('REG_RATE_003','REG_RATE_004');
INSERT INTO ig_rate_config SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE (scope='RATE_LIMIT' AND config_key IN ('RATE_CLIENT_OTP_PHONE_CROSSSESSION.max_requests','RATE_CLIENT_OTP_PHONE_CROSSSESSION.window_seconds')) OR (scope='AUTH' AND config_key IN ('ONBOARDING_PER_DNI_MAX_ATTEMPTS','ONBOARDING_PER_DNI_WINDOW_HOURS'));

-- REG_RATE_003: own profile, two config refs, exact patch proposal, own savepoint pairs.
DO $pre_r003$
DECLARE patch jsonb;
BEGIN
SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-AF234BD624BE33FA3324FE79' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_rate_probe WHERE code='REG_RATE_003')<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas s ON s.id=rp.pantalla_id WHERE r.codigo='REG_RATE_003' AND r.estado='VIGENTE' AND s.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-AF234BD624BE33FA3324FE79' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-AF234BD624BE33FA3324FE79' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RATE_003')<>'73db7081ae8c1422642c6ac63ccc2e3e3093d6024dde0a80aae5199fda2aece6'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_rate_probe WHERE code='REG_RATE_003')<>'73db7081ae8c1422642c6ac63ccc2e3e3093d6024dde0a80aae5199fda2aece6'
  OR (SELECT count(*) FROM ig_rate_config WHERE scope='RATE_LIMIT' AND config_key='RATE_CLIENT_OTP_PHONE_CROSSSESSION.max_requests' AND config_value='5' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR (SELECT count(*) FROM ig_rate_config WHERE scope='RATE_LIMIT' AND config_key='RATE_CLIENT_OTP_PHONE_CROSSSESSION.window_seconds' AND config_value='3600' AND value_type='INTEGER' AND value_status='REAL')<>1
  OR (SELECT payload#>>'{valor_config,max_codigos}' FROM ig_rate_probe WHERE code='REG_RATE_003')<>'5'
 OR (SELECT payload#>>'{valor_config,ventana_minutos}' FROM ig_rate_probe WHERE code='REG_RATE_003')<>'60'
 
 OR NOT EXISTS (SELECT 1 FROM lf_ops.politicas_rate_limit pl WHERE pl.policy_code='RATE-CLIENT-OTP-PHONE-CROSSSESSION' AND pl.status='VIGENTE' AND pl.scope_key='PHONE_HASH' AND pl.max_requests IS NULL AND pl.window_seconds IS NULL AND pl.config_refs#>>'{max_requests,scope}'='RATE_LIMIT' AND pl.config_refs#>>'{max_requests,config_key}'='RATE_CLIENT_OTP_PHONE_CROSSSESSION.max_requests' AND pl.config_refs#>>'{window_seconds,scope}'='RATE_LIMIT' AND pl.config_refs#>>'{window_seconds,config_key}'='RATE_CLIENT_OTP_PHONE_CROSSSESSION.window_seconds')
 OR patch->>'rule_code'<>'REG_RATE_003'
 OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'2753e82ecb53c4a6c7e7ae575ff69c78ad5cd6fa8be7b54d4dda1ba28b7db5c3'
 
 OR patch#>>'{changes,valor_config,max_codigos_config_ref,scope}'<>'RATE_LIMIT'
 OR patch#>>'{changes,valor_config,max_codigos_config_ref,config_key}'<>'RATE_CLIENT_OTP_PHONE_CROSSSESSION.max_requests'
 OR (patch#>'{changes,valor_config}')?'max_codigos'
 OR patch#>>'{changes,valor_config,ventana_segundos_config_ref,scope}'<>'RATE_LIMIT'
 OR patch#>>'{changes,valor_config,ventana_segundos_config_ref,config_key}'<>'RATE_CLIENT_OTP_PHONE_CROSSSESSION.window_seconds'
 OR (patch#>'{changes,valor_config}')?'ventana_minutos'
THEN RAISE EXCEPTION 'R003_PG17_PREIMAGE_OR_PROFILE_DRIFT'; END IF;
RAISE NOTICE 'R003_PG17_SOURCE_CONFIG_PROFILE_PASS';
END $pre_r003$;
SAVEPOINT ig_r003_positive;
UPDATE ig_rate_probe t SET payload=t.payload||jsonb_build_object('descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-AF234BD624BE33FA3324FE79' AND s.step_id='execute_profile'),'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-AF234BD624BE33FA3324FE79' AND s.step_id='execute_profile')) WHERE code='REG_RATE_003';
DO $positive_r003$
BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_rate_probe WHERE code='REG_RATE_003')<>'eca92a37a2179172bbf5bb1391a2b25824c5516306f673d16d7ecddc9b1821ae' THEN RAISE EXCEPTION 'R003_PG17_CANDIDATE_SHA_FAIL'; END IF;
RAISE NOTICE 'R003_PG17_CANDIDATE_PASS';
END $positive_r003$;
ROLLBACK TO SAVEPOINT ig_r003_positive;
RELEASE SAVEPOINT ig_r003_positive;
DO $rollback_r003$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_rate_probe WHERE code='REG_RATE_003')<>'73db7081ae8c1422642c6ac63ccc2e3e3093d6024dde0a80aae5199fda2aece6' THEN RAISE EXCEPTION 'R003_POSITIVE_ROLLBACK_FAIL'; END IF;
END $rollback_r003$;
SAVEPOINT ig_r003_negative;
UPDATE ig_rate_probe t SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb) WHERE code='REG_RATE_003';
DELETE FROM ig_rate_config WHERE scope='RATE_LIMIT' AND config_key='RATE_CLIENT_OTP_PHONE_CROSSSESSION.max_requests';
DO $negative_r003$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_rate_probe WHERE code='REG_RATE_003')='73db7081ae8c1422642c6ac63ccc2e3e3093d6024dde0a80aae5199fda2aece6'
 OR EXISTS(SELECT 1 FROM ig_rate_config WHERE scope='RATE_LIMIT' AND config_key='RATE_CLIENT_OTP_PHONE_CROSSSESSION.max_requests') THEN RAISE EXCEPTION 'R003_NEGATIVE_NOT_DETECTED'; END IF;
RAISE NOTICE 'R003_NEGATIVE_DRIFT_DETECTED';
END $negative_r003$;
ROLLBACK TO SAVEPOINT ig_r003_negative;
RELEASE SAVEPOINT ig_r003_negative;
DO $final_r003$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_rate_probe WHERE code='REG_RATE_003')<>'73db7081ae8c1422642c6ac63ccc2e3e3093d6024dde0a80aae5199fda2aece6'
 OR NOT EXISTS(SELECT 1 FROM ig_rate_config WHERE scope='RATE_LIMIT' AND config_key='RATE_CLIENT_OTP_PHONE_CROSSSESSION.max_requests' AND config_value='5')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RATE_003')<>'73db7081ae8c1422642c6ac63ccc2e3e3093d6024dde0a80aae5199fda2aece6'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-AF234BD624BE33FA3324FE79' AND rule_code='REG_RATE_003')
THEN RAISE EXCEPTION 'R003_INDEPENDENT_SELECT_FAILED'; END IF;
RAISE NOTICE 'R003_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final_r003$;

-- REG_RATE_004: own profile, two config refs, exact patch proposal, own savepoint pairs.
DO $pre_r004$
DECLARE patch jsonb;
BEGIN
SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-A0F4E234FA4B53B3D8612ABB' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_rate_probe WHERE code='REG_RATE_004')<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas s ON s.id=rp.pantalla_id WHERE r.codigo='REG_RATE_004' AND r.estado='VIGENTE' AND s.codigo='ONB_003')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-A0F4E234FA4B53B3D8612ABB' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_003' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-A0F4E234FA4B53B3D8612ABB' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RATE_004')<>'1144312e88c85e7e3dacaad947f1b896954cb4596bcd6a2b7eb83c7396d07fa1'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_rate_probe WHERE code='REG_RATE_004')<>'1144312e88c85e7e3dacaad947f1b896954cb4596bcd6a2b7eb83c7396d07fa1'
  OR (SELECT count(*) FROM ig_rate_config WHERE scope='AUTH' AND config_key='ONBOARDING_PER_DNI_MAX_ATTEMPTS' AND config_value='3' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR (SELECT count(*) FROM ig_rate_config WHERE scope='AUTH' AND config_key='ONBOARDING_PER_DNI_WINDOW_HOURS' AND config_value='24' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('ONBOARDING_PER_DNI_MAX_ATTEMPTS')<>3
 OR public.lf_auth_config_integer_v1('ONBOARDING_PER_DNI_WINDOW_HOURS')<>24
  OR (SELECT payload#>>'{valor_config,max_intentos}' FROM ig_rate_probe WHERE code='REG_RATE_004')<>'3'
 OR (SELECT payload#>>'{valor_config,ventana_horas}' FROM ig_rate_probe WHERE code='REG_RATE_004')<>'24'
 
 OR patch->>'rule_code'<>'REG_RATE_004'
 OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'cda579b464cdaeb77be1777a03c52f3bba260ce138eed9f3f9dbda63a98b8dd9'
 
 OR patch#>>'{changes,valor_config,max_intentos_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,max_intentos_config,config_key}'<>'ONBOARDING_PER_DNI_MAX_ATTEMPTS'
 OR (patch#>'{changes,valor_config}')?'max_intentos'
 OR patch#>>'{changes,valor_config,ventana_horas_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,ventana_horas_config,config_key}'<>'ONBOARDING_PER_DNI_WINDOW_HOURS'
 OR (patch#>'{changes,valor_config}')?'ventana_horas'
THEN RAISE EXCEPTION 'R004_PG17_PREIMAGE_OR_PROFILE_DRIFT'; END IF;
RAISE NOTICE 'R004_PG17_SOURCE_CONFIG_PROFILE_PASS';
END $pre_r004$;
SAVEPOINT ig_r004_positive;
UPDATE ig_rate_probe t SET payload=t.payload||jsonb_build_object('descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-A0F4E234FA4B53B3D8612ABB' AND s.step_id='execute_profile'),'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-A0F4E234FA4B53B3D8612ABB' AND s.step_id='execute_profile')) WHERE code='REG_RATE_004';
DO $positive_r004$
BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_rate_probe WHERE code='REG_RATE_004')<>'b8383c7775c69e9ae75538268b900a40268f4f169ee9d944a5ac3c3afb9cec47' THEN RAISE EXCEPTION 'R004_PG17_CANDIDATE_SHA_FAIL'; END IF;
RAISE NOTICE 'R004_PG17_CANDIDATE_PASS';
END $positive_r004$;
ROLLBACK TO SAVEPOINT ig_r004_positive;
RELEASE SAVEPOINT ig_r004_positive;
DO $rollback_r004$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_rate_probe WHERE code='REG_RATE_004')<>'1144312e88c85e7e3dacaad947f1b896954cb4596bcd6a2b7eb83c7396d07fa1' THEN RAISE EXCEPTION 'R004_POSITIVE_ROLLBACK_FAIL'; END IF;
END $rollback_r004$;
SAVEPOINT ig_r004_negative;
UPDATE ig_rate_probe t SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb) WHERE code='REG_RATE_004';
DELETE FROM ig_rate_config WHERE scope='AUTH' AND config_key='ONBOARDING_PER_DNI_MAX_ATTEMPTS';
DO $negative_r004$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_rate_probe WHERE code='REG_RATE_004')='1144312e88c85e7e3dacaad947f1b896954cb4596bcd6a2b7eb83c7396d07fa1'
 OR EXISTS(SELECT 1 FROM ig_rate_config WHERE scope='AUTH' AND config_key='ONBOARDING_PER_DNI_MAX_ATTEMPTS') THEN RAISE EXCEPTION 'R004_NEGATIVE_NOT_DETECTED'; END IF;
RAISE NOTICE 'R004_NEGATIVE_DRIFT_DETECTED';
END $negative_r004$;
ROLLBACK TO SAVEPOINT ig_r004_negative;
RELEASE SAVEPOINT ig_r004_negative;
DO $final_r004$ BEGIN
IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_rate_probe WHERE code='REG_RATE_004')<>'1144312e88c85e7e3dacaad947f1b896954cb4596bcd6a2b7eb83c7396d07fa1'
 OR NOT EXISTS(SELECT 1 FROM ig_rate_config WHERE scope='AUTH' AND config_key='ONBOARDING_PER_DNI_MAX_ATTEMPTS' AND config_value='3')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RATE_004')<>'1144312e88c85e7e3dacaad947f1b896954cb4596bcd6a2b7eb83c7396d07fa1'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-A0F4E234FA4B53B3D8612ABB' AND rule_code='REG_RATE_004')
THEN RAISE EXCEPTION 'R004_INDEPENDENT_SELECT_FAILED'; END IF;
RAISE NOTICE 'R004_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final_r004$;
COMMIT;
