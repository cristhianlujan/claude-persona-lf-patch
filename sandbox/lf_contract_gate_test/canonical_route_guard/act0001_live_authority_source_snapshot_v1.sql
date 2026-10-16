-- READ-ONLY source snapshot from Supabase main, 2026-10-16.
-- Exact function bodies were obtained through pg_get_functiondef.
-- Included only inside an ephemeral PG17 transaction and rolled back.
-- Dependencies other than the two functions below are sandbox stubs.

CREATE OR REPLACE FUNCTION public.lf_router_downstream_authority_consumer_v1(p_operation_code text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select coalesce(
    (
      select case
        when jsonb_typeof(a.metadata #> '{transversal_inventory,consumers_known}')='array'
        then (a.metadata #> '{transversal_inventory,consumers_known}') ? p_operation_code
        when jsonb_typeof(a.metadata #> '{transversal_inventory,consumers_known}')='string'
        then (a.metadata #>> '{transversal_inventory,consumers_known}')=p_operation_code
        else false
      end
      from public.lf_activos a
      where a.codigo_activo='ROUTER_DOWNSTREAM_AUTHORITY'
        and a.archived_at is null
        and a.estado_operativo='ACTIVO'
      limit 1
    ),
    false
  );
$function$;

CREATE OR REPLACE FUNCTION public.lf_router_downstream_authority_validate_v1(p_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_receipt jsonb;
  v_core jsonb;
  v_expected_fp text;
  v_count integer;
  v_action text;
  v_router jsonb;
  v_current_revision text;
  v_current_binding_sha text;
begin
  select * into v_exec
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found then
    return jsonb_build_object('applicable',true,'valid',false,'code','ROUTER_AUTHORITY_EXECUTION_NOT_FOUND');
  end if;

  if not public.lf_router_downstream_authority_consumer_v1(v_exec.operation_code) then
    return jsonb_build_object(
      'applicable',false,'valid',true,'code','ROUTER_DOWNSTREAM_AUTHORITY_NOT_BOUND',
      'execution_id',v_exec.execution_id,'operation_code',v_exec.operation_code
    );
  end if;

  v_receipt := v_exec.manifest->'router_authority_receipt';
  if v_receipt is null or jsonb_typeof(v_receipt)<>'object' then
    return jsonb_build_object('applicable',true,'valid',false,'code','ROUTER_AUTHORITY_RECEIPT_MISSING');
  end if;

  if v_receipt->>'schema_version' is distinct from 'LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1'
     or v_receipt->>'execution_id' is distinct from v_exec.execution_id
     or v_receipt->>'operation_code' is distinct from v_exec.operation_code
     or v_receipt->>'target_type' is distinct from v_exec.target_type
     or v_receipt->>'target_code' is distinct from v_exec.target_code
     or (v_receipt->>'target_repo') is distinct from v_exec.target_repo
     or (v_receipt->>'target_path') is distinct from v_exec.target_path
     or v_receipt->>'router' is distinct from 'ACT-0001'
     or v_receipt->>'producer_ref' is distinct from 'public.lf_router_resolve_v1'
     or v_receipt->>'authority_ref' is distinct from 'ROUTER_DOWNSTREAM_AUTHORITY' then
    return jsonb_build_object('applicable',true,'valid',false,'code','ROUTER_AUTHORITY_RECEIPT_IDENTITY_MISMATCH');
  end if;

  v_core := v_receipt - 'fingerprint_sha256';
  v_expected_fp := encode(
    extensions.digest(convert_to(v_core::text,'UTF8'),'sha256'),
    'hex'
  );
  if coalesce(v_receipt->>'fingerprint_sha256','') !~ '^[0-9a-f]{64}$'
     or v_receipt->>'fingerprint_sha256'<>v_expected_fp then
    return jsonb_build_object('applicable',true,'valid',false,'code','ROUTER_AUTHORITY_RECEIPT_FINGERPRINT_INVALID');
  end if;

  select count(*), min(action_code)
    into v_count,v_action
  from public.lf_router_action_registry
  where operation_code=v_exec.operation_code
    and asset_type=v_exec.target_type
    and status='ACTIVE';

  if v_count<>1 or v_action is distinct from v_receipt->>'action_code' then
    return jsonb_build_object(
      'applicable',true,'valid',false,'code','ROUTER_AUTHORITY_ROUTE_BINDING_STALE',
      'route_count',v_count
    );
  end if;

  v_current_revision := public.lf_operation_revision_sha256_v1(v_exec.operation_code);
  v_current_binding_sha := encode(
    extensions.digest(
      convert_to(
        coalesce(
          (
            select jsonb_agg(
              to_jsonb(b)-array['created_at','updated_at','created_by_execution_id','updated_by_execution_id']
              order by b.step_order,b.step_id
            )
            from public.lf_operation_step_judge_bindings b
            where b.operation_code=v_exec.operation_code
              and b.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
          ),
          '[]'::jsonb
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  if v_receipt->>'operation_revision_sha256' is distinct from v_current_revision then
    return jsonb_build_object(
      'applicable',true,'valid',false,'code','ROUTER_AUTHORITY_REVISION_STALE',
      'receipt_revision',v_receipt->>'operation_revision_sha256',
      'current_revision',v_current_revision
    );
  end if;

  if v_receipt->>'step_binding_sha256' is distinct from v_current_binding_sha then
    return jsonb_build_object(
      'applicable',true,'valid',false,'code','ROUTER_AUTHORITY_STEP_BINDING_STALE',
      'receipt_binding_sha256',v_receipt->>'step_binding_sha256',
      'current_binding_sha256',v_current_binding_sha
    );
  end if;

  v_router := public.lf_router_resolve_v1(
    format('canonical authority revalidate %s %s',v_action,v_exec.target_type),
    null,
    v_action,
    v_exec.target_type,
    'ROUTER'
  );

  if coalesce(v_router->>'status','')<>'READY_TO_EXECUTE'
     or coalesce((v_router->>'downstream_execution_allowed')::boolean,false) is not true
     or v_router->>'router' is distinct from 'ACT-0001'
     or v_router->>'operation_code' is distinct from v_exec.operation_code
     or v_router->>'asset_type' is distinct from v_exec.target_type
     or v_router->>'action_code' is distinct from v_action then
    return jsonb_build_object(
      'applicable',true,'valid',false,'code','ROUTER_AUTHORITY_REVALIDATION_NOT_READY',
      'router_result',v_router
    );
  end if;

  if coalesce(v_router->'contract_refs','[]'::jsonb) is distinct from coalesce(v_receipt->'contract_refs','[]'::jsonb)
     or coalesce(v_router->'policy_refs','[]'::jsonb) is distinct from coalesce(v_receipt->'policy_refs','[]'::jsonb)
     or coalesce((v_router->>'required_policy_count')::integer,0) is distinct from coalesce((v_receipt->>'required_policy_count')::integer,0)
     or coalesce((v_router->>'resolved_policy_count')::integer,0) is distinct from coalesce((v_receipt->>'resolved_policy_count')::integer,0)
     or (v_router->>'operation_status') is distinct from (v_receipt->>'operation_status')
     or (v_router->>'operation_lifecycle_state') is distinct from (v_receipt->>'operation_lifecycle_state') then
    return jsonb_build_object(
      'applicable',true,'valid',false,'code','ROUTER_AUTHORITY_ROUTE_SNAPSHOT_STALE'
    );
  end if;

  return jsonb_build_object(
    'applicable',true,
    'valid',true,
    'code','ROUTER_DOWNSTREAM_AUTHORITY_VALID',
    'execution_id',v_exec.execution_id,
    'operation_code',v_exec.operation_code,
    'target_type',v_exec.target_type,
    'target_code',v_exec.target_code,
    'action_code',v_action,
    'operation_revision_sha256',v_current_revision,
    'step_binding_sha256',v_current_binding_sha,
    'fingerprint_sha256',v_receipt->>'fingerprint_sha256',
    'revalidated_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );
end;
$function$;
