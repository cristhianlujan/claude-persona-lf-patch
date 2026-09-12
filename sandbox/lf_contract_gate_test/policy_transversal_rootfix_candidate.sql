-- SOURCE-ONLY SANDBOX CANDIDATE. DO NOT APPLY DIRECTLY TO PRODUCTION.
-- Root objective: graduate existing mother policies from pilot scope and inherit them once
-- through the canonical policy snapshot projection. Operation-specific bindings remain overrides.
-- Running this file is intentionally non-persistent: all mutations are inside BEGIN/ROLLBACK.

begin;

-- A. Preconditions: exact policy candidate versions are sourced separately in
-- policy_transversal_candidate_versions.sql and must match their expected SHA.
do $$
begin
  if not exists (
    select 1 from public.lf_policy_versions
    where policy_code='POL-LF-POLICY-CONSUMPTION'
      and policy_version='v1.1-transversal-candidate'
      and policy_sha='e5eb786e14a4b735e271a81b702a0a775e0bf39ba174d333531a82a0858b5553'
      and status='CANDIDATE'
  ) then raise exception 'CANDIDATE_POLICY_CONSUMPTION_MISSING_OR_MISMATCH'; end if;

  if not exists (
    select 1 from public.lf_policy_versions
    where policy_code='POL-LF-SOURCE-RESOLUTION'
      and policy_version='v1.2-transversal-candidate'
      and policy_sha='459d9ec975d5955d63619876e13abf2f0975a978e38cfff0aa5eed2d68295ae0'
      and status='CANDIDATE'
  ) then raise exception 'CANDIDATE_SOURCE_RESOLUTION_MISSING_OR_MISMATCH'; end if;

  if not exists (
    select 1 from public.lf_policy_versions
    where policy_code='POL-LF-STATE-MODEL'
      and policy_version='v1.1-transversal-candidate'
      and policy_sha='f451bb4d2b17cdac48c4dddb250108b2874a9d036edcfb9d2f7fa540416332aa'
      and status='CANDIDATE'
  ) then raise exception 'CANDIDATE_STATE_MODEL_MISSING_OR_MISMATCH'; end if;
end;
$$;

-- B. Governed graduation model under test.
-- ACTIVATION_ROUTING is intentionally NOT generalized: it mixes Profile/Adapter-specific rules.
update public.lf_activos
set metadata = (coalesce(metadata,'{}'::jsonb) - 'pilot_operation')
               || jsonb_build_object('pilot',false,'transversal',true,'router_required',true),
    raw_payload = case codigo_activo
      when 'POL-LF-POLICY-CONSUMPTION' then (
        select policy_payload from public.lf_policy_versions
        where policy_code='POL-LF-POLICY-CONSUMPTION'
          and policy_version='v1.1-transversal-candidate'
      )
      when 'POL-LF-SOURCE-RESOLUTION' then (
        select policy_payload from public.lf_policy_versions
        where policy_code='POL-LF-SOURCE-RESOLUTION'
          and policy_version='v1.2-transversal-candidate'
      )
      when 'POL-LF-STATE-MODEL' then (
        select policy_payload from public.lf_policy_versions
        where policy_code='POL-LF-STATE-MODEL'
          and policy_version='v1.1-transversal-candidate'
      )
      else raw_payload
    end
where codigo_activo in (
  'POL-LF-OPERATION-LIFECYCLE',
  'POL-LF-POLICY-CONSUMPTION',
  'POL-LF-SOURCE-RESOLUTION',
  'POL-LF-STATE-MODEL'
);

-- Candidate creation time is not enforcement time. Superseded versions stop being active now;
-- newly promoted candidates become effective now so pre-promotion executions retain legacy compatibility.
update public.lf_policy_versions
set status='CANDIDATE', superseded_at=now()
where status='ACTIVE'
  and policy_code in (
    'POL-LF-POLICY-CONSUMPTION',
    'POL-LF-SOURCE-RESOLUTION',
    'POL-LF-STATE-MODEL'
  );

update public.lf_policy_versions
set status='ACTIVE', effective_at=now(), superseded_at=null,
    updated_by_execution_id='GPT-GOV-POLICY-TRANSVERSAL-ROOTFIX-20260905-001',
    updated_at=now()
