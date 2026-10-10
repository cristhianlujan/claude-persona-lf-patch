-- T-REMED: rule levels derived from real use (no table, no stored flag).
-- fn_t_remed_global_rules_v1(min_share): rules used by at least min_share of all screens that are either VIGENTE or
--   CANDIDATO with a PASS verdict from the independent promotion judge. The share is a caller parameter (default 0.25), not code.
-- fn_t_remed_effective_rules_v1(screen, min_share): the rules a screen has by itself plus the global ones it inherits.
-- Read-only. Measured (16 screens, rolled back): share 0.25 -> MISSING 227->136, COMPLETE 287->349; share 0.10 -> MISSING 129, COMPLETE 380; share 0.50 -> no rule qualifies.

create or replace function programacion.fn_t_remed_global_rules_v1(p_min_share numeric default 0.25)
 returns table(regla_id bigint, regla_codigo text, regla_estado text, screens integer, share numeric, basis text)
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
  with tot as (select count(*)::numeric n from lf_ops.pantallas),
  use as (select z.regla_id rid, count(distinct z.pantalla_id)::int c from lf_ops.reglas_pantallas z group by 1),
  pass as (select v.regla_id rid from programacion.fn_t_remed_rule_promotion_verdicts_v1(5,null) v where v.verdict='PASS')
  select r.id::bigint, r.codigo::text, r.estado::text, u.c, round(u.c/t.n,4),
         case when r.estado='VIGENTE' then 'VIGENTE' else 'JUDGE_PASS' end
  from lf_ops.reglas r join use u on u.rid=r.id cross join tot t
  where u.c >= coalesce(p_min_share,0.25)*t.n
    and (r.estado='VIGENTE' or (r.estado='CANDIDATO' and r.id in (select rid from pass)))
  order by r.id
$fn$;

create or replace function programacion.fn_t_remed_effective_rules_v1(p_pantalla_id integer, p_min_share numeric default 0.25)
 returns table(regla_id bigint, origin text)
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
  select z.regla_id::bigint, 'OWN'::text from lf_ops.reglas_pantallas z
   where z.pantalla_id=p_pantalla_id and exists(select 1 from lf_ops.pantallas where id=p_pantalla_id)
  union
  select g.regla_id, 'GLOBAL' from programacion.fn_t_remed_global_rules_v1(p_min_share) g
   where exists(select 1 from lf_ops.pantallas where id=p_pantalla_id)
     and not exists(select 1 from lf_ops.reglas_pantallas z where z.pantalla_id=p_pantalla_id and z.regla_id=g.regla_id)
$fn$;

comment on function programacion.fn_t_remed_global_rules_v1(numeric) is
  'T-REMED derived global level: rules used by >= min_share of screens, VIGENTE or CANDIDATO with judge PASS. Read-only, no stored flag.';
comment on function programacion.fn_t_remed_effective_rules_v1(integer, numeric) is
  'T-REMED effective rules of a screen: OWN links plus inherited GLOBAL ones. Read-only; unknown screen returns no rows.';
revoke all on function programacion.fn_t_remed_global_rules_v1(numeric), programacion.fn_t_remed_effective_rules_v1(integer,numeric) from public, anon, authenticated;
