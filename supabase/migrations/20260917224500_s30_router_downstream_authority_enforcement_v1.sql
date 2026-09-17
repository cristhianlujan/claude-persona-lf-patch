-- S30 / A - Router downstream authority enforcement v1.
-- Transversal primitive, first consumer: ACTUALIZACION_DB_LF.
-- Source-first only. No live apply through Supabase apply_migration.

do $pre$
declare
  v_execution_id constant text := 'EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001';
begin
  if not exists (
    select 1
    from public.lf_operation_execution
    where execution_id=v_execution_id
      and operation_code='ACTUALIZACION_DB_LF'
      and target_type='MIGRATION'
      and target_code='ROUTER_DOWNSTREAM_AUTHORITY_A1_V1'
      and target_repo='cristhianlujan/claude-persona-lf-patch'
      and target_path='supabase/migrations/20260917224500_s30_router_downstream_authority_enforcement_v1.sql'
      and status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_ROUTER_AUTHORITY_A1_EXECUTION_BINDING';
  end if;

  if to_regprocedure('public.lf_router_resolve_v1(text,text,text,text,text)') is null
     or to_regprocedure('public.lf_operation_revision_sha256_v1(text)') is null
     or to_regprocedure('public.fn_lf_operation_reserve_effect_v1(text,text,bigint,text,text,text,text)') is null
     or to_regprocedure('public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)') is null then
    raise exception 'BLOCK_ROUTER_AUTHORITY_A1_DEPENDENCY_MISSING';
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='ROUTER_DOWNSTREAM_AUTHORITY'
      and estado_operativo='ACTIVO'
      and archived_at is null
  ) then
    raise exception 'BLOCK_ROUTER_AUTHORITY_A1_ASSET_MISSING';
  end if;

  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='ACTUALIZACION_DB_LF'
      and status='SANDBOX_ACTIVE'
  ) then
    raise exception 'BLOCK_ROUTER_AUTHORITY_A1_CONSUMER_MISSING';
  end if;
end
$pre$;

create or replace function public.lf_router_downstream_authority_consumer_v1(
  p_operation_code text
)
returns boolean
language sql
stable
security invoker
set search_path = pg_catalog, public
as $function$
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