where (policy_code='POL-LF-POLICY-CONSUMPTION' and policy_version='v1.1-transversal-candidate')
   or (policy_code='POL-LF-SOURCE-RESOLUTION' and policy_version='v1.2-transversal-candidate')
   or (policy_code='POL-LF-STATE-MODEL' and policy_version='v1.1-transversal-candidate');

-- C. Canonical projection.
-- Explicit binding wins by policy_code. Transversal mother policy fills only missing codes for
-- ACTIVE Router-mapped operations. LEFT JOIN preserves required-but-unresolved rows fail-closed.
create or replace view public.v_lf_operation_policy_snapshot as
with routable as (
  select distinct operation_code
  from public.lf_router_action_registry
  where status='ACTIVE' and operation_code is not null
), expected as (
  select
    b.operation_code,
    b.policy_role,
    b.required,
    b.distribution_modes,
    b.policy_code,
    b.updated_at as binding_updated_at,
    0 as precedence
  from public.lf_operation_policy_bindings b
  where b.binding_status='ACTIVE'

  union all

  select
    r.operation_code,
    case a.metadata->>'policy_kind'
      when 'OPERATION_LIFECYCLE_POLICY' then 'GOVERNANCE_LIFECYCLE'
      when 'POLICY_CONSUMPTION_POLICY' then 'POLICY_CONSUMPTION'
      when 'SOURCE_RESOLUTION_POLICY' then 'SOURCE_RESOLUTION'
      when 'STATE_MODEL_POLICY' then 'STATE_MODEL'
    end as policy_role,
    true as required,
    array['ROUTER']::text[] as distribution_modes,
    a.codigo_activo as policy_code,
    null::timestamptz as binding_updated_at,
    1 as precedence
  from routable r
  cross join public.lf_activos a
  where a.archived_at is null
    and a.tipo_activo='REGLA'
    and a.nivel_control='TRANSVERSAL'
    and coalesce((a.metadata->>'transversal')::boolean,false)
    and coalesce((a.metadata->>'router_required')::boolean,false)
    and a.metadata->>'policy_kind' in (
      'OPERATION_LIFECYCLE_POLICY',
      'POLICY_CONSUMPTION_POLICY',
      'SOURCE_RESOLUTION_POLICY',
      'STATE_MODEL_POLICY'
    )
), dedup as (
  select distinct on (operation_code,policy_code)
    operation_code,policy_role,required,distribution_modes,policy_code,binding_updated_at
  from expected
  order by operation_code,policy_code,precedence
)
select
  d.operation_code,
  d.policy_role,
  d.required,
  d.distribution_modes,
  d.policy_code,
  a.nombre_canonico as policy_name,
  a.tipo_activo,
  a.subtipo_activo,
  v.policy_version,
  v.policy_sha,
  v.policy_payload,
  v.effective_at,
  v.source_ref,
  d.binding_updated_at,
  v.updated_at as policy_updated_at
from dedup d
join public.lf_activos a on a.codigo_activo=d.policy_code
left join public.lf_policy_versions v
  on v.policy_code=d.policy_code
 and v.status='ACTIVE';

-- D. ACT-0001 remains the single Router. Only required/resolved accounting changes source:
-- both values are derived from the same canonical projection.
do $router_patch$
declare
  v_def text;
  v_old_required text := $old_required$  select count(*) filter (where b.required) into v_required_policy_count
  from public.lf_operation_policy_bindings b
  where b.operation_code=v_operation.operation_code and b.binding_status='ACTIVE'
    and (p_distribution_mode is null or p_distribution_mode=any(b.distribution_modes));$old_required$;
  v_new_required text := $new_required$  select count(*) filter (where p.required) into v_required_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));$new_required$;
  v_old_resolved text := $old_resolved$  select count(*) into v_resolved_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code and p.required
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));$old_resolved$;
  v_new_resolved text := $new_resolved$  select count(*) filter (where p.required and p.policy_sha is not null) into v_resolved_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));$new_resolved$;
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)
  into v_def;

  if length(v_def)-length(replace(v_def,v_old_required,'')) <> length(v_old_required) then
    raise exception 'ROUTER_REQUIRED_POLICY_BLOCK_NOT_EXACTLY_ONCE';
  end if;
  if length(v_def)-length(replace(v_def,v_old_resolved,'')) <> length(v_old_resolved) then
    raise exception 'ROUTER_RESOLVED_POLICY_BLOCK_NOT_EXACTLY_ONCE';
  end if;

  v_def := replace(v_def,v_old_required,v_new_required);
  v_def := replace(v_def,v_old_resolved,v_new_resolved);
  execute v_def;
