-- ACT-0001 hotfix: align Product helper/cycle ACLs with the governed Router readers.
-- #3138 introduced the Product context helper and cycle, but default/explicit ACLs
-- left the helper callable by anon/authenticated while supabase_read_only_user
-- could call lf_router_route_v1 but not the nested helper. This migration fixes
-- both the security exposure and the governed read-only route regression.
BEGIN;

REVOKE ALL ON FUNCTION public.lf_router_product_context_v1(text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_router_product_cycle_v1(jsonb) FROM PUBLIC;

DO $acl$
DECLARE
  v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role','supabase_read_only_user'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format(
        'REVOKE ALL ON FUNCTION public.lf_router_product_context_v1(text,jsonb) FROM %I',
        v_role
      );
      EXECUTE format(
        'REVOKE ALL ON FUNCTION public.lf_router_product_cycle_v1(jsonb) FROM %I',
        v_role
      );
    END IF;
  END LOOP;

  FOREACH v_role IN ARRAY ARRAY['service_role','supabase_read_only_user'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format(
        'GRANT EXECUTE ON FUNCTION public.lf_router_product_context_v1(text,jsonb) TO %I',
        v_role
      );
      EXECUTE format(
        'GRANT EXECUTE ON FUNCTION public.lf_router_product_cycle_v1(jsonb) TO %I',
        v_role
      );
    END IF;
  END LOOP;
END
$acl$;

COMMENT ON FUNCTION public.lf_router_product_context_v1(text,jsonb) IS
'ACT-0001 governed read-only Product context loader. SECURITY DEFINER is restricted to postgres/service_role/supabase_read_only_user; anon/authenticated are denied.';

COMMENT ON FUNCTION public.lf_router_product_cycle_v1(jsonb) IS
'ACT-0001 read-only Product structural-cycle transition resolver. Execution is restricted to governed Router readers; it does not authorize effects.';

DO $test$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r)
       AND has_function_privilege(r,'public.lf_router_product_context_v1(text,jsonb)','EXECUTE') THEN
      RAISE EXCEPTION 'PRODUCT_CONTEXT_UNSAFE_EXECUTE_ROLE:%',r;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r)
       AND has_function_privilege(r,'public.lf_router_product_cycle_v1(jsonb)','EXECUTE') THEN
      RAISE EXCEPTION 'PRODUCT_CYCLE_UNSAFE_EXECUTE_ROLE:%',r;
    END IF;
  END LOOP;

  FOREACH r IN ARRAY ARRAY['service_role','supabase_read_only_user'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r)
       AND NOT has_function_privilege(r,'public.lf_router_product_context_v1(text,jsonb)','EXECUTE') THEN
      RAISE EXCEPTION 'PRODUCT_CONTEXT_GOVERNED_READER_MISSING:%',r;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r)
       AND NOT has_function_privilege(r,'public.lf_router_product_cycle_v1(jsonb)','EXECUTE') THEN
      RAISE EXCEPTION 'PRODUCT_CYCLE_GOVERNED_READER_MISSING:%',r;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='lf_router_product_context_v1'
      AND p.prosecdef IS TRUE
  ) THEN
    RAISE EXCEPTION 'PRODUCT_CONTEXT_SECURITY_DEFINER_EXPECTED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='lf_router_route_v1'
      AND p.prosecdef IS TRUE
  ) THEN
    RAISE EXCEPTION 'ROUTER_ROUTE_MUST_NOT_BE_SECURITY_DEFINER';
  END IF;
END
$test$;

COMMIT;
