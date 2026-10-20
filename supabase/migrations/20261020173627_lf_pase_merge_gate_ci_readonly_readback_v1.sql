-- PASE/POST-PASE X16 step 2: read-only database access for the pase-merge-gate shadow run.
--
-- pase-merge-gate reads CONTROL_SYSTEM qualification through
-- public.lf_control_system_qualification_readback_v1 (SECURITY INVOKER). The CI
-- read-only role lf_ci_readonly (environment lf-ci-readonly, secret
-- LF_SUPABASE_DB_READONLY_PASSWORD) cannot read the tables behind it
-- (public.lf_qualification_receipts and public.lf_operation_effect_guard have RLS
-- without a policy for it; no USAGE on lf_ops/extensions), so calling the readback
-- as lf_ci_readonly fails or returns nothing.
--
-- Same pattern as public.get_lf_repository_governance_bundle_v4(): one
-- SECURITY DEFINER read-only wrapper, EXECUTE only for lf_ci_readonly and
-- service_role. No table or schema grant is added; the original readback is
-- not modified. Owner decision 2026-10-20: CI uses read-only credentials only.
DO $pre$
DECLARE
  v_fn regprocedure;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lf_ci_readonly') THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_PRECONDITION_ROLE_MISSING:lf_ci_readonly';
  END IF;
  v_fn := to_regprocedure('public.lf_control_system_qualification_readback_v1(text,text,text,text)');
  IF v_fn IS NULL THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_PRECONDITION_READBACK_MISSING';
  END IF;
  IF (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = v_fn) THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_PRECONDITION_READBACK_NOT_INVOKER';
  END IF;
  IF (SELECT p.provolatile FROM pg_proc p WHERE p.oid = v_fn) <> 's' THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_PRECONDITION_READBACK_NOT_STABLE';
  END IF;
  IF pg_get_function_result(v_fn) <> 'jsonb' THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_PRECONDITION_READBACK_RESULT';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.lf_ci_control_system_qualification_readback_v1(
  p_candidate_id text,
  p_repository text,
  p_base_sha text,
  p_head_sha text
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT public.lf_control_system_qualification_readback_v1(
    p_candidate_id, p_repository, p_base_sha, p_head_sha
  );
$fn$;

COMMENT ON FUNCTION public.lf_ci_control_system_qualification_readback_v1(text, text, text, text) IS
  'CI read-only CONTROL_SYSTEM qualification readback for pase-merge-gate (lf_ci_readonly). '
  'Delegates to lf_control_system_qualification_readback_v1; read-only; no table grants.';

REVOKE ALL ON FUNCTION public.lf_ci_control_system_qualification_readback_v1(text, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_ci_control_system_qualification_readback_v1(text, text, text, text)
  TO lf_ci_readonly, service_role;

DO $post$
DECLARE
  c_sig constant text := 'public.lf_ci_control_system_qualification_readback_v1(text,text,text,text)';
  v_fn regprocedure := to_regprocedure(c_sig);
BEGIN
  IF v_fn IS NULL THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_POSTCHECK_WRAPPER_MISSING';
  END IF;
  IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = v_fn) THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_POSTCHECK_NOT_DEFINER';
  END IF;
  IF (SELECT p.provolatile FROM pg_proc p WHERE p.oid = v_fn) <> 's' THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_POSTCHECK_NOT_STABLE';
  END IF;
  IF NOT coalesce((SELECT 'search_path=""' = ANY (p.proconfig) FROM pg_proc p WHERE p.oid = v_fn), false) THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_POSTCHECK_SEARCH_PATH';
  END IF;
  IF NOT has_function_privilege('lf_ci_readonly', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_POSTCHECK_CI_EXECUTE_MISSING';
  END IF;
  IF NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_POSTCHECK_SERVICE_EXECUTE_MISSING';
  END IF;
  IF has_function_privilege('anon', v_fn, 'EXECUTE')
     OR has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_POSTCHECK_PUBLIC_EXECUTE';
  END IF;
  -- Negative boundary: the wrapper must not come with table access.
  IF has_table_privilege('lf_ci_readonly', 'public.lf_qualification_receipts', 'SELECT')
     OR has_table_privilege('lf_ci_readonly', 'public.lf_operation_effect_guard', 'SELECT') THEN
    RAISE EXCEPTION 'LF_MERGE_GATE_RO_POSTCHECK_TABLE_ACCESS_WIDENED';
  END IF;
END
$post$;
