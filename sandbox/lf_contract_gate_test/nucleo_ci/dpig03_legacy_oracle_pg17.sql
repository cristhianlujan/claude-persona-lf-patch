-- SOLO PG17 aislado, no se aplica en la base real. Oráculo de selección legado con los 7 cuerpos PG leídos de LF_SUPABASE_SANDBOX, sin alterar su lógica.
-- Fuente 2026-11-21. Las tablas adicionales son proyecciones sintéticas de estructura; sin datos cliente.
CREATE SCHEMA IF NOT EXISTS programacion;
CREATE TABLE IF NOT EXISTS lf_ops.app_shells (design_system_code text);
ALTER TABLE lf_ops.app_shells ADD COLUMN IF NOT EXISTS app_shell_id bigint;
ALTER TABLE lf_ops.app_shells ADD COLUMN IF NOT EXISTS app_shell_code text;
ALTER TABLE lf_ops.modulos ADD COLUMN IF NOT EXISTS app_shell_id bigint;
ALTER TABLE lf_ops.modulos ADD COLUMN IF NOT EXISTS module_code text;
-- source md5 573649516a63d889f69725690a8de8db
CREATE OR REPLACE FUNCTION programacion.fn_input_rule_target_context_v1(p_pantalla_id integer, p_consumer text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
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

-- source md5 1123257c0c6c7eb1e2aa26783f3ccc0a
CREATE OR REPLACE FUNCTION programacion.fn_input_rule_selector_clause_matches_v1(p_clause jsonb, p_context jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
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

-- source md5 3b912c7872aceff83de24e9e8d1ad934
CREATE OR REPLACE FUNCTION programacion.fn_input_rule_selector_matches_v1(p_selector jsonb, p_context jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
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

-- source md5 433445c108c36b25cf26f5a1bddb7a99
CREATE OR REPLACE FUNCTION programacion.fn_t_remed_scope_judge_v1(p_min_share numeric DEFAULT 0.25)
 RETURNS TABLE(regla_id bigint, regla_codigo text, categoria text, real_shells integer, category_shells integer, pendiente boolean, verdict text, reason text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
  with tot as (select count(*)::numeric n from lf_ops.pantallas),
  use as (select regla_id rid, count(distinct pantalla_id) c from lf_ops.reglas_pantallas group by 1),
  rs as (
    select distinct rp.regla_id rid, m.app_shell_id sh
    from lf_ops.reglas_pantallas rp join lf_ops.pantallas s on s.id=rp.pantalla_id join lf_ops.modulos m on m.module_id=s.module_id
    where m.app_shell_id is not null
  ), cand as (
    select r.id, r.codigo, r.categoria, r.pendiente_decision
    from lf_ops.reglas r left join use u on u.rid=r.id cross join tot t
    where r.estado='VIGENTE' and r.es_transversal and coalesce(u.c,0) < coalesce(p_min_share,0.25)*t.n
  ), own as (select rid, count(*)::int n from rs group by 1),
  cat as (
    select c.id, count(distinct x.sh)::int n
    from cand c join lf_ops.reglas o on o.categoria is not distinct from c.categoria and o.id<>c.id and o.estado='VIGENTE'
    join rs x on x.rid=o.id group by c.id
  )
  select c.id::bigint, c.codigo::text, c.categoria::text, coalesce(w.n,0), coalesce(k.n,0), coalesce(c.pendiente_decision,false),
    case when coalesce(c.pendiente_decision,false) then 'MANUAL'
         when coalesce(w.n,0)>=2 or coalesce(k.n,0)>=2 then 'PASS_GLOBAL' else 'MANUAL' end,
    case when coalesce(c.pendiente_decision,false) then 'PENDING_DECISION'
         when coalesce(w.n,0)>=2 then 'USED_IN_2_CHANNELS'
         when coalesce(k.n,0)>=2 then 'CATEGORY_USED_IN_2_CHANNELS'
         else 'NO_CROSS_CHANNEL_EVIDENCE' end
  from cand c left join own w on w.rid=c.id left join cat k on k.id=c.id order by c.id
$function$;

-- source md5 7d8b7a58f16bc5b53867c3322fd1befb
CREATE OR REPLACE FUNCTION programacion.fn_t_remed_global_rules_v1(p_min_share numeric DEFAULT 0.25)
 RETURNS TABLE(regla_id bigint, regla_codigo text, regla_estado text, screens integer, share numeric, basis text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
  with tot as (select count(*)::numeric n from lf_ops.pantallas),
  use as (select z.regla_id rid, count(distinct z.pantalla_id)::int c from lf_ops.reglas_pantallas z group by 1),
  pj as (select j.regla_id rid from programacion.fn_t_remed_scope_judge_v1(p_min_share) j where j.verdict='PASS_GLOBAL')
  select r.id::bigint, r.codigo::text, r.estado::text, coalesce(u.c,0), round(coalesce(u.c,0)/t.n,4),
         case when coalesce(u.c,0) >= coalesce(p_min_share,0.25)*t.n then 'USAGE' else 'DECLARED' end
  from lf_ops.reglas r left join use u on u.rid=r.id cross join tot t
  where r.estado='VIGENTE' and (coalesce(u.c,0) >= coalesce(p_min_share,0.25)*t.n or r.id in (select rid from pj)) order by r.id
$function$;

-- source md5 990226616c7f48fc82346799e54c2bdf
CREATE OR REPLACE FUNCTION programacion.fn_input_declared_rule_links_v1(p_pantalla_id integer, p_consumer text DEFAULT 'INPUT_GOVERNANCE'::text)
 RETURNS TABLE(pantalla_id integer, regla_id integer, binding_source text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
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

-- source md5 156247a925d74c6f4accd7a6d2508489
CREATE OR REPLACE FUNCTION programacion.fn_input_effective_rule_links_v1(p_pantalla_id integer, p_consumer text DEFAULT 'INPUT_GOVERNANCE'::text)
 RETURNS TABLE(pantalla_id integer, regla_id integer, binding_source text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
  with legacy as (
    select rp.pantalla_id,rp.regla_id,'LEGACY_EXPLICIT'::text as binding_source
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and jsonb_typeof(r.valor_config->'applicability_v1') is distinct from 'object'
  ), declared as (
    select d.pantalla_id,d.regla_id,d.binding_source from programacion.fn_input_declared_rule_links_v1(p_pantalla_id,p_consumer) d
  ), inherited as (
    select p_pantalla_id as pantalla_id, g.regla_id::integer as regla_id, 'DERIVED_GLOBAL'::text as binding_source
    from programacion.fn_t_remed_global_rules_v1(0.25) g join lf_ops.reglas r on r.id=g.regla_id
    where exists(select 1 from lf_ops.pantallas where id=p_pantalla_id)
      and jsonb_typeof(r.valor_config->'applicability_v1') is distinct from 'object'
      and not exists(select 1 from lf_ops.reglas_pantallas z where z.pantalla_id=p_pantalla_id and z.regla_id=g.regla_id)
  )
  select * from legacy union all select * from declared union all select * from inherited
$function$;

