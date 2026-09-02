-- DEC-INPUT-GOV-RUNTIME-001 + INPUT_FRESHNESS_DELTA_CONTRACT
--
-- A completed run may be stale because a pinned source digest changed while the
-- dependency graph proves that zero readiness families are affected. In that case
-- the governed safe path is assertion rebind + independent Validator, not a full
-- semantic recuration. Any affected family, terminal successor or resolution error
-- continues through the existing recuration/fail-closed path.
--
-- Scope: Curator routing only. No Story/Implementation/QA/Production gate is relaxed.

create or replace function programacion.fn_input_governance_curator_materialize_v1(
  p_pantalla_id integer,
  p_consumer text,
  p_curator_identity text,
  p_force_selftest boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_completed bigint;
  v_scope jsonb;
  v_delta jsonb;
  v_changed_sources integer:=0;
  v_affected_families integer:=0;
  v_successor_required boolean:=false;
  v_resolution_errors integer:=0;
begin
  select id,scope
    into v_completed,v_scope
    from programacion.input_readiness_runs
   where version_id=19
     and pantalla_id=p_pantalla_id
     and status='COMPLETED'
   order by id desc
   limit 1;

  if v_completed is null then
    return programacion.fn_input_governance_bootstrap_materialize_v2(
      p_pantalla_id,p_consumer,p_curator_identity
    );
  end if;

  if not p_force_selftest
     and coalesce(v_scope->>'mode','') in ('GOVERNED_CANONICAL_BOOTSTRAP_V1','RUNTIME_GOVERNED_RECURATION_V2')
     and not programacion.fn_input_readiness_run_is_current(v_completed)
  then
    v_delta:=programacion.fn_input_freshness_delta(v_completed);
    v_changed_sources:=coalesce((v_delta#>>'{summary,changed_source_count}')::integer,0);
    v_affected_families:=coalesce((v_delta#>>'{summary,affected_family_count}')::integer,0);
    v_successor_required:=coalesce((v_delta#>>'{summary,use_successor_required}')::boolean,false);

    select count(*)
      into v_resolution_errors
      from jsonb_array_elements(coalesce(v_delta->'source_changes','[]'::jsonb)) x(value)
     where x.value->>'state'='RESOLUTION_ERROR';

    if v_changed_sources>0
       and v_affected_families=0
       and not v_successor_required
       and v_resolution_errors=0
    then
      return programacion.fn_input_governance_curator_rebind_v1(
        p_pantalla_id,p_consumer,p_curator_identity,p_force_selftest
      );
    end if;

    return programacion.fn_input_governance_recurate_v2(
      p_pantalla_id,p_consumer,p_curator_identity
    );
  end if;

  return programacion.fn_input_governance_curator_rebind_v1(
    p_pantalla_id,p_consumer,p_curator_identity,p_force_selftest
  );
end;
$function$;
