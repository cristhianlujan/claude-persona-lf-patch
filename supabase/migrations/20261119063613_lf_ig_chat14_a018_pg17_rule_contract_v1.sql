-- IG Familia A / REG_ATQ_018: real PG17 reversible contract proof.
-- Separate auth config controls from SESSION-CLIENT-DEFAULT.refresh_chain_max_days;
-- no authoritative mutations, no Owner V2, no backend E2E assertion.
BEGIN;
CREATE TEMP TABLE ig_a018_probe(payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_a018_config(scope text,config_key text,config_value text,value_type text,value_status text) ON COMMIT DROP;
CREATE TEMP TABLE ig_a018_policy(policy_code text,status text,cookie_policy jsonb,refresh_rotation_enabled boolean,
 idle_timeout_seconds integer,absolute_timeout_seconds integer,access_token_ttl_seconds integer) ON COMMIT DROP;
INSERT INTO ig_a018_probe SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_ATQ_018';
INSERT INTO ig_a018_config SELECT scope,config_key,config_value,value_type,value_status
 FROM public.lf_global_config WHERE scope='AUTH' AND config_key IN
 ('SESSION_ACCESS_TOKEN_TTL_SECONDS','SESSION_IDLE_TIMEOUT_SECONDS','SESSION_ABSOLUTE_TIMEOUT_SECONDS');
INSERT INTO ig_a018_policy SELECT policy_code,status,cookie_policy,refresh_rotation_enabled,
 idle_timeout_seconds,absolute_timeout_seconds,access_token_ttl_seconds
 FROM lf_ops.politicas_sesion WHERE policy_code='SESSION-CLIENT-DEFAULT';
DO $pre$
DECLARE p constant text:='EXEC-PROFILE-GATE2-1D8D2E809B7A0E83786E8BD0'; src constant text:='5fd95746c30e57bc9840a4bf4b42a958d8c8ae5cebf21d08ce55084462845549';
 prop constant text:='87a2a9b05a9016a84efb481d00c8c151ddd681a91107a3ab973b5dda1de81c69'; patch jsonb; old_cfg jsonb;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_a018_probe)<>1 OR (SELECT count(*) FROM ig_a018_config)<>3
 OR (SELECT count(*) FROM ig_a018_policy)<>1
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=p
   AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest->>'no_write'='true'
   AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='HOME_002')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
   JOIN lf_ops.pantallas s ON s.id=rp.pantalla_id
   WHERE r.codigo='REG_ATQ_018' AND r.estado='VIGENTE' AND s.codigo='HOME_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps e
   WHERE e.execution_id=p AND e.step_id='output_validate' AND e.status='STEP_PASS_WITH_EVIDENCE'
   AND e.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ATQ_018')<>src
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
   FROM ig_a018_probe)<>src
 THEN RAISE EXCEPTION 'A018_PG17_SOURCE_PARENT_DRIFT'; END IF;
 SELECT payload->'valor_config' INTO old_cfg FROM ig_a018_probe;
 IF old_cfg->>'access_token_ttl_seconds'<>'3600'
  OR old_cfg->>'idle_timeout_seconds'<>'86400'
  OR old_cfg->>'absolute_timeout_seconds'<>'2592000'
  OR old_cfg->>'refresh_token_max_days'<>'30'
  OR old_cfg->>'source_decision_number'<>'105'
  OR old_cfg->>'rotacion_refresh'<>'true'
  OR old_cfg->>'session_policy_code'<>'SESSION-CLIENT-DEFAULT'
 THEN RAISE EXCEPTION 'A018_PG17_SOURCE_CONTROL_DRIFT'; END IF;
 IF (SELECT count(*) FROM ig_a018_config WHERE scope='AUTH' AND value_type='INTEGER' AND value_status='REAL'
  AND ((config_key='SESSION_ACCESS_TOKEN_TTL_SECONDS' AND config_value='3600')
   OR (config_key='SESSION_IDLE_TIMEOUT_SECONDS' AND config_value='86400')
   OR (config_key='SESSION_ABSOLUTE_TIMEOUT_SECONDS' AND config_value='2592000')))<>3
 OR public.lf_auth_config_integer_v1('SESSION_ACCESS_TOKEN_TTL_SECONDS')<>3600
 OR public.lf_auth_config_integer_v1('SESSION_IDLE_TIMEOUT_SECONDS')<>86400
 OR public.lf_auth_config_integer_v1('SESSION_ABSOLUTE_TIMEOUT_SECONDS')<>2592000
 OR NOT EXISTS(SELECT 1 FROM ig_a018_policy WHERE policy_code='SESSION-CLIENT-DEFAULT' AND status='VIGENTE'
   AND cookie_policy->>'refresh_chain_max_days'='30' AND refresh_rotation_enabled
   AND access_token_ttl_seconds=3600 AND idle_timeout_seconds=86400 AND absolute_timeout_seconds=2592000)
 THEN RAISE EXCEPTION 'A018_PG17_SOURCE_CONFIG_OR_POLICY_DRIFT'; END IF;
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch
 FROM public.lf_operation_execution_steps WHERE execution_id=p AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF patch->>'rule_code'<>'REG_ATQ_018' OR patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>prop
 OR patch#>>'{changes,valor_config,access_token_ttl_config,config_key}'<>'SESSION_ACCESS_TOKEN_TTL_SECONDS'
 OR patch#>>'{changes,valor_config,idle_timeout_config,config_key}'<>'SESSION_IDLE_TIMEOUT_SECONDS'
 OR patch#>>'{changes,valor_config,absolute_timeout_config,config_key}'<>'SESSION_ABSOLUTE_TIMEOUT_SECONDS'
 OR patch#>>'{changes,valor_config,refresh_token_max_policy_ref,policy_code}'<>'SESSION-CLIENT-DEFAULT'
 OR patch#>>'{changes,valor_config,refresh_token_max_policy_ref,policy_path}'<>'cookie_policy.refresh_chain_max_days'
 OR patch#>>'{changes,valor_config,source_decision_number}'<>'105'
 OR patch#>>'{changes,valor_config,rotacion_refresh}'<>'true'
 OR (patch#>'{changes,valor_config}')?'refresh_token_max_days'
 OR (patch#>'{changes,valor_config}')?'absolute_timeout_seconds'
 OR (patch#>'{changes,valor_config}')?'idle_timeout_seconds'
 OR (patch#>'{changes,valor_config}')?'access_token_ttl_seconds'
 OR position('reautenticación' in patch#>>'{changes,descripcion}')=0
 OR position('Supabase Auth' in patch#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'A018_PG17_PATCH_SEMANTICS_DRIFT'; END IF;
 RAISE NOTICE 'A018_PG17_SOURCE_CONFIG_POLICY_PROFILE_PASS';
END $pre$;
SAVEPOINT ig_a018_positive;
UPDATE ig_a018_probe t SET payload=t.payload||jsonb_build_object(
 'descripcion',(SELECT evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}'
  FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-1D8D2E809B7A0E83786E8BD0' AND step_id='execute_profile'),
 'valor_config',(SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}'
  FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-1D8D2E809B7A0E83786E8BD0' AND step_id='execute_profile'));
DO $positive$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a018_probe)
 <> 'f94157d45ffa25aab6c951b06fcc2a54291a7935009ff738e8f87913dd46bd05' THEN RAISE EXCEPTION 'A018_PG17_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'A018_PG17_POSITIVE_CANDIDATE_PASS';
END $positive$;
ROLLBACK TO SAVEPOINT ig_a018_positive;
RELEASE SAVEPOINT ig_a018_positive;
DO $rb$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a018_probe)
 <> '5fd95746c30e57bc9840a4bf4b42a958d8c8ae5cebf21d08ce55084462845549' THEN RAISE EXCEPTION 'A018_PG17_ROLLBACK_FAIL'; END IF;
 RAISE NOTICE 'A018_PG17_POSITIVE_ROLLBACK_READBACK_PASS';
END $rb$;
SAVEPOINT ig_a018_negative;
UPDATE ig_a018_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb);
DELETE FROM ig_a018_config WHERE config_key='SESSION_IDLE_TIMEOUT_SECONDS';
DELETE FROM ig_a018_policy;
DO $negative$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a018_probe)
 = '5fd95746c30e57bc9840a4bf4b42a958d8c8ae5cebf21d08ce55084462845549'
 OR EXISTS(SELECT 1 FROM ig_a018_config WHERE config_key='SESSION_IDLE_TIMEOUT_SECONDS')
 OR EXISTS(SELECT 1 FROM ig_a018_policy)
 THEN RAISE EXCEPTION 'A018_PG17_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'A018_PG17_NEGATIVE_SOURCE_CONFIG_POLICY_DRIFT_DETECTED';
END $negative$;
ROLLBACK TO SAVEPOINT ig_a018_negative;
RELEASE SAVEPOINT ig_a018_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a018_probe)
 <> '5fd95746c30e57bc9840a4bf4b42a958d8c8ae5cebf21d08ce55084462845549'
 OR (SELECT count(*) FROM ig_a018_config)<>3
 OR (SELECT count(*) FROM ig_a018_policy)<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ATQ_018')<>'5fd95746c30e57bc9840a4bf4b42a958d8c8ae5cebf21d08ce55084462845549'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-1D8D2E809B7A0E83786E8BD0' AND rule_code='REG_ATQ_018')
 THEN RAISE EXCEPTION 'A018_PG17_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'A018_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;