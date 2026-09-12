-- Strategy 28 / P2 regression guard for downstream graph reuse candidate.
-- Read-only semantic assertions; creates no durable business data or runtime switch.

do $regression$
declare
  r record;
  f record;
  v_graph jsonb;
  v_old jsonb;
  v_new jsonb;
  v_screen_id integer;
  v_family_count integer;
  v_full_cases integer:=0;
  v_sensitive_cases integer:=0;
  v_exec_def text;
  v_current_old boolean;
  v_current_new boolean;
  v_current_cases integer:=0;
begin
  select count(*) into v_family_count
  from lf_ops.reglas q
  cross join lateral jsonb_array_elements_text(q.valor_config->'families') e(value)
  where q.codigo='B2B-RULE-STORY-READINESS-001';
  if v_family_count<>47 then raise exception 'S28_REGRESSION_FAMILY_UNIVERSE_MISMATCH:%',v_family_count; end if;

  -- Full 47-family exact-output equivalence on one B2B and one B2C surface.
  for r in select * from (values ('B2B-CARGA-001'::text),('HOME_002'::text)) x(screen_code)
  loop
    select p.id into strict v_screen_id from lf_ops.pantallas p where p.codigo=r.screen_code;
    v_graph:=programacion.fn_input_screen_canonical_graph(v_screen_id,19);

    for f in
      select e.value as family_code
      from lf_ops.reglas q
      cross join lateral jsonb_array_elements_text(q.valor_config->'families') e(value)
      where q.codigo='B2B-RULE-STORY-READINESS-001'
      order by e.value
    loop
      v_old:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(v_screen_id,f.family_code,19,v_graph);
      v_new:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(v_screen_id,f.family_code,19,v_graph);
      v_full_cases:=v_full_cases+1;
      if v_old is distinct from v_new then
        raise exception 'S28_REGRESSION_CLASSIFIER_OUTPUT_MISMATCH:%:%',r.screen_code,f.family_code;
      end if;
      if nullif(v_new->>'classifier_sha256','') is null then
        raise exception 'S28_REGRESSION_CLASSIFIER_SHA_MISSING:%:%',r.screen_code,f.family_code;
      end if;
    end loop;
  end loop;

  if v_full_cases<>94 then raise exception 'S28_REGRESSION_FULL_CASE_COUNT_MISMATCH:%',v_full_cases; end if;

  -- Sensitive semantic families on auth/OTP surfaces: authority, N/A, fields, actions,
  -- transitions, security and design depth must remain byte-equivalent.
  for r in select * from (values ('B2B-AUTH-004'::text),('ONB_002'::text)) x(screen_code)
  loop
    select p.id into strict v_screen_id from lf_ops.pantallas p where p.codigo=r.screen_code;
    v_graph:=programacion.fn_input_screen_canonical_graph(v_screen_id,19);

    for f in
      select unnest(array[
        'ACTIONS','DESIGN_SYSTEM','FIELDS','MFA_OTP_SSO','PERMISSIONS','PROFILES',
        'ROUTING_NAVIGATION','SECURITY','TRANSITIONS','VALIDATIONS'
      ]::text[]) as family_code
    loop
      v_old:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(v_screen_id,f.family_code,19,v_graph);
      v_new:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(v_screen_id,f.family_code,19,v_graph);
      v_sensitive_cases:=v_sensitive_cases+1;
      if v_old is distinct from v_new then
        raise exception 'S28_REGRESSION_SENSITIVE_OUTPUT_MISMATCH:%:%',r.screen_code,f.family_code;
      end if;
    end loop;
  end loop;

  if v_sensitive_cases<>20 then raise exception 'S28_REGRESSION_SENSITIVE_CASE_COUNT_MISMATCH:%',v_sensitive_cases; end if;

  -- If durable readiness runs are present in the test database, compare complete old/new
  -- currentness decisions on a bounded mix of latest COMPLETED and predecessor runs.
  for r in
    with latest as (
      select distinct on (pantalla_id) id,pantalla_id
      from programacion.input_readiness_runs
      where status='COMPLETED'
      order by pantalla_id,id desc
    ), recent_latest as (
      select id from latest order by id desc limit 6
    ), predecessors as (
      select rr.id
      from programacion.input_readiness_runs rr
      join latest l on l.pantalla_id=rr.pantalla_id and rr.id<l.id
      order by rr.id desc
      limit 4
    ), sample as (
      select id from recent_latest
      union
      select id from predecessors
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

  -- No runtime switch: the proven public execution still uses cached_v1 until a separate
  -- promotion decision is explicitly approved.
  select pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure) into v_exec_def;
  if position('fn_input_readiness_run_is_current_cached_v1' in v_exec_def)=0
     or position('fn_input_readiness_run_is_current_cached_v2' in v_exec_def)>0 then
    raise exception 'S28_REGRESSION_RUNTIME_SWITCH_DETECTED';
  end if;

  raise notice 'S28_GRAPH_REUSE_REGRESSION_PASS full_cases=% sensitive_cases=% currentness_cases=%',v_full_cases,v_sensitive_cases,v_current_cases;
end;
$regression$;
