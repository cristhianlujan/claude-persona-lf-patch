-- LF PE10 v0.2 -- helper RPC ACL hardening only.
-- Repair direct EXECUTE grants inherited from PostgreSQL default privileges.
-- No function bodies, operation steps, policies or execution state are modified.
-- EKB precedent: CARD-UPDATE-VALIDATOR-ACL-DIRECT-GRANT-001.
-- Source-first; apply via canonical LF Migration Train only.
BEGIN;

REVOKE EXECUTE ON FUNCTION public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.lf_profile_update_effective_route_v1(text)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.lf_profile_update_evolution_step_guard_v1(text,text,jsonb)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_profile_update_effective_route_v1(text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_profile_update_evolution_step_guard_v1(text,text,jsonb)
  TO service_role;

DO $pe10_acl$
DECLARE
  v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)',
    'public.lf_profile_update_effective_route_v1(text)',
    'public.lf_profile_update_evolution_step_guard_v1(text,text,jsonb)'
  ]
  LOOP
    IF to_regprocedure(v_fn) IS NULL THEN
      RAISE EXCEPTION 'PE10_HELPER_ACL_FUNCTION_MISSING:%', v_fn;
    END IF;
    IF has_function_privilege('anon',v_fn,'EXECUTE')
       OR has_function_privilege('authenticated',v_fn,'EXECUTE')
       OR NOT has_function_privilege('service_role',v_fn,'EXECUTE')
    THEN RAISE EXCEPTION 'PE10_HELPER_ACL_HARDENING_FAILED:%', v_fn; END IF;
  END LOOP;
END
$pe10_acl$;
COMMIT;
