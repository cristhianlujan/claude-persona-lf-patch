-- N-4 / PAULO-169 — micro-lot A.
-- Persist governed applicability_v1 for the 32 current VIGENTE transversal rules.
-- This migration DOES NOT cut over the 13 Input Governance readers.
-- Legacy reglas_pantallas is used only as owner-authorized migration evidence to preserve
-- the current positive applicability set; after this migration applicability_v1 is authority.
-- Runtime matching never infers applicability from es_transversal and contains no rule-code scope map.

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

  if v_path is null or cardinality(v_path) = 0 or v_path[1] is distinct from 'target' then
    return false;
  end if;

  v_op := upper(coalesce(p_clause->>'op',''));
  v_actual := p_context #> v_path;

  if v_op = 'EXISTS' then
    return v_actual is not null;
  elsif v_op = 'EQ' then
    if not (p_clause ? 'value') or v_actual is null then return false; end if;
    return v_actual = p_clause->'value';
  elsif v_op = 'IN' then
    if jsonb_typeof(p_clause->'values') <> 'array' or v_actual is null then return false; end if;
    return exists (
      select 1 from jsonb_array_elements(p_clause->'values') as x(value)
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
  v_clause_count integer := 0;
begin
  if jsonb_typeof(p_selector) <> 'object' or jsonb_typeof(p_context) <> 'object' then return false; end if;
  if p_selector->>'schema_version' is distinct from 'lf-rule-applicability/v1' then return false; end if;
  if p_selector->>'status' is distinct from 'ACTIVE' then return false; end if;

  if exists (
    select 1 from jsonb_object_keys(p_selector) as k(key)
    where k.key not in ('schema_version','status','consumer_roles','all','any','provenance')
  ) then return false; end if;

  if jsonb_typeof(p_selector->'consumer_roles') <> 'array'
     or jsonb_array_length(p_selector->'consumer_roles') = 0 then return false; end if;
  if not exists (
    select 1 from jsonb_array_elements_text(p_selector->'consumer_roles') as c(role_code)
    where c.role_code = p_context->>'consumer_role'
  ) then return false; end if;

  v_all := coalesce(p_selector->'all','[]'::jsonb);
  v_any := coalesce(p_selector->'any','[]'::jsonb);
  if jsonb_typeof(v_all) <> 'array' or jsonb_typeof(v_any) <> 'array' then return false; end if;
  v_clause_count := jsonb_array_length(v_all) + jsonb_array_length(v_any);
  -- Consumer-only applicability would be an implicit global. N-4 forbids it.
  if v_clause_count = 0 then return false; end if;

  for v_clause in select value from jsonb_array_elements(v_all)
  loop
    if programacion.fn_input_rule_selector_clause_matches_v1(v_clause,p_context) is not true then return false; end if;
  end loop;

  if jsonb_array_length(v_any) > 0 then
    for v_clause in select value from jsonb_array_elements(v_any)
    loop
      if programacion.fn_input_rule_selector_clause_matches_v1(v_clause,p_context) is true then
        v_any_match := true; exit;
      end if;
    end loop;
    if not v_any_match then return false; end if;
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

create or replace function programacion.fn_input_declared_rule_links_v1(
  p_pantalla_id integer,
  p_consumer text default 'INPUT_GOVERNANCE'
)
returns table(pantalla_id integer, regla_id integer, binding_source text)
language sql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
  with ctx as (
    select programacion.fn_input_rule_target_context_v1(p_pantalla_id,p_consumer) as context
  )
  select p_pantalla_id,r.id,'DECLARATIVE_APPLICABILITY_V1'::text
  from lf_ops.reglas r
  cross join ctx
  where r.estado='VIGENTE'
    and jsonb_typeof(r.valor_config->'applicability_v1')='object'
    and ctx.context is not null
    and programacion.fn_input_rule_selector_matches_v1(r.valor_config->'applicability_v1',ctx.context)
$function$;

comment on function programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb) is
  'N-4 domain-local data-driven selector evaluator. Fail-closed; no rule-code map, no business-scope enum, no es_transversal inference.';
comment on function programacion.fn_input_declared_rule_links_v1(integer,text) is
  'N-4 shadow resolver over governed lf_ops.reglas.valor_config.applicability_v1. VIGENTE + explicit selector match only.';

