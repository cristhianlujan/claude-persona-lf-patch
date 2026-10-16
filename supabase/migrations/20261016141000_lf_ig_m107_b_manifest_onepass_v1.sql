-- M10.7 B: additive private SQL candidate; no existing guard changes.
CREATE OR REPLACE FUNCTION programacion.fn_ig_m107_currentness_from_manifest_v1(p_run_id bigint, p_read_manifest jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion'
AS $function$
DECLARE
  v_run record;
  v_contract_schema integer;
  v_contract_revision text;
  v_contract_payload jsonb;
  v_contract_sha text;
  v_analysis_revision text;
  v_policy_revision text;
  v_has_terminal_successor boolean:=false;
  v_current_manifest jsonb;
  v_current_sha text;
  v_stored_identity_sha text;
  v_lifecycle_ok boolean:=false;
  v_contract_ok boolean:=false;
  v_policy_ok boolean:=true;
  v_manifest_ok boolean:=false;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING(capability_code)
    WHERE r.capability_code='CURRENTNESS_AUTHORITY'
      AND r.status='ACTIVE'
  ) THEN
    RETURN jsonb_build_object(
      'schema_version','INPUT_RUN_SOURCE_CURRENTNESS_V1',
      'authority','CURRENTNESS_AUTHORITY',
      'run_id',p_run_id,
      'source_current',false,
      'code','CURRENTNESS_AUTHORITY_NOT_CURRENT',
      'classifier_checked',false,
      'semantic_depth_checked',false,
      'dimensions','{}'::jsonb
    );
  END IF;

  SELECT
    r.status,r.version_id,r.pantalla_id,
    r.contract_version,r.contract_revision,r.contract_snapshot_sha256,
    r.source_manifest,r.source_snapshot_sha256,r.invalidated_at,r.scope
  INTO v_run
  FROM programacion.input_readiness_runs r
  WHERE r.id=p_run_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'schema_version','INPUT_RUN_SOURCE_CURRENTNESS_V1',
      'authority','CURRENTNESS_AUTHORITY',
      'run_id',p_run_id,
      'source_current',false,
      'code','RUN_NOT_FOUND',
      'classifier_checked',false,
      'semantic_depth_checked',false,
      'dimensions','{}'::jsonb
    );
  END IF;

  SELECT EXISTS(
    SELECT 1
    FROM programacion.input_readiness_runs n
    WHERE n.supersedes_run_id=p_run_id
      AND n.status='COMPLETED'
  ) INTO v_has_terminal_successor;

  v_lifecycle_ok := v_run.status='COMPLETED'
                    AND v_run.source_snapshot_sha256 IS NOT NULL
                    AND v_run.invalidated_at IS NULL
                    AND NOT v_has_terminal_successor;

  SELECT
    (c.especificacion->>'schema_version')::integer,
    c.especificacion->>'contract_revision',
    jsonb_build_object(
      'id',c.id,
      'version_id',c.version_id,
      'contrato_codigo',c.contrato_codigo,
      'fail_closed',c.fail_closed,
      'estado',c.estado,
      'especificacion',c.especificacion
    )
  INTO v_contract_schema,v_contract_revision,v_contract_payload
  FROM programacion.contratos c
  WHERE c.version_id=v_run.version_id
    AND c.contrato_codigo='INPUT_READINESS_CONTRACT';

  IF v_contract_schema IS NOT NULL AND v_contract_revision IS NOT NULL THEN
    v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract_payload);
    v_contract_ok := v_run.contract_version=v_contract_schema
                     AND v_run.contract_revision IS NOT DISTINCT FROM v_contract_revision
                     AND v_run.contract_snapshot_sha256 IS NOT DISTINCT FROM v_contract_sha;
  END IF;

  IF coalesce(v_run.scope->>'mode','') IN (
    'GOVERNED_CANONICAL_BOOTSTRAP_V1',
    'RUNTIME_GOVERNED_RECURATION_V2'
  ) THEN
    SELECT
      especificacion->>'analysis_revision',
      especificacion->'remediation_loop'->>'policy_revision'
    INTO v_analysis_revision,v_policy_revision
    FROM programacion.contratos
    WHERE version_id=v_run.version_id
      AND contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      AND estado='defined'
      AND fail_closed;

    v_policy_ok := v_analysis_revision IS NOT NULL
                   AND v_run.scope->>'analysis_revision' IS NOT DISTINCT FROM v_analysis_revision
                   AND (
                     v_policy_revision IS NULL
                     OR v_run.scope->>'remediation_policy_revision' IS NOT DISTINCT FROM v_policy_revision
                   );
  END IF;

  v_current_manifest:=p_read_manifest;
  v_current_sha:=programacion.fn_v09_sha256_jsonb(
    programacion.fn_input_source_manifest_identity_v1(v_current_manifest)
  );
  v_stored_identity_sha:=programacion.fn_v09_sha256_jsonb(
    programacion.fn_input_source_manifest_identity_v1(v_run.source_manifest)
  );
  v_manifest_ok := v_current_sha=v_stored_identity_sha;

  RETURN jsonb_build_object(
    'schema_version','INPUT_RUN_SOURCE_CURRENTNESS_V1',
    'authority','CURRENTNESS_AUTHORITY',
    'run_id',p_run_id,
    'source_current',v_lifecycle_ok AND v_contract_ok AND v_policy_ok AND v_manifest_ok,
    'classifier_checked',false,
    'semantic_depth_checked',false,
    'dimensions',jsonb_build_object(
      'lifecycle',jsonb_build_object(
        'current',v_lifecycle_ok,
        'terminal_successor',v_has_terminal_successor
      ),
      'readiness_contract',jsonb_build_object(
        'current',v_contract_ok,
        'revision',v_contract_revision
      ),
      'execution_policy',jsonb_build_object(
        'current',v_policy_ok,
        'analysis_revision',v_analysis_revision,
        'policy_revision',v_policy_revision
      ),
      'source_manifest',jsonb_build_object(
        'current',v_manifest_ok,
        'current_sha256',v_current_sha,
        'stored_sha256',v_stored_identity_sha,
        'stored_snapshot_sha256',v_run.source_snapshot_sha256,
        'comparison_contract','IG_SOURCE_MANIFEST_IDENTITY_V1'
      )
    )
  );
