-- S30 transversal operation policy context v1.
-- Fixes EKB: OPERATION-POLICY-CONTEXT-AMBIGUOUS-NONE-001.
-- Architecture: explicit policy applicability -> resolution -> immutable start context -> lifecycle enforcement.
-- No parallel policy registry, no parallel lifecycle engine.

do $pre$
declare
  v_attach_sha text;
  v_guard_sha text;
begin
  select encode(
           extensions.digest(
             convert_to(pg_get_functiondef('public.lf_attach_operation_policy_snapshot_v1()'::regprocedure),'UTF8'),
             'sha256'
           ),
           'hex'
         )
    into v_attach_sha;
  if v_attach_sha is distinct from '483451ba3aa1cfd4c9c4fe767325ac54bedde2f4b1362ea17d22cfba1beec674' then
    raise exception 'BLOCK_OPERATION_POLICY_ATTACH_PRESTATE_DRIFT expected=% actual=%',
      '483451ba3aa1cfd4c9c4fe767325ac54bedde2f4b1362ea17d22cfba1beec674',
      v_attach_sha;
  end if;

  select encode(
           extensions.digest(
             convert_to(pg_get_functiondef('public.lf_operation_policy_snapshot_guard_v1()'::regprocedure),'UTF8'),
             'sha256'
           ),
           'hex'
         )
    into v_guard_sha;
  if v_guard_sha is distinct from '9e32778549d02bf2ed81f6d17dc5c403ba4edbac754f769b9ed9567c6c62acb1' then
    raise exception 'BLOCK_OPERATION_POLICY_GUARD_PRESTATE_DRIFT expected=% actual=%',
      '9e32778549d02bf2ed81f6d17dc5c403ba4edbac754f769b9ed9567c6c62acb1',
      v_guard_sha;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='lf_operation_registry'
      and column_name='policy_requirement_mode'
  ) then
    raise exception 'BLOCK_OPERATION_POLICY_MODE_ALREADY_MATERIALIZED';
  end if;
end
$pre$;

alter table public.lf_operation_registry
  add column policy_requirement_mode text;

alter table public.lf_operation_registry
  add constraint lf_operation_registry_policy_requirement_mode_ck
  check (
    policy_requirement_mode is null
    or policy_requirement_mode in ('REQUIRED','NONE_EXPLICIT')
  );

-- Existing operational operations that already resolve one or more policy materials
-- are explicitly REQUIRED. This includes Router-derived transversal policies.
update public.lf_operation_registry r
set policy_requirement_mode='REQUIRED',
    updated_at=clock_timestamp(),
    updated_by_execution_id=coalesce(updated_by_execution_id,created_by_execution_id)
where r.lifecycle_state_code='OP_OPERATIONAL'
  and exists (
    select 1
    from public.v_lf_operation_policy_snapshot s
    where s.operation_code=r.operation_code
  );

-- Reconciled operational operations with no policy binding/resolution are not given
-- an invented policy. Their "no policy applies" state becomes explicit and auditable.
update public.lf_operation_registry r
set policy_requirement_mode='NONE_EXPLICIT',
    updated_at=clock_timestamp(),
    updated_by_execution_id=coalesce(updated_by_execution_id,created_by_execution_id)
where r.lifecycle_state_code='OP_OPERATIONAL'
  and r.policy_requirement_mode is null
  and r.operation_code in (
    'ANALISIS_RIESGO_CONTENIDO_LF',
    'ESCRITURA_BASE_CONOCIMIENTO_LF',
    'EXTRACCION_DOCUMENTOS_REGULATORIOS_LF',
    'EXTRACCION_FUENTES_DIGITALES_LF',
    'EXTRACCION_NOTICIAS_FINANCIERAS_LF',
    'HOMOLOGACION_FUENTES_DIGITALES_LF',
    'ORQUESTACION_PIPELINE_LF',
    'VULNERABILITY_COVERAGE_REPAIR_LF'
  )
  and not exists (
    select 1
    from public.v_lf_operation_policy_snapshot s
    where s.operation_code=r.operation_code
  )
  and not exists (
    select 1
    from public.lf_operation_policy_bindings b
    where b.operation_code=r.operation_code
      and b.binding_status='ACTIVE'
  );

