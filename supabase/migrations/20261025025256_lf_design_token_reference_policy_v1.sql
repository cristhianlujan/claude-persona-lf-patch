BEGIN;

ALTER TABLE private.lf_repository_governance_bundle_v4
  DROP CONSTRAINT lf_repository_governance_bundle_v4_control_kind_check;

ALTER TABLE private.lf_repository_governance_bundle_v4
  ADD CONSTRAINT lf_repository_governance_bundle_v4_control_kind_check
  CHECK (control_kind = ANY (ARRAY[
    'SOURCE_WORKFLOW'::text,
    'RECONCILIATION_WORKFLOW'::text,
    'VALIDATOR'::text,
    'POLICY'::text
  ]));

COMMENT ON FUNCTION lf_design.guard_component_token_bindings_v1() IS
'Enforcement DB de LF-DESIGN-TOKEN-REFERENCE-POLICY-V1. Prohíbe colores literales en component_tokens.token_bindings y valida referencias cromáticas canónicas por nombre/status.';

COMMENT ON TRIGGER trg_guard_component_token_bindings_v1 ON lf_design.component_tokens IS
'DB enforcement de LF-DESIGN-TOKEN-REFERENCE-POLICY-V1 para INSERT/UPDATE de token_bindings/status.';

DO $policy_pin$
DECLARE
  v_path constant text := 'docs/standards/LF_DESIGN_TOKEN_REFERENCE_POLICY_V1.md';
  v_sha256 constant text := 'd62ce24ccd0bb166b0177e852a38513b755ffc21a57c2e4697383b67db8d7688';
  v_blob constant text := '516932cc70240c1cb0b2383c9b629062b5107454';
  v_existing record;
BEGIN
  SELECT *
    INTO v_existing
  FROM public.get_lf_repository_governance_bundle_v4()
  WHERE path=v_path
  LIMIT 1;

  IF FOUND THEN
    IF (v_existing.expected_sha256,v_existing.expected_git_blob,v_existing.control_kind)
       IS DISTINCT FROM (v_sha256,v_blob,'POLICY')
    THEN
      INSERT INTO private.lf_repository_governance_bundle_v4(
        path,expected_sha256,expected_git_blob,control_kind,active,
        approved_commit_sha,approved_by_execution_id,approved_at
      )
      VALUES(
        v_path,v_sha256,v_blob,'POLICY',true,
        'd72ed6ad7b7323344c3b36e3e61d9b922ee3c933',
        'LF-DESIGN-TOKEN-REFERENCE-POLICY-V1',
        clock_timestamp()
      );
    END IF;
  ELSE
    INSERT INTO private.lf_repository_governance_bundle_v4(
      path,expected_sha256,expected_git_blob,control_kind,active,
      approved_commit_sha,approved_by_execution_id,approved_at
    )
    VALUES(
      v_path,v_sha256,v_blob,'POLICY',true,
      'd72ed6ad7b7323344c3b36e3e61d9b922ee3c933',
      'LF-DESIGN-TOKEN-REFERENCE-POLICY-V1',
      clock_timestamp()
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.get_lf_repository_governance_bundle_v4()
    WHERE path=v_path
      AND expected_sha256=v_sha256
      AND expected_git_blob=v_blob
      AND control_kind='POLICY'
  ) THEN
    RAISE EXCEPTION 'DESIGN_TOKEN_POLICY_GOVERNANCE_PIN_FAILED';
  END IF;

  IF obj_description(
       'lf_design.guard_component_token_bindings_v1()'::regprocedure,
       'pg_proc'
     ) NOT LIKE '%LF-DESIGN-TOKEN-REFERENCE-POLICY-V1%'
  THEN
    RAISE EXCEPTION 'DESIGN_TOKEN_POLICY_DB_ENFORCEMENT_NOT_BOUND';
  END IF;
END
$policy_pin$;

COMMIT;
