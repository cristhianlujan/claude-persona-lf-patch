-- IG Family A REG_ATQ_017 real PG17 rule-contract test only.
-- No authoritative rule/global_config writes; positive/negative SAVEPOINT/ROLLBACK.
BEGIN;
CREATE TEMP TABLE ig_a017_probe(payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_a017_cfg(scope text,config_key text,config_value text,value_type text,value_status text) ON COMMIT DROP;
INSERT INTO ig_a017_probe SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_ATQ_017';
INSERT INTO ig_a017_cfg SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='AUTH' AND config_key IN ('FAILED_PHONE_PER_DNI_LIMIT','FAILED_PHONE_PER_DNI_WINDOW_HOURS');
DO $pre$
DECLARE
 v_old constant text:='7f8ee2effa0b5165e7fb80b80d371fe6dc3cd521e74adec424ce4077d478bf4a'; v_prop constant text:='20b7a102320a253c2069441ad2495775503dddf10147e20d8643507e72f0cf8b';
 p constant text:='EXEC-PROFILE-GATE2-698A6DDC240929423FA48388'; v_patch jsonb;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_a017_probe)<>1
 OR (SELECT count(*) FROM ig_a017_cfg)<>2
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=p
   AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest->>'no_write'='true'
   AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_003')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
     JOIN lf_ops.pantallas s ON s.id=rp.pantalla_id WHERE r.codigo='REG_ATQ_017' AND s.codigo='ONB_003' AND r.estado='VIGENTE')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps e WHERE e.execution_id=p AND e.step_id='output_validate'
   AND e.status='STEP_PASS_WITH_EVIDENCE' AND e.evidence_payload->>'output_contract_result'='PASS')
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ATQ_017')<>v_old
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a017_probe)<>v_old
 THEN RAISE EXCEPTION 'A017_PG17_SOURCE_RUN_SCREEN_DRIFT'; END IF;
 IF (SELECT count(*) FROM ig_a017_cfg WHERE scope='AUTH' AND value_type='INTEGER' AND value_status='REAL'
      AND ((config_key='FAILED_PHONE_PER_DNI_LIMIT' AND config_value='3')
        OR (config_key='FAILED_PHONE_PER_DNI_WINDOW_HOURS' AND config_value='24')))<>2
 OR public.lf_auth_config_integer_v1('FAILED_PHONE_PER_DNI_LIMIT')<>3
 OR public.lf_auth_config_integer_v1('FAILED_PHONE_PER_DNI_WINDOW_HOURS')<>24
 OR (SELECT payload#>>'{valor_config,max_celulares_por_dni_fallidos}' FROM ig_a017_probe)<>'3'
 OR (SELECT payload#>>'{valor_config,ventana_horas}' FROM ig_a017_probe)<>'24'
 THEN RAISE EXCEPTION 'A017_PG17_CONFIG_DRIFT'; END IF;
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch
 FROM public.lf_operation_execution_steps WHERE execution_id=p AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF v_patch->>'rule_code'<>'REG_ATQ_017' OR v_patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex')<>v_prop
 OR v_patch#>>'{changes,valor_config,accion}'<>'marcar_sospechoso_revision_manual'
 OR v_patch#>>'{changes,valor_config,max_celulares_por_dni_fallidos_config,scope}'<>'AUTH'
 OR v_patch#>>'{changes,valor_config,max_celulares_por_dni_fallidos_config,config_key}'<>'FAILED_PHONE_PER_DNI_LIMIT'
 OR v_patch#>>'{changes,valor_config,ventana_horas_config,scope}'<>'AUTH'
 OR v_patch#>>'{changes,valor_config,ventana_horas_config,config_key}'<>'FAILED_PHONE_PER_DNI_WINDOW_HOURS'
 OR (v_patch#>'{changes,valor_config}')?'max_celulares_por_dni_fallidos'
 OR (v_patch#>'{changes,valor_config}')?'ventana_horas'
 OR position('supera el límite' in v_patch#>>'{changes,descripcion}')=0
 OR position('intentos fallidos' in v_patch#>>'{changes,descripcion}')=0
 OR position('revisión manual antes' in v_patch#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'A017_PG17_PROFILE_PATCH_SEMANTICS_DRIFT'; END IF;
 RAISE NOTICE 'A017_PG17_SOURCE_PROFILE_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_a017_positive;
UPDATE ig_a017_probe t SET payload=payload||jsonb_build_object(
 'descripcion',(SELECT evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}'
  FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-698A6DDC240929423FA48388' AND step_id='execute_profile'),
 'valor_config',(SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}'
  FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-698A6DDC240929423FA48388' AND step_id='execute_profile'));
DO $positive$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a017_probe)
 IS DISTINCT FROM '59b0b7ecb476876a793eaf587f44a3bd411515f34331ec3840110916bbbb7204' THEN RAISE EXCEPTION 'A017_PG17_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'A017_PG17_CANDIDATE_SHA_PASS';
END $positive$;
ROLLBACK TO SAVEPOINT ig_a017_positive;
RELEASE SAVEPOINT ig_a017_positive;
DO $back$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a017_probe)
 IS DISTINCT FROM '7f8ee2effa0b5165e7fb80b80d371fe6dc3cd521e74adec424ce4077d478bf4a' THEN RAISE EXCEPTION 'A017_POSITIVE_ROLLBACK_FAILED'; END IF;
 RAISE NOTICE 'A017_POSITIVE_ROLLBACK_READBACK_PASS';
END $back$;
SAVEPOINT ig_a017_negative;
UPDATE ig_a017_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb);
DELETE FROM ig_a017_cfg WHERE config_key='FAILED_PHONE_PER_DNI_LIMIT';
DO $negative$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a017_probe)
 = '7f8ee2effa0b5165e7fb80b80d371fe6dc3cd521e74adec424ce4077d478bf4a' OR EXISTS(SELECT 1 FROM ig_a017_cfg WHERE config_key='FAILED_PHONE_PER_DNI_LIMIT')
 THEN RAISE EXCEPTION 'A017_NEGATIVE_NOT_DETECTED'; END IF;
 RAISE NOTICE 'A017_NEGATIVE_SOURCE_DRIFT_AND_MISSING_CONFIG_DETECTED';
END $negative$;
ROLLBACK TO SAVEPOINT ig_a017_negative;
RELEASE SAVEPOINT ig_a017_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_a017_probe)
 <> '7f8ee2effa0b5165e7fb80b80d371fe6dc3cd521e74adec424ce4077d478bf4a' OR (SELECT count(*) FROM ig_a017_cfg)<>2
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ATQ_017')<>'7f8ee2effa0b5165e7fb80b80d371fe6dc3cd521e74adec424ce4077d478bf4a'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-698A6DDC240929423FA48388' AND rule_code='REG_ATQ_017')
 THEN RAISE EXCEPTION 'A017_PG17_INDEPENDENT_READBACK_FAILED'; END IF;
 RAISE NOTICE 'A017_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;