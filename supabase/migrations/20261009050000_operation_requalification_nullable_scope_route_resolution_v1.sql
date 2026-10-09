-- Generic requalification compatibility repair for operations whose canonical
-- subject scope is contract-driven rather than a single registry asset type.
--
-- Root cause:
--   lf_operation_requalification_bootstrap_v1 historically required
--   lf_operation_registry.applies_to_asset_type to be non-null.
--   INDEPENDENT_ASSURANCE V3 correctly generalized the existing independent
--   review operation in place (applies_to_asset_type=NULL), so the generic
--   bootstrap must resolve the exact active route instead of requiring a
--   registry-level fixed subject type.
--
-- Compatibility:
--   Preserve the existing qualification/safety flags required by the canonical
--   operation qualification matrix while retaining the V3 generic contract.
-- No capability promotion, runtime activation or production activation occurs here.

do $pre$
begin
  if to_regprocedure('public.lf_operation_requalification_bootstrap_v1(text,text,text,text,text,text,text)') is null then
    raise exception 'BLOCK_REQUAL_BOOTSTRAP_MISSING';
  end if;

  if not exists (
    select 1
    from public.lf_operation_registry
    where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      and operation_type='INDEPENDENT_REVIEW'
      and lifecycle_state_code='OP_OPERATIONAL'
      and applies_to_asset_type is null
  ) then
    raise exception 'BLOCK_INDEPENDENT_ASSURANCE_V3_GENERIC_OPERATION_NOT_PRESENT';
  end if;

  if not exists (
    select 1
    from public.lf_capability_current
    where capability_code='INDEPENDENT_ASSURANCE'
      and version='1.0.1'
      and manifest_sha256='b12c44ca0e07d2da4fdcb27f7e8e8da311dfcdaf390e645d45a3cf407a31e6c1'
  ) then
    raise exception 'BLOCK_INDEPENDENT_ASSURANCE_CURRENT_NOT_1_0_1_PRE_REQUAL';
  end if;
end
$pre$;

update public.lf_operation_contracts
set allowed = coalesce(allowed,'{}'::jsonb) || jsonb_build_object(
      'qualification_evidence_write_allowed',true,
      'independent_review_required',true,
      'direct_business_write_allowed',false,
      'strategy_snapshot_mutation_allowed',false,
      'runtime_activation',false,
      'production_activation',false,
      'scheduler_activation',false,
      'orchestrator_activation',false
    ),
    updated_at=clock_timestamp(),
    updated_by_execution_id='PROFILE_EVOLUTION_REARCH-20261008-001'
where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
  and status='ACTIVE_ENFORCEMENT';

