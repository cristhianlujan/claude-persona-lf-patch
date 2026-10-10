-- T-REMED: judge v2 and declared level.
-- 1) Promotion judge: NO_PENDING_MARKER now counts open definition dependencies from fn_t_remed_pending_deps_v1, ignoring
--    state words (a status name that merely contains PENDING) and the implementation_status path. The Input Governance resolvers
--    already separate definition completeness (coverage COMPLETE) from implementation readiness (stage blockers), so the judge does the same.
-- 2) Global level: a VIGENTE rule is global when used by >= min_share of screens (USAGE) or when its author declared it transversal
--    (es_transversal, basis DECLARED). The declared flag is existing data; no new table or column.
-- Measured with ROLLBACK on all 42 screens (promoting the 8 rules the new judge passes): MISSING 336->245, COMPLETE 950->1089, PARTIAL 668->620.
create or replace function programacion.fn_t_remed_rule_promotion_verdicts_v1(
  p_min_screens integer default 5, p_regla_id bigint default null)
 returns table(regla_id bigint, regla_codigo text, screens integer, criteria jsonb, verdict text, failed text[])
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
  with r as (
    select * from lf_ops.reglas where estado='CANDIDATO' and (p_regla_id is null or id=p_regla_id)
  ), n as (
    select z.regla_id rid, count(distinct z.pantalla_id)::int c from lf_ops.reglas_pantallas z group by 1
  ), pr as (
    select d.regla_id rid, count(*)::int pm from programacion.fn_t_remed_pending_deps_v1(p_regla_id) d
    where d.kind<>'STATE_WORD' and d.path<>'/implementation_status' group by 1
  ), dup as (
    select r.id, (r.valor_config is not null and r.valor_config<>'{}'::jsonb and exists(
      select 1 from lf_ops.reglas o where o.id<>r.id and o.estado in ('VIGENTE','CANDIDATO')
        and o.categoria is not distinct from r.categoria and o.valor_config=r.valor_config)) d
    from r
  ), c as (
    select r.id, r.codigo, coalesce(n.c,0) screens,
      jsonb_build_object(
        'NO_PENDING_DECISION', not coalesce(r.pendiente_decision,false),
        'NO_PENDING_MARKER', coalesce(pr.pm,0)=0,
        'HAS_STATED_REASON', nullif(btrim(coalesce(r.razon,'')),'') is not null,
        'USED_BY_ENOUGH_SCREENS', coalesce(n.c,0)>=p_min_screens,
        'NO_DUPLICATE_ACTIVE_RULE', not dup.d) crit
    from r left join n on n.rid=r.id left join pr on pr.rid=r.id join dup on dup.id=r.id
  )
  select c.id::bigint, c.codigo::text, c.screens, c.crit,
    case when exists(select 1 from jsonb_each(c.crit) e where e.value='false'::jsonb) then 'HOLD' else 'PASS' end,
    array(select e.key::text from jsonb_each(c.crit) e where e.value='false'::jsonb order by e.key)
  from c order by c.id
$fn$;
comment on function programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint) is
  'T-REMED rule promotion judge (read-only, derived). PASS only if all criteria hold; HOLD lists the failed ones. Does not promote.';
revoke all on function programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint) from public, anon, authenticated;

create or replace function programacion.fn_t_remed_global_rules_v1(p_min_share numeric default 0.25)
 returns table(regla_id bigint, regla_codigo text, regla_estado text, screens integer, share numeric, basis text)
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
  with tot as (select count(*)::numeric n from lf_ops.pantallas),
  use as (select z.regla_id rid, count(distinct z.pantalla_id)::int c from lf_ops.reglas_pantallas z group by 1)
  select r.id::bigint, r.codigo::text, r.estado::text, coalesce(u.c,0), round(coalesce(u.c,0)/t.n,4),
         case when coalesce(u.c,0) >= coalesce(p_min_share,0.25)*t.n then 'USAGE' else 'DECLARED' end
  from lf_ops.reglas r left join use u on u.rid=r.id cross join tot t
  where r.estado='VIGENTE' and (coalesce(u.c,0) >= coalesce(p_min_share,0.25)*t.n or r.es_transversal) order by r.id
$fn$;
comment on function programacion.fn_t_remed_global_rules_v1(numeric) is
  'T-REMED derived global level: VIGENTE rules used by >= min_share of screens (USAGE) or declared es_transversal (DECLARED). Read-only, no stored flag.';
