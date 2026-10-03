-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M2.5 / PAULO-021
-- Separate source currentness from semantic/classifier revalidation.
-- CURRENTNESS_AUTHORITY remains transversal authority; no private generic currentness engine.
-- Owner: SUPER_ADMIN.

DO $pre$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING (capability_code)
    WHERE r.capability_code='CURRENTNESS_AUTHORITY'
      AND r.status='ACTIVE'
      AND c.version='1.0.0'
  ) THEN
    RAISE EXCEPTION 'BLOCK_M2_5_CURRENTNESS_AUTHORITY_NOT_CURRENT';
  END IF;

  IF to_regprocedure('programacion.fn_input_run_source_currentness_v1(bigint)') IS NOT NULL
     OR to_regprocedure('programacion.fn_input_run_is_source_current(bigint)') IS NOT NULL
     OR to_regprocedure('programacion.fn_input_run_semantic_revalidation_v1(bigint)') IS NOT NULL THEN
    RAISE EXCEPTION 'BLOCK_M2_5_DELIVERABLE_PREEXISTING';
  END IF;

  IF md5(pg_get_functiondef('programacion.fn_input_readiness_run_is_current(bigint)'::regprocedure))
       <> 'e8a1b6eaf8f8bdc08aa63249d301692c' THEN
    RAISE EXCEPTION 'M2_5_STRONG_CURRENTNESS_SOURCE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_readiness_run_is_current_cached_v1(bigint)'::regprocedure))
       <> '3e812b14738da9d5ba52e6b357256908' THEN
    RAISE EXCEPTION 'M2_5_CACHED_V1_SOURCE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_readiness_run_is_current_cached_v2(bigint)'::regprocedure))
       <> 'f78615dba3d88e643e0c6f37e74d15bb' THEN
    RAISE EXCEPTION 'M2_5_CACHED_V2_SOURCE_DRIFT';
  END IF;
END $pre$;

CREATE OR REPLACE FUNCTION programacion.fn_input_run_source_currentness_v1(p_run_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public,programacion
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
      AND n.status IN ('COMPLETED','BLOCKED')
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

  v_current_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  v_manifest_ok := v_current_sha=v_run.source_snapshot_sha256
                   AND v_current_manifest=v_run.source_manifest;

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
        'stored_sha256',v_run.source_snapshot_sha256
      )
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_run_is_source_current(p_run_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,programacion
AS $function$
  SELECT coalesce(
    (programacion.fn_input_run_source_currentness_v1(p_run_id)->>'source_current')::boolean,
    false
  );
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_run_semantic_revalidation_v1(p_run_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,programacion
AS $function$
DECLARE
  v_run record;
  v_graph jsonb;
  v_a record;
  v_expected jsonb;
  v_classifier_drift integer:=0;
  v_missing_classifier integer:=0;
  v_depth_drift integer:=0;
  v_expected_subject jsonb;
  v_expected_threat jsonb;
BEGIN
  SELECT id,version_id,pantalla_id
  INTO v_run
  FROM programacion.input_readiness_runs
  WHERE id=p_run_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('required',false,'eligible',false,'reason','RUN_NOT_FOUND');
  END IF;

  IF NOT programacion.fn_input_run_is_source_current(p_run_id) THEN
    RETURN jsonb_build_object('required',false,'eligible',false,'reason','SOURCE_NOT_CURRENT');
  END IF;

  v_graph:=programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id);

  FOR v_a IN
    SELECT
      family_code,
      curator_evidence->>'bootstrap_classifier_sha256' AS stored_classifier_sha,
      subject_coverage,
      threat_coverage
    FROM programacion.input_family_assessments
    WHERE run_id=p_run_id
    ORDER BY family_code
  LOOP
    IF nullif(v_a.stored_classifier_sha,'') IS NULL THEN
      v_missing_classifier:=v_missing_classifier+1;
    ELSE
      v_expected:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
        v_run.pantalla_id,v_a.family_code,v_run.version_id,v_graph
      );
      IF v_a.stored_classifier_sha IS DISTINCT FROM v_expected->>'classifier_sha256' THEN
        v_classifier_drift:=v_classifier_drift+1;
      END IF;
    END IF;

    IF v_a.family_code='DESIGN_SYSTEM' THEN
      v_expected_subject:=programacion.fn_input_subject_depth_expected(
        v_run.pantalla_id,'DESIGN_SYSTEM'
      );
      IF v_a.subject_coverage IS DISTINCT FROM v_expected_subject THEN
        v_depth_drift:=v_depth_drift+1;
      END IF;
    ELSIF v_a.family_code='SECURITY' THEN
      v_expected_subject:=programacion.fn_input_subject_depth_expected(
        v_run.pantalla_id,'SECURITY'
      );
      v_expected_threat:=programacion.fn_input_security_threat_expected(v_run.pantalla_id);
      IF v_a.subject_coverage IS DISTINCT FROM v_expected_subject
         OR v_a.threat_coverage IS DISTINCT FROM v_expected_threat THEN
        v_depth_drift:=v_depth_drift+1;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'schema_version','INPUT_RUN_SEMANTIC_REVALIDATION_V1',
    'eligible',true,
    'required',(v_classifier_drift+v_missing_classifier+v_depth_drift)>0,
    'classifier_drift_count',v_classifier_drift,
    'missing_classifier_count',v_missing_classifier,
    'semantic_depth_drift_count',v_depth_drift
  );
