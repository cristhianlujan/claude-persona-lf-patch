-- REG_ATQ_020 PG17 reversible contract proof; no authoritative writes.
-- Preserve strict geo > max and elapsed time < window from existing descripcion.
BEGIN;
CREATE TEMP TABLE ig_a020_rule(payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_a020_cfg(scope text,config_key text,config_value text,value_type text,value_status text) ON COMMIT DROP;
INSERT INTO ig_a020_rule SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_ATQ_020';
INSERT INTO ig_a020_cfg SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='AUTH' AND config_key IN ('JWT_DISTINCT_GEO_LIMIT','JWT_GEO_WINDOW_MINUTES');
DO $pre$
DECLARE p constant text:='EXEC-PROFILE-GATE2-F11127D166FAA6CFF00D9C70'; rule_sha constant text:='1ff8c4a3780c816d64e7289860e920d7b3ee5f87b2abda7104a29a5c76725a75'; proposal_sha constant text:='8446fc017ac92efa1038164822c115bf1088682fbeae5e0d5d176e351f8bf708'; patch jsonb; v_src jsonb;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_a020_rule)<>1 OR (SELECT count(*) FROM ig_a020_cfg)<>2
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ATQ_020')<>rule_sha
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a020_rule)<>rule_sha
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=p AND e.status='IN_PROGRESS'
   AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.manifest->>'no_write'='true' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='HOME_002')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
   JOIN lf_ops.pantallas sc ON sc.id=rp.pantalla_id WHERE r.codigo='REG_ATQ_020' AND r.estado='VIGENTE' AND sc.codigo='HOME_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id=p AND s.step_id='output_validate'
   AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 THEN RAISE EXCEPTION 'A020_PG17_SOURCE_RUN_SCOPE_DRIFT'; END IF;
 SELECT payload INTO v_src FROM ig_a020_rule;
 IF v_src#>>'{valor_config,condicion}'<>'2_geos_distintas_en_10min'
  OR v_src#>>'{valor_config,accion}'<>'revocar_y_forzar_reautenticacion'
  OR v_src#>>'{valor_config,notificar_usuario}'<>'true'
  OR position('más de 2 ubicaciones' in v_src->>'descripcion')=0
  OR position('menos de 10 minutos' in v_src->>'descripcion')=0
 THEN RAISE EXCEPTION 'A020_PG17_SOURCE_COMPARATORS_DRIFT'; END IF;
 IF (SELECT count(*) FROM ig_a020_cfg WHERE scope='AUTH' AND value_type='INTEGER' AND value_status='REAL'
  AND ((config_key='JWT_DISTINCT_GEO_LIMIT' AND config_value='2')
    OR (config_key='JWT_GEO_WINDOW_MINUTES' AND config_value='10')))<>2
 OR public.lf_auth_config_integer_v1('JWT_DISTINCT_GEO_LIMIT')<>2
 OR public.lf_auth_config_integer_v1('JWT_GEO_WINDOW_MINUTES')<>10
 THEN RAISE EXCEPTION 'A020_PG17_CONFIG_DRIFT'; END IF;
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch
 FROM public.lf_operation_execution_steps WHERE execution_id=p AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF patch->>'rule_code'<>'REG_ATQ_020' OR patch->>'change_kind'<>'FUNCTIONAL'
  OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>proposal_sha
  OR patch#>>'{changes,valor_config,accion}'<>'revocar_y_forzar_reautenticacion'
  OR patch#>>'{changes,valor_config,notificar_usuario}'<>'true'
  OR patch#>>'{changes,valor_config,comparador_geos}'<>'SUPERA_MAXIMO'
  OR patch#>>'{changes,valor_config,comparador_ventana}'<>'MENOR_QUE_VENTANA'
  OR patch#>>'{changes,valor_config,jwt_distinct_geo_limit_config,scope}'<>'AUTH'
  OR patch#>>'{changes,valor_config,jwt_distinct_geo_limit_config,config_key}'<>'JWT_DISTINCT_GEO_LIMIT'
  OR patch#>>'{changes,valor_config,jwt_geo_window_config,scope}'<>'AUTH'
  OR patch#>>'{changes,valor_config,jwt_geo_window_config,config_key}'<>'JWT_GEO_WINDOW_MINUTES'
  OR (patch#>'{changes,valor_config}')?'condicion'
  OR position('más ubicaciones geográficas distintas que el límite' in patch#>>'{changes,descripcion}')=0
  OR position('estrictamente menor' in patch#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'A020_PG17_PATCH_SEMANTICS_DRIFT'; END IF;
 RAISE NOTICE 'A020_PG17_SOURCE_PROFILE_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_a020_positive;
UPDATE ig_a020_rule t SET payload=t.payload||jsonb_build_object(
 'descripcion',(SELECT evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}'
  FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-F11127D166FAA6CFF00D9C70' AND step_id='execute_profile'),
 'valor_config',(SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}'
  FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-F11127D166FAA6CFF00D9C70' AND step_id='execute_profile'));
DO $candidate$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a020_rule)
 <> '5c1cb188df8716dbc84041b293a03fb8c18b67b2883a8ee1e9e5ce3882e82e7f' THEN RAISE EXCEPTION 'A020_PG17_CANDIDATE_SHA_DRIFT'; END IF;
 RAISE NOTICE 'A020_PG17_CANDIDATE_PASS';
END $candidate$;
ROLLBACK TO SAVEPOINT ig_a020_positive;
RELEASE SAVEPOINT ig_a020_positive;
DO $pos_back$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a020_rule)
 <> '1ff8c4a3780c816d64e7289860e920d7b3ee5f87b2abda7104a29a5c76725a75' THEN RAISE EXCEPTION 'A020_PG17_POSITIVE_ROLLBACK_FAIL'; END IF;
 RAISE NOTICE 'A020_PG17_POSITIVE_ROLLBACK_PASS';
END $pos_back$;
SAVEPOINT ig_a020_negative;
UPDATE ig_a020_rule SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb);
DELETE FROM ig_a020_cfg WHERE config_key='JWT_DISTINCT_GEO_LIMIT';
DO $negative$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a020_rule)='1ff8c4a3780c816d64e7289860e920d7b3ee5f87b2abda7104a29a5c76725a75'
 OR EXISTS(SELECT 1 FROM ig_a020_cfg WHERE config_key='JWT_DISTINCT_GEO_LIMIT')
 THEN RAISE EXCEPTION 'A020_PG17_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'A020_PG17_NEGATIVE_SOURCE_DRIFT_AND_MISSING_CONFIG_DETECTED';
END $negative$;
ROLLBACK TO SAVEPOINT ig_a020_negative;
RELEASE SAVEPOINT ig_a020_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a020_rule)<>'1ff8c4a3780c816d64e7289860e920d7b3ee5f87b2abda7104a29a5c76725a75'
 OR (SELECT count(*) FROM ig_a020_cfg)<>2
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ATQ_020')<>'1ff8c4a3780c816d64e7289860e920d7b3ee5f87b2abda7104a29a5c76725a75'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-F11127D166FAA6CFF00D9C70' AND rule_code='REG_ATQ_020')
 THEN RAISE EXCEPTION 'A020_PG17_INDEPENDENT_READBACK_FAILED'; END IF;
 RAISE NOTICE 'A020_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;