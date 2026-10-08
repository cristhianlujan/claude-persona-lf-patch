-- M8.2 non-mutating readback. Does not manufacture run data, measurements, or semantic PASS.
do $ig_m82_readback$
declare
 v_trigger text;
 v_facade text;
 v_target jsonb;
 v_untouched_total bigint;
 v_timing_nested bigint;
begin
 select pg_get_functiondef('programacion.fn_input_curator_compose_before_insert_v1()'::regprocedure)
   into v_trigger;
 select pg_get_functiondef('programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure)
   into v_facade;
 if position('v_m82_deterministic_ms' in v_trigger)=0
   or position('v_m82_semantic_ms' in v_trigger)=0
   or position('lf.input_curator_family_timings_v1' in v_trigger)=0
   or position('semantic_sha_excluded' in v_trigger)=0 then
     raise exception 'M82_PER_FAMILY_HOOK_ABSENT'; end if;
 if position('new.curator_sha256:=programacion.fn_v09_sha256_jsonb' in v_trigger)=0
   or position('new.curator_sha256:=programacion.fn_v09_sha256_jsonb' in v_trigger)
        > position('v_m82_spans:=coalesce' in v_trigger) then
     raise exception 'M82_SEMANTIC_SHA_IS_NOT_COMPUTED_BEFORE_TIMING'; end if;
 if position('IG_CURATOR_PER_FAMILY_TIMING_V1' in v_facade)=0
   or position('v_m82_expected' in v_facade)=0
   or position('timing_sink_emitted' in v_facade)=0
   or position('NOT_APPLICABLE_NO_FAMILY_MATERIALIZATION' in v_facade)=0 then
     raise exception 'M82_FACADE_OBSERVABILITY_GUARD_MISSING'; end if;
 select unit_metadata#>'{action_specs_v1,PER_FAMILY_RESOLVER,target,declared_objects}'
   into v_target from programacion.engineering_plan_units
   where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M8.2';
 if v_target <> jsonb_build_array(
      'programacion.fn_input_governance_curator_materialize_v1',
      'programacion.fn_input_curator_compose_before_insert_v1') then
   raise exception 'M82_DECLARED_TARGETS_DRIFT'; end if;
 select count(*),count(*) filter(where curator_evidence ? 'performance_observation'
       or curator_evidence ? 'per_family_resolver_spans'
       or curator_evidence ? 'elapsed_ms')
   into v_untouched_total,v_timing_nested
 from programacion.input_family_assessments;
 if v_timing_nested<>0 then raise exception 'M82_TIMINGS_IN_SEMANTIC_ASSESSMENT:%',v_timing_nested; end if;
 if v_untouched_total=0 then raise exception 'M82_ASSURANCE_BASELINE_EMPTY'; end if;
 raise notice 'PASS M8.2 SQL readback, semantic assessment timing contamination=0; live runtime sample still required';
end; $ig_m82_readback$;