end;
$router_patch$;

-- E. Execution snapshot: explicit bound policies preserve the historical full payload contract.
-- Newly inherited mother policies use the already-governed minimum immutable identity fields.
create or replace function public.lf_attach_operation_policy_snapshot_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_required_count integer := 0;
  v_resolved_required_count integer := 0;
  v_snapshots jsonb;
begin
  select
    count(*) filter (where p.required),
    count(*) filter (where p.required and p.policy_sha is not null)
  into v_required_count,v_resolved_required_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=new.operation_code;

  if v_required_count > v_resolved_required_count then
    raise exception 'BLOCK_OPERATION_POLICY_MISSING operation=% required=% resolved=%',
      new.operation_code,v_required_count,v_resolved_required_count;
  end if;

  select jsonb_object_agg(
    p.policy_role,
    case
      when p.binding_updated_at is null then
        jsonb_build_object(
          'policy_code',p.policy_code,
          'policy_version',p.policy_version,
          'policy_sha',p.policy_sha,
          'effective_at',p.effective_at
        )
      else
        jsonb_build_object(
          'policy_code',p.policy_code,
          'policy_version',p.policy_version,
          'policy_sha',p.policy_sha,
          'policy_payload',p.policy_payload,
          'distribution_modes',to_jsonb(p.distribution_modes),
          'effective_at',p.effective_at,
          'source_ref',p.source_ref
        )
    end
  )
  into v_snapshots
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=new.operation_code
    and p.policy_sha is not null;

  if v_snapshots is not null then
    new.manifest := coalesce(new.manifest,'{}'::jsonb) || jsonb_build_object(
      'operation_policy_snapshots',v_snapshots,
      'operation_policy_snapshot_at',now(),
      'operation_policy_source','SUPABASE'
    );
  end if;

  return new;
end;
$$;

revoke all on function public.lf_attach_operation_policy_snapshot_v1() from public,anon,authenticated;

-- F. Guard consumes the same canonical expected/resolved set and preserves snapshot immutability.
create or replace function public.lf_operation_policy_snapshot_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_required_count integer := 0;
  v_resolved_required_count integer := 0;
  v_enforcement_at timestamptz;
  r record;
  v_current_sha text;
begin
  select
    count(*) filter (where p.required),
    count(*) filter (where p.required and p.policy_sha is not null),
    min(p.effective_at) filter (where p.required and p.policy_sha is not null)
  into v_required_count,v_resolved_required_count,v_enforcement_at
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=new.operation_code;

  if v_required_count > v_resolved_required_count then
    raise exception 'BLOCK_OPERATION_POLICY_MISSING operation=% required=% resolved=%',
      new.operation_code,v_required_count,v_resolved_required_count;
  end if;

  if old.manifest ? 'operation_policy_snapshots'
     and (old.manifest->'operation_policy_snapshots') is distinct from (new.manifest->'operation_policy_snapshots') then
    raise exception 'BLOCK_POLICY_SNAPSHOT_IMMUTABLE execution=% operation=%',
      new.execution_id,new.operation_code;
  end if;

  if new.status is distinct from old.status and v_required_count > 0 then
    if not (new.manifest ? 'operation_policy_snapshots') then
      if v_enforcement_at is not null and old.started_at < v_enforcement_at then
        return new;
      end if;
      raise exception 'BLOCK_OPERATION_POLICY_MISSING execution=% operation=%',
        new.execution_id,new.operation_code;
    end if;

    for r in
      select key as policy_role,value as snapshot
      from jsonb_each(new.manifest->'operation_policy_snapshots')
    loop
      select p.policy_sha into v_current_sha
      from public.v_lf_operation_policy_snapshot p
      where p.operation_code=new.operation_code
        and p.policy_role=r.policy_role
        and p.policy_sha is not null
      limit 1;

      if v_current_sha is null then
        raise exception 'BLOCK_OPERATION_POLICY_MISSING execution=% role=%',
          new.execution_id,r.policy_role;
      end if;

      if v_current_sha <> (r.snapshot->>'policy_sha') then
        raise exception 'BLOCK_STALE_OPERATION_POLICY execution=% role=% snapshot_sha=% current_sha=%',
          new.execution_id,r.policy_role,r.snapshot->>'policy_sha',v_current_sha;
      end if;
    end loop;
  end if;

  return new;