END;
$function$;

-- Legacy compatibility surfaces now mean source currentness only.
CREATE OR REPLACE FUNCTION programacion.fn_input_readiness_run_is_current(p_run_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,programacion
AS $function$
  SELECT programacion.fn_input_run_is_source_current(p_run_id);
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_readiness_run_is_current_cached_v1(p_run_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,programacion
AS $function$
  SELECT programacion.fn_input_run_is_source_current(p_run_id);
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_readiness_run_is_current_cached_v2(p_run_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,programacion
AS $function$
  SELECT programacion.fn_input_run_is_source_current(p_run_id);
$function$;

DO $relation$
DECLARE
  v_batch uuid:=gen_random_uuid();
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_activo_relaciones
    WHERE codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET'
      AND relacionado_codigo='CURRENTNESS_AUTHORITY'
      AND relacion_tipo='DEPENDE_DE'
  ) THEN
    INSERT INTO public.lf_activo_relaciones(
      codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
      migration_batch_id,created_by_execution_id
    ) VALUES (
      'PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET',
      'CURRENTNESS_AUTHORITY',
      'DEPENDE_DE',
      'SOURCE_CURRENTNESS_AUTHORITY',
      'IG_CURATOR_VALIDATOR_REFACTOR_V2:M2.5',
      v_batch,
      'CHATGPT-IG-CV-M2-5-20261003'
    );
  END IF;
END $relation$;

DO $post$
DECLARE
  v_bad integer;
  v_receipt jsonb;
BEGIN
  SELECT count(*) INTO v_bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion'
    AND p.proname IN (
      'fn_input_readiness_run_is_current',
      'fn_input_readiness_run_is_current_cached_v1',
      'fn_input_readiness_run_is_current_cached_v2'
    )
    AND (
      p.prosrc ILIKE '%classifier%'
      OR p.prosrc ILIKE '%subject_depth%'
      OR p.prosrc ILIKE '%threat%'
    );
  IF v_bad<>0 THEN
    RAISE EXCEPTION 'M2_5_LEGACY_CURRENTNESS_STILL_SEMANTIC:%',v_bad;
  END IF;

  v_receipt:=programacion.fn_input_run_source_currentness_v1(373);
  IF v_receipt->>'classifier_checked'<>'false'
     OR v_receipt->>'semantic_depth_checked'<>'false' THEN
    RAISE EXCEPTION 'M2_5_SOURCE_CURRENTNESS_SEMANTIC_COUPLING_REMAINS:%',v_receipt;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activo_relaciones
    WHERE codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET'
      AND relacionado_codigo='CURRENTNESS_AUTHORITY'
      AND relacion_tipo='DEPENDE_DE'
  ) THEN
    RAISE EXCEPTION 'M2_5_CURRENTNESS_AUTHORITY_RELATION_MISSING';
  END IF;
END $post$;