-- Every operational operation must declare one of the two explicit modes.
alter table public.lf_operation_registry
  add constraint lf_operation_registry_operational_policy_mode_ck
  check (
    lifecycle_state_code <> 'OP_OPERATIONAL'
    or policy_requirement_mode in ('REQUIRED','NONE_EXPLICIT')
  );

create or replace function public.lf_attach_operation_policy_snapshot_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_mode text;
  v_lifecycle_state text;
  v_required_count integer := 0;
  v_resolved_required_count integer := 0;
  v_policy_row_count integer := 0;
  v_active_binding_count integer := 0;
  v_snapshots jsonb := '{}'::jsonb;
  v_snapshots_sha text;
  v_started_at timestamptz := coalesce(new.started_at,clock_timestamp());
begin
  select r.policy_requirement_mode,r.lifecycle_state_code
    into v_mode,v_lifecycle_state
  from public.lf_operation_registry r
  where r.operation_code=new.operation_code;

  if v_lifecycle_state is null then
    raise exception 'BLOCK_OPERATION_POLICY_OPERATION_UNKNOWN operation=%',new.operation_code;
  end if;

  if v_mode is null or v_mode not in ('REQUIRED','NONE_EXPLICIT') then
    raise exception 'BLOCK_OPERATION_POLICY_MODE_UNDECLARED operation=% lifecycle=%',
      new.operation_code,v_lifecycle_state;
  end if;

  select
    count(*),
    count(*) filter (where p.required),
    count(*) filter (where p.required and p.policy_sha is not null)
  into v_policy_row_count,v_required_count,v_resolved_required_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=new.operation_code;

  select count(*)
    into v_active_binding_count
  from public.lf_operation_policy_bindings b
  where b.operation_code=new.operation_code
    and b.binding_status='ACTIVE';

  if v_mode='REQUIRED' then
    if v_required_count=0 then
      raise exception 'BLOCK_OPERATION_POLICY_REQUIRED_EMPTY operation=%',new.operation_code;
    end if;

    if v_required_count > v_resolved_required_count then
      raise exception 'BLOCK_OPERATION_POLICY_MISSING operation=% required=% resolved=%',
        new.operation_code,v_required_count,v_resolved_required_count;
    end if;

    select coalesce(
      jsonb_object_agg(
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
      ),
      '{}'::jsonb
    )
    into v_snapshots
    from public.v_lf_operation_policy_snapshot p
    where p.operation_code=new.operation_code
      and p.policy_sha is not null;

    if v_snapshots='{}'::jsonb then
      raise exception 'BLOCK_OPERATION_POLICY_REQUIRED_SNAPSHOT_EMPTY operation=%',new.operation_code;
    end if;
  else
    if v_policy_row_count<>0 or v_active_binding_count<>0 then
      raise exception 'BLOCK_OPERATION_POLICY_NONE_HAS_BINDINGS operation=% snapshot_rows=% active_bindings=%',
        new.operation_code,v_policy_row_count,v_active_binding_count;
    end if;
    v_required_count := 0;
    v_resolved_required_count := 0;
    v_snapshots := '{}'::jsonb;
  end if;

  v_snapshots_sha := encode(
    extensions.digest(convert_to(v_snapshots::text,'UTF8'),'sha256'),
    'hex'
  );

  new.manifest := coalesce(new.manifest,'{}'::jsonb) || jsonb_build_object(
    'operation_policy_context',
      jsonb_build_object(
        'schema_version','LF_OPERATION_POLICY_CONTEXT_V1',
        'mode',v_mode,
        'required_count',v_required_count,
        'resolved_count',v_resolved_required_count,
        'snapshots_sha256',v_snapshots_sha,
        'evaluated_at',v_started_at,
        'source','SUPABASE'
      ),
    'operation_policy_snapshots',v_snapshots,
    'operation_policy_snapshot_at',v_started_at,
    'operation_policy_source','SUPABASE'
  );

  return new;
