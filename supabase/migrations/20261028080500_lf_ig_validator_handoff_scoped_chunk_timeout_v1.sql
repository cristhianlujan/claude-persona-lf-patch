-- Validator's currently-used handoff-aware PostgREST RPC has no function
-- statement_timeout override, so its first 10-family chunk hits
-- authenticator's 8-second limit with PostgreSQL 57014.
-- Existing measured validator chunks: run 511 max 28,567 ms; run 833
-- max 29,288 ms; 45 s gives ~1.5x headroom. This is not the
-- monolithic 385 s Validator budget: existing Edge chunk/continuation
-- controls remain responsible for the 47-family run.
-- No timeout changes to roles, internal schema or unrelated public RPCs.
DO $guard$
DECLARE
 v_rpc oid := to_regprocedure('public.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)');
 v_cfg text;
BEGIN
 IF v_rpc IS NULL THEN RAISE EXCEPTION 'IG_VALIDATOR_HANDOFF_RPC_MISSING'; END IF;
 IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_rpc)
    OR NOT has_function_privilege('service_role',v_rpc,'EXECUTE')
    OR has_function_privilege('anon',v_rpc,'EXECUTE')
    OR has_function_privilege('authenticated',v_rpc,'EXECUTE')
 THEN RAISE EXCEPTION 'IG_VALIDATOR_HANDOFF_RPC_AUTHORITY_DRIFT'; END IF;
 SELECT substring(x FROM '^statement_timeout=(.*)$') INTO v_cfg
 FROM pg_proc p CROSS JOIN LATERAL unnest(coalesce(p.proconfig,ARRAY[]::text[])) x
 WHERE p.oid=v_rpc AND x LIKE 'statement_timeout=%';
 IF v_cfg IS NOT NULL THEN
    RAISE EXCEPTION 'IG_VALIDATOR_HANDOFF_RPC_TIMEOUT_UNEXPECTED:%',v_cfg;
 END IF;
END
$guard$;
ALTER FUNCTION public.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)
  SET statement_timeout TO '45s';
DO $verify$
BEGIN
 IF NOT EXISTS (
   SELECT 1 FROM pg_proc p,LATERAL unnest(p.proconfig) c
   WHERE p.oid='public.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)'::regprocedure
      AND c='statement_timeout=45s'
 ) THEN RAISE EXCEPTION 'IG_VALIDATOR_HANDOFF_RPC_TIMEOUT_POSTCHECK_FAILED'; END IF;
END
$verify$;
