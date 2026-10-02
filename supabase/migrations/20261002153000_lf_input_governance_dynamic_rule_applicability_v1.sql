-- N-4 / PAULO-169 — dynamic, data-driven applicability for transversal rules in Input Governance.
-- Source-first. Exact-version transport required for live application.
-- Do NOT use SUPABASE_MCP_APPLY_MIGRATION when exact version parity is required.
-- No rule-code hardcoding, no GLOBAL/FRONT/MODULE enum, no automatic scope inference.
-- Canonical selector lives in lf_ops.reglas.valor_config->'applicability_v1'.
-- Existing lf_ops.reglas_pantallas rows remain an explicit legacy binding surface only.
-- Legacy bindings preserve their current visibility, including CANDIDATO rows used as evidence;
-- lifecycle VIGENTE is required only for NEW declarative auto-applicability.

begin;

create or replace function programacion.fn_input_rule_selector_clause_matches_v1(
  p_clause jsonb,
  p_context jsonb
)
returns boolean
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v_path text[];
  v_actual jsonb;
  v_op text;
begin
  if jsonb_typeof(p_clause) <> 'object' or jsonb_typeof(p_context) <> 'object' then
    return false;
  end if;

  if jsonb_typeof(p_clause->'path') <> 'array' or jsonb_array_length(p_clause->'path') = 0 then
    return false;
  end if;

  select array_agg(value order by ordinality)
    into v_path
  from jsonb_array_elements_text(p_clause->'path') with ordinality as x(value, ordinality);

  if v_path is null or cardinality(v_path) = 0 then
    return false;
  end if;

  v_op := upper(coalesce(p_clause->>'op',''));
  v_actual := p_context #> v_path;

  if v_op = 'EXISTS' then
    return v_actual is not null;
  elsif v_op = 'EQ' then
    if not (p_clause ? 'value') or v_actual is null then
      return false;
    end if;
    return v_actual = p_clause->'value';
  elsif v_op = 'IN' then
    if jsonb_typeof(p_clause->'values') <> 'array' or v_actual is null then
      return false;
    end if;
    return exists (
      select 1
      from jsonb_array_elements(p_clause->'values') as x(value)
      where x.value = v_actual
    );
  end if;

  return false;
end;
$function$;

create or replace function programacion.fn_input_rule_selector_matches_v1(
  p_selector jsonb,
  p_context jsonb
)
returns boolean
language plpgsql
immutable
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_all jsonb;
  v_any jsonb;
  v_clause jsonb;
  v_any_match boolean := false;
begin
  if jsonb_typeof(p_selector) <> 'object' or jsonb_typeof(p_context) <> 'object' then
    return false;
  end if;

  if p_selector->>'schema_version' is distinct from 'lf-rule-applicability/v1' then
    return false;
  end if;

  if exists (
    select 1
    from jsonb_object_keys(p_selector) as k(key)
    where k.key not in ('schema_version','consumer_roles','all','any')
  ) then
    return false;
  end if;

  if jsonb_typeof(p_selector->'consumer_roles') <> 'array'
     or jsonb_array_length(p_selector->'consumer_roles') = 0 then
    return false;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements_text(p_selector->'consumer_roles') as c(role_code)
    where c.role_code = p_context->>'consumer_role'
  ) then
    return false;
  end if;

  if not (p_selector ? 'all') and not (p_selector ? 'any') then
    return false;
  end if;

  v_all := coalesce(p_selector->'all','[]'::jsonb);
  v_any := coalesce(p_selector->'any','[]'::jsonb);

  if jsonb_typeof(v_all) <> 'array' or jsonb_typeof(v_any) <> 'array' then
    return false;
  end if;

  for v_clause in select value from jsonb_array_elements(v_all)
  loop
    if programacion.fn_input_rule_selector_clause_matches_v1(v_clause,p_context) is not true then
      return false;
    end if;
  end loop;

  if jsonb_array_length(v_any) > 0 then
    for v_clause in select value from jsonb_array_elements(v_any)
    loop
      if programacion.fn_input_rule_selector_clause_matches_v1(v_clause,p_context) is true then
        v_any_match := true;
        exit;
      end if;
    end loop;
    if not v_any_match then
      return false;
    end if;
  end if;

  return true;