end;
$function$;

create or replace function public.lf_operation_policy_snapshot_guard_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
  v_ok boolean;
  v_context jsonb;
  v_snapshots jsonb;
  v_mode text;
  v_required_count integer;
  v_resolved_count integer;
  v_expected_sha text;
  v_actual_sha text;
begin
  if old.manifest ? 'operation_policy_context'
     and (old.manifest->'operation_policy_context') is distinct from (new.manifest->'operation_policy_context') then
    raise exception 'BLOCK_POLICY_CONTEXT_IMMUTABLE execution=% operation=%',
      new.execution_id,new.operation_code;
  end if;

  if old.manifest ? 'operation_policy_snapshots'
     and (old.manifest->'operation_policy_snapshots') is distinct from (new.manifest->'operation_policy_snapshots') then
    raise exception 'BLOCK_POLICY_SNAPSHOT_IMMUTABLE execution=% operation=%',
      new.execution_id,new.operation_code;
  end if;

  if new.status is distinct from old.status then
    -- Backward-compatible closure for executions created before V1 that already
    -- possess a real legacy policy snapshot. New executions always get V1 context.
    if not (new.manifest ? 'operation_policy_context') then
      if not (new.manifest ? 'operation_policy_snapshots') then
        raise exception 'BLOCK_OPERATION_POLICY_MISSING execution=% operation=%',
          new.execution_id,new.operation_code;
      end if;

      for r in
        select key as policy_role,value as snapshot
        from jsonb_each(new.manifest->'operation_policy_snapshots')
      loop
        select exists(
          select 1
          from public.lf_policy_versions p
          where p.policy_code=r.snapshot->>'policy_code'
            and p.policy_version=r.snapshot->>'policy_version'
            and p.policy_sha=r.snapshot->>'policy_sha'
            and p.effective_at<=old.started_at
            and (p.superseded_at is null or p.superseded_at>old.started_at)
        ) into v_ok;

        if not v_ok then
          raise exception 'BLOCK_OPERATION_POLICY_START_SNAPSHOT_INVALID execution=% role=% policy=% version=%',
            new.execution_id,r.policy_role,r.snapshot->>'policy_code',r.snapshot->>'policy_version';
        end if;
      end loop;

      return new;
    end if;

    v_context := new.manifest->'operation_policy_context';
    v_snapshots := new.manifest->'operation_policy_snapshots';

    if jsonb_typeof(v_context) is distinct from 'object'
       or v_context->>'schema_version' is distinct from 'LF_OPERATION_POLICY_CONTEXT_V1'
       or v_context->>'source' is distinct from 'SUPABASE'
       or jsonb_typeof(v_snapshots) is distinct from 'object' then
      raise exception 'BLOCK_OPERATION_POLICY_CONTEXT_INVALID execution=% operation=%',
        new.execution_id,new.operation_code;
    end if;

    v_mode := v_context->>'mode';
    if v_mode not in ('REQUIRED','NONE_EXPLICIT') then
      raise exception 'BLOCK_OPERATION_POLICY_CONTEXT_MODE_INVALID execution=% operation=% mode=%',
        new.execution_id,new.operation_code,v_mode;
    end if;

    begin
      v_required_count := (v_context->>'required_count')::integer;
      v_resolved_count := (v_context->>'resolved_count')::integer;
    exception when others then
      raise exception 'BLOCK_OPERATION_POLICY_CONTEXT_COUNT_INVALID execution=% operation=%',
        new.execution_id,new.operation_code;
    end;

    v_expected_sha := v_context->>'snapshots_sha256';
    v_actual_sha := encode(
      extensions.digest(convert_to(v_snapshots::text,'UTF8'),'sha256'),
      'hex'
    );
    if v_expected_sha is null
       or v_expected_sha !~ '^[0-9a-f]{64}$'
       or v_expected_sha is distinct from v_actual_sha then
      raise exception 'BLOCK_OPERATION_POLICY_CONTEXT_DIGEST_INVALID execution=% operation=%',
        new.execution_id,new.operation_code;
    end if;

    if v_mode='NONE_EXPLICIT' then
      if v_required_count<>0
         or v_resolved_count<>0
         or v_snapshots<>'{}'::jsonb then
        raise exception 'BLOCK_OPERATION_POLICY_NONE_CONTEXT_NONEMPTY execution=% operation=%',
          new.execution_id,new.operation_code;
      end if;
      return new;
    end if;

    if v_required_count<1
       or v_resolved_count<>v_required_count
       or v_snapshots='{}'::jsonb then
      raise exception 'BLOCK_OPERATION_POLICY_REQUIRED_CONTEXT_INCOMPLETE execution=% operation=% required=% resolved=%',
        new.execution_id,new.operation_code,v_required_count,v_resolved_count;
    end if;

    for r in
      select key as policy_role,value as snapshot
      from jsonb_each(v_snapshots)
    loop
      select exists(
        select 1
        from public.lf_policy_versions p
        where p.policy_code=r.snapshot->>'policy_code'
          and p.policy_version=r.snapshot->>'policy_version'
          and p.policy_sha=r.snapshot->>'policy_sha'
          and p.effective_at<=old.started_at
          and (p.superseded_at is null or p.superseded_at>old.started_at)
      ) into v_ok;

      if not v_ok then
        raise exception 'BLOCK_OPERATION_POLICY_START_SNAPSHOT_INVALID execution=% role=% policy=% version=%',
          new.execution_id,r.policy_role,r.snapshot->>'policy_code',r.snapshot->>'policy_version';
      end if;
    end loop;
  end if;

  return new;