-- Owner-authorized migration: convert the CURRENT positive legacy binding set for the 32
-- VIGENTE transversal rules into governed selectors. Compression is allowed only where it
-- is exactly equivalent across the complete current canonical target registry.
do $seed$
declare
  v_rule_count integer;
  v_preexisting integer;
  v_updated integer;
begin
  select count(*) into v_rule_count
  from lf_ops.reglas
  where estado='VIGENTE' and es_transversal=true;
  if v_rule_count <> 32 then raise exception 'N4_RULE_COHORT_DRIFT:expected=32 actual=%',v_rule_count; end if;

  select count(*) into v_preexisting
  from lf_ops.reglas
  where estado='VIGENTE' and es_transversal=true
    and valor_config ? 'applicability_v1';
  if v_preexisting <> 0 then raise exception 'N4_APPLICABILITY_PREEXISTS:%',v_preexisting; end if;

  with migrated_rules as (
    select id from lf_ops.reglas where estado='VIGENTE' and es_transversal=true
  ), targets as (
    select p.id as pantalla_id,m.module_code,a.app_shell_code
    from lf_ops.pantallas p
    left join lf_ops.modulos m on m.module_id=p.module_id
    left join lf_ops.app_shells a on a.app_shell_id=m.app_shell_id
  ), positive as (
    select mr.id as regla_id,t.pantalla_id,t.module_code,t.app_shell_code
    from migrated_rules mr
    join lf_ops.reglas_pantallas rp on rp.regla_id=mr.id
    join targets t on t.pantalla_id=rp.pantalla_id
  ), full_fronts as (
    select mr.id as regla_id,t.app_shell_code
    from migrated_rules mr
    join targets t on t.app_shell_code is not null
    group by mr.id,t.app_shell_code
    having count(*) = count(*) filter(where exists(
      select 1 from positive p where p.regla_id=mr.id and p.pantalla_id=t.pantalla_id
    ))
  ), full_modules as (
    select mr.id as regla_id,t.module_code
    from migrated_rules mr
    join targets t on t.module_code is not null
    where not exists (
      select 1 from full_fronts f where f.regla_id=mr.id and f.app_shell_code=t.app_shell_code
    )
    group by mr.id,t.module_code
    having count(*) = count(*) filter(where exists(
      select 1 from positive p where p.regla_id=mr.id and p.pantalla_id=t.pantalla_id
    ))
  ), residual as (
    select p.regla_id,p.pantalla_id
    from positive p
    where not exists(select 1 from full_fronts f where f.regla_id=p.regla_id and f.app_shell_code=p.app_shell_code)
      and not exists(select 1 from full_modules m where m.regla_id=p.regla_id and m.module_code=p.module_code)
  ), parts as (
    select mr.id as regla_id,
      coalesce((select jsonb_agg(f.app_shell_code order by f.app_shell_code) from full_fronts f where f.regla_id=mr.id),'[]'::jsonb) as fronts,
      coalesce((select jsonb_agg(m.module_code order by m.module_code) from full_modules m where m.regla_id=mr.id),'[]'::jsonb) as modules,
      coalesce((select jsonb_agg(x.pantalla_id order by x.pantalla_id) from residual x where x.regla_id=mr.id),'[]'::jsonb) as screens,
      exists(select 1 from positive p where p.regla_id=mr.id) as has_positive
    from migrated_rules mr
  ), seeded as (
    select regla_id,
      jsonb_build_object(
        'schema_version','lf-rule-applicability/v1',
        'status',case when has_positive then 'ACTIVE' else 'UNRESOLVED' end,
        'consumer_roles',jsonb_build_array('INPUT_GOVERNANCE'),
        'all','[]'::jsonb,
        'any',
          (case when jsonb_array_length(fronts)>0 then jsonb_build_array(jsonb_build_object('path',jsonb_build_array('target','app_shell','app_shell_code'),'op','IN','values',fronts)) else '[]'::jsonb end)
          || (case when jsonb_array_length(modules)>0 then jsonb_build_array(jsonb_build_object('path',jsonb_build_array('target','module','module_code'),'op','IN','values',modules)) else '[]'::jsonb end)
          || (case when jsonb_array_length(screens)>0 then jsonb_build_array(jsonb_build_object('path',jsonb_build_array('target','screen','id'),'op','IN','values',screens)) else '[]'::jsonb end),
        'provenance',jsonb_build_object(
          'authority','OWNER_AUTHORIZED_GOVERNED_MIGRATION',
          'decision_event_id',19948,
          'r14_event_id',19951,
          'migration_version','20261002173000',
          'migration_source','LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY'
        )
      ) as applicability
    from parts
  )
  update lf_ops.reglas r
  set valor_config=jsonb_set(coalesce(r.valor_config,'{}'::jsonb),'{applicability_v1}',s.applicability,true),
      updated_at=now()
  from seeded s
  where r.id=s.regla_id;

  get diagnostics v_updated = row_count;
  if v_updated <> 32 then raise exception 'N4_APPLICABILITY_UPDATE_COUNT:%',v_updated; end if;
