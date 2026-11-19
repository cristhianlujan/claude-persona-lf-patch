-- IG Familia A REG_ATQ_010: source-bound proof with actual PostgreSQL 17.
-- TEMP only. BEGIN / SAVEPOINT / ROLLBACK to SAVEPOINT / readback SELECT.
-- Never mutates lf_ops.reglas, official owner, Train evidence, or global_config.
BEGIN;
CREATE TEMP TABLE ig_atq010_rule_probe(payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_atq010_config_probe(scope text,config_key text,config_value text,value_type text,value_status text) ON COMMIT DROP;
INSERT INTO ig_atq010_rule_probe SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE r.codigo='REG_ATQ_010';
INSERT INTO ig_atq010_config_probe
SELECT scope,config_key,config_value,value_type,value_status
FROM public.lf_global_config WHERE scope='AUTH' AND config_key='ERROR_RESPONSE_MINIMUM_MS';
DO $pre$
DECLARE
 p constant text:='EXEC-PROFILE-GATE2-87ECB467A64FF2AFD0C80C09';
 src constant text:='220496f8c7291c17ee5c9691e97e2d67e1c75b9c4eb5606ce487267446d68f15';
 prop constant text:='201ae3aa72cbc27d31d26ef7be125d07da5874bab397323a1818b0e1a8d42a53';
 oldhash text; patch jsonb;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_atq010_rule_probe)<>1
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=p
     AND e.operation_code='EJECUCION_PERFIL_LF' AND e.status='IN_PROGRESS'
     AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
     AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001'
     AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
     JOIN lf_ops.pantallas sc ON sc.id=rp.pantalla_id
     WHERE r.codigo='REG_ATQ_010' AND sc.codigo='ONB_001' AND r.estado='VIGENTE')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps WHERE execution_id=p
      AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE'
      AND evidence_payload->>'output_contract_result'='PASS')
 THEN RAISE EXCEPTION 'ATQ010_PG17_RUN_OR_SCOPE_INVALID'; END IF;
 SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') INTO oldhash FROM ig_atq010_rule_probe;
 IF oldhash IS DISTINCT FROM src OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ATQ_010')<>src
  OR (SELECT payload#>>'{valor_config,tiempo_minimo_respuesta_ms}' FROM ig_atq010_rule_probe) IS DISTINCT FROM '200'
  OR (SELECT payload->'valor_config'->'aplica_a' FROM ig_atq010_rule_probe)
       IS DISTINCT FROM '["validacion_dni","validacion_celular","verificacion_otp"]'::jsonb
  OR (SELECT count(*) FROM ig_atq010_config_probe WHERE scope='AUTH' AND
       config_key='ERROR_RESPONSE_MINIMUM_MS' AND config_value='200' AND value_type='INTEGER' AND value_status='REAL')<>1
  OR public.lf_auth_config_integer_v1('ERROR_RESPONSE_MINIMUM_MS')<>200
 THEN RAISE EXCEPTION 'ATQ010_PG17_SOURCE_OR_GLOBAL_CONFIG_DRIFT'; END IF;
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO patch
 FROM public.lf_operation_execution_steps WHERE execution_id=p AND step_id='execute_profile'
 AND status='STEP_PASS_WITH_EVIDENCE';
 IF patch->>'rule_code'<>'REG_ATQ_010' OR patch->>'change_kind'<>'FUNCTIONAL'
  OR encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex')<>prop
  OR patch#>>'{changes,valor_config,tiempo_minimo_respuesta_config,scope}'<>'AUTH'
  OR patch#>>'{changes,valor_config,tiempo_minimo_respuesta_config,config_key}'<>'ERROR_RESPONSE_MINIMUM_MS'
  OR (patch#>'{changes,valor_config}')?'tiempo_minimo_respuesta_ms'
  OR patch#>'{changes,valor_config,aplica_a}'
      IS DISTINCT FROM '["validacion_dni","validacion_celular","verificacion_otp"]'::jsonb
  OR position('mínimo constante' in patch#>>'{changes,descripcion}')=0
  OR position('ataques de tiempo' in patch#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'ATQ010_PG17_PATCH_SEMANTICS_CHANGED'; END IF;
 RAISE NOTICE 'IG_ATQ010_PREIMAGE_RAW_CONFIG_AND_SCOPE_PASS';
END $pre$;
SAVEPOINT ig_atq010_positive;
UPDATE ig_atq010_rule_probe t SET payload=t.payload||jsonb_build_object(
'descripcion',(SELECT evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}'
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-87ECB467A64FF2AFD0C80C09' AND step_id='execute_profile'),
'valor_config',(SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}'
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-87ECB467A64FF2AFD0C80C09' AND step_id='execute_profile'));
DO $candidate$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
 FROM ig_atq010_rule_probe) IS DISTINCT FROM '01deb254f5cf71907564c724211f23c7ea48a3d42cc9f43d775edb9f7979059c'
 THEN RAISE EXCEPTION 'ATQ010_PG17_CANDIDATE_SHA_BAD'; END IF;
 RAISE NOTICE 'IG_ATQ010_REAL_CANDIDATE_PROBE_PASS';
END $candidate$;
ROLLBACK TO SAVEPOINT ig_atq010_positive;
RELEASE SAVEPOINT ig_atq010_positive;
DO $rb$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
 FROM ig_atq010_rule_probe) IS DISTINCT FROM '220496f8c7291c17ee5c9691e97e2d67e1c75b9c4eb5606ce487267446d68f15'
 THEN RAISE EXCEPTION 'ATQ010_POSITIVE_ROLLBACK_MISSING'; END IF;
 RAISE NOTICE 'IG_ATQ010_POSITIVE_ROLLBACK_READBACK_PASS';
END $rb$;
SAVEPOINT ig_atq010_negative;
UPDATE ig_atq010_rule_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb);
DELETE FROM ig_atq010_config_probe;
DO $negative$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
 FROM ig_atq010_rule_probe)='220496f8c7291c17ee5c9691e97e2d67e1c75b9c4eb5606ce487267446d68f15'
 OR EXISTS(SELECT 1 FROM ig_atq010_config_probe)
 THEN RAISE EXCEPTION 'ATQ010_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_ATQ010_NEGATIVE_SOURCE_DRIFT_AND_CONFIG_MISSING_DETECTED';
END $negative$;
ROLLBACK TO SAVEPOINT ig_atq010_negative;
RELEASE SAVEPOINT ig_atq010_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
 FROM ig_atq010_rule_probe) IS DISTINCT FROM '220496f8c7291c17ee5c9691e97e2d67e1c75b9c4eb5606ce487267446d68f15'
 OR (SELECT count(*) FROM ig_atq010_config_probe WHERE config_value='200')<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ATQ_010')
 IS DISTINCT FROM '220496f8c7291c17ee5c9691e97e2d67e1c75b9c4eb5606ce487267446d68f15'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE
 parent_execution_id='EXEC-PROFILE-GATE2-87ECB467A64FF2AFD0C80C09' AND rule_code='REG_ATQ_010')
 THEN RAISE EXCEPTION 'ATQ010_REAL_INDEPENDENT_READBACK_FAILED'; END IF;
 RAISE NOTICE 'IG_ATQ010_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;