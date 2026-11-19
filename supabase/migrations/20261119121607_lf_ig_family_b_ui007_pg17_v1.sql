-- Familia B REG_UI_007 native V2 PG17 source-bound, TEMP only with positive/negative rollback.
BEGIN;
CREATE TEMP TABLE ig_b_regui007_probe(code text PRIMARY KEY,payload jsonb NOT NULL) ON COMMIT DROP;
INSERT INTO ig_b_regui007_probe SELECT codigo,to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_UI_007';
CREATE TEMP TABLE ig_b_regui007_cfg AS SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='UX' AND config_key='HOME_VARIANT_MAX_SKELETON_SECONDS';
DO $pre$
DECLARE v_patch jsonb;
BEGIN
 SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_patch
 FROM public.lf_operation_execution_steps WHERE execution_id='EXEC-PROFILE-GATE2-B61F053224091B267AF23EFD' AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_regui007_probe)<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo='REG_UI_007' AND es_actual)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo='REG_UI_007' AND r.estado='VIGENTE' AND p.codigo='PASO3_MULTI_OFERTA')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-PROFILE-GATE2-B61F053224091B267AF23EFD' AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='PASO3_MULTI_OFERTA' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-B61F053224091B267AF23EFD' AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_regui007_probe)<>'49dc81d9c04ff59fcbae358df0a33b1ed87ea035a7cf446a02e341384363c274'
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_UI_007')<>'49dc81d9c04ff59fcbae358df0a33b1ed87ea035a7cf446a02e341384363c274'
 OR (SELECT count(*) FROM ig_b_regui007_cfg WHERE scope='UX' AND config_key='HOME_VARIANT_MAX_SKELETON_SECONDS' AND config_value='5' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR v_patch->>'rule_code'<>'REG_UI_007' OR v_patch->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex')<>'216cb7a8b7c202fb0936d559542c072689a52ff35d11602e48324ad53a43163d'
 OR v_patch#>>'{changes,valor_config,duracion_maxima_s_config_ref,scope}'<>'UX'
 OR v_patch#>>'{changes,valor_config,duracion_maxima_s_config_ref,config_key}'<>'HOME_VARIANT_MAX_SKELETON_SECONDS'
 OR (v_patch#>'{changes,valor_config}')?'duracion_maxima_s'
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%public.lf_global_config%'
 OR (v_patch#>'{changes}')?'titulo'
  OR v_patch#>>'{changes,valor_config,tipo}' IS DISTINCT FROM 'skeleton_contextual'
 OR v_patch#>>'{changes,valor_config,fallback_si_supera}' IS DISTINCT FROM 'home_variant_sin_oferta'
 OR position('home_variant_sin_oferta' in v_patch#>>'{changes,descripcion}')=0
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-B61F053224091B267AF23EFD' AND rule_code='REG_UI_007')
 THEN RAISE EXCEPTION 'IG_B_regui007_SOURCE_NATIVE_SHA_CONFIG_FAIL'; END IF;
 RAISE NOTICE 'IG_B_regui007_SOURCE_PROFILE_CONFIG_PASS';
END $pre$;
SAVEPOINT ig_b_regui007_positive;
UPDATE ig_b_regui007_probe t SET payload=t.payload||jsonb_build_object(
 'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}' FROM public.lf_operation_execution_steps s WHERE execution_id='EXEC-PROFILE-GATE2-B61F053224091B267AF23EFD' AND step_id='execute_profile'),
 'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}' FROM public.lf_operation_execution_steps s WHERE execution_id='EXEC-PROFILE-GATE2-B61F053224091B267AF23EFD' AND step_id='execute_profile')
) WHERE code='REG_UI_007';
DO $pos$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_regui007_probe)<>'08c6769c06cc3d4a4daaa38f717ed2fa23092dddd8e98debfc678b05c7e747be'
 THEN RAISE EXCEPTION 'IG_B_regui007_CANDIDATE_SHA_FAIL'; END IF;
 RAISE NOTICE 'IG_B_regui007_CANDIDATE_PASS';
END $pos$;
ROLLBACK TO SAVEPOINT ig_b_regui007_positive;
RELEASE SAVEPOINT ig_b_regui007_positive;
DO $rb$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_regui007_probe)<>'49dc81d9c04ff59fcbae358df0a33b1ed87ea035a7cf446a02e341384363c274'
 THEN RAISE EXCEPTION 'IG_B_regui007_POSITIVE_ROLLBACK_FAIL'; END IF;
END $rb$;
SAVEPOINT ig_b_regui007_negative;
UPDATE ig_b_regui007_probe SET payload=jsonb_set(payload,'{descripcion}','"SOURCE_DRIFT"'::jsonb) WHERE code='REG_UI_007';
DELETE FROM ig_b_regui007_cfg WHERE config_key='HOME_VARIANT_MAX_SKELETON_SECONDS';
DO $neg$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_regui007_probe)='49dc81d9c04ff59fcbae358df0a33b1ed87ea035a7cf446a02e341384363c274'
 OR EXISTS(SELECT 1 FROM ig_b_regui007_cfg WHERE config_key='HOME_VARIANT_MAX_SKELETON_SECONDS')
 THEN RAISE EXCEPTION 'IG_B_regui007_NEGATIVE_DRIFT_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_B_regui007_NEGATIVE_DRIFT_AND_MISSING_CONFIG_PASS';
END $neg$;
ROLLBACK TO SAVEPOINT ig_b_regui007_negative;
RELEASE SAVEPOINT ig_b_regui007_negative;
DO $post$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') FROM ig_b_regui007_probe)<>'49dc81d9c04ff59fcbae358df0a33b1ed87ea035a7cf446a02e341384363c274'
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_UI_007')<>'49dc81d9c04ff59fcbae358df0a33b1ed87ea035a7cf446a02e341384363c274'
 OR (SELECT count(*) FROM ig_b_regui007_cfg WHERE config_value='5' AND value_type='INTEGER' AND value_status='REAL')<>1
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id='EXEC-PROFILE-GATE2-B61F053224091B267AF23EFD' AND rule_code='REG_UI_007')
 THEN RAISE EXCEPTION 'IG_B_regui007_INDEPENDENT_READBACK_FAIL'; END IF;
 RAISE NOTICE 'IG_B_regui007_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; INDEPENDENT_READBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $post$;
COMMIT;
