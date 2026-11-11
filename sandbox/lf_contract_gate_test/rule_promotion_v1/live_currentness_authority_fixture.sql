-- Exact CURRENTNESS_AUTHORITY live function; supporting tables/mocks are isolated fixtures.
CREATE OR REPLACE FUNCTION programacion.fn_input_run_source_currentness_v1(p_run_id bigint)
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

  v_current_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
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
;
