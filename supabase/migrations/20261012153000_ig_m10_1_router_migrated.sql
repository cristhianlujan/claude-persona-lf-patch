-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M10.1 / ROUTER_MIGRATED
-- The Router is a consumer: it must use public IG facades, not private IG calls.
-- Reuse public.fn_input_governance_execute. Add only missing read-only, role-restricted facades.
-- Repair checkpoint contract + local governance with implementation in one atomic unit.
-- No changes to IG private implementations, to allowed consumers, to release or runtime.
DO $m101router$
DECLARE
  v_unit_id bigint;
  v_metadata jsonb;
  v_spec jsonb;
  v_objects jsonb;
  v_sources jsonb;
  v_source text;
  v_new text;
  v_oid oid;
  v_after jsonb;
  v_query text := $query$
    SELECT p.oid::regprocedure::text router_signature,
      (length(p.prosrc)-length(replace(p.prosrc,'programacion.fn_input_governance_','')))
      /length('programacion.fn_input_governance_') AS private_governance_calls,
      (length(p.prosrc)-length(replace(p.prosrc,'programacion.fn_input_readiness_','')))
      /length('programacion.fn_input_readiness_') AS private_readiness_calls,
      (length(p.prosrc)-length(replace(p.prosrc,'public.fn_input_governance_','')))
      /length('public.fn_input_governance_') AS public_governance_calls,
      (length(p.prosrc)-length(replace(p.prosrc,'public.fn_input_readiness_','')))
      /length('public.fn_input_readiness_') AS public_readiness_calls
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='programacion' AND p.proname='fn_lf_router_input_governance_resolve_v1'
  $query$;
