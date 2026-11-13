-- B12/G08 rollback PLAN ONLY. Never apply directly to live; use separate governed migration.
-- Only valid for the exact deployed UP state; fails closed if unexpected drift.
BEGIN;
DO $b12_rollback_preflight$
DECLARE v_oid oid;
BEGIN
  v_oid:=to_regprocedure('public.lf_rule_promotion_guard_v1()');
  IF v_oid IS NULL OR md5(pg_get_functiondef(v_oid)) IS DISTINCT FROM 'ee782e4bd0128c80ee13881899c0d74e'
     OR (SELECT proacl::text FROM pg_proc WHERE oid=v_oid) IS DISTINCT FROM
        '{postgres=X/postgres,service_role=X/postgres}'
  THEN RAISE EXCEPTION 'B12_G08_ROLLBACK_PREIMAGE_DRIFT'; END IF;
END $b12_rollback_preflight$;

GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_guard_v1()
TO PUBLIC, anon, authenticated;

DO $b12_rollback_readback$
DECLARE v_oid oid;
BEGIN
  v_oid:=to_regprocedure('public.lf_rule_promotion_guard_v1()');
  IF (SELECT proacl::text FROM pg_proc WHERE oid=v_oid) IS DISTINCT FROM
       '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
     OR NOT has_function_privilege('anon',v_oid,'EXECUTE')
     OR NOT has_function_privilege('authenticated',v_oid,'EXECUTE')
     OR NOT has_function_privilege('service_role',v_oid,'EXECUTE')
  THEN RAISE EXCEPTION 'B12_G08_ROLLBACK_READBACK_FAILED'; END IF;
END $b12_rollback_readback$;
COMMIT;
