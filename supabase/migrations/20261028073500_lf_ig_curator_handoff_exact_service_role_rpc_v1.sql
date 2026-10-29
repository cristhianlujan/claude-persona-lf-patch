-- PostgREST integration repair: Curator's Edge caller requires the
-- canonical handoff receipt RPC, but only the programacion implementation
-- exists. Expose the *same* verification under public for service_role only.
-- The implementation verifies the run, identity, family set and receipt.
-- It reuses a persisted receipt if present. No new receipt algorithm,
-- EKB bypass, service-role grant to anon, or profile-specific behavior.
DO $guard$
BEGIN
  IF to_regprocedure('public.fn_input_governance_curator_handoff_receipt_v1(bigint,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'IG_CURATOR_PUBLIC_HANDOFF_ALREADY_EXISTS_REVIEW_BEFORE_OVERWRITE';
  END IF;
  IF to_regprocedure('programacion.fn_input_governance_curator_handoff_receipt_v1(bigint,text)') IS NULL
  THEN RAISE EXCEPTION 'IG_CURATOR_CANONICAL_HANDOFF_UNRESOLVED'; END IF;
  IF NOT has_function_privilege('service_role',
    'programacion.fn_input_governance_curator_handoff_receipt_v1(bigint,text)'::regprocedure,
    'EXECUTE')
  THEN RAISE EXCEPTION 'IG_CURATOR_CANONICAL_HANDOFF_SERVICE_ROLE_DENIED'; END IF;
END
$guard$;

CREATE FUNCTION public.fn_input_governance_curator_handoff_receipt_v1(
  p_run_id bigint,
  p_expected_curator_identity text
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path TO 'pg_catalog', 'programacion'
SET statement_timeout TO '20s'
AS $function$
  SELECT programacion.fn_input_governance_curator_handoff_receipt_v1(
    p_run_id, p_expected_curator_identity
  )
$function$;

REVOKE ALL ON FUNCTION public.fn_input_governance_curator_handoff_receipt_v1(bigint,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_input_governance_curator_handoff_receipt_v1(bigint,text)
  TO service_role;

DO $verify$
DECLARE
  v_rpc oid := 'public.fn_input_governance_curator_handoff_receipt_v1(bigint,text)'::regprocedure;
BEGIN
  IF (SELECT prosecdef FROM pg_proc WHERE oid=v_rpc)
     OR NOT has_function_privilege('service_role',v_rpc,'EXECUTE')
     OR has_function_privilege('anon',v_rpc,'EXECUTE')
     OR has_function_privilege('authenticated',v_rpc,'EXECUTE')
     OR (SELECT pg_get_function_result(v_rpc)) <> 'jsonb'
  THEN RAISE EXCEPTION 'IG_CURATOR_PUBLIC_HANDOFF_ACL_OR_CONTRACT_INVALID'; END IF;
END
$verify$;