end;
$$;

revoke all on function public.lf_operation_policy_snapshot_guard_v1() from public,anon,authenticated;

-- G. Positive structural assertions for this sandbox source.
do $positive_assertions$
declare
  v_router_ops integer;
  v_all_four integer;
  v_duplicate_codes integer;
  v_role_collisions integer;
  v_max_ref_chars integer;
  v_db jsonb;
  v_profile jsonb;
  v_profile_exec jsonb;
  v_card jsonb;
  v_db_snapshot_bytes integer;
begin
  with q as (
    select operation_code,
           count(*) filter (where policy_code in (
             'POL-LF-OPERATION-LIFECYCLE','POL-LF-POLICY-CONSUMPTION',
             'POL-LF-SOURCE-RESOLUTION','POL-LF-STATE-MODEL')) as global_count,
           count(*)-count(distinct policy_code) as dups,
           length(jsonb_agg(jsonb_build_array(policy_code,policy_version,policy_sha)
                    order by policy_role,policy_code)::text) as ref_chars
    from public.v_lf_operation_policy_snapshot
    where 'ROUTER'=any(distribution_modes)
      and operation_code in (
        select distinct operation_code from public.lf_router_action_registry
        where status='ACTIVE' and operation_code is not null
      )
    group by operation_code
  )
  select count(*),count(*) filter(where global_count=4),coalesce(sum(dups),0),max(ref_chars)
  into v_router_ops,v_all_four,v_duplicate_codes,v_max_ref_chars
  from q;

  select count(*) into v_role_collisions
  from (
    select operation_code,policy_role
    from public.v_lf_operation_policy_snapshot
    where operation_code in (
      select distinct operation_code from public.lf_router_action_registry
      where status='ACTIVE' and operation_code is not null
    )
    group by operation_code,policy_role
    having count(*)>1
  ) x;

  if v_router_ops<>12 or v_all_four<>12 or v_duplicate_codes<>0 or v_role_collisions<>0 then
    raise exception 'TRANSVERSAL_POLICY_COVERAGE_ASSERTION_FAILED router_ops=% all_four=% duplicate_codes=% role_collisions=%',
      v_router_ops,v_all_four,v_duplicate_codes,v_role_collisions;
  end if;
  if v_max_ref_chars>594 then
    raise exception 'TRANSVERSAL_POLICY_COMPACT_REF_REGRESSION max_chars=%',v_max_ref_chars;
  end if;

  v_db := public.lf_router_resolve_v1('actualizar migracion',null,'UPDATE','MIGRATION','ROUTER');
  v_profile := public.lf_router_resolve_v1('actualizar perfil','PERFIL-QUALITY-PACK','PROFILE_UPDATE','PERFIL','ROUTER');
  v_profile_exec := public.lf_router_resolve_v1('ejecutar perfil','PERFIL-QUALITY-PACK','PROFILE_EXECUTION','PERFIL','ROUTER');
  v_card := public.lf_router_resolve_v1('crear card','CARD-CANARY-NONEXISTENT-ROOTFIX-001','CARD_CREATE','CARD','ROUTER');

  if v_db->>'status'<>'READY_TO_EXECUTE' or v_db->>'required_policy_count'<>'4' or v_db->>'resolved_policy_count'<>'4' then
    raise exception 'DB_ROUTER_POLICY_ASSERTION_FAILED result=%',v_db;
  end if;
  if v_profile->>'status'<>'READY_TO_EXECUTE' or v_profile->>'required_policy_count'<>'5' or v_profile->>'resolved_policy_count'<>'5' then
    raise exception 'PROFILE_UPDATE_POLICY_ASSERTION_FAILED result=%',v_profile;
  end if;
  if v_profile_exec->>'status'<>'READY_TO_EXECUTE' or v_profile_exec->>'required_policy_count'<>'5' or v_profile_exec->>'resolved_policy_count'<>'5' then
    raise exception 'PROFILE_EXEC_POLICY_ASSERTION_FAILED result=%',v_profile_exec;
  end if;
  if v_card->>'status'<>'READY_TO_EXECUTE' or v_card->>'required_policy_count'<>'4' or v_card->>'resolved_policy_count'<>'4' then
    raise exception 'CARD_POLICY_ASSERTION_FAILED result=%',v_card;
  end if;

  if not exists (
    select 1 from public.v_lf_operation_policy_snapshot
    where operation_code='ACTUALIZACION_DB_LF'
      and policy_code='POL-LF-SOURCE-RESOLUTION'
      and (policy_payload#>'{family_strategies,MIGRATION,rules}') ? 'SUPABASE_FIRST_MIGRATIONS'
      and (policy_payload#>'{family_strategies,MIGRATION,rules}') ? 'NO_ZIP_MIGRATIONS'
  ) then raise exception 'MIGRATION_SOURCE_RESOLUTION_RULES_MISSING'; end if;

  insert into public.lf_operation_execution(
    execution_id,operation_code,target_type,target_code,status,manifest,
    created_by_execution_id,updated_by_execution_id
  ) values (
    'EXEC-CANARY-POLICY-ROOTFIX-SOURCE-POS-20260905-001',
    'ACTUALIZACION_DB_LF','MIGRATION','test://policy-rootfix-source-positive',
    'IN_PROGRESS','{"canary":true}'::jsonb,
    'GPT-GOV-POLICY-TRANSVERSAL-ROOTFIX-20260905-001',
    'GPT-GOV-POLICY-TRANSVERSAL-ROOTFIX-20260905-001'
  );

  select pg_column_size(manifest->'operation_policy_snapshots') into v_db_snapshot_bytes
  from public.lf_operation_execution
  where execution_id='EXEC-CANARY-POLICY-ROOTFIX-SOURCE-POS-20260905-001';

  if v_db_snapshot_bytes>1050 then
    raise exception 'INHERITED_SNAPSHOT_SIZE_REGRESSION bytes=%',v_db_snapshot_bytes;
  end if;
end;
$positive_assertions$;

-- H. Negative fail-closed assertions. Remove one active mother policy inside this transaction:
-- Router and execution attach must both reject required=4/resolved=3. Then restore it for cleanup.
do $negative_assertions$
declare
  v_result jsonb;
  v_insert_blocked boolean := false;
  v_error text;
begin
  update public.lf_policy_versions
  set status='CANDIDATE'
  where policy_code='POL-LF-SOURCE-RESOLUTION'
    and policy_version='v1.2-transversal-candidate'
    and status='ACTIVE';

  v_result := public.lf_router_resolve_v1('actualizar migracion',null,'UPDATE','MIGRATION','ROUTER');
  if v_result->>'status'<>'BLOCKED'
     or v_result->>'blocking_code'<>'BLOCK_REQUIRED_POLICY_MISSING'
     or v_result->>'required_policy_count'<>'4'
     or v_result->>'resolved_policy_count'<>'3' then
    raise exception 'NEGATIVE_ROUTER_FAIL_CLOSED_ASSERTION_FAILED result=%',v_result;
  end if;

  begin
    insert into public.lf_operation_execution(
      execution_id,operation_code,target_type,target_code,status,manifest,created_by_execution_id
    ) values (
      'EXEC-CANARY-POLICY-ROOTFIX-SOURCE-NEG-20260905-001',
      'ACTUALIZACION_DB_LF','MIGRATION','test://policy-rootfix-source-negative',
      'IN_PROGRESS','{"canary":true}'::jsonb,
      'GPT-GOV-POLICY-TRANSVERSAL-ROOTFIX-20260905-001'
    );
  exception when others then
    v_error := sqlerrm;
    if v_error like 'BLOCK_OPERATION_POLICY_MISSING operation=ACTUALIZACION_DB_LF required=4 resolved=3%' then
      v_insert_blocked := true;
    else
      raise;
    end if;
  end;

  if not v_insert_blocked then
    raise exception 'NEGATIVE_EXECUTION_ATTACH_DID_NOT_FAIL_CLOSED';
  end if;

  update public.lf_policy_versions
  set status='ACTIVE'
  where policy_code='POL-LF-SOURCE-RESOLUTION'
    and policy_version='v1.2-transversal-candidate';
end;
$negative_assertions$;

-- Source-only sandbox: no candidate activation, DDL or canary execution persists.
rollback;
