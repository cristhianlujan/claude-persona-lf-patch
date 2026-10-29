-- Fix 42501 in the existing service-role-only Validator PostgREST bridge.
-- Both public entrypoints were SECURITY INVOKER. The configured service_role
-- deliberately has no USAGE on programacion, so the invoker cannot call the
-- existing validated SECURITY DEFINER implementations.
-- Preserve the schema boundary: change only the *two exact* public wrappers
-- to execute with their existing postgres owner. Do NOT grant schema USAGE.
-- The underlying validator/handoff checks continue to enforce exact run
-- id, receipt verification, identity and ordered chunk semantics.
DO $guard$
DECLARE
  v_signature text;
  v_rpc oid;
  v_inner oid;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'fn_input_governance_validator_handoff_assert_v1(bigint,bigint)',
    'fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)'
  ] LOOP
    v_rpc:=to_regprocedure('public.'||v_signature);
    v_inner:=to_regprocedure('programacion.'||v_signature);
    IF v_rpc IS NULL OR v_inner IS NULL THEN
      RAISE EXCEPTION 'IG_VALIDATOR_RPC_PAIR_MISSING:%',v_signature;
    END IF;
    IF (SELECT prosecdef FROM pg_proc WHERE oid=v_rpc)
      OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_inner)
      OR (SELECT rolname FROM pg_roles WHERE oid=(SELECT proowner FROM pg_proc WHERE oid=v_rpc))<>'postgres'
      OR NOT has_function_privilege('service_role',v_rpc,'EXECUTE')
      OR has_function_privilege('anon',v_rpc,'EXECUTE')
      OR has_function_privilege('authenticated',v_rpc,'EXECUTE')
    THEN RAISE EXCEPTION 'IG_VALIDATOR_RPC_BASELINE_DRIFT:%',v_signature; END IF;
    IF has_schema_privilege('service_role','programacion','USAGE') THEN
      RAISE EXCEPTION 'IG_VALIDATOR_INTERNAL_SCHEMA_WAS_BROADENED'; END IF;
  END LOOP;
END
$guard$;

ALTER FUNCTION public.fn_input_governance_validator_handoff_assert_v1(bigint,bigint)
  SECURITY DEFINER;
ALTER FUNCTION public.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)
  SECURITY DEFINER;

DO $verify$
DECLARE
  v_signature text;
  v_rpc oid;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'fn_input_governance_validator_handoff_assert_v1(bigint,bigint)',
    'fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)'
  ] LOOP
    v_rpc:=to_regprocedure('public.'||v_signature);
    IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_rpc)
      OR NOT has_function_privilege('service_role',v_rpc,'EXECUTE')
      OR has_function_privilege('anon',v_rpc,'EXECUTE')
      OR has_function_privilege('authenticated',v_rpc,'EXECUTE')
      OR (SELECT rolname FROM pg_roles WHERE oid=(SELECT proowner FROM pg_proc WHERE oid=v_rpc))<>'postgres'
    THEN RAISE EXCEPTION 'IG_VALIDATOR_RPC_SECURITY_CONTEXT_INVALID:%',v_signature; END IF;
  END LOOP;
  IF has_schema_privilege('service_role','programacion','USAGE') THEN
    RAISE EXCEPTION 'IG_VALIDATOR_INTERNAL_SCHEMA_PRIVILEGE_DRIFT';
  END IF;
END
$verify$;
