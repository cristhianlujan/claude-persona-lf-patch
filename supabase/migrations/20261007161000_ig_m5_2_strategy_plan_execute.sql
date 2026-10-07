-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M5.2
-- Explicit read-only strategy planning + material execution split.

create or replace function programacion.fn_input_governance_curator_plan_v1(
  p_pantalla_id integer,
  p_force_selftest boolean default false,
  p_completed_run_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','public'
as $function$
declare
  v_completed bigint;
  v_scope jsonb;
  v_mode text;
  v_delta jsonb;
  v_changed_sources integer:=0;
  v_affected_families integer:=0;
  v_successor_required boolean:=false;
  v_resolution_errors integer:=0;
  v_run_state text;
  v_current boolean:=false;
  v_strategy text;
  v_reason text;
begin
  if p_completed_run_id is not null then
    select id,scope
      into v_completed,v_scope
    from programacion.input_readiness_runs
    where id=p_completed_run_id
      and pantalla_id=p_pantalla_id
      and status='COMPLETED'
      and version_id=public.fn_lf_version_compatibility_current_version_id_v1(
        'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
      );
  else
    select id,scope
      into v_completed,v_scope
    from programacion.input_readiness_runs
    where version_id=public.fn_lf_version_compatibility_current_version_id_v1(
            'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
          )
      and pantalla_id=p_pantalla_id
      and status='COMPLETED'
    order by id desc
    limit 1;
  end if;

  if v_completed is null then
    return jsonb_build_object(
      'schema_version','INPUT_GOVERNANCE_CURATOR_STRATEGY_PLAN_V1',
      'strategy','BOOTSTRAP',
      'reason','NO_COMPLETED_RUN',
      'completed_run_id',null,
      'write_performed',false
    );
  end if;

  if p_force_selftest then
    return jsonb_build_object(
      'schema_version','INPUT_GOVERNANCE_CURATOR_STRATEGY_PLAN_V1',
      'strategy','REBIND',
      'reason','FORCE_SELFTEST',
      'completed_run_id',v_completed,
      'write_performed',false
    );
  end if;

  v_mode:=coalesce(v_scope->>'mode','');
  if v_mode not in (
    'GOVERNED_CANONICAL_BOOTSTRAP_V1',
    'RUNTIME_GOVERNED_RECURATION_V2',
    'RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1'
  ) then
    return jsonb_build_object(
      'schema_version','INPUT_GOVERNANCE_CURATOR_STRATEGY_PLAN_V1',
      'strategy','BLOCK',
      'reason','AMBIGUOUS_OR_UNSUPPORTED_SCOPE_MODE',
      'completed_run_id',v_completed,
      'scope_mode',v_mode,
      'write_performed',false
    );
  end if;

  v_delta:=programacion.fn_input_freshness_delta(v_completed);
  v_run_state:=coalesce(v_delta->>'run_state','');
  v_changed_sources:=coalesce((v_delta#>>'{summary,changed_source_count}')::integer,0);
  v_affected_families:=coalesce((v_delta#>>'{summary,affected_family_count}')::integer,0);
  v_successor_required:=coalesce((v_delta#>>'{summary,use_successor_required}')::boolean,false);

  select count(*)
    into v_resolution_errors
  from jsonb_array_elements(coalesce(v_delta->'source_changes','[]'::jsonb)) x(value)
  where x.value->>'state'='RESOLUTION_ERROR';

  if v_resolution_errors>0 then
    v_strategy:='BLOCK';
    v_reason:='SOURCE_RESOLUTION_ERROR';
  elsif v_run_state='STALE' then
    if v_changed_sources<=0 then
      v_strategy:='BLOCK';
      v_reason:='AMBIGUOUS_STALE_WITHOUT_CHANGED_SOURCE';
    elsif v_successor_required then
      v_strategy:='FULL_RECURATE';
      v_reason:='STALE_SUCCESSOR_REQUIRED';
    elsif v_affected_families=0 then
      v_strategy:='REBIND';
      v_reason:='STALE_NON_SEMANTIC_SOURCE_CHANGE';
    else
      v_strategy:='SOURCE_STALE_RECURATE';
      v_reason:='STALE_AFFECTED_FAMILIES';
    end if;
  elsif v_run_state='CURRENT' then
    v_current:=programacion.fn_input_readiness_run_is_current_cached_v1(v_completed);
    if v_current then
      v_strategy:='NOOP';
      v_reason:='COMPLETED_RUN_CURRENT';
    else
      v_strategy:='FULL_RECURATE';
      v_reason:='CURRENT_FRESHNESS_BUT_AUTHORITY_NOT_CURRENT';
    end if;
  else
    v_strategy:='BLOCK';
    v_reason:='AMBIGUOUS_RUN_STATE';
  end if;

  return jsonb_build_object(
    'schema_version','INPUT_GOVERNANCE_CURATOR_STRATEGY_PLAN_V1',
    'strategy',v_strategy,
    'reason',v_reason,
    'completed_run_id',v_completed,
    'scope_mode',v_mode,
    'run_state',v_run_state,
    'changed_source_count',v_changed_sources,
    'affected_family_count',v_affected_families,
    'successor_required',v_successor_required,
    'resolution_error_count',v_resolution_errors,
    'run_current',v_current,
    'write_performed',false
  );
end;
$function$;

revoke all on function programacion.fn_input_governance_curator_plan_v1(integer,boolean,bigint) from public;
grant execute on function programacion.fn_input_governance_curator_plan_v1(integer,boolean,bigint) to service_role;

comment on function programacion.fn_input_governance_curator_plan_v1(integer,boolean,bigint)
is 'M5.2 read-only strategy planner. Exclusive outcomes: BOOTSTRAP, REBIND, SOURCE_STALE_RECURATE, FULL_RECURATE, NOOP, BLOCK. No persistence.';

create or replace function programacion.fn_input_governance_curator_materialize_v1(
  p_pantalla_id integer,
  p_consumer text,
  p_curator_identity text,
  p_force_selftest boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','public'
as $function$
declare
  v_plan jsonb;
  v_strategy text;
  v_completed bigint;
begin
  v_plan:=programacion.fn_input_governance_curator_plan_v1(
    p_pantalla_id,p_force_selftest,null
  );
  v_strategy:=v_plan->>'strategy';
  v_completed:=nullif(v_plan->>'completed_run_id','')::bigint;

  case v_strategy
    when 'BOOTSTRAP' then
      return programacion.fn_input_governance_bootstrap_materialize_v2(
        p_pantalla_id,p_consumer,p_curator_identity
      );
    when 'REBIND' then
      return programacion.fn_input_governance_curator_rebind_v1(
        p_pantalla_id,p_consumer,p_curator_identity,p_force_selftest
      );
    when 'SOURCE_STALE_RECURATE' then
      return programacion.fn_input_governance_recurate_source_stale_v1(
        p_pantalla_id,p_consumer,p_curator_identity,v_completed
      );
    when 'FULL_RECURATE' then
      return programacion.fn_input_governance_recurate_v2(
        p_pantalla_id,p_consumer,p_curator_identity
      );
    when 'NOOP' then
      return jsonb_build_object(
        'schema_version','INPUT_GOVERNANCE_CURATOR_EXECUTION_V1',
        'status','NOOP_CURRENT_RUN',
        'strategy','NOOP',
        'run_id',v_completed,
        'pantalla_id',p_pantalla_id,
        'consumer',p_consumer,
        'write_performed',false,
        'strategy_plan',v_plan,
        'promotion_authorized',false,
        'production_authorized',false
      );
    when 'BLOCK' then
      return jsonb_build_object(
        'schema_version','INPUT_GOVERNANCE_CURATOR_EXECUTION_V1',
        'status','BLOCKED',
        'strategy','BLOCK',
        'blocker','CURATOR_STRATEGY_PLAN_BLOCKED',
        'pantalla_id',p_pantalla_id,
        'consumer',p_consumer,
        'write_performed',false,
        'strategy_plan',v_plan,
        'promotion_authorized',false,
        'production_authorized',false
      );
    else
      raise exception 'INPUT_GOVERNANCE_CURATOR_STRATEGY_UNSUPPORTED:%',coalesce(v_strategy,'<NULL>');
  end case;
end;
$function$;

revoke all on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean) from public;
grant execute on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean) to service_role;