end;
$function$;

create or replace function programacion.fn_input_rule_target_context_v1(
  p_pantalla_id integer,
  p_consumer text
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
  select jsonb_build_object(
    'schema_version','lf-rule-target-context/v1',
    'consumer_role',p_consumer,
    'target',jsonb_build_object(
      'screen',to_jsonb(p),
      'module',case when m.module_id is null then null else to_jsonb(m) end,
      'app_shell',case when a.app_shell_id is null then null else to_jsonb(a) end
    )
  )
  from lf_ops.pantallas p
  left join lf_ops.modulos m on m.module_id=p.module_id
  left join lf_ops.app_shells a on a.app_shell_id=m.app_shell_id
  where p.id=p_pantalla_id
$function$;

create or replace function programacion.fn_input_effective_rule_links_v1(
  p_pantalla_id integer,
  p_consumer text default 'INPUT_GOVERNANCE'
)
returns table(
  pantalla_id integer,
  regla_id integer,
  binding_source text
)
language sql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
  with ctx as (
    select programacion.fn_input_rule_target_context_v1(p_pantalla_id,p_consumer) as context
  ),
  legacy as (
    select rp.pantalla_id,rp.regla_id,'LEGACY_EXPLICIT'::text as binding_source
    from lf_ops.reglas_pantallas rp
    where rp.pantalla_id=p_pantalla_id
  ),
  declared as (
    select p_pantalla_id as pantalla_id,r.id as regla_id,'DECLARATIVE_SELECTOR'::text as binding_source
    from lf_ops.reglas r
    cross join ctx
    where coalesce(r.es_transversal,false)=true
      and r.estado='VIGENTE'
      and jsonb_typeof(r.valor_config->'applicability_v1')='object'
      and ctx.context is not null
      and programacion.fn_input_rule_selector_matches_v1(r.valor_config->'applicability_v1',ctx.context)
      and not exists (
        select 1 from legacy l where l.regla_id=r.id
      )
  )
  select * from legacy
  union all
  select * from declared
$function$;

comment on function programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb) is
  'N-4 domain-local dynamic selector evaluator. No business scope enum and no rule-code hardcoding.';
comment on function programacion.fn_input_effective_rule_links_v1(integer,text) is
  'Effective IG rule links = all explicit legacy bindings unchanged + NEW VIGENTE transversal rules whose applicability_v1 selector matches canonical target context.';

-- Deterministic contract tests over synthetic context. These do not seed or infer rule scopes.
do $tests$
declare
  v_ctx jsonb := jsonb_build_object(
    'schema_version','lf-rule-target-context/v1',
    'consumer_role','INPUT_GOVERNANCE',
    'target',jsonb_build_object(
      'screen',jsonb_build_object('id',43,'codigo','B2B-CARGA-001'),
      'module',jsonb_build_object('module_code','B2B_CARGAS'),
      'app_shell',jsonb_build_object('app_shell_code','B2B_APP_SHELL')
    )
  );
