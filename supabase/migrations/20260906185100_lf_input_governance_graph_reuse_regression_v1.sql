-- Strategy 28 / P2 regression guard for downstream graph reuse candidate.
-- Read-only semantic assertions; creates no durable business data or runtime switch.

do $regression$
declare
  r record;
  f record;
  v_graph jsonb;
  v_candidate jsonb;
  v_agg text;
  v_count integer;
  v_expected text;
  v_exec_def text;
  v_current_old boolean;
  v_current_new boolean;
  v_current_cases integer:=0;
begin
  -- Golden aggregate hashes were read directly from current main/live authority before
  -- candidate source creation. Each aggregate covers all 47 classifier_sha256 values
  -- ordered by family_code for the exact screen.
  for r in
    select * from (values
      ('B2B-AUTH-004'::text,'e28e0ad6bad503238ae8e7ea425a4d2e0a3919d548bdcf6878028e71ae48db29'::text),
      ('B2B-CARGA-001','4a2cc99daef419746b8d8042f6c3fb47a98285d56acda9010b77fa6f2c7e66de'),
      ('HOME_002','5d56bb2c7193a98c4347223222ae8ea441a80e5624e413bf5f040f09aba8b918'),
      ('ONB_002','32ebeb62ab023c37381005a85a1528d51eaa79a9f011014acc40ed2e42165bf8')
    ) x(screen_code,expected_sha)
  loop
    select p.id into strict v_count from lf_ops.pantallas p where p.codigo=r.screen_code;
    -- v_count is the screen id here; reuse only inside this iteration.
    v_graph:=programacion.fn_input_screen_canonical_graph(v_count,19);
    v_agg:='';
    v_expected:=r.expected_sha;

    for f in
      select e.value as family_code
      from lf_ops.reglas q
      cross join lateral jsonb_array_elements_text(q.valor_config->'families') e(value)
      where q.codigo='B2B-RULE-STORY-READINESS-001'
      order by e.value
    loop
      v_candidate:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(v_count,f.family_code,19,v_graph);
      if nullif(v_candidate->>'classifier_sha256','') is null then
        raise exception 'S28_REGRESSION_CLASSIFIER_SHA_MISSING:%:%',r.screen_code,f.family_code;
      end if;
      v_agg:=v_agg || case when v_agg='' then '' else '|' end || f.family_code || ':' || (v_candidate->>'classifier_sha256');
    end loop;

    select count(*) into v_count
    from lf_ops.reglas q
    cross join lateral jsonb_array_elements_text(q.valor_config->'families') e(value)
    where q.codigo='B2B-RULE-STORY-READINESS-001';
    if v_count<>47 then raise exception 'S28_REGRESSION_FAMILY_UNIVERSE_MISMATCH:%',v_count; end if;

    if encode(extensions.digest(convert_to(v_agg,'UTF8'),'sha256'),'hex') is distinct from v_expected then
      raise exception 'S28_REGRESSION_CLASSIFIER_AGGREGATE_MISMATCH:% expected=% observed=%',
        r.screen_code,v_expected,encode(extensions.digest(convert_to(v_agg,'UTF8'),'sha256'),'hex');
    end if;
  end loop;

  -- If durable readiness runs are present in the test database, compare the complete
  -- old/new currentness decision on a bounded mix of latest COMPLETED and predecessor runs.
  for r in
    with latest as (
      select distinct on (pantalla_id) id,pantalla_id
      from programacion.input_readiness_runs
      where status='COMPLETED'
      order by pantalla_id,id desc
    ), sample as (
      select id from latest order by id desc limit 6
      union
      select rr.id
      from programacion.input_readiness_runs rr
      join latest l on l.pantalla_id=rr.pantalla_id and rr.id<l.id
      order by rr.id desc limit 4
    )
    select id from sample order by id
  loop
    v_current_old:=programacion.fn_input_readiness_run_is_current_cached_v1(r.id);
    v_current_new:=programacion.fn_input_readiness_run_is_current_cached_v2(r.id);
    v_current_cases:=v_current_cases+1;
    if v_current_old is distinct from v_current_new then
      raise exception 'S28_REGRESSION_CURRENTNESS_DECISION_MISMATCH:run=% old=% new=%',r.id,v_current_old,v_current_new;
    end if;
  end loop;

  -- No runtime switch: public execution must still reference the proven v1 currentness path.
  select pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure) into v_exec_def;
  if position('fn_input_readiness_run_is_current_cached_v1' in v_exec_def)=0
     or position('fn_input_readiness_run_is_current_cached_v2' in v_exec_def)>0 then
    raise exception 'S28_REGRESSION_RUNTIME_SWITCH_DETECTED';
  end if;

  raise notice 'S28_GRAPH_REUSE_REGRESSION_PASS screens=4 families_per_screen=47 currentness_cases=%',v_current_cases;
end;
$regression$;
