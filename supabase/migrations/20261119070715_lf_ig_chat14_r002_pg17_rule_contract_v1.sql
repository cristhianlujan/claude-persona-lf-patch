-- REG_RATE_002 real PostgreSQL 17 rule-contract test, no authoritative writes.
BEGIN;
CREATE TEMP TABLE ig_r002_probe(payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_r002_cfg(scope text,config_key text,config_value text,value_type text,value_status text) ON COMMIT DROP;
INSERT INTO ig_r002_probe SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_RATE_002';
INSERT INTO ig_r002_cfg SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config
 WHERE scope='AUTH' AND config_key IN ('OTP_VALIDATION_PER_IP_MAX_ATTEMPTS','OTP_VALIDATION_PER_IP_WINDOW_MINUTES');
DO $pre$
DECLARE p constant text:='EXEC-PROFILE-GATE2-96767B36C844EB28D3B6896D'; rule_sha constant text:='7b27a6a8dd3cf53668527fd136d872d4e66772a1682db4d9cb2be47b9a72d13d'; proposal_sha constant text:='0296745400a8a2ef3c1afa721c9964c74ca43f44967d68fa88522c79918eb684'; patch jsonb; before_config jsonb;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_r002_probe)<>1 OR (SELECT count(*) FROM ig_r002_cfg)<>2
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RATE_002')<>rule_sha
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_r002_probe)<>rule_sha
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=p AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.status='IN_PROGRESS' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest->>'no_write'='true'
   AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
   JOIN lf_ops.pantallas sc ON sc.id=rp.pantalla_id WHERE r.codigo='REG_RATE_002' AND r.estado='VIGENTE' AND sc.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id=p AND s.step_id='output_validate'
   AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 THEN RAISE EXCEPTION 'R002_PG17_SOURCE_RUN_DRIFT'; END IF;
 SELECT payload->'valor_config' INTO before_config FROM ig_r002_probe;
 IF before_config->>'max_intentos'<>'10' OR before_config->>'ventana_minutos'<>'10'
 THEN RAISE EXCEPTION 'R002_PG17_BEHAVIOR_DRIFT'; END IF;
 IF (SELECT count(*) FROM ig_r002_cfg WHERE scope='AUTH' AND value_type='INTEGER' AND value_status='REAL'
  AND ((config_key='OTP_VALIDATION_PER_IP_MAX_ATTEMPTS' AND config_value='10')
   OR (config_key='OTP_VALIDATION_PER_IP_WINDOW_MINUTES' AND config_value='10')))<>2
 OR public.lf_auth_config_integer_v1('OTP_VALIDATION_PER_IP_MAX_ATTEMPTS')<>10
 OR public.lf_auth_config_integer_v1('OTP_VALIDATION_PER_IP_WINDOW_MINUTES')<>10
 THEN RAISE EXCEPTION 'R002_PG17_GLOBAL_CONFIG_DRIFT'; END IF;
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch
 FROM public.lf_operation_execution_steps WHERE execution_id=p AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF patch->>'rule_code'<>'REG_RATE_002' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>proposal_sha
 OR patch#>>'{changes,valor_config,max_intentos_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,max_intentos_config,config_key}'<>'OTP_VALIDATION_PER_IP_MAX_ATTEMPTS'
 OR patch#>>'{changes,valor_config,ventana_minutos_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,ventana_minutos_config,config_key}'<>'OTP_VALIDATION_PER_IP_WINDOW_MINUTES'
 OR (patch#>'{changes,valor_config}')?'max_intentos'
 OR (patch#>'{changes,valor_config}')?'ventana_minutos'
 OR position('misma IP' in patch#>>'{changes,descripcion}')=0
 OR position('independientemente de la sesión' in patch#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'R002_PG17_PATCH_SCOPE_SEMANTICS_INVALID'; END IF;
 RAISE NOTICE 'R002_PG17_SOURCE_PROFILE_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_r002_positive;
UPDATE ig_r002_probe t SET payload=t.payload||jsonb_build_object(
 'descripcion',(SELECT evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}'
  FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-96767B36C844EB28D3B6896D' AND step_id='execute_profile'),
 'valor_config',(SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}'
  FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-96767B36C844EB28D3B6896D' AND step_id='execute_profile'));
DO $pos$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_r002_probe)<>'69c8f71364e725bbb8c14dbddf06d65ddec93a00aae49b25163692774565c5a0'
 THEN RAISE EXCEPTION 'R002_PG17_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'R002_PG17_POSITIVE_CANDIDATE_PASS';
END $pos$;
ROLLBACK TO SAVEPOINT ig_r002_positive;
RELEASE SAVEPOINT ig_r002_positive;
DO $pos_rb$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_r002_probe)<>'7b27a6a8dd3cf53668527fd136d872d4e66772a1682db4d9cb2be47b9a72d13d'
 THEN RAISE EXCEPTION 'R002_POSITIVE_ROLLBACK_FAIL'; END IF;
 RAISE NOTICE 'R002_POSITIVE_ROLLBACK_PASS';
END $pos_rb$;
SAVEPOINT ig_r002_negative;
UPDATE ig_r002_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb);
DELETE FROM ig_r002_cfg WHERE config_key='OTP_VALIDATION_PER_IP_WINDOW_MINUTES';
DO $neg$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_r002_probe)='7b27a6a8dd3cf53668527fd136d872d4e66772a1682db4d9cb2be47b9a72d13d'
 OR EXISTS(SELECT 1 FROM ig_r002_cfg WHERE config_key='OTP_VALIDATION_PER_IP_WINDOW_MINUTES')
 THEN RAISE EXCEPTION 'R002_PG17_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'R002_PG17_NEGATIVE_SOURCE_CONFIG_DRIFT_PASS';
END $neg$;
ROLLBACK TO SAVEPOINT ig_r002_negative;
RELEASE SAVEPOINT ig_r002_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_r002_probe)<>'7b27a6a8dd3cf53668527fd136d872d4e66772a1682db4d9cb2be47b9a72d13d'
 OR (SELECT count(*) FROM ig_r002_cfg)<>2
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RATE_002')<>'7b27a6a8dd3cf53668527fd136d872d4e66772a1682db4d9cb2be47b9a72d13d'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-96767B36C844EB28D3B6896D' AND rule_code='REG_RATE_002')
 THEN RAISE EXCEPTION 'R002_PG17_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'R002_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;