end;
$seed$;

-- Shadow gate: declarative applicability must be exactly equivalent to legacy positive
-- bindings for all current targets before any IG reader is allowed to cut over.
do $equivalence$
declare
  v_loaded integer;
  v_diff integer;
  v_baseline_diff integer;
  v_active integer;
  v_unresolved integer;
begin
  select count(*),
         count(*) filter(where valor_config#>>'{applicability_v1,status}'='ACTIVE'),
         count(*) filter(where valor_config#>>'{applicability_v1,status}'='UNRESOLVED')
    into v_loaded,v_active,v_unresolved
  from lf_ops.reglas
  where estado='VIGENTE' and es_transversal=true
    and jsonb_typeof(valor_config->'applicability_v1')='object';
  if v_loaded <> 32 or v_active+v_unresolved <> 32 then
    raise exception 'N4_APPLICABILITY_LOAD_READBACK:loaded=% active=% unresolved=%',v_loaded,v_active,v_unresolved;
  end if;

  with rules as (
    select id from lf_ops.reglas where estado='VIGENTE' and es_transversal=true
  ), targets as (
    select id as pantalla_id from lf_ops.pantallas
  ), cmp as (
    select r.id,t.pantalla_id,
      exists(select 1 from lf_ops.reglas_pantallas rp where rp.regla_id=r.id and rp.pantalla_id=t.pantalla_id) as legacy_applies,
      exists(select 1 from programacion.fn_input_declared_rule_links_v1(t.pantalla_id,'INPUT_GOVERNANCE') d where d.regla_id=r.id) as declared_applies
    from rules r cross join targets t
  )
  select count(*) into v_diff from cmp where legacy_applies is distinct from declared_applies;
  if v_diff <> 0 then raise exception 'N4_ALL_TARGET_EQUIVALENCE_FAILED:%',v_diff; end if;

  with rules as (
    select id from lf_ops.reglas where estado='VIGENTE' and es_transversal=true
  ), targets(pantalla_id) as (
    values (1),(2),(3),(5),(43),(51),(52),(53),(54),(55),(56),(57),(58)
  ), cmp as (
    select r.id,t.pantalla_id,
      exists(select 1 from lf_ops.reglas_pantallas rp where rp.regla_id=r.id and rp.pantalla_id=t.pantalla_id) as legacy_applies,
      exists(select 1 from programacion.fn_input_declared_rule_links_v1(t.pantalla_id,'INPUT_GOVERNANCE') d where d.regla_id=r.id) as declared_applies
    from rules r cross join targets t
  )
  select count(*) into v_baseline_diff from cmp where legacy_applies is distinct from declared_applies;
  if v_baseline_diff <> 0 then raise exception 'N4_13X32_EQUIVALENCE_FAILED:%',v_baseline_diff; end if;

  if position('es_transversal' in lower(pg_get_functiondef('programacion.fn_input_declared_rule_links_v1(integer,text)'::regprocedure))) > 0 then
    raise exception 'N4_RUNTIME_ES_TRANSVERSAL_DEPENDENCY_FORBIDDEN';
  end if;

  if programacion.fn_input_rule_selector_matches_v1(
    '{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[],"any":[]}'::jsonb,
    '{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"id":1}}}'::jsonb
  ) is true then raise exception 'N4_CONSUMER_ONLY_IMPLICIT_GLOBAL_FORBIDDEN'; end if;

  if programacion.fn_input_rule_selector_matches_v1(
    '{"schema_version":"lf-rule-applicability/v1","status":"UNRESOLVED","consumer_roles":["INPUT_GOVERNANCE"],"all":[],"any":[{"path":["target","screen","id"],"op":"EQ","value":1}]}'::jsonb,
    '{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"id":1}}}'::jsonb
  ) is true then raise exception 'N4_UNRESOLVED_MUST_FAIL_CLOSED'; end if;
end;
$equivalence$;

commit;