create or replace function public.lf_router_downstream_authority_build_v1(
  p_execution_id text,
  p_operation_code text,
  p_target_type text,
  p_target_code text,
  p_target_repo text default null,
  p_target_path text default null
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = pg_catalog, public, extensions
as $function$
declare
  v_count integer;
  v_action text;
  v_router jsonb;
  v_revision text;
  v_binding_sha text;
  v_core jsonb;
  v_fingerprint text;
begin
  if not public.lf_router_downstream_authority_consumer_v1(p_operation_code) then
    return jsonb_build_object(
      'applicable',false,
      'valid',true,
      'code','ROUTER_DOWNSTREAM_AUTHORITY_NOT_BOUND'
    );
  end if;

  if btrim(coalesce(p_execution_id,''))=''
     or btrim(coalesce(p_operation_code,''))=''
     or btrim(coalesce(p_target_type,''))=''
     or btrim(coalesce(p_target_code,''))='' then
    return jsonb_build_object(
      'applicable',true,'valid',false,'code','ROUTER_AUTHORITY_IDENTITY_MISSING'
    );
  end if;

  select count(*), min(action_code)
    into v_count,v_action
  from public.lf_router_action_registry
  where operation_code=p_operation_code
    and asset_type=p_target_type
    and status='ACTIVE';

  if v_count<>1 then
    return jsonb_build_object(
      'applicable',true,'valid',false,
      'code',case when v_count=0 then 'ROUTER_AUTHORITY_EXACT_ROUTE_MISSING' else 'ROUTER_AUTHORITY_EXACT_ROUTE_AMBIGUOUS' end,
      'route_count',v_count
    );
  end if;

  v_router := public.lf_router_resolve_v1(
    format('canonical authority bind %s %s',v_action,p_target_type),
    null,
    v_action,
    p_target_type,
    'ROUTER'
  );

  if coalesce(v_router->>'status','')<>'READY_TO_EXECUTE'
     or coalesce((v_router->>'downstream_execution_allowed')::boolean,false) is not true
     or v_router->>'router' is distinct from 'ACT-0001'
     or v_router->>'operation_code' is distinct from p_operation_code
     or v_router->>'asset_type' is distinct from p_target_type
     or v_router->>'action_code' is distinct from v_action then
    return jsonb_build_object(
      'applicable',true,'valid',false,'code','ROUTER_AUTHORITY_RESOLUTION_NOT_READY',
      'router_result',v_router
    );
  end if;

  v_revision := public.lf_operation_revision_sha256_v1(p_operation_code);
  v_binding_sha := encode(
    extensions.digest(
      convert_to(
        coalesce(
          (
            select jsonb_agg(
              to_jsonb(b)-array['created_at','updated_at','created_by_execution_id','updated_by_execution_id']
              order by b.step_order,b.step_id
            )
            from public.lf_operation_step_judge_bindings b
            where b.operation_code=p_operation_code
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

  v_core := jsonb_build_object(
    'schema_version','LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1',
    'execution_id',p_execution_id,
    'operation_code',p_operation_code,
    'target_type',p_target_type,
    'target_code',p_target_code,
    'target_repo',p_target_repo,
    'target_path',p_target_path,
    'action_code',v_action,
    'router','ACT-0001',
    'producer_ref','public.lf_router_resolve_v1',
    'authority_ref','ROUTER_DOWNSTREAM_AUTHORITY',
    'operation_revision_sha256',v_revision,
    'step_binding_sha256',v_binding_sha,
    'contract_refs',coalesce(v_router->'contract_refs','[]'::jsonb),
    'policy_refs',coalesce(v_router->'policy_refs','[]'::jsonb),
    'required_policy_count',coalesce((v_router->>'required_policy_count')::integer,0),
    'resolved_policy_count',coalesce((v_router->>'resolved_policy_count')::integer,0),
    'operation_status',v_router->>'operation_status',
    'operation_lifecycle_state',v_router->>'operation_lifecycle_state',
    'issued_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );

  v_fingerprint := encode(
    extensions.digest(convert_to(v_core::text,'UTF8'),'sha256'),
    'hex'
  );

  return jsonb_build_object(
    'applicable',true,
    'valid',true,
    'code','ROUTER_DOWNSTREAM_AUTHORITY_ISSUED',
    'receipt',v_core || jsonb_build_object('fingerprint_sha256',v_fingerprint)
  );
end;
$function$;

create or replace function public.lf_router_downstream_authority_validate_v1(
  p_execution_id text
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = pg_catalog, public, extensions
as $function$
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

create or replace function public.lf_router_downstream_authority_execution_insert_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $function$
declare
  v_auth jsonb;
begin
  if public.lf_router_downstream_authority_consumer_v1(new.operation_code) then
    v_auth := public.lf_router_downstream_authority_build_v1(
      new.execution_id,new.operation_code,new.target_type,new.target_code,new.target_repo,new.target_path
    );
    if coalesce((v_auth->>'valid')::boolean,false) is not true then
      raise exception 'ROUTER_DOWNSTREAM_AUTHORITY_INSERT_BLOCKED:%',coalesce(v_auth->>'code','UNKNOWN');
    end if;
    new.manifest := (coalesce(new.manifest,'{}'::jsonb) - 'router_authority_receipt')
      || jsonb_build_object('router_authority_receipt',v_auth->'receipt');
  else
    new.manifest := coalesce(new.manifest,'{}'::jsonb) - 'router_authority_receipt';
  end if;
  return new;
end;
$function$;

create or replace function public.lf_router_downstream_authority_execution_update_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if old.manifest ? 'router_authority_receipt' then
    if new.execution_id is distinct from old.execution_id
       or new.operation_code is distinct from old.operation_code
       or new.target_type is distinct from old.target_type
       or new.target_code is distinct from old.target_code
       or new.target_repo is distinct from old.target_repo
       or new.target_path is distinct from old.target_path then
      raise exception 'ROUTER_DOWNSTREAM_AUTHORITY_EXECUTION_IDENTITY_IMMUTABLE';
    end if;
    if new.manifest->'router_authority_receipt'
       is distinct from old.manifest->'router_authority_receipt' then
      raise exception 'ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_IMMUTABLE';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_lf_router_downstream_authority_insert_v1 on public.lf_operation_execution;
create trigger trg_lf_router_downstream_authority_insert_v1
before insert on public.lf_operation_execution
for each row execute function public.lf_router_downstream_authority_execution_insert_v1();

drop trigger if exists trg_lf_router_downstream_authority_update_guard_v1 on public.lf_operation_execution;
create trigger trg_lf_router_downstream_authority_update_guard_v1
before update of operation_code,target_type,target_code,target_repo,target_path,manifest
on public.lf_operation_execution
for each row execute function public.lf_router_downstream_authority_execution_update_guard_v1();

create or replace function public.fn_lf_operation_reserve_effect_v1(
  p_execution_id text,
  p_lease_owner text,
  p_lease_fence bigint,
  p_effect_scope text,
  p_effect_request_sha256 text,
  p_dispatch_key text,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_now timestamptz := clock_timestamp();
  v_exec public.lf_operation_execution%rowtype;
  v_effect public.lf_operation_effect_guard%rowtype;
  v_inserted boolean := false;
  v_auth jsonb;
begin
  if btrim(coalesce(p_effect_scope,''))='' or length(p_effect_scope)>200 then raise exception 'INVALID_EFFECT_SCOPE'; end if;
  if coalesce(p_effect_request_sha256,'') !~ '^[0-9a-f]{64}$' then raise exception 'INVALID_EFFECT_REQUEST_SHA256'; end if;
  if btrim(coalesce(p_dispatch_key,''))='' or length(p_dispatch_key)>200 then raise exception 'INVALID_DISPATCH_KEY'; end if;

  select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id for update;
  if v_exec.execution_id is null then raise exception 'EXECUTION_NOT_FOUND'; end if;
  if v_exec.lease_owner is distinct from p_lease_owner or v_exec.lease_fence is distinct from p_lease_fence
     or v_exec.lease_expires_at is null or v_exec.lease_expires_at<=v_now then
    raise exception 'STALE_OR_MISSING_LEASE_FENCE';
  end if;

  v_auth := public.lf_router_downstream_authority_validate_v1(p_execution_id);
  if coalesce((v_auth->>'applicable')::boolean,false)
     and coalesce((v_auth->>'valid')::boolean,false) is not true then
    raise exception 'ROUTER_DOWNSTREAM_AUTHORITY_EFFECT_BLOCKED:%',coalesce(v_auth->>'code','UNKNOWN');
  end if;

  insert into public.lf_operation_effect_guard(
    execution_id,effect_scope,effect_request_sha256,dispatch_key,created_by_execution_id
  ) values (p_execution_id,p_effect_scope,p_effect_request_sha256,p_dispatch_key,p_actor_execution_id)
  on conflict (execution_id,effect_scope) do nothing
  returning * into v_effect;

  if v_effect.execution_id is not null then
    v_inserted := true;
  else
    select * into v_effect from public.lf_operation_effect_guard
    where execution_id=p_execution_id and effect_scope=p_effect_scope;
  end if;

  if v_effect.effect_request_sha256 is distinct from p_effect_request_sha256
     or v_effect.dispatch_key is distinct from p_dispatch_key then
    raise exception 'EFFECT_SCOPE_REUSED_WITH_DIFFERENT_REQUEST';
  end if;

  if v_inserted then
    return jsonb_build_object(
      'result','EFFECT_RESERVED_NEW','dispatch_permitted',true,
      'execution_id',p_execution_id,'effect_scope',p_effect_scope,'dispatch_key',p_dispatch_key,
      'effect_request_sha256',p_effect_request_sha256,
      'router_authority_validation',v_auth
    );
  end if;
  if v_effect.state='SUCCEEDED' then
    return jsonb_build_object(
      'result','REPLAY_SUCCEEDED_EFFECT','dispatch_permitted',false,
      'execution_id',p_execution_id,'effect_scope',p_effect_scope,'dispatch_key',p_dispatch_key,
      'effect_request_sha256',p_effect_request_sha256,
      'receipt',v_effect.receipt,'router_authority_validation',v_auth
    );
  end if;
  return jsonb_build_object(
    'result','RECONCILIATION_REQUIRED','dispatch_permitted',false,
    'code','EXISTING_EFFECT_RESERVATION_OUTCOME_NOT_DURABLY_RESOLVED',
    'execution_id',p_execution_id,'effect_scope',p_effect_scope,'dispatch_key',p_dispatch_key,
    'effect_request_sha256',p_effect_request_sha256,
    'router_authority_validation',v_auth
  );
end;
$function$;

create or replace function public.lf_record_db_operation_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_auth jsonb;
  v_valid boolean;
  v_assertions jsonb := '[]'::jsonb;
  v_hard_fails jsonb := '[]'::jsonb;
  v_trust jsonb;
  v_scope text;
  v_dispatch_key text;
  v_effect_sha text;
  v_effect public.lf_operation_effect_guard%rowtype;
  v_payload jsonb;
begin
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false);
  end if;

  select * into v_exec
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found
     or v_exec.operation_code<>'ACTUALIZACION_DB_LF'
     or v_exec.target_type not in ('DB','MIGRATION','FUNCTION','TRIGGER') then
    return jsonb_build_object('outcome','BLOCKED','code','DB_EXECUTION_IDENTITY_INVALID','durable',false);
  end if;

  v_payload := p_evidence_payload;
  v_auth := public.lf_router_downstream_authority_validate_v1(p_execution_id);
  v_valid := coalesce((v_auth->>'applicable')::boolean,false)
             and coalesce((v_auth->>'valid')::boolean,false);

  if v_valid then
    v_assertions := v_assertions || jsonb_build_array('router_authority_valid');
  else
    v_hard_fails := v_hard_fails || jsonb_build_array('router_authority_invalid');
  end if;

  v_payload := v_payload
    || jsonb_build_object(
      'router_binding',jsonb_build_object(
        'router','ACT-0001',
        'status',case when v_valid then 'READY_TO_EXECUTE' else 'BLOCKED' end,
        'asset_type',v_exec.target_type,
        'operation_code',v_exec.operation_code,
        'target_code',v_exec.target_code,
        'authority_fingerprint',v_exec.manifest #>> '{router_authority_receipt,fingerprint_sha256}'
      )
    );

  if p_step_id='preflight' then
    v_payload := v_payload || jsonb_build_object(
      'router_authority_receipt',v_exec.manifest->'router_authority_receipt',
      'router_authority_validation',v_auth
    );
  elsif p_step_id='patch' then
    v_payload := v_payload || jsonb_build_object('router_authority_pre_effect',v_auth);
  elsif p_step_id='verify' then
    v_payload := v_payload || jsonb_build_object('router_authority_readback',v_auth);
  end if;

  if p_step_id in ('patch','verify') then
    if jsonb_typeof(p_evidence_payload->'operation_effect_guard_reservation')='object' then
      v_scope := p_evidence_payload #>> '{operation_effect_guard_reservation,effect_scope}';
      v_dispatch_key := p_evidence_payload #>> '{operation_effect_guard_reservation,dispatch_key}';
      v_effect_sha := p_evidence_payload #>> '{operation_effect_guard_reservation,effect_request_sha256}';
    end if;

    if btrim(coalesce(v_scope,''))='' then
      v_valid := false;
      v_hard_fails := v_hard_fails || jsonb_build_array('effect_guard_reservation_missing');
    else
      select * into v_effect
      from public.lf_operation_effect_guard
      where execution_id=p_execution_id and effect_scope=v_scope;

      if not found
         or v_effect.dispatch_key is distinct from v_dispatch_key
         or v_effect.effect_request_sha256 is distinct from v_effect_sha
         or (p_step_id='patch' and v_effect.state not in ('RESERVED','SUCCEEDED'))
         or (p_step_id='verify' and (v_effect.state<>'SUCCEEDED' or v_effect.receipt is null)) then
        v_valid := false;
        v_hard_fails := v_hard_fails || jsonb_build_array(
          case when p_step_id='patch' then 'effect_guard_not_reserved' else 'effect_guard_not_succeeded' end
        );
      else
        v_assertions := v_assertions || jsonb_build_array(
          case when p_step_id='patch' then 'effect_guard_reserved' else 'effect_guard_succeeded' end
        );

        v_payload := v_payload || jsonb_build_object(
          'operation_effect_guard_reservation',
          jsonb_build_object(
            'execution_id',v_effect.execution_id,
            'effect_scope',v_effect.effect_scope,
            'effect_request_sha256',v_effect.effect_request_sha256,
            'dispatch_key',v_effect.dispatch_key,
            'state',v_effect.state,
            'reserved_at',v_effect.reserved_at
          )
        );

        if p_step_id='verify' then
          v_payload := v_payload || jsonb_build_object(
            'operation_effect_guard_readback',
            jsonb_build_object(
              'execution_id',v_effect.execution_id,
              'effect_scope',v_effect.effect_scope,
              'state',v_effect.state,
              'receipt',v_effect.receipt,
              'resolved_at',v_effect.resolved_at
            )
          );
        end if;
      end if;
    end if;
  end if;

  v_trust := jsonb_build_object(
    'valid',v_valid,
    'code',case when v_valid then 'DB_ROUTER_AUTHORITY_TRUST_VALID' else 'DB_ROUTER_AUTHORITY_TRUST_INVALID' end,
    'details',jsonb_build_object('router_authority',v_auth,'step_id',p_step_id),
    'server_assertions',v_assertions,
    'server_hard_fails',v_hard_fails
  );

  return public.lf_record_operation_step_core_v1(
    p_execution_id,
    p_step_id,
    p_evidence_ref,
    v_payload,
    p_actor_execution_id,
    'ACTUALIZACION_DB_LF',
    v_exec.target_type,
    'ACTIVE_ENFORCEMENT',
    'ACTIVE_ENFORCEMENT',
    'ACTIVE_ENFORCEMENT',
    v_trust,
    false,
    'lf_record_db_operation_step_v1'
  );
end;
$function$;

revoke all on function public.lf_router_downstream_authority_consumer_v1(text) from public, anon, authenticated;
revoke all on function public.lf_router_downstream_authority_build_v1(text,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.lf_router_downstream_authority_validate_v1(text) from public, anon, authenticated;
revoke all on function public.lf_record_db_operation_step_v1(text,text,text,jsonb,text) from public, anon, authenticated;
grant execute on function public.lf_router_downstream_authority_consumer_v1(text) to service_role;
grant execute on function public.lf_router_downstream_authority_validate_v1(text) to service_role;
grant execute on function public.lf_record_db_operation_step_v1(text,text,text,jsonb,text) to service_role;

do $bind$
declare
  v_execution_id constant text := 'EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001';
  v_judge constant text := 'JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1';
  v_exec public.lf_operation_execution%rowtype;
  v_auth jsonb;
begin
  update public.lf_activos
  set version='v0.4',
      metadata=jsonb_set(
        jsonb_set(
          jsonb_set(
            coalesce(metadata,'{}'::jsonb),
            '{transversal_inventory,consumers_known}',
            '["ACTUALIZACION_DB_LF"]'::jsonb,
            true
          ),
          '{transversal_inventory,enforcement_mode}',
          '"SERVER_BOUND_RECEIPT_PLUS_EFFECT_REVALIDATION"'::jsonb,
          true
        ),
        '{transversal_inventory,gap}',
        '"consumer coverage audit remains; ACTUALIZACION_DB_LF is first enforced consumer"'::jsonb,
        true
      ),
      updated_by_execution_id=v_execution_id,
      updated_at=clock_timestamp()
  where codigo_activo='ROUTER_DOWNSTREAM_AUTHORITY'
    and archived_at is null;

  update public.lf_operation_contracts
  set required_before_write=(
        select coalesce(jsonb_agg(to_jsonb(v) order by v),'[]'::jsonb)
        from (
          select distinct value as v
          from jsonb_array_elements_text(
            required_before_write || jsonb_build_array(
              'router_downstream_authority_receipt',
              'router_downstream_authority_validation',
              'operation_effect_guard_reservation'
            )
          )
        ) q
      ),
      blocked=(
        select coalesce(jsonb_agg(to_jsonb(v) order by v),'[]'::jsonb)
        from (
          select distinct value as v
          from jsonb_array_elements_text(
            blocked || jsonb_build_array(
              'router_authority_missing',
              'router_authority_spoof',
              'router_authority_stale',
              'router_authority_replay',
              'router_authority_toctou'
            )
          )
        ) q
      ),
      required_after_write=(
        select coalesce(jsonb_agg(to_jsonb(v) order by v),'[]'::jsonb)
        from (
          select distinct value as v
          from jsonb_array_elements_text(
            required_after_write || jsonb_build_array(
              'router_downstream_authority_readback',
              'operation_effect_guard_readback'
            )
          )
        ) q
      ),
      allowed=allowed || jsonb_build_object(
        'router_downstream_authority_capability','ROUTER_DOWNSTREAM_AUTHORITY',
        'router_downstream_authority_version','v0.4',
        'router_authority_receipt_schema','LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1',
        'router_authority_recorder','lf_record_db_operation_step_v1'
      ),
      updated_by_execution_id=v_execution_id,
      updated_at=clock_timestamp()
  where operation_code='ACTUALIZACION_DB_LF'
    and contract_code='CONTRACT-ACTUALIZACION-DB-LF-v0.1'
    and status='ACTIVE_ENFORCEMENT';

  update public.lf_operation_contracts
  set contract_sha=encode(
        extensions.digest(
          convert_to(
            jsonb_build_object(
              'operation_code',operation_code,
              'contract_code',contract_code,
              'contract_path',contract_path,
              'required_before_write',required_before_write,
              'allowed',allowed,
              'blocked',blocked,
              'required_after_write',required_after_write
            )::text,
            'UTF8'
          ),
          'sha256'
        ),
        'hex'
      ),
      updated_by_execution_id=v_execution_id,
      updated_at=clock_timestamp()
  where operation_code='ACTUALIZACION_DB_LF'
    and contract_code='CONTRACT-ACTUALIZACION-DB-LF-v0.1'
    and status='ACTIVE_ENFORCEMENT';

  update public.lf_operation_step_contracts
  set input_required=(
        select coalesce(jsonb_agg(to_jsonb(v) order by v),'[]'::jsonb)
        from (
          select distinct value as v
          from jsonb_array_elements_text(
            input_required || jsonb_build_array('router_authority_receipt','router_authority_validation')
          )
        ) q
      ),
      required_evidence_keys=(
        select coalesce(jsonb_agg(to_jsonb(v) order by v),'[]'::jsonb)
        from (
          select distinct value as v
          from jsonb_array_elements_text(
            required_evidence_keys || jsonb_build_array('router_authority_receipt','router_authority_validation')
          )
        ) q
      ),
      mini_judge_code=v_judge,
      updated_by_execution_id=v_execution_id,
      updated_at=clock_timestamp()
  where operation_code='ACTUALIZACION_DB_LF'
    and step_id='preflight'
    and status='ACTIVE_ENFORCEMENT';

  update public.lf_operation_step_contracts
  set input_required=(
        select coalesce(jsonb_agg(to_jsonb(v) order by v),'[]'::jsonb)
        from (
          select distinct value as v
          from jsonb_array_elements_text(
            input_required || jsonb_build_array('router_authority_pre_effect','operation_effect_guard_reservation')
          )
        ) q
      ),
      required_evidence_keys=(
        select coalesce(jsonb_agg(to_jsonb(v) order by v),'[]'::jsonb)
        from (
          select distinct value as v
          from jsonb_array_elements_text(
            required_evidence_keys || jsonb_build_array('router_authority_pre_effect','operation_effect_guard_reservation')
          )
        ) q
      ),
      mini_judge_code=v_judge,
      updated_by_execution_id=v_execution_id,
      updated_at=clock_timestamp()
  where operation_code='ACTUALIZACION_DB_LF'
    and step_id='patch'
    and status='ACTIVE_ENFORCEMENT';

  update public.lf_operation_step_contracts
  set input_required=(
        select coalesce(jsonb_agg(to_jsonb(v) order by v),'[]'::jsonb)
        from (
          select distinct value as v
          from jsonb_array_elements_text(
            input_required || jsonb_build_array('router_authority_readback','operation_effect_guard_readback')
          )
        ) q
      ),
      required_evidence_keys=(
        select coalesce(jsonb_agg(to_jsonb(v) order by v),'[]'::jsonb)
        from (
          select distinct value as v
          from jsonb_array_elements_text(
            required_evidence_keys || jsonb_build_array('router_authority_readback','operation_effect_guard_readback')
          )
        ) q
      ),
      mini_judge_code=v_judge,
      updated_by_execution_id=v_execution_id,
      updated_at=clock_timestamp()
  where operation_code='ACTUALIZACION_DB_LF'
    and step_id='verify'
    and status='ACTIVE_ENFORCEMENT';

  insert into public.lf_operation_judges(
    operation_code,judge_code,judge_path,judge_sha,
    pass_if,fail_if,result_values,status,
    created_by_execution_id,updated_by_execution_id
  ) values (
    'ACTUALIZACION_DB_LF',v_judge,
    'supabase://public/lf_operation_judges/ACTUALIZACION_DB_LF/JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1',
    'ROUTER_DOWNSTREAM_AUTHORITY_A1_V1',
    '[]'::jsonb,'[]'::jsonb,
    '["PASS_CLEAN","RETURN_TO_WORKER","BLOCKED_BY_ENFORCEMENT"]'::jsonb,
    'ACTIVE_ENFORCEMENT',
    v_execution_id,v_execution_id
  )
  on conflict (operation_code,judge_code) do update
  set judge_path=excluded.judge_path,
      judge_sha=excluded.judge_sha,
      pass_if=excluded.pass_if,
      fail_if=excluded.fail_if,
      result_values=excluded.result_values,
      status=excluded.status,
      updated_by_execution_id=excluded.updated_by_execution_id,
      updated_at=clock_timestamp();

  insert into public.lf_operation_step_judge_bindings(
    operation_code,step_order,step_id,judge_code,
    clean_result_value,blocked_result_value,return_result_value,
    required_evidence_keys,status,
    created_by_execution_id,updated_by_execution_id
  )
  select
    s.operation_code,s.step_order,s.step_id,v_judge,
    'PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER',
    c.required_evidence_keys,
    'ACTIVE_ENFORCEMENT',
    v_execution_id,v_execution_id
  from public.lf_operation_steps s
  join public.lf_operation_step_contracts c
    on c.operation_code=s.operation_code
   and c.step_id=s.step_id
   and c.step_order=s.step_order
   and c.status='ACTIVE_ENFORCEMENT'
  where s.operation_code='ACTUALIZACION_DB_LF'
    and s.active=true
    and s.required=true
  on conflict (operation_code,step_order,step_id) do update
  set judge_code=excluded.judge_code,
      clean_result_value=excluded.clean_result_value,
      blocked_result_value=excluded.blocked_result_value,
      return_result_value=excluded.return_result_value,
      required_evidence_keys=excluded.required_evidence_keys,
      status=excluded.status,
      updated_by_execution_id=excluded.updated_by_execution_id,
      updated_at=clock_timestamp();

  update public.lf_operation_steps
  set evidence_required=case
      when evidence_required ilike '%router_downstream_authority%' then evidence_required
      else evidence_required || '; router_downstream_authority'
    end,
    updated_by_execution_id=v_execution_id,
    updated_at=clock_timestamp()
  where operation_code='ACTUALIZACION_DB_LF'
    and active=true;

  update public.lf_operation_registry
  set source_paths=(
        select coalesce(jsonb_agg(to_jsonb(v) order by v),'[]'::jsonb)
        from (
          select distinct value as v
          from jsonb_array_elements_text(
            source_paths || jsonb_build_array(
              'public.lf_operation_effect_guard',
              'public.lf_operation_step_judge_bindings',
              'public.lf_operation_judges',
              'public.lf_router_action_registry',
              'public.lf_router_downstream_authority_validate_v1'
            )
          )
        ) q
      ),
      notes=case
        when coalesce(notes,'') ilike '%server-bound Router authority%'
        then notes
        else coalesce(notes,'') || ' A1 uses server-bound Router authority receipt and effect-time revalidation; caller-declared router JSON is not authority.'
      end,
      updated_by_execution_id=v_execution_id,
      updated_at=clock_timestamp()
  where operation_code='ACTUALIZACION_DB_LF';

  select * into v_exec
  from public.lf_operation_execution
  where execution_id=v_execution_id
  for update;

  v_auth := public.lf_router_downstream_authority_build_v1(
    v_exec.execution_id,v_exec.operation_code,v_exec.target_type,v_exec.target_code,v_exec.target_repo,v_exec.target_path
  );
  if coalesce((v_auth->>'valid')::boolean,false) is not true then
    raise exception 'ROUTER_AUTHORITY_A1_SELF_EXECUTION_BACKFILL_FAILED:%',coalesce(v_auth->>'code','UNKNOWN');
  end if;

  update public.lf_operation_execution
  set manifest=(coalesce(manifest,'{}'::jsonb)-'router_authority_receipt')
      || jsonb_build_object('router_authority_receipt',v_auth->'receipt'),
      updated_by_execution_id=v_execution_id,
      updated_at=clock_timestamp()
  where execution_id=v_execution_id;

  v_auth := public.lf_router_downstream_authority_validate_v1(v_execution_id);
  if coalesce((v_auth->>'valid')::boolean,false) is not true then
    raise exception 'ROUTER_AUTHORITY_A1_SELF_EXECUTION_VALIDATE_AFTER_BACKFILL_FAILED:%',coalesce(v_auth->>'code','UNKNOWN');
  end if;

  update public.lf_operation_execution_steps
  set evidence_payload=coalesce(evidence_payload,'{}'::jsonb)
      || jsonb_build_object(
        'router_binding',jsonb_build_object(
          'router','ACT-0001',
          'status','READY_TO_EXECUTE',
          'asset_type',v_exec.target_type,
          'operation_code',v_exec.operation_code,
          'target_code',v_exec.target_code,
          'authority_fingerprint',(select manifest #>> '{router_authority_receipt,fingerprint_sha256}' from public.lf_operation_execution where execution_id=v_execution_id)
        ),
        'router_authority_receipt',(select manifest->'router_authority_receipt' from public.lf_operation_execution where execution_id=v_execution_id),
        'router_authority_validation',v_auth
      ),
      updated_at=clock_timestamp()
  where execution_id=v_execution_id
    and step_id='preflight'
    and status in ('PASS_CLEAN','STEP_PASS_WITH_EVIDENCE');
end
$bind$;

create or replace function public.lf_db_operation_step_authority_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_auth jsonb;
  v_scope text;
  v_dispatch_key text;
  v_effect_sha text;
  v_effect public.lf_operation_effect_guard%rowtype;
  v_receipt_fp text;
  v_payload_fp text;
begin
  select * into v_exec
  from public.lf_operation_execution
  where execution_id=new.execution_id;

  if not found or v_exec.operation_code<>'ACTUALIZACION_DB_LF' then
    return new;
  end if;

  if new.status<>'PASS_CLEAN' then
    return new;
  end if;

  v_auth := public.lf_router_downstream_authority_validate_v1(new.execution_id);
  if coalesce((v_auth->>'valid')::boolean,false) is not true then
    raise exception 'DB_STEP_PASS_ROUTER_AUTHORITY_INVALID:%',coalesce(v_auth->>'code','UNKNOWN');
  end if;

  v_receipt_fp := v_exec.manifest #>> '{router_authority_receipt,fingerprint_sha256}';

  if new.step_id='preflight' then
    v_payload_fp := coalesce(
      new.evidence_payload #>> '{router_authority_receipt,fingerprint_sha256}',
      new.evidence_payload #>> '{router_binding,authority_fingerprint}'
    );
    if coalesce(v_receipt_fp,'')='' or v_payload_fp is distinct from v_receipt_fp then
      raise exception 'DB_STEP_PASS_ROUTER_AUTHORITY_EVIDENCE_MISMATCH:preflight';
    end if;
  elsif new.step_id in ('patch','verify') then
    if new.step_id='patch' then
      v_payload_fp := new.evidence_payload #>> '{router_authority_pre_effect,fingerprint_sha256}';
    else
      v_payload_fp := new.evidence_payload #>> '{router_authority_readback,fingerprint_sha256}';
    end if;
    if coalesce(v_receipt_fp,'')='' or v_payload_fp is distinct from v_receipt_fp then
      raise exception 'DB_STEP_PASS_ROUTER_AUTHORITY_EVIDENCE_MISMATCH:%',new.step_id;
    end if;

    v_scope := new.evidence_payload #>> '{operation_effect_guard_reservation,effect_scope}';
    v_dispatch_key := new.evidence_payload #>> '{operation_effect_guard_reservation,dispatch_key}';
    v_effect_sha := new.evidence_payload #>> '{operation_effect_guard_reservation,effect_request_sha256}';

    select * into v_effect
    from public.lf_operation_effect_guard
    where execution_id=new.execution_id
      and effect_scope=v_scope;

    if not found
       or v_effect.dispatch_key is distinct from v_dispatch_key
       or v_effect.effect_request_sha256 is distinct from v_effect_sha
       or (new.step_id='patch' and v_effect.state not in ('RESERVED','SUCCEEDED'))
       or (new.step_id='verify' and (v_effect.state<>'SUCCEEDED' or v_effect.receipt is null)) then
      raise exception 'DB_STEP_PASS_EFFECT_GUARD_INVALID:%',new.step_id;
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_lf_db_operation_step_authority_guard_v1
on public.lf_operation_execution_steps;

create trigger trg_lf_db_operation_step_authority_guard_v1
before insert or update of status,evidence_payload
on public.lf_operation_execution_steps
for each row execute function public.lf_db_operation_step_authority_guard_v1();

revoke all on function public.lf_db_operation_step_authority_guard_v1() from public, anon, authenticated;

do $post$
declare
  v_probe jsonb;
  v_type text;
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.lf_operation_execution'::regclass
      and tgname='trg_lf_router_downstream_authority_insert_v1'
      and not tgisinternal
  ) then
    raise exception 'ROUTER_AUTHORITY_A1_INSERT_TRIGGER_MISSING';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.lf_operation_execution'::regclass
      and tgname='trg_lf_router_downstream_authority_update_guard_v1'
      and not tgisinternal
  ) then
    raise exception 'ROUTER_AUTHORITY_A1_UPDATE_TRIGGER_MISSING';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.lf_operation_execution_steps'::regclass
      and tgname='trg_lf_db_operation_step_authority_guard_v1'
      and not tgisinternal
  ) then
    raise exception 'ROUTER_AUTHORITY_A1_STEP_TRIGGER_MISSING';
  end if;

  if (
    select count(*)
    from public.lf_operation_step_judge_bindings
    where operation_code='ACTUALIZACION_DB_LF'
      and status='ACTIVE_ENFORCEMENT'
  ) <> 3 then
    raise exception 'ROUTER_AUTHORITY_A1_DB_JUDGE_BINDING_COUNT';
  end if;

  if not exists (
    select 1 from public.lf_operation_judges
    where operation_code='ACTUALIZACION_DB_LF'
      and judge_code='JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1'
      and status='ACTIVE_ENFORCEMENT'
  ) then
    raise exception 'ROUTER_AUTHORITY_A1_DB_JUDGE_MISSING';
  end if;

  if not exists (
    select 1 from public.lf_operation_contracts
    where operation_code='ACTUALIZACION_DB_LF'
      and status='ACTIVE_ENFORCEMENT'
      and required_before_write ? 'router_downstream_authority_receipt'
      and required_before_write ? 'router_downstream_authority_validation'
      and required_before_write ? 'operation_effect_guard_reservation'
      and blocked ? 'router_authority_spoof'
      and blocked ? 'router_authority_replay'
      and blocked ? 'router_authority_toctou'
      and required_after_write ? 'router_downstream_authority_readback'
      and required_after_write ? 'operation_effect_guard_readback'
  ) then
    raise exception 'ROUTER_AUTHORITY_A1_CONTRACT_READBACK_FAILED';
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='ROUTER_DOWNSTREAM_AUTHORITY'
      and version='v0.4'
      and metadata #> '{transversal_inventory,consumers_known}' @> '["ACTUALIZACION_DB_LF"]'::jsonb
      and metadata #>> '{transversal_inventory,enforcement_mode}'='SERVER_BOUND_RECEIPT_PLUS_EFFECT_REVALIDATION'
      and estado_operativo='ACTIVO'
      and archived_at is null
  ) then
    raise exception 'ROUTER_AUTHORITY_A1_ASSET_READBACK_FAILED';
  end if;

  v_probe := public.lf_router_downstream_authority_validate_v1(
    'EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001'
  );
  if coalesce((v_probe->>'valid')::boolean,false) is not true then
    raise exception 'ROUTER_AUTHORITY_A1_SELF_EXECUTION_VALIDATE_FAILED payload=%',v_probe::text;
  end if;

  foreach v_type in array array['DB','MIGRATION','FUNCTION','TRIGGER']
  loop
    v_probe := public.lf_router_downstream_authority_build_v1(
      'PROBE-A1-'||v_type,
      'ACTUALIZACION_DB_LF',
      v_type,
      'PROBE_TARGET_'||v_type,
      null,
      null
    );
    if coalesce((v_probe->>'applicable')::boolean,false) is not true
       or coalesce((v_probe->>'valid')::boolean,false) is not true
       or v_probe #>> '{receipt,router}'<>'ACT-0001'
       or v_probe #>> '{receipt,authority_ref}'<>'ROUTER_DOWNSTREAM_AUTHORITY'
       or coalesce(v_probe #>> '{receipt,fingerprint_sha256}','') !~ '^[0-9a-f]{64}$' then
      raise exception 'ROUTER_AUTHORITY_A1_BUILD_PROBE_FAILED type=% payload=%',v_type,v_probe::text;
    end if;
  end loop;
end
$post$;

comment on function public.lf_router_downstream_authority_validate_v1(text) is
  'Transversal deterministic Router downstream authority validator. Binds execution, operation, target, Router producer, operation revision, policies/contracts and revalidates current route before guarded effect reservation.';

comment on function public.lf_record_db_operation_step_v1(text,text,text,jsonb,text) is
  'ACTUALIZACION_DB_LF operation-neutral step recorder wrapper. Derives Router authority trust server-side and requires effect-guard reservation/success for patch/verify.';
