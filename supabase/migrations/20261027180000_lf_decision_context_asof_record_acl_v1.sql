-- DECISION_CONTEXT_ASOF: restrict the as-of writer to the service role.
--
-- public.fn_lf_decision_context_asof_record_v1(jsonb,text) is SECURITY DEFINER and
-- was created without explicit grants, so it inherited EXECUTE for PUBLIC and the
-- Supabase default privileges for anon and authenticated. Any holder of the
-- publishable key could record an append-only decision context and attribute it to
-- an arbitrary p_actor_execution_id. The PG-01 runtime writer (#3193) relies on
-- created_by_execution_id to prove that a snapshot came from its source execution.
--
-- This migration changes privileges and sets the function comment. It does not change
-- the function body, its search_path, its SECURITY DEFINER mode, the store, the
-- resolver or any row.
-- Residual trust boundary: service_role can still declare any actor id. That is
-- documented in DECISION_CONTEXT_ASOF_RECORD_ACL_V1.md and is not closed here.

REVOKE ALL ON FUNCTION public.fn_lf_decision_context_asof_record_v1(jsonb, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_lf_decision_context_asof_record_v1(jsonb, text)
  TO service_role;

COMMENT ON FUNCTION public.fn_lf_decision_context_asof_record_v1(jsonb, text) IS
  'DECISION_CONTEXT_ASOF writer. EXECUTE restricted to service_role (and owner). p_actor_execution_id is declared by the caller, not verified.';

-- Effective-privilege assertions. has_function_privilege includes privileges inherited
-- through role membership, so a revoke that only changes the ACL text cannot pass.
-- It does not see SET-only memberships (PG16+, INHERIT FALSE); PostgREST clients
-- cannot issue SET ROLE. The PUBLIC and service_role checks guard against edits to
-- the statements above; they cannot fire while those statements are unchanged.
DO $assert$
DECLARE
  v_fn constant regprocedure := 'public.fn_lf_decision_context_asof_record_v1(jsonb,text)'::regprocedure;
  v_acl aclitem[];
BEGIN
  SELECT proacl INTO v_acl FROM pg_catalog.pg_proc WHERE oid = v_fn;
  IF EXISTS (SELECT 1 FROM pg_catalog.aclexplode(v_acl) a WHERE a.grantee = 0) THEN
    RAISE EXCEPTION 'LF_ASOF_RECORD_ACL_PUBLIC_STILL_GRANTED';
  END IF;
  IF pg_catalog.has_function_privilege('anon', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'LF_ASOF_RECORD_ACL_ANON_STILL_EFFECTIVE';
  END IF;
  IF pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'LF_ASOF_RECORD_ACL_AUTHENTICATED_STILL_EFFECTIVE';
  END IF;
  IF NOT pg_catalog.has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'LF_ASOF_RECORD_ACL_SERVICE_ROLE_MISSING';
  END IF;
END
$assert$;