begin
  if programacion.fn_input_rule_selector_matches_v1(
    '{"schema_version":"lf-rule-applicability/v1","consumer_roles":["INPUT_GOVERNANCE"],"all":[]}'::jsonb,
    v_ctx
  ) is not true then
    raise exception 'N4_DYNAMIC_SELECTOR_GLOBAL_CONSUMER_TEST_FAILED';
  end if;

  if programacion.fn_input_rule_selector_matches_v1(
    '{"schema_version":"lf-rule-applicability/v1","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","id"],"op":"IN","values":[1,43,58]}]}'::jsonb,
    v_ctx
  ) is not true then
    raise exception 'N4_DYNAMIC_SELECTOR_SCREEN_SET_TEST_FAILED';
  end if;

  if programacion.fn_input_rule_selector_matches_v1(
    '{"schema_version":"lf-rule-applicability/v1","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","module","module_code"],"op":"EQ","value":"B2B_CARGAS"}]}'::jsonb,
    v_ctx
  ) is not true then
    raise exception 'N4_DYNAMIC_SELECTOR_MODULE_TEST_FAILED';
  end if;

  if programacion.fn_input_rule_selector_matches_v1(
    '{"schema_version":"lf-rule-applicability/v1","consumer_roles":["OTHER_CONSUMER"],"all":[]}'::jsonb,
    v_ctx
  ) is true then
    raise exception 'N4_DYNAMIC_SELECTOR_CONSUMER_NEGATIVE_FAILED';
  end if;

  if programacion.fn_input_rule_selector_matches_v1(
    '{"schema_version":"lf-rule-applicability/v1","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","id"],"op":"IN","values":[999]}]}'::jsonb,
    v_ctx
  ) is true then
    raise exception 'N4_DYNAMIC_SELECTOR_NONMATCH_NEGATIVE_FAILED';
  end if;

  if programacion.fn_input_rule_selector_matches_v1(
    '{"consumer_roles":["INPUT_GOVERNANCE"],"all":[]}'::jsonb,
    v_ctx
  ) is true then
    raise exception 'N4_DYNAMIC_SELECTOR_SCHEMA_NEGATIVE_FAILED';
  end if;

  if exists (
    select 1
    from lf_ops.reglas_pantallas rp
    where not exists (
      select 1
      from programacion.fn_input_effective_rule_links_v1(rp.pantalla_id,'INPUT_GOVERNANCE') e
      where e.regla_id=rp.regla_id
    )
  ) then
    raise exception 'N4_LEGACY_BINDING_PRESERVATION_FAILED';
  end if;
end;
$tests$;

-- Patch only the 13 verified IG readers. Exact preimage MD5 blocks stale/drifted definitions.
do $patch$
declare
  v_row record;
  v_def text;
  v_new text;
  v_before integer;
  v_after integer;
