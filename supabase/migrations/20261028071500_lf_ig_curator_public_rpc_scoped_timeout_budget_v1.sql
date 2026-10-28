-- IG Curator runtime remediation: fail-closed, narrowly-scoped RPC budget.
-- Evidence:
--   public.fn_input_governance_curator_materialize_v1 is the PostgREST entrypoint.
--   Its prior 30-second function-local limit caused PostgreSQL 57014.
--   pg_stat_statements: 7 post-fastpath Curator calls: mean 33.0 s, max 57.7 s.
--   90 s provides 1.55x headroom over the observed maximum, without touching
--   role/global settings, validators, unrelated operations, or source data.
--   The Curator remains atomic, retains its per-screen advisory transaction
--   lock, identity validation, receipts and fail-closed transaction semantics.
-- If longer runs exceed the scoped budget, diagnose and optimize the
-- specific slow stage; do not automatically escalate timeout or retry.
DO $guard$
DECLARE
  v_rpc oid := to_regprocedure('public.fn_input_governance_curator_materialize_v1(integer,text,text)');
  v_impl oid := to_regprocedure('programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)');
  v_timeout text;
  v_impl_timeout text;
BEGIN
  IF v_rpc IS NULL OR v_impl IS NULL THEN
    RAISE EXCEPTION 'IG_CURATOR_TIMEOUT_TARGET_UNRESOLVED';
  END IF;
  SELECT substring(x FROM '^statement_timeout=(.*)$')
    INTO v_timeout
    FROM pg_proc p CROSS JOIN LATERAL unnest(coalesce(p.proconfig,ARRAY[]::text[])) x
   WHERE p.oid = v_rpc AND x LIKE 'statement_timeout=%';
  IF v_timeout IS DISTINCT FROM '30s' THEN
    RAISE EXCEPTION 'IG_CURATOR_TIMEOUT_BASELINE_DRIFT:%',coalesce(v_timeout,'NULL');
  END IF;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_rpc)
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_impl)
  THEN RAISE EXCEPTION 'IG_CURATOR_DEFINER_AUTHORITY_MISSING'; END IF;
  SELECT substring(x FROM '^statement_timeout=(.*)$')
    INTO v_impl_timeout
    FROM pg_proc p CROSS JOIN LATERAL unnest(coalesce(p.proconfig,ARRAY[]::text[])) x
   WHERE p.oid = v_impl AND x LIKE 'statement_timeout=%';
  IF v_impl_timeout IS NOT NULL THEN
    RAISE EXCEPTION 'IG_CURATOR_INTERNAL_TIMEOUT_OVERRIDE_NOT_ALLOWED:%',v_impl_timeout;
  END IF;
END
$guard$;

ALTER FUNCTION public.fn_input_governance_curator_materialize_v1(integer,text,text)
  SET statement_timeout TO '90s';

DO $verify$
DECLARE
  v_rpc oid := 'public.fn_input_governance_curator_materialize_v1(integer,text,text)'::regprocedure;
  v_timeout text;
BEGIN
  SELECT substring(x FROM '^statement_timeout=(.*)$') INTO v_timeout
  FROM pg_proc p CROSS JOIN LATERAL unnest(coalesce(p.proconfig,ARRAY[]::text[])) x
  WHERE p.oid=v_rpc AND x LIKE 'statement_timeout=%';
  IF v_timeout IS DISTINCT FROM '90s' THEN
    RAISE EXCEPTION 'IG_CURATOR_SCOPED_TIMEOUT_NOT_INSTALLED:%',coalesce(v_timeout,'NULL');
  END IF;
  IF (SELECT count(*) FROM pg_proc WHERE oid=v_rpc) <> 1 THEN
    RAISE EXCEPTION 'IG_CURATOR_RPC_MISSING_AFTER_ALTER';
  END IF;
END
$verify$;
