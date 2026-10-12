-- T-REMED: wire derived global-level rules into the Input Governance rule path.
-- 1) fn_t_remed_global_rules_v1 now considers VIGENTE rules only (candidates reach VIGENTE through the judge-gated promotion step); this also removes the per-call judge cost.
-- 2) fn_input_effective_rule_links_v1 gains an `inherited` source (binding_source DERIVED_GLOBAL): global rules the screen does not already link and that carry no applicability_v1 object.
-- 3) lf_ops.fn_b2b_backoffice_login_contract: attached_rules also includes DERIVED_GLOBAL links (patched in place; guarded, fails if the expected fragment is absent).
-- Measured with ROLLBACK on 16 screens (47 families each): MISSING 227->136, PARTIAL 197->252, COMPLETE 322->358 (baseline before promotion: C287 P232 M227).
create or replace function programacion.fn_t_remed_global_rules_v1(p_min_share numeric default 0.25)
 returns table(regla_id bigint, regla_codigo text, regla_estado text, screens integer, share numeric, basis text)
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
  with tot as (select count(*)::numeric n from lf_ops.pantallas),
  use as (select z.regla_id rid, count(distinct z.pantalla_id)::int c from lf_ops.reglas_pantallas z group by 1)
  select r.id::bigint, r.codigo::text, r.estado::text, u.c, round(u.c/t.n,4), 'VIGENTE'::text
  from lf_ops.reglas r join use u on u.rid=r.id cross join tot t
  where r.estado='VIGENTE' and u.c >= coalesce(p_min_share,0.25)*t.n order by r.id
$fn$;
comment on function programacion.fn_t_remed_global_rules_v1(numeric) is
  'T-REMED derived global level: VIGENTE rules used by >= min_share of screens. Read-only, no stored flag.';

create or replace function programacion.fn_input_effective_rule_links_v1(p_pantalla_id integer, p_consumer text default 'INPUT_GOVERNANCE')
 returns table(pantalla_id integer, regla_id integer, binding_source text)
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
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
$fn$;

do $patch$
declare d text; d2 text; frag text; neu text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='lf_ops' and p.proname='fn_b2b_backoffice_login_contract';
  if d is null then raise exception 'LOGIN_CONTRACT_NOT_FOUND'; end if;
  if position('DERIVED_GLOBAL' in d)>0 then return; end if;
  frag:=E'attached_rules as (\n  select rp.pantalla_id, r.*\n  from lf_ops.reglas_pantallas rp\n  join lf_ops.reglas r on r.id = rp.regla_id\n  join ctx c on c.pantalla_id = rp.pantalla_id\n)';
  neu:=E'attached_rules as (\n  select rp.pantalla_id, r.*\n  from lf_ops.reglas_pantallas rp\n  join lf_ops.reglas r on r.id = rp.regla_id\n  join ctx c on c.pantalla_id = rp.pantalla_id\n  union all\n  select l.pantalla_id, r.*\n  from ctx c\n  cross join lateral programacion.fn_input_effective_rule_links_v1(c.pantalla_id, ''INPUT_GOVERNANCE'') l\n  join lf_ops.reglas r on r.id = l.regla_id\n  where l.binding_source = ''DERIVED_GLOBAL''\n)';
  d2:=replace(d,frag,neu);
  if d2=d then raise exception 'LOGIN_CONTRACT_FRAGMENT_NOT_FOUND'; end if;
  execute d2;
end $patch$;