begin
  for v_row in
    select * from (values
      ('programacion.fn_input_api_contract_resolution(integer)'::regprocedure,'80e934fa700e8d0014cee77f6b377ccf'),
      ('programacion.fn_input_design_binding_graph(integer)'::regprocedure,'48ed44ca56f00b790bb7694b60c31322'),
      ('programacion.fn_input_design_system_resolution_v1(integer)'::regprocedure,'9fedf8afcf6fa7b7772d5020fbfd2e08'),
      ('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure,'131d3d43204984ea646fe4536f83ad11'),
      ('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)'::regprocedure,'2a3e2f583c1c08d070039a1d85480d5f'),
      ('programacion.fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint)'::regprocedure,'d4e8c28fefab8a2cc7a4b95cc4bdb745'),
      ('programacion.fn_input_resolve_source_ref_v510(jsonb,integer,bigint)'::regprocedure,'035753b88e1e03259c11a96f9fd5706a'),
      ('programacion.fn_input_screen_canonical_graph(integer,bigint)'::regprocedure,'454e90aba0760cb5dd727e50bffc99be'),
      ('programacion.fn_input_security_capability_profile(integer)'::regprocedure,'d2801802d1dccf02f663fbc5e5a24f20'),
      ('programacion.fn_input_security_threat_expected_v510(integer)'::regprocedure,'01bdf9f01f57d1d2506fd437277dce93'),
      ('programacion.fn_input_subject_depth_expected(integer,text)'::regprocedure,'05fa302a4acce07c7d2395743dc14e8b'),
      ('programacion.fn_input_subject_depth_expected_v510(integer,text)'::regprocedure,'032b571cdf8ef629eb2ada1305a36251')
    ) as x(proc_oid, expected_md5)
  loop
    v_def := pg_get_functiondef(v_row.proc_oid);
    if md5(v_def) is distinct from v_row.expected_md5 then
      raise exception 'N4_FUNCTION_PREIMAGE_DRIFT:% expected=% actual=%',v_row.proc_oid,v_row.expected_md5,md5(v_def);
    end if;

    v_before :=
      (length(lower(v_def))-length(replace(lower(v_def),'from lf_ops.reglas_pantallas','')))/length('from lf_ops.reglas_pantallas')
      +
      (length(lower(v_def))-length(replace(lower(v_def),'join lf_ops.reglas_pantallas','')))/length('join lf_ops.reglas_pantallas');

    if v_before < 1 then
      raise exception 'N4_EXPECTED_RULE_LINK_READ_MISSING:%',v_row.proc_oid;
    end if;

    v_new := replace(v_def,
      'from lf_ops.reglas_pantallas',
      'from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,''INPUT_GOVERNANCE'')'
    );
    v_new := replace(v_new,
      'join lf_ops.reglas_pantallas',
      'join programacion.fn_input_effective_rule_links_v1(p_pantalla_id,''INPUT_GOVERNANCE'')'
    );

    execute v_new;

    select
      (length(lower(pg_get_functiondef(v_row.proc_oid)))-length(replace(lower(pg_get_functiondef(v_row.proc_oid)),'lf_ops.reglas_pantallas','')))/length('lf_ops.reglas_pantallas')
    into v_after;
    if v_after <> 0 then
      raise exception 'N4_RULE_LINK_READ_RESIDUAL:% count=%',v_row.proc_oid,v_after;
    end if;
  end loop;

  -- The remediation summary receives only p_run_id; derive its screen through its existing rc CTE.
  v_def := pg_get_functiondef('programacion.fn_input_actionable_remediation_summary_v1(bigint)'::regprocedure);
  if md5(v_def) <> '1fc06a6f4b3a70af92dcff7efcf9a821' then
    raise exception 'N4_FUNCTION_PREIMAGE_DRIFT:fn_input_actionable_remediation_summary_v1 actual=%',md5(v_def);
  end if;

  v_before :=
    (length(lower(v_def))-length(replace(lower(v_def),'join lf_ops.reglas_pantallas','')))/length('join lf_ops.reglas_pantallas');
  if v_before <> 2 then
    raise exception 'N4_REMEDIATION_RULE_LINK_COUNT_DRIFT:%',v_before;
  end if;

  v_new := replace(v_def,
    'join lf_ops.reglas_pantallas',
    'join programacion.fn_input_effective_rule_links_v1((select pantalla_id from rc limit 1),''INPUT_GOVERNANCE'')'
  );
  execute v_new;

  if position('lf_ops.reglas_pantallas' in lower(pg_get_functiondef('programacion.fn_input_actionable_remediation_summary_v1(bigint)'::regprocedure))) > 0 then
    raise exception 'N4_REMEDIATION_RULE_LINK_RESIDUAL';
  end if;
end;
$patch$;

-- Structural readback: exactly the original 13 readers must now consume the adapter.
do $readback$
declare
  v_direct integer;
  v_consumers integer;
begin
  select count(*) into v_direct
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname in (
      'fn_input_actionable_remediation_summary_v1',
      'fn_input_api_contract_resolution',
      'fn_input_design_binding_graph',
      'fn_input_design_system_resolution_v1',
      'fn_input_governance_semantic_probe_v3',
      'fn_input_governance_semantic_probe_v3_cached_v1',
      'fn_input_governance_shadow_priority_oracle_v2',
      'fn_input_resolve_source_ref_v510',
      'fn_input_screen_canonical_graph',
      'fn_input_security_capability_profile',
      'fn_input_security_threat_expected_v510',
      'fn_input_subject_depth_expected',
      'fn_input_subject_depth_expected_v510'
    )
    and p.prosrc ilike '%lf_ops.reglas_pantallas%';

  select count(*) into v_consumers
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname in (
      'fn_input_actionable_remediation_summary_v1',
      'fn_input_api_contract_resolution',
      'fn_input_design_binding_graph',
      'fn_input_design_system_resolution_v1',
      'fn_input_governance_semantic_probe_v3',
      'fn_input_governance_semantic_probe_v3_cached_v1',
      'fn_input_governance_shadow_priority_oracle_v2',
      'fn_input_resolve_source_ref_v510',
      'fn_input_screen_canonical_graph',
      'fn_input_security_capability_profile',
      'fn_input_security_threat_expected_v510',
      'fn_input_subject_depth_expected',
      'fn_input_subject_depth_expected_v510'
    )
    and p.prosrc ilike '%fn_input_effective_rule_links_v1%';

  if v_direct <> 0 or v_consumers <> 13 then
    raise exception 'N4_STRUCTURAL_READBACK_FAILED:direct=% consumers=%',v_direct,v_consumers;
  end if;
end;
$readback$;

commit;
