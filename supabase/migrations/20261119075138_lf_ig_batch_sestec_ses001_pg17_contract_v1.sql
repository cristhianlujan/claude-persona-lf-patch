-- SESSION family A: REG_SES_001 PG17 contract proof, reversible only.
-- REG_TEC_009 retained for same final group when own RUN is admitted. No authoritative writes.
BEGIN;
CREATE TEMP TABLE ig_ses001_probe(payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_ses001_cfg(scope text,config_key text,config_value text,value_type text,value_status text) ON COMMIT DROP;
INSERT INTO ig_ses001_probe SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_SES_001';
INSERT INTO ig_ses001_cfg SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='AUTH' AND config_key='ONBOARDING_UNVERIFIED_SESSION_EXPIRATION_MINUTES';
DO $pre_ses001$
DECLARE patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-2C4DAADFFE1D14C023FE06F0' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_ses001_probe)<>1
 OR (SELECT count(*) FROM ig_ses001_cfg WHERE config_value='30' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR public.lf_auth_config_integer_v1('ONBOARDING_UNVERIFIED_SESSION_EXPIRATION_MINUTES')<>30
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_SES_001')<>'e05151f6651886e76997db86b82674422d25fdd0ec72a22bcb98e50d73b836e5'
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_ses001_probe)<>'e05151f6651886e76997db86b82674422d25fdd0ec72a22bcb98e50d73b836e5'
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas s ON s.id=rp.pantalla_id WHERE r.codigo='REG_SES_001' AND r.estado='VIGENTE' AND s.codigo='ONB_001')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-2C4DAADFFE1D14C023FE06F0' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-2C4DAADFFE1D14C023FE06F0' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR (SELECT payload#>>'{valor_config,expiracion_minutos}' FROM ig_ses001_probe)<>'30'
 OR (SELECT payload#>>'{valor_config,estado_resultado}' FROM ig_ses001_probe)<>'ABANDONED'
 OR patch->>'rule_code'<>'REG_SES_001' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>'24ab21544f295eef49d281f5ce1adfb8ab9030f34976436855dfdb4833542846'
 OR patch#>>'{changes,valor_config,expiracion_minutos_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,expiracion_minutos_config,config_key}'<>'ONBOARDING_UNVERIFIED_SESSION_EXPIRATION_MINUTES'
 OR patch#>>'{changes,valor_config,estado_resultado}'<>'ABANDONED'
 OR (patch#>'{changes,valor_config}')?'expiracion_minutos'
 OR position('desde su creación' in patch#>>'{changes,descripcion}')=0
 OR position('no puede retomarse' in patch#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'SES001_PG17_PREIMAGE_PROFILE_CONFIG_OR_SEMANTIC_DRIFT'; END IF;
 RAISE NOTICE 'SES001_PG17_SOURCE_PROFILE_CONFIG_PASS';
END $pre_ses001$;
SAVEPOINT ig_ses001_positive;
UPDATE ig_ses001_probe SET payload=payload||jsonb_build_object(
 'descripcion',(SELECT evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-2C4DAADFFE1D14C023FE06F0' AND step_id='execute_profile'),
 'valor_config',(SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-2C4DAADFFE1D14C023FE06F0' AND step_id='execute_profile'));
DO $pos_ses001$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_ses001_probe)<>'2ee7af7af41d18547b74644649a020d8e31657c862e85242af0829b423ec32f8' THEN RAISE EXCEPTION 'SES001_PG17_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'SES001_PG17_CANDIDATE_PASS';
END $pos_ses001$;
ROLLBACK TO SAVEPOINT ig_ses001_positive;
RELEASE SAVEPOINT ig_ses001_positive;
DO $rb_ses001$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_ses001_probe)<>'e05151f6651886e76997db86b82674422d25fdd0ec72a22bcb98e50d73b836e5' THEN RAISE EXCEPTION 'SES001_POSITIVE_ROLLBACK_FAIL'; END IF;
 RAISE NOTICE 'SES001_POSITIVE_ROLLBACK_READBACK_PASS';
END $rb_ses001$;
SAVEPOINT ig_ses001_negative;
UPDATE ig_ses001_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb);
DELETE FROM ig_ses001_cfg;
DO $negative_ses001$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_ses001_probe)='e05151f6651886e76997db86b82674422d25fdd0ec72a22bcb98e50d73b836e5'
 OR EXISTS(SELECT 1 FROM ig_ses001_cfg) THEN RAISE EXCEPTION 'SES001_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'SES001_NEGATIVE_DRIFT_DETECTED';
END $negative_ses001$;
ROLLBACK TO SAVEPOINT ig_ses001_negative;
RELEASE SAVEPOINT ig_ses001_negative;
DO $final_ses001$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_ses001_probe)<>'e05151f6651886e76997db86b82674422d25fdd0ec72a22bcb98e50d73b836e5'
 OR (SELECT count(*) FROM ig_ses001_cfg WHERE config_value='30')<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_SES_001')<>'e05151f6651886e76997db86b82674422d25fdd0ec72a22bcb98e50d73b836e5'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-2C4DAADFFE1D14C023FE06F0' AND rule_code='REG_SES_001')
 THEN RAISE EXCEPTION 'SES001_INDEPENDENT_SELECT_FAILED'; END IF;
 RAISE NOTICE 'SES001_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final_ses001$;
COMMIT;
