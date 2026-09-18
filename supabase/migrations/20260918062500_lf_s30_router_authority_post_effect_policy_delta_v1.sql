begin;

-- S30 narrow repair for governed self-mutation of Router policy context.
-- Root cause: DB-ROUTER-AUTHORITY-POST-EFFECT-SELF-INVALIDATION-001.
-- The immutable pre-effect authority receipt remains authoritative.
-- Only an exact, already-SUCCEEDED effect may explain one declared policy delta.
-- All other Router/contract/revision/binding drift remains fail-closed.

do $pre$
declare
  v_execution_id constant text := 'EXEC-S30-ROUTER-AUTHORITY-POST-EFFECT-20260918-001';
  v_validator_sha text;
begin
  if not exists (
    select 1
    from public.lf_operation_execution e
    where e.execution_id=v_execution_id
      and e.operation_code='ACTUALIZACION_DB_LF'
      and e.target_type='MIGRATION'
      and e.target_code='ROUTER_AUTHORITY_POST_EFFECT_POLICY_DELTA_V1'
      and e.target_repo='cristhianlujan/claude-persona-lf-patch'
      and e.target_path='supabase/migrations/20260918062500_lf_s30_router_authority_post_effect_policy_delta_v1.sql'
      and e.status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_ROUTER_AUTHORITY_POST_EFFECT_GOVERNED_EXECUTION_BINDING:%',v_execution_id;
  end if;

  select encode(
    extensions.digest(
      convert_to(pg_get_functiondef('public.lf_router_downstream_authority_validate_v1(text)'::regprocedure),'UTF8'),
      'sha256'
    ),
    'hex'
  ) into v_validator_sha;

  if v_validator_sha is distinct from '952ccc37bbbab1c32f9439eb183b5f2726bb5ad9f962765a9fad7e9237f9b7f4' then
    raise exception 'BLOCK_ROUTER_AUTHORITY_VALIDATOR_PRESTATE_DRIFT expected=% actual=%',
      '952ccc37bbbab1c32f9439eb183b5f2726bb5ad9f962765a9fad7e9237f9b7f4',
      v_validator_sha;
  end if;
end
$pre$;

create or replace function public.lf_router_downstream_authority_post_effect_validate_v1(
  p_execution_id text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $function$
declare
  v_base jsonb;
  v_exec public.lf_operation_execution%rowtype;
  v_receipt jsonb;
  v_effect public.lf_operation_effect_guard%rowtype;
  v_effect_count integer;
  v_effect_receipt jsonb;
  v_pre_policy jsonb;
  v_post_policy jsonb;
  v_policy_code text;
  v_router jsonb;
  v_pre_others jsonb;
  v_post_others jsonb;
  v_version text;
  v_name text;
  v_source_blob text;
  v_action text;
  v_expected_filename text;
begin
  v_base:=public.lf_router_downstream_authority_validate_v1(p_execution_id);

  if coalesce((v_base->>'valid')::boolean,false) is true
     or coalesce((v_base->>'applicable')::boolean,false) is false then
    return v_base;
  end if;

  if v_base->>'code' is distinct from 'ROUTER_AUTHORITY_ROUTE_SNAPSHOT_STALE' then
    return v_base;
  end if;

  select * into v_exec
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found
     or v_exec.operation_code<>'ACTUALIZACION_DB_LF'
     or v_exec.target_type<>'MIGRATION'
     or v_exec.status<>'IN_PROGRESS' then
    return v_base;
  end if;

  v_receipt:=v_exec.manifest->'router_authority_receipt';
  if v_receipt is null or jsonb_typeof(v_receipt)<>'object' then
    return v_base;
  end if;

  select count(*) into v_effect_count
  from public.lf_operation_effect_guard
  where execution_id=p_execution_id
    and state='SUCCEEDED'
    and effect_scope like 'SUPABASE_MIGRATION:%';

  if v_effect_count<>1 then
    return jsonb_build_object(
      'applicable',true,'valid',false,
      'code','ROUTER_AUTHORITY_POST_EFFECT_EXACT_EFFECT_REQUIRED',
      'effect_count',v_effect_count
    );
  end if;

  select * into v_effect
  from public.lf_operation_effect_guard
  where execution_id=p_execution_id
    and state='SUCCEEDED'
    and effect_scope like 'SUPABASE_MIGRATION:%'
  limit 1;

  v_effect_receipt:=v_effect.receipt;
  if v_effect_receipt is null
     or jsonb_typeof(v_effect_receipt)<>'object'
     or v_effect_receipt->>'schema_version' is distinct from 'lf-db-write-effect-receipt/v1'
     or v_effect_receipt->>'pre_router_authority_fingerprint'
        is distinct from v_receipt->>'fingerprint_sha256' then
    return jsonb_build_object(
      'applicable',true,'valid',false,
      'code','ROUTER_AUTHORITY_POST_EFFECT_RECEIPT_INVALID'
    );
  end if;

  v_pre_policy:=v_effect_receipt->'pre_policy';
  v_post_policy:=v_effect_receipt->'post_policy';
  if jsonb_typeof(v_pre_policy) is distinct from 'object'
     or jsonb_typeof(v_post_policy) is distinct from 'object'
     or v_pre_policy->>'policy_code' is null
     or v_pre_policy->>'policy_code' is distinct from v_post_policy->>'policy_code'
     or coalesce(v_pre_policy->>'policy_version','')=''
     or coalesce(v_pre_policy->>'policy_sha','') !~ '^[0-9a-f]{64}$'
     or coalesce(v_post_policy->>'policy_version','')=''
     or coalesce(v_post_policy->>'policy_sha','') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object(
      'applicable',true,'valid',false,
      'code','ROUTER_AUTHORITY_POST_EFFECT_POLICY_DELTA_INVALID'
    );
  end if;

  v_policy_code:=v_pre_policy->>'policy_code';
  v_version:=v_effect_receipt->>'migration_version';
  v_name:=v_effect_receipt->>'migration_name';
  v_source_blob:=v_effect_receipt->>'source_blob';
  v_action:=v_receipt->>'action_code';
  v_expected_filename:=v_version||'_'||v_name||'.sql';

  if coalesce(v_version,'') !~ '^[0-9]{14}$'
     or coalesce(v_name,'')=''
     or coalesce(v_source_blob,'') !~ '^[0-9a-f]{40}$'
     or v_effect.effect_scope is distinct from 'SUPABASE_MIGRATION:'||v_version
     or v_exec.target_path is null
     or right(v_exec.target_path,length(v_expected_filename)) is distinct from v_expected_filename
     or not exists (
       select 1
       from supabase_migrations.schema_migrations sm
       where sm.version=v_version
         and sm.name=v_name
         and sm.idempotency_key='gitblob:'||v_source_blob
     ) then
    return jsonb_build_object(
      'applicable',true,'valid',false,
      'code','ROUTER_AUTHORITY_POST_EFFECT_SOURCE_BINDING_INVALID'
    );
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(coalesce(v_receipt->'policy_refs','[]'::jsonb)) x(value)
    where value->>0=v_policy_code
      and value->>1=v_pre_policy->>'policy_version'
      and value->>2=v_pre_policy->>'policy_sha'
  ) then
    return jsonb_build_object(
      'applicable',true,'valid',false,
      'code','ROUTER_AUTHORITY_POST_EFFECT_PRE_POLICY_NOT_IN_RECEIPT'
    );
  end if;

  v_router:=public.lf_router_resolve_v1(
    format('canonical post-effect authority revalidate %s %s',v_action,v_exec.target_type),
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
     or v_router->>'action_code' is distinct from v_action
     or coalesce(v_router->'contract_refs','[]'::jsonb)
        is distinct from coalesce(v_receipt->'contract_refs','[]'::jsonb)
     or coalesce((v_router->>'required_policy_count')::integer,0)
        is distinct from coalesce((v_receipt->>'required_policy_count')::integer,0)
     or coalesce((v_router->>'resolved_policy_count')::integer,0)
        is distinct from coalesce((v_receipt->>'resolved_policy_count')::integer,0)
     or v_router->>'operation_status' is distinct from v_receipt->>'operation_status'
     or v_router->>'operation_lifecycle_state' is distinct from v_receipt->>'operation_lifecycle_state' then
    return jsonb_build_object(
      'applicable',true,'valid',false,
      'code','ROUTER_AUTHORITY_POST_EFFECT_NON_POLICY_DRIFT'
    );
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(coalesce(v_router->'policy_refs','[]'::jsonb)) x(value)
    where value->>0=v_policy_code
      and value->>1=v_post_policy->>'policy_version'
      and value->>2=v_post_policy->>'policy_sha'
  ) then
    return jsonb_build_object(
      'applicable',true,'valid',false,
      'code','ROUTER_AUTHORITY_POST_EFFECT_POST_POLICY_NOT_CURRENT'
    );
  end if;

  select coalesce(jsonb_agg(value order by value::text),'[]'::jsonb)
  into v_pre_others
  from jsonb_array_elements(coalesce(v_receipt->'policy_refs','[]'::jsonb))
  where value->>0<>v_policy_code;

  select coalesce(jsonb_agg(value order by value::text),'[]'::jsonb)
  into v_post_others
  from jsonb_array_elements(coalesce(v_router->'policy_refs','[]'::jsonb))
  where value->>0<>v_policy_code;

  if v_pre_others is distinct from v_post_others then
    return jsonb_build_object(
      'applicable',true,'valid',false,
      'code','ROUTER_AUTHORITY_POST_EFFECT_ADDITIONAL_POLICY_DRIFT'
    );
  end if;

  return jsonb_build_object(
    'applicable',true,
    'valid',true,
    'code','ROUTER_DOWNSTREAM_AUTHORITY_VALID_POST_EFFECT_CAUSAL_POLICY_DELTA',
    'execution_id',v_exec.execution_id,
    'operation_code',v_exec.operation_code,
    'target_type',v_exec.target_type,
    'target_code',v_exec.target_code,
    'action_code',v_action,
    'pre_authority_fingerprint',v_receipt->>'fingerprint_sha256',
    'changed_policy_code',v_policy_code,
    'pre_policy_version',v_pre_policy->>'policy_version',
    'post_policy_version',v_post_policy->>'policy_version',
    'effect_scope',v_effect.effect_scope,
    'effect_request_sha256',v_effect.effect_request_sha256,
    'revalidated_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );
end;
$function$;

revoke execute on function public.lf_router_downstream_authority_post_effect_validate_v1(text)
  from public,anon,authenticated;
grant execute on function public.lf_router_downstream_authority_post_effect_validate_v1(text)
  to service_role;

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

  if new.step_id in ('patch','verify') then
    v_auth:=public.lf_router_downstream_authority_post_effect_validate_v1(new.execution_id);
  else
    v_auth:=public.lf_router_downstream_authority_validate_v1(new.execution_id);
  end if;

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

do $post$
declare
  v_probe jsonb;
begin
  v_probe:=public.lf_router_downstream_authority_post_effect_validate_v1(
    'EXEC-S30-CONTEXT-ADMISSION-COMPACT-20260918-001'
  );

  if coalesce((v_probe->>'valid')::boolean,false) is not true
     or v_probe->>'code'
        is distinct from 'ROUTER_DOWNSTREAM_AUTHORITY_VALID_POST_EFFECT_CAUSAL_POLICY_DELTA' then
    raise exception 'BLOCK_ROUTER_AUTHORITY_POST_EFFECT_POSITIVE_PROBE:%',v_probe::text;
  end if;

  if strpos(
       pg_get_functiondef('public.lf_db_operation_step_authority_guard_v1()'::regprocedure),
       'lf_router_downstream_authority_post_effect_validate_v1'
     )=0 then
    raise exception 'BLOCK_DB_STEP_GUARD_POST_EFFECT_VALIDATOR_NOT_WIRED';
  end if;
end
$post$;

commit;