create or replace function public.lf_operation_requalification_bootstrap_v1(
  p_execution_id text,
  p_operation_code text,
  p_route_action_code text,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_exact_source_head text
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
declare
  r public.lf_operation_registry%rowtype;
  x public.lf_operation_execution%rowtype;
  reserve_result jsonb;
  qualification_result jsonb;
  rev text;
  fp text;
  target_path text;
  current_after boolean;
  binding_kind text;
  route_asset_type text;
  route_count integer := 0;
begin
  if btrim(coalesce(p_execution_id,''))=''
     or btrim(coalesce(p_operation_code,''))=''
     or btrim(coalesce(p_route_action_code,''))=''
     or coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$'
     or btrim(coalesce(p_idempotency_key,''))=''
     or btrim(coalesce(p_actor_execution_id,''))=''
     or coalesce(p_exact_source_head,'') !~ '^[0-9a-f]{40}$' then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_INPUT_INVALID';
  end if;

  select * into r
  from public.lf_operation_registry
  where operation_code=p_operation_code;

  if not found or r.lifecycle_state_code not in ('OP_OPERATIONAL','OP_CANDIDATE') then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_TARGET_INVALID:%',p_operation_code;
  end if;

  if r.lifecycle_state_code='OP_OPERATIONAL' then
    binding_kind:='ACTIVE_ROUTER';

    select count(*), min(a.asset_type)
      into route_count, route_asset_type
    from public.lf_router_action_registry a
    where a.action_code=p_route_action_code
      and a.operation_code=p_operation_code
      and a.status='ACTIVE';

    if route_count<>1 or btrim(coalesce(route_asset_type,''))='' then
      raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_ROUTE_INVALID_OR_AMBIGUOUS:%:%:%',
        p_operation_code,p_route_action_code,route_count;
    end if;

    if r.applies_to_asset_type is not null
       and r.applies_to_asset_type is distinct from route_asset_type then
      raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_ROUTE_SCOPE_MISMATCH:%:%:%',
        p_operation_code,r.applies_to_asset_type,route_asset_type;
    end if;
  else
    binding_kind:='PREPROMOTION_LIFECYCLE_QUALIFICATION';
    route_asset_type:=r.applies_to_asset_type;

    if btrim(coalesce(route_asset_type,''))='' then
      raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_ROUTE_SCOPE_MISSING:%',p_operation_code;
    end if;

    if exists (
      select 1
      from public.lf_router_action_registry a
      where a.operation_code=p_operation_code
        and a.status='ACTIVE'
    ) then
      raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_CANDIDATE_ROUTER_ALREADY_ACTIVE:%',p_operation_code;
    end if;

    if not exists (
      select 1
      from lf_ops.estados_transiciones t
      where t.entity_type='OPERATION_LIFECYCLE'
        and t.from_state_code='OP_CANDIDATE'
        and t.to_state_code='OP_OPERATIONAL'
        and t.action_code=p_route_action_code
        and t.status='VIGENTE'
        and coalesce((t.condition_config->>'requires_qualification')::boolean,false)=true
        and t.condition_config->>'qualification_scope'='OPERATION'
    ) then
      raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_CANDIDATE_PREPROMOTION_AUTHORITY_INVALID:%:%',
        p_operation_code,p_route_action_code;
    end if;
  end if;

  rev:=public.lf_operation_revision_sha256_v1(p_operation_code);
  fp:=public.lf_required_test_suite_fingerprint_v1('OPERATION',p_operation_code);

  if public.lf_qualification_current_v1('OPERATION',p_operation_code,rev) then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_NOT_NEEDED:%',p_operation_code;
  end if;

  target_path:='supabase://public/lf_operation_registry/'||p_operation_code;

  reserve_result:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,p_operation_code,'OPERATION',p_operation_code,
    p_idempotency_key,p_request_sha256,p_actor_execution_id,null,target_path,
    jsonb_build_object(
      'mode','OPERATION_REQUALIFICATION_BOOTSTRAP_ONLY',
      'operation_requalification_bootstrap_only',true,
      'qualification_target_operation',p_operation_code,
      'qualification_target_revision_sha256',rev,
      'qualification_target_suite_fingerprint',fp,
      'route_binding',jsonb_build_object(
        'binding_kind',binding_kind,
        'asset_type',route_asset_type,
        'action_code',p_route_action_code,
        'operation_code',p_operation_code,
        'operation_lifecycle_state',r.lifecycle_state_code,
        'router_activation_authorized',false
      ),
      'exact_source_head',p_exact_source_head,
      'runtime_activation',false,
      'production_activation',false,
      'promotion_authorized',false,
      'router_activation_authorized',false
    )
  );

  select * into x
  from public.lf_operation_execution
  where execution_id=reserve_result->>'execution_id'
  for update;

  if not found or x.status<>'IN_PROGRESS'
     or x.operation_code is distinct from p_operation_code
     or x.target_type is distinct from 'OPERATION'
     or x.target_code is distinct from p_operation_code
     or x.target_path is distinct from target_path then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_EXECUTION_BINDING_INVALID';
  end if;

  if coalesce(x.manifest->>'operation_policy_source','')<>'SUPABASE'
     or jsonb_typeof(x.manifest->'operation_policy_snapshots') is distinct from 'object' then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_POLICY_SNAPSHOT_MISSING';
  end if;

  if rev is distinct from public.lf_operation_revision_sha256_v1(p_operation_code)
     or fp is distinct from public.lf_required_test_suite_fingerprint_v1('OPERATION',p_operation_code) then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_TARGET_CHANGED:%',p_operation_code;
  end if;

  qualification_result:=public.lf_run_operation_qualification_v1(p_operation_code,x.execution_id);
  current_after:=public.lf_qualification_current_v1('OPERATION',p_operation_code,rev);

  update public.lf_operation_execution
  set status='COMPLETED',
      completed_at=clock_timestamp(),
      updated_by_execution_id=p_actor_execution_id,
      manifest=manifest||jsonb_build_object(
        'qualification_bootstrap_result',qualification_result,
        'qualification_current_after_runner',current_after,
        'qualification_bootstrap_closed',true,
        'runtime_activation',false,
        'production_activation',false,
        'promotion_authorized',false,
        'router_activation_authorized',false
      )
  where execution_id=x.execution_id;

  return jsonb_build_object(
    'execution_id',x.execution_id,
    'operation_code',p_operation_code,
    'operation_lifecycle_state',r.lifecycle_state_code,
    'route_binding_kind',binding_kind,
    'route_asset_type',route_asset_type,
    'revision_sha256',rev,
    'suite_set_fingerprint',fp,
    'qualification',qualification_result,
    'qualification_current',current_after,
    'exact_source_head',p_exact_source_head,
    'runtime_activation',false,
    'production_activation',false,
    'promotion_authorized',false,
    'router_activation_authorized',false,
    'bootstrap_execution_status','COMPLETED'
  );
