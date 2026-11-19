-- REG_RATE_001 real PostgreSQL 17 rule-contract test, no authoritative writes.
BEGIN;
CREATE TEMP TABLE ig_r001_probe(payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_r001_cfg(scope text,config_key text,config_value text,value_type text,value_status text) ON COMMIT DROP;
INSERT INTO ig_r001_probe SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_RATE_001';
INSERT INTO ig_r001_cfg SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config
 WHERE scope='AUTH' AND config_key IN ('REGISTRATION_PER_IP_MAX_ATTEMPTS','REGISTRATION_PER_IP_WINDOW_MINUTES');
DO $pre$
DECLARE p constant text:='EXEC-PROFILE-GATE2-1B7F46E3AA4D5366D67DF298'; rule_sha constant text:='3d6d874f105141b73dfe506f3892ab43b6890d557d04ac8b84e1c5479c29afc0'; proposal_sha constant text:='d31e89eae36d52317eb6bef389218b019c4d82eb9cfcbbadf3d37e5af94ef3a4'; patch jsonb; before_config jsonb;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_r001_probe)<>1 OR (SELECT count(*) FROM ig_r001_cfg)<>2
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RATE_001')<>rule_sha
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_r001_probe)<>rule_sha
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=p AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.status='IN_PROGRESS' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest->>'no_write'='true'
   AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
   JOIN lf_ops.pantallas sc ON sc.id=rp.pantalla_id WHERE r.codigo='REG_RATE_001' AND r.estado='VIGENTE' AND sc.codigo='ONB_001')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id=p AND s.step_id='output_validate'
   AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 THEN RAISE EXCEPTION 'R001_PG17_SOURCE_RUN_DRIFT'; END IF;
 SELECT payload->'valor_config' INTO before_config FROM ig_r001_probe;
 IF before_config->>'max_envios'<>'5' OR before_config->>'ventana_minutos'<>'10'
  OR before_config->>'accion'<>'bloquear_ip_temporalmente'
 THEN RAISE EXCEPTION 'R001_PG17_BEHAVIOR_DRIFT'; END IF;
 IF (SELECT count(*) FROM ig_r001_cfg WHERE scope='AUTH' AND value_type='INTEGER' AND value_status='REAL'
  AND ((config_key='REGISTRATION_PER_IP_MAX_ATTEMPTS' AND config_value='5')
   OR (config_key='REGISTRATION_PER_IP_WINDOW_MINUTES' AND config_value='10')))<>2
 OR public.lf_auth_config_integer_v1('REGISTRATION_PER_IP_MAX_ATTEMPTS')<>5
 OR public.lf_auth_config_integer_v1('REGISTRATION_PER_IP_WINDOW_MINUTES')<>10
 THEN RAISE EXCEPTION 'R001_PG17_GLOBAL_CONFIG_DRIFT'; END IF;
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch
 FROM public.lf_operation_execution_steps WHERE execution_id=p AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF patch->>'rule_code'<>'REG_RATE_001' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>proposal_sha
 OR patch#>>'{changes,valor_config,accion}'<>'bloquear_ip_temporalmente'
 OR patch#>>'{changes,valor_config,max_envios_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,max_envios_config,config_key}'<>'REGISTRATION_PER_IP_MAX_ATTEMPTS'
 OR patch#>>'{changes,valor_config,ventana_minutos_config,scope}'<>'AUTH'
 OR patch#>>'{changes,valor_config,ventana_minutos_config,config_key}'<>'REGISTRATION_PER_IP_WINDOW_MINUTES'
 OR (patch#>'{changes,valor_config}')?'max_envios'
 OR (patch#>'{changes,valor_config}')?'ventana_minutos'
 OR position('misma IP' in patch#>>'{changes,descripcion}')=0
 OR position('Al superar ese máximo' in patch#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'R001_PG17_PATCH_SCOPE_SEMANTICS_INVALID'; END IF;
 RAISE NOTICE 'R001_PG17_SOURCE_PROFILE_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_r001_positive;
UPDATE ig_r001_probe t SET payload=t.payload||jsonb_build_object(
 'descripcion',(SELECT evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}'
  FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-1B7F46E3AA4D5366D67DF298' AND step_id='execute_profile'),
 'valor_config',(SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}'
  FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-1B7F46E3AA4D5366D67DF298' AND step_id='execute_profile'));
DO $pos$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_r001_probe)<>'27cf19fc6821140918494e0dc46c8f16d806b49e76e8bff7632f6a922e9d3d96'
 THEN RAISE EXCEPTION 'R001_PG17_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'R001_PG17_POSITIVE_CANDIDATE_PASS';
END $pos$;
ROLLBACK TO SAVEPOINT ig_r001_positive;
RELEASE SAVEPOINT ig_r001_positive;
DO $pos_rb$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_r001_probe)<>'3d6d874f105141b73dfe506f3892ab43b6890d557d04ac8b84e1c5479c29afc0'
 THEN RAISE EXCEPTION 'R001_POSITIVE_ROLLBACK_FAIL'; END IF;
 RAISE NOTICE 'R001_POSITIVE_ROLLBACK_PASS';
END $pos_rb$;
SAVEPOINT ig_r001_negative;
UPDATE ig_r001_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb);
DELETE FROM ig_r001_cfg WHERE config_key='REGISTRATION_PER_IP_WINDOW_MINUTES';
DO $neg$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_r001_probe)='3d6d874f105141b73dfe506f3892ab43b6890d557d04ac8b84e1c5479c29afc0'
 OR EXISTS(SELECT 1 FROM ig_r001_cfg WHERE config_key='REGISTRATION_PER_IP_WINDOW_MINUTES')
 THEN RAISE EXCEPTION 'R001_PG17_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'R001_PG17_NEGATIVE_SOURCE_CONFIG_DRIFT_PASS';
END $neg$;
ROLLBACK TO SAVEPOINT ig_r001_negative;
RELEASE SAVEPOINT ig_r001_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_r001_probe)<>'3d6d874f105141b73dfe506f3892ab43b6890d557d04ac8b84e1c5479c29afc0'
 OR (SELECT count(*) FROM ig_r001_cfg)<>2
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_RATE_001')<>'3d6d874f105141b73dfe506f3892ab43b6890d557d04ac8b84e1c5479c29afc0'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-1B7F46E3AA4D5366D67DF298' AND rule_code='REG_RATE_001')
 THEN RAISE EXCEPTION 'R001_PG17_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'R001_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;