END;
$function$


CREATE FUNCTION programacion.fn_ig_m107_bundle_from_manifest_v1(p_run_id bigint,p_manifest jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion'
AS $fb$
DECLARE v_run record; v_authority jsonb; v_decision jsonb; v_g1 jsonb; v_sha text; v_full boolean;
BEGIN
 SELECT r.id,r.status,r.source_manifest,r.source_snapshot_sha256 INTO v_run
 FROM programacion.input_readiness_runs r WHERE r.id=p_run_id;
 IF NOT FOUND OR v_run.status NOT IN ('VALIDATING','COMPLETED') THEN
 RAISE EXCEPTION 'IG_M107_B_BUNDLE_RUN_NOT_ELIGIBLE:%',p_run_id; END IF;
 IF jsonb_typeof(p_manifest)<>'array' THEN
 RAISE EXCEPTION 'IG_M107_B_BUNDLE_MANIFEST_INVALID'; END IF;
 v_authority:=programacion.fn_ig_m107_currentness_from_manifest_v1(p_run_id,p_manifest);
 v_decision:=programacion.fn_input_governance_continuation_currentness_decide_v1(v_run.status,v_authority);
 v_g1:=v_decision || jsonb_build_object('schema_version','IG_CONTINUATION_CURRENTNESS_V1',
    'run_id',p_run_id,'authority_readback',v_authority);
 v_sha:=programacion.fn_v09_sha256_jsonb(p_manifest);
 v_full:=(v_sha IS NOT DISTINCT FROM v_run.source_snapshot_sha256
    AND p_manifest IS NOT DISTINCT FROM v_run.source_manifest);
 RETURN jsonb_build_object('schema_version','IG_M107_B_MANIFEST_BUNDLE_V1',
 'run_id',p_run_id,'g1',v_g1,'full_manifest_current',v_full,
 'full_manifest_sha256',v_sha);
END $fb$;
CREATE FUNCTION programacion.fn_ig_m107_manifest_guard_bundle_v1(p_run_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion'
AS $fn$
DECLARE v_manifest jsonb;
BEGIN
 v_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
 RETURN programacion.fn_ig_m107_bundle_from_manifest_v1(p_run_id,v_manifest);
END $fn$;
REVOKE ALL ON FUNCTION programacion.fn_ig_m107_currentness_from_manifest_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION programacion.fn_ig_m107_bundle_from_manifest_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION programacion.fn_ig_m107_manifest_guard_bundle_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;


DO $proof$
DECLARE v_baseline jsonb; v_bundle jsonb; v_manifest jsonb; v_modified jsonb; v_tamper jsonb;
 v_expected_full boolean; v_func text; v_stored jsonb; v_synthetic_positive jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M107-B-GRAPH-INVOKE-REUSE-029') THEN RAISE EXCEPTION 'IG_M107_B_DEPENDENCY_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M107-B-MANIFEST-ONEPASS-030') THEN RAISE EXCEPTION 'IG_M107_B_DUPLICATE_EKB'; END IF;
 SELECT pg_get_functiondef(p.oid) INTO v_func FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='programacion' AND p.proname='fn_ig_m107_manifest_guard_bundle_v1';
 IF (length(v_func)-length(replace(v_func,'fn_input_build_source_manifest(','')))/length('fn_input_build_source_manifest(')<>1
 THEN RAISE EXCEPTION 'IG_M107_B_DUPLICATE_MANIFEST_CALL_IN_CANDIDATE'; END IF;
 v_baseline:=programacion.fn_input_governance_continuation_currentness_v1(933);
 v_bundle:=programacion.fn_ig_m107_manifest_guard_bundle_v1(933);
 IF v_baseline IS DISTINCT FROM v_bundle->'g1' THEN RAISE EXCEPTION 'IG_M107_B_G1_PARITY_FAIL'; END IF;
 v_manifest:=programacion.fn_input_build_source_manifest(933);
 SELECT (v_manifest IS NOT DISTINCT FROM r.source_manifest
   AND programacion.fn_v09_sha256_jsonb(v_manifest) IS NOT DISTINCT FROM r.source_snapshot_sha256)
 INTO v_expected_full FROM programacion.input_readiness_runs r WHERE id=933;
 IF ((v_bundle->>'full_manifest_current')::boolean) IS DISTINCT FROM v_expected_full
 THEN RAISE EXCEPTION 'IG_M107_B_FULL_PARITY_FAIL'; END IF;
 -- Positive exact pinned-manifest fixture, separate from historical live currentness.
 SELECT r.source_manifest INTO v_stored FROM programacion.input_readiness_runs r WHERE id=933;
 v_synthetic_positive:=programacion.fn_ig_m107_bundle_from_manifest_v1(933,v_stored);
 IF (v_synthetic_positive->>'full_manifest_current')::boolean IS NOT TRUE
 THEN RAISE EXCEPTION 'IG_M107_B_PINNED_MANIFEST_POSITIVE_FAIL'; END IF;
 -- A lifecycle-only modification must fail full equality even if identity is unchanged.
 v_modified:=jsonb_set(v_stored,'{0,lifecycle,synthetic_negative}','"LIFECYCLE_DRIFT"'::jsonb,true);
 IF programacion.fn_input_source_manifest_identity_v1(v_modified) IS DISTINCT FROM
    programacion.fn_input_source_manifest_identity_v1(v_stored)
 THEN RAISE EXCEPTION 'IG_M107_B_BAD_LIFECYCLE_FIXTURE'; END IF;
 v_tamper:=programacion.fn_ig_m107_bundle_from_manifest_v1(933,v_modified);
 IF (v_tamper->>'full_manifest_current')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'IG_M107_B_LIFECYCLE_TAMPER_ACCEPTED'; END IF;
 v_modified:=jsonb_set(v_stored,'{0,observed_sha256}',to_jsonb(repeat('0',64)),true);
 v_tamper:=programacion.fn_ig_m107_bundle_from_manifest_v1(933,v_modified);
 IF (v_tamper#>>'{g1,authority_readback,dimensions,source_manifest,current}')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'IG_M107_B_IDENTITY_TAMPER_ACCEPTED'; END IF;
 IF has_function_privilege('anon','programacion.fn_ig_m107_manifest_guard_bundle_v1(bigint)','EXECUTE')
 OR has_function_privilege('authenticated','programacion.fn_ig_m107_manifest_guard_bundle_v1(bigint)','EXECUTE')
 OR has_function_privilege('service_role','programacion.fn_ig_m107_manifest_guard_bundle_v1(bigint)','EXECUTE')
 OR has_function_privilege('anon','programacion.fn_ig_m107_bundle_from_manifest_v1(bigint,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','programacion.fn_ig_m107_currentness_from_manifest_v1(bigint,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'IG_M107_B_ACL_UNSAFE'; END IF;
END $proof$;


INSERT INTO public.lf_error_knowledge
(id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,
lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
VALUES(
gen_random_uuid(),'IG-M107-B-MANIFEST-ONEPASS-030','GOVERNANCE',
'M10.7 B: doble cotejo con una sola construcción del manifiesto (candidato)',
'Helper backend aislado: una construcción del manifiesto alimenta currentness G1 y cotejo completo. Ningún trigger ni runtime existente se modifica.',
'La ruta original reconstruye manifiesto en currentness y en el guard final de familia/propuesta.',
'ONEPASS_FULL_MANIFEST_DUAL_ATTESTATION',
'Preservar ambos chequeos sin cache global o entre triggers hasta evidencia de vigencia de fuentes y concurrencia; no dar permisos publicos.',
'Train: paridad G1 JSONB, paridad cotejo completo, lifecycle tamper fail, identity tamper fail, verificación estructural 1 construcción y ACL privada; caso histórico 933, no prueba runtime.',
'MEDIUM',1,clock_timestamp(),clock_timestamp(),
'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/LOT_B','ACTIVO',
jsonb_build_object('schema_version','IG_M107_B_ONEPASS_DUAL_ATTESTATION_V1',
'structural_manifest_builds_in_wrapper',1,'g1_parity',true,'full_manifest_parity',true,
'lifecycle_negative',true,'identity_negative',true,
'historical_run_id',933,'runtime_triggers_changed',false,'cross_trigger_reuse_active',false,
'lot_B_closed',false,'cp3_closed',false)::text,
clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
'Backend owner-only function candidate; no runtime binding or activation',
'docs/ig/IG_M107_B_MANIFEST_ONEPASS_V1.md');