end
$function$;

do $post$
declare
  v_allowed jsonb;
  v_count integer;
begin
  select allowed into v_allowed
  from public.lf_operation_contracts
  where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
    and status='ACTIVE_ENFORCEMENT'
  order by updated_at desc
  limit 1;

  if not (
    (v_allowed->>'qualification_evidence_write_allowed')::boolean is true
    and (v_allowed->>'independent_review_required')::boolean is true
    and (v_allowed->>'direct_business_write_allowed')::boolean is false
    and (v_allowed->>'strategy_snapshot_mutation_allowed')::boolean is false
    and (v_allowed->>'runtime_activation')::boolean is false
    and (v_allowed->>'production_activation')::boolean is false
    and (v_allowed->>'scheduler_activation')::boolean is false
    and (v_allowed->>'orchestrator_activation')::boolean is false
    and v_allowed->>'subject_contract_mode'='CONTRACT_DRIVEN_ANY_SUBJECT'
    and (v_allowed->>'subject_type_whitelist')::boolean is false
  ) then
    raise exception 'BLOCK_INDEPENDENT_ASSURANCE_COMPATIBILITY_FLAGS_INVALID';
  end if;

  select count(*) into v_count
  from public.lf_operation_registry
  where operation_type='INDEPENDENT_REVIEW';
  if v_count<>1 then
    raise exception 'BLOCK_PARALLEL_INDEPENDENT_REVIEW_OPERATION:%',v_count;
  end if;

  select count(*) into v_count
  from public.lf_operation_judges
  where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
    and status='ACTIVE_ENFORCEMENT';
  if v_count<>6 then
    raise exception 'BLOCK_INDEPENDENT_REVIEW_JUDGE_COUNT:%',v_count;
  end if;

  if not exists (
    select 1
    from public.lf_capability_current
    where capability_code='INDEPENDENT_ASSURANCE'
      and version='1.0.1'
      and manifest_sha256='b12c44ca0e07d2da4fdcb27f7e8e8da311dfcdaf390e645d45a3cf407a31e6c1'
  ) then
    raise exception 'BLOCK_PREMATURE_INDEPENDENT_ASSURANCE_PROMOTION';
  end if;

  if to_regprocedure('public.lf_independent_review_begin_v3(text,text,text,text,text,uuid,text,text,text,uuid,text,text,text,jsonb)') is null
     or to_regprocedure('public.lf_record_independent_review_step_v3(text,text,text,jsonb,text,text)') is null then
    raise exception 'BLOCK_INDEPENDENT_ASSURANCE_V3_RPC_MISSING';
  end if;
end
$post$;
