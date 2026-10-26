-- Retire obsolete PRODUCTO-only profile entrypoints after channel-neutral cutover.
BEGIN;

DO $precheck$
DECLARE
  v_dep_count integer;
BEGIN
  IF to_regprocedure(
       'public.lf_router_profile_after_selection_v1(jsonb,jsonb)'
     ) IS NULL
     OR to_regprocedure(
       'public.lf_router_profile_after_selection_raw_v1(jsonb,text)'
     ) IS NULL
     OR to_regprocedure(
       'public.lf_router_profile_gate2_result_from_selection_v1(jsonb,jsonb)'
     ) IS NULL
  THEN
    RAISE EXCEPTION 'LEGACY_PRODUCT_ENTRYPOINT_RETIRE_CANONICAL_MISSING';
  END IF;

  SELECT count(*) INTO v_dep_count
  FROM pg_proc target
  JOIN pg_namespace tn ON tn.oid=target.pronamespace
  JOIN pg_depend d ON d.refobjid=target.oid
  JOIN pg_proc consumer ON consumer.oid=d.objid
  WHERE tn.nspname='public'
    AND target.proname IN (
      'lf_router_product_profile_after_selection_v1',
      'lf_router_product_profile_after_selection_raw_v1',
      'lf_router_product_gate2_result_from_selection_v1'
    )
    AND d.classid='pg_proc'::regclass;

  IF v_dep_count<>0 THEN
    RAISE EXCEPTION 'LEGACY_PRODUCT_ENTRYPOINT_RETIRE_ACTIVE_DEPENDENCIES:%',
      v_dep_count;
  END IF;

  IF strpos(
       pg_get_functiondef(
         'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)'::regprocedure
       ),
       'lf_router_product_'
     )>0
  THEN
    RAISE EXCEPTION 'LEGACY_PRODUCT_ENTRYPOINT_RETIRE_NATIVE_BRIDGE_STILL_REFERENCES_LEGACY';
  END IF;

  IF strpos(
       pg_get_functiondef(
         'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
       ),
       'public.lf_router_product_profile_after_selection_raw_v1'
     )>0
  THEN
    RAISE EXCEPTION 'LEGACY_PRODUCT_ENTRYPOINT_RETIRE_ROUTE_STILL_REFERENCES_LEGACY_RAW';
  END IF;
END
$precheck$;

DROP FUNCTION public.lf_router_product_profile_after_selection_v1(jsonb,jsonb);
DROP FUNCTION public.lf_router_product_profile_after_selection_raw_v1(jsonb,text);
DROP FUNCTION public.lf_router_product_gate2_result_from_selection_v1(jsonb,jsonb);

DO $postcheck$
DECLARE
  v_refs integer;
BEGIN
  IF to_regprocedure(
       'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)'
     ) IS NOT NULL
     OR to_regprocedure(
       'public.lf_router_product_profile_after_selection_raw_v1(jsonb,text)'
     ) IS NOT NULL
     OR to_regprocedure(
       'public.lf_router_product_gate2_result_from_selection_v1(jsonb,jsonb)'
     ) IS NOT NULL
  THEN
    RAISE EXCEPTION 'LEGACY_PRODUCT_ENTRYPOINT_RETIRE_DROP_FAILED';
  END IF;

  IF to_regprocedure(
       'public.lf_router_profile_after_selection_v1(jsonb,jsonb)'
     ) IS NULL
     OR to_regprocedure(
       'public.lf_router_profile_after_selection_raw_v1(jsonb,text)'
     ) IS NULL
     OR to_regprocedure(
       'public.lf_router_profile_gate2_result_from_selection_v1(jsonb,jsonb)'
     ) IS NULL
     OR to_regprocedure(
       'public.lf_router_profile_execution_after_gate2_v1(jsonb,jsonb,text,text,jsonb,text,text,text)'
     ) IS NULL
  THEN
    RAISE EXCEPTION 'LEGACY_PRODUCT_ENTRYPOINT_RETIRE_CANONICAL_POSTCHECK_FAILED';
  END IF;

  SELECT count(*) INTO v_refs
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE p.prokind='f'
    AND (
      p.prosrc ILIKE '%lf_router_product_profile_after_selection_v1%'
      OR p.prosrc ILIKE '%lf_router_product_profile_after_selection_raw_v1%'
      OR p.prosrc ILIKE '%lf_router_product_gate2_result_from_selection_v1%'
    );

  IF v_refs<>0 THEN
    RAISE EXCEPTION 'LEGACY_PRODUCT_ENTRYPOINT_RETIRE_RUNTIME_SOURCE_REFS:%',v_refs;
  END IF;

  IF NOT has_function_privilege(
       'service_role',
       'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION 'LEGACY_PRODUCT_ENTRYPOINT_RETIRE_BRIDGE_ACL_REGRESSION';
  END IF;
END
$postcheck$;

COMMIT;