BEGIN
  SELECT u.id,u.unit_metadata INTO v_unit_id,v_metadata
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.1'
    AND c.checkpoint_code='ROUTER_MIGRATED' AND c.status='PENDING'
  FOR UPDATE OF u;
  IF v_unit_id IS NULL OR v_metadata ? 'm10_1_router_facade_governance_v1'
  THEN RAISE EXCEPTION 'M101_CP4_PRESTATE_MISMATCH'; END IF;
  v_spec:=v_metadata#>'{action_specs_v1,ROUTER_MIGRATED}';
  IF v_spec->>'recipe_mode' IS DISTINCT FROM 'GIT_FIRST_MIGRATION'
     OR v_spec#>>'{authoring_contract,runtime_activation}' IS DISTINCT FROM 'NOT_IMPLIED'
     OR v_spec#>>'{assertion_contract,pass_when,git_merged}' IS DISTINCT FROM 'true'
     OR v_metadata#>>'{m10_1_consumer_inventory_governance_v1,classification}'
        IS DISTINCT FROM 'ENGINEERING_SANDBOX_INVENTORY'
  THEN RAISE EXCEPTION 'M101_CP4_ACTION_SPEC_OR_CP3_GOVERNANCE_DRIFT'; END IF;
  IF (SELECT coalesce(metadata->>'runtime_authorized','false') <> 'false'
       OR coalesce(metadata->>'production_authorized','false') <> 'false'
      FROM public.lf_activos WHERE codigo_activo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')
  THEN RAISE EXCEPTION 'M101_ROUTER_SANDBOX_BOUNDARY_NOT_SATISFIED'; END IF;

  IF to_regprocedure('public.fn_input_governance_worker_spec(integer,text)') IS NOT NULL
    OR to_regprocedure('public.fn_input_readiness_run_is_current(bigint)') IS NOT NULL
  THEN RAISE EXCEPTION 'M101_FACADE_ALREADY_PRESENT_RECONCILE_SOURCE_FIRST'; END IF;
  SELECT p.oid,pg_get_functiondef(p.oid) INTO v_oid,v_source
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='programacion'
       AND p.proname='fn_lf_router_input_governance_resolve_v1'
       AND p.oid::regprocedure::text =
          'programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)';
  IF v_oid IS NULL THEN RAISE EXCEPTION 'M101_ROUTER_SIGNATURE_MISSING'; END IF;
  IF (length(v_source)-length(replace(v_source,'programacion.fn_input_governance_worker_spec(','')))
      /length('programacion.fn_input_governance_worker_spec(') <> 3
    OR (length(v_source)-length(replace(v_source,'programacion.fn_input_governance_execute(','')))
      /length('programacion.fn_input_governance_execute(') <> 1
    OR (length(v_source)-length(replace(v_source,'programacion.fn_input_readiness_run_is_current(','')))
      /length('programacion.fn_input_readiness_run_is_current(') <> 1
  THEN RAISE EXCEPTION 'M101_ROUTER_PRIVATE_CALL_FINGERPRINT_CHANGED'; END IF;

  -- Minimal purpose-bound façades (SECURITY INVOKER; no new data authorities).
  EXECUTE $create_worker$
    CREATE FUNCTION public.fn_input_governance_worker_spec(
      p_pantalla_id integer, p_consumer text DEFAULT 'STORY_CREATOR'::text)
    RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
    SET search_path TO 'pg_catalog','programacion'
    AS $function$
       SELECT programacion.fn_input_governance_worker_spec(p_pantalla_id,p_consumer)
    $function$
  $create_worker$;
  EXECUTE 'REVOKE ALL ON FUNCTION public.fn_input_governance_worker_spec(integer,text) FROM PUBLIC,anon,authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.fn_input_governance_worker_spec(integer,text) TO service_role';

  EXECUTE $create_current$
    CREATE FUNCTION public.fn_input_readiness_run_is_current(p_run_id bigint)
    RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER
    SET search_path TO 'pg_catalog','programacion'
    AS $function$
       SELECT programacion.fn_input_readiness_run_is_current(p_run_id)
    $function$
  $create_current$;
  EXECUTE 'REVOKE ALL ON FUNCTION public.fn_input_readiness_run_is_current(bigint) FROM PUBLIC,anon,authenticated,service_role';
  -- Not exposed to service_role: underlying private run-currentness capability
  -- is not granted to service_role. Owner-only invocation from governed Router.

  v_new:=replace(v_source,
            'programacion.fn_input_governance_worker_spec(',
            'public.fn_input_governance_worker_spec(');
  v_new:=replace(v_new,
            'programacion.fn_input_governance_execute(',
            'public.fn_input_governance_execute(');
  v_new:=replace(v_new,
            'programacion.fn_input_readiness_run_is_current(',
            'public.fn_input_readiness_run_is_current(');
  EXECUTE v_new;

  IF EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_oid
     AND (p.prosrc LIKE '%programacion.fn_input_governance_%'
       OR p.prosrc LIKE '%programacion.fn_input_readiness_%'))
  THEN RAISE EXCEPTION 'M101_ROUTER_STILL_REFERENCES_PRIVATE_IG'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_oid
     AND p.prosrc LIKE '%public.fn_input_governance_execute(%'
     AND p.prosrc LIKE '%public.fn_input_governance_worker_spec(%'
     AND p.prosrc LIKE '%public.fn_input_readiness_run_is_current(%')
  THEN RAISE EXCEPTION 'M101_ROUTER_PUBLIC_FACADES_NOT_RESOLVED'; END IF;
  IF has_function_privilege('anon',
       'public.fn_input_governance_worker_spec(integer,text)','EXECUTE')
     OR has_function_privilege('authenticated',
       'public.fn_input_governance_worker_spec(integer,text)','EXECUTE')
     OR has_function_privilege('anon',
       'public.fn_input_readiness_run_is_current(bigint)','EXECUTE')
     OR has_function_privilege('authenticated',
       'public.fn_input_readiness_run_is_current(bigint)','EXECUTE')
     OR has_function_privilege('service_role',
       'public.fn_input_readiness_run_is_current(bigint)','EXECUTE')
  THEN RAISE EXCEPTION 'M101_NEW_FACADE_PUBLIC_ROLE_EXPOSURE'; END IF;

  v_objects:=(v_spec#>'{authoring_contract,db_targets_exact}') ||
   jsonb_build_array('public.fn_input_governance_worker_spec',
                      'public.fn_input_readiness_run_is_current');
  v_spec:=jsonb_set(v_spec,'{authoring_contract,db_targets_exact}',v_objects,true);
  v_objects:=(v_spec#>'{target,declared_objects}') ||
   jsonb_build_array('public.fn_input_governance_worker_spec',
                      'public.fn_input_readiness_run_is_current');
  v_spec:=jsonb_set(v_spec,'{target,declared_objects}',v_objects,true);
  v_spec:=jsonb_set(v_spec,'{expected}',to_jsonb(
    'Sandbox technical migration of the existing Router to public IG facades. Preserve live consumer allowlist, behavior, grants and runtime/release state. CP4 proves Router source readback, NOT independent operational/live runtime admission.'::text),true);
  v_spec:=jsonb_set(v_spec,'{assertion_contract,pass_when}',
     (v_spec#>'{assertion_contract,pass_when}') ||
      jsonb_build_object('private_internal_refs',0,
         'public_facades_verified',true,'consumer_allowlist_preserved',true,
         'runtime_unchanged',true,'no_new_anon_or_authenticated_grants',true),true);
  v_spec:=jsonb_set(v_spec,'{verification_queries}',jsonb_build_array(v_query),true);
  v_metadata:=jsonb_set(v_metadata,'{action_specs_v1,ROUTER_MIGRATED}',v_spec,true);
  v_sources:=v_metadata#>'{source_pack_v1,checkpoint_inputs,ROUTER_MIGRATED,inputs,db_objects}';
  v_metadata:=jsonb_set(v_metadata,
     '{source_pack_v1,checkpoint_inputs,ROUTER_MIGRATED,inputs,db_objects}',
     coalesce(v_sources,'[]'::jsonb) || jsonb_build_array(
     'public.fn_input_governance_worker_spec',
     'public.fn_input_readiness_run_is_current'),true);
  v_metadata:=jsonb_set(v_metadata,
     '{source_pack_v1,checkpoint_inputs,ROUTER_MIGRATED,inputs,queries}',
     jsonb_build_array(v_query),true);
  v_metadata:=jsonb_set(v_metadata,'{m10_1_router_facade_governance_v1}',
    jsonb_build_object(
       'schema_version','IG_M101_ROUTER_FACADE_BOUNDARY_V1',
       'phase','ENGINEERING_SANDBOX_ROUTER_SOURCE_MIGRATION',
       'validation_owner','IG_CHECKPOINT_EXECUTOR',
       'consumer_authority','programacion.contratos.INPUT_GOVERNANCE_EXECUTION_CONTRACT.allowed_consumers',
       'private_IG_callers','NO_DIRECT_OUTBOUND_CALLS_FROM_ROUTER',
       'public_facades','EXECUTE_EXISTING_AND_TWO_MINIMAL_READ_ONLY_ROLE_RESTRICTED',
       'runtime_activation',false,'production_activation',false,
       'operational_admission','INDEPENDENT_NOT_IMPLIED',
       'negative_scope','DISTINGUISH_PRIVATE_IMPLEMENTATION_AND_PUBLIC_FACADES',
       'currentness_service_role_grant',false),true);

  UPDATE programacion.engineering_plan_units SET unit_metadata=v_metadata WHERE id=v_unit_id;
  v_after:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.1');
  IF v_after->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
    OR v_after#>>'{execution_packet,status}' IS DISTINCT FROM 'READY'
    OR v_after#>>'{execution_packet,assertion_contract,status}' IS DISTINCT FROM 'READY'
  THEN RAISE EXCEPTION 'M101_POST_MIGRATION_CHECKPOINT_PACKET_NOT_READY:%',
       v_after#>>'{execution_packet,status}'; END IF;
END $m101router$;