end
$function$;

do $post$
declare
  v_unclassified text[];
  v_required_without_policy text[];
  v_none_with_policy text[];
begin
  select array_agg(r.operation_code order by r.operation_code)
    into v_unclassified
  from public.lf_operation_registry r
  where r.lifecycle_state_code='OP_OPERATIONAL'
    and r.policy_requirement_mode is null;

  if coalesce(array_length(v_unclassified,1),0)<>0 then
    raise exception 'BLOCK_OPERATION_POLICY_OPERATIONAL_UNCLASSIFIED:%',v_unclassified;
  end if;

  select array_agg(r.operation_code order by r.operation_code)
    into v_required_without_policy
  from public.lf_operation_registry r
  where r.lifecycle_state_code='OP_OPERATIONAL'
    and r.policy_requirement_mode='REQUIRED'
    and not exists (
      select 1 from public.v_lf_operation_policy_snapshot s
      where s.operation_code=r.operation_code
        and s.required
        and s.policy_sha is not null
    );

  if coalesce(array_length(v_required_without_policy,1),0)<>0 then
    raise exception 'BLOCK_OPERATION_POLICY_REQUIRED_WITHOUT_RESOLVED_POLICY:%',v_required_without_policy;
  end if;

  select array_agg(r.operation_code order by r.operation_code)
    into v_none_with_policy
  from public.lf_operation_registry r
  where r.lifecycle_state_code='OP_OPERATIONAL'
    and r.policy_requirement_mode='NONE_EXPLICIT'
    and (
      exists (
        select 1 from public.v_lf_operation_policy_snapshot s
        where s.operation_code=r.operation_code
      )
      or exists (
        select 1 from public.lf_operation_policy_bindings b
        where b.operation_code=r.operation_code
          and b.binding_status='ACTIVE'
      )
    );

  if coalesce(array_length(v_none_with_policy,1),0)<>0 then
    raise exception 'BLOCK_OPERATION_POLICY_NONE_WITH_POLICY:%',v_none_with_policy;
  end if;
end
$post$;
