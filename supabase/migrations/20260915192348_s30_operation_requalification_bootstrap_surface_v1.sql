-- S30-R22: bounded Operation self-requalification bootstrap.

CREATE OR REPLACE FUNCTION public.lf_operation_requalification_bootstrap_v1(
  p_execution_id text,
  p_operation_code text,
  p_route_action_code text,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_exact_source_head text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  r public.lf_operation_registry%rowtype;
  x public.lf_operation_execution%rowtype;
  reserve_result jsonb;
  qualification_result jsonb;
  rev text;
  fp text;
  target_path text;
  current_after boolean;
BEGIN
  IF btrim(coalesce(p_execution_id,''))=''
     OR btrim(coalesce(p_operation_code,''))=''
     OR btrim(coalesce(p_route_action_code,''))=''
     OR coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$'
     OR btrim(coalesce(p_idempotency_key,''))=''
     OR btrim(coalesce(p_actor_execution_id,''))=''
     OR coalesce(p_exact_source_head,'') !~ '^[0-9a-f]{40}$' THEN
    RAISE EXCEPTION 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_INPUT_INVALID';
  END IF;

  SELECT * INTO r FROM public.lf_operation_registry WHERE operation_code=p_operation_code;
  IF NOT FOUND OR r.lifecycle_state_code IS DISTINCT FROM 'OP_OPERATIONAL' THEN
    RAISE EXCEPTION 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_TARGET_INVALID:%',p_operation_code;
  END IF;
  IF btrim(coalesce(r.applies_to_asset_type,''))='' THEN
    RAISE EXCEPTION 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_ROUTE_SCOPE_MISSING:%',p_operation_code;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_router_action_registry a
    WHERE a.asset_type=r.applies_to_asset_type
      AND a.action_code=p_route_action_code
      AND a.operation_code=p_operation_code
      AND a.status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_ROUTE_INVALID:%:%',p_operation_code,p_route_action_code;
  END IF;

  rev:=public.lf_operation_revision_sha256_v1(p_operation_code);
  fp:=public.lf_required_test_suite_fingerprint_v1('OPERATION',p_operation_code);
  IF public.lf_qualification_current_v1('OPERATION',p_operation_code,rev) THEN
    RAISE EXCEPTION 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_NOT_NEEDED:%',p_operation_code;
  END IF;

  target_path:='supabase://public/lf_operation_registry/'||p_operation_code;
  reserve_result:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,p_operation_code,'OPERATION',p_operation_code,
    p_idempotency_key,p_request_sha256,p_actor_execution_id,NULL,target_path,
    jsonb_build_object(
      'mode','OPERATION_REQUALIFICATION_BOOTSTRAP_ONLY',
      'operation_requalification_bootstrap_only',true,
      'qualification_target_operation',p_operation_code,
      'qualification_target_revision_sha256',rev,
      'qualification_target_suite_fingerprint',fp,
      'route_binding',jsonb_build_object('asset_type',r.applies_to_asset_type,'action_code',p_route_action_code,'operation_code',p_operation_code),
      'exact_source_head',p_exact_source_head,
      'runtime_activation',false,
      'production_activation',false
    )
  );

  SELECT * INTO x FROM public.lf_operation_execution
  WHERE execution_id=reserve_result->>'execution_id' FOR UPDATE;
  IF NOT FOUND OR x.status<>'IN_PROGRESS'
     OR x.operation_code IS DISTINCT FROM p_operation_code
     OR x.target_type IS DISTINCT FROM 'OPERATION'
     OR x.target_code IS DISTINCT FROM p_operation_code
     OR x.target_path IS DISTINCT FROM target_path THEN
    RAISE EXCEPTION 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_EXECUTION_BINDING_INVALID';
  END IF;
  IF coalesce(x.manifest->>'operation_policy_source','')<>'SUPABASE'
     OR jsonb_typeof(x.manifest->'operation_policy_snapshots') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_POLICY_SNAPSHOT_MISSING';
  END IF;
  IF rev IS DISTINCT FROM public.lf_operation_revision_sha256_v1(p_operation_code)
     OR fp IS DISTINCT FROM public.lf_required_test_suite_fingerprint_v1('OPERATION',p_operation_code) THEN
    RAISE EXCEPTION 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_TARGET_CHANGED:%',p_operation_code;
  END IF;

  qualification_result:=public.lf_run_operation_qualification_v1(p_operation_code,x.execution_id);
  current_after:=public.lf_qualification_current_v1('OPERATION',p_operation_code,rev);

  UPDATE public.lf_operation_execution
     SET status='COMPLETED',completed_at=clock_timestamp(),updated_by_execution_id=p_actor_execution_id,
         manifest=manifest||jsonb_build_object(
           'qualification_bootstrap_result',qualification_result,
           'qualification_current_after_runner',current_after,
           'qualification_bootstrap_closed',true,
           'runtime_activation',false,'production_activation',false
         )
   WHERE execution_id=x.execution_id;

  RETURN jsonb_build_object(
    'execution_id',x.execution_id,
    'operation_code',p_operation_code,
    'revision_sha256',rev,
    'suite_set_fingerprint',fp,
    'qualification',qualification_result,
    'qualification_current',current_after,
    'exact_source_head',p_exact_source_head,
    'bootstrap_execution_status','COMPLETED'
  );
END
$function$;
