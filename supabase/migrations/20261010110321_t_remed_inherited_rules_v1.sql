-- T-REMED completion by inheritance (layer 2 candidate source), read-only and derived: no table, never stale.
-- fn_t_remed_inherited_rules_v1(pantalla): rules that the most similar screens already have and this screen lacks.
--   similarity  : generic signals read from lf_ops.pantallas (code prefix, module, flow, text overlap of name/description/objective)
--   neighbours  : screens with MORE rules than the target (a thin screen never learns from another thin one); k = round(sqrt(#screens-1))
--   proposal    : a rule held by >= p_min_share of the neighbours (default 0.3); by default only rules already VIGENTE (p_only_vigente),
--                 so nothing is promoted and no rule state changes. Writes nothing.
-- Measured on the 11 thin screens (rolled back, 54 links, VIGENTE-only): COMPLETE families 170 -> 186, MISSING 293 -> 265, PARTIAL 51 -> 63; deterministic, no writes.
create or replace function programacion.fn_t_remed_inherited_rules_v1(
  p_pantalla_id integer, p_min_share numeric default 0.3, p_only_vigente boolean default true)
 returns table(regla_id bigint, regla_codigo text, regla_estado text, share numeric, neighbor_count integer)
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
  with m as (
    select distinct rp.pantalla_id p, rp.regla_id r
    from lf_ops.reglas_pantallas rp join lf_ops.reglas x on x.id=rp.regla_id
    where x.estado in ('VIGENTE','CANDIDATO')
  ), sc as (
    select p, count(*) n from m group by p
  ), me as (
    select coalesce((select n from sc where p=p_pantalla_id),0) n
  ), pa as (
    select s.id p, split_part(s.codigo,'-',1) pf, s.module_code mc, s.flujo fl,
      (select array_agg(distinct w) from regexp_split_to_table(lower(coalesce(s.nombre,'')||' '||coalesce(s.descripcion,'')||' '||coalesce(s.objective,'')),'[^a-záéíóúñ0-9]+') w where length(w)>3) words
    from lf_ops.pantallas s
  ), cand as (
    select y.p,
      (x.pf=y.pf)::int + (x.mc is not distinct from y.mc)::int + (x.fl is not null and x.fl is not distinct from y.fl)::int +
      coalesce((select count(*) from unnest(x.words) w where w=any(y.words))::numeric
        / nullif(cardinality(x.words)+cardinality(y.words)-(select count(*) from unnest(x.words) w where w=any(y.words)),0),0) score
    from pa x join pa y on y.p<>x.p
    where x.p=p_pantalla_id and y.p in (select p from sc where n>(select n from me))
  ), kk as (
    select greatest(1,round(sqrt((select count(*) from sc)-1))::int) k
  ), nb as (
    select p from cand where score>0 order by score desc, md5(p::text||p_pantalla_id::text) limit (select k from kk)
  ), agg as (
    select m.r, count(*)::numeric/(select count(*) from nb) share, (select count(*) from nb)::int nn
    from nb join m on m.p=nb.p group by m.r
  )
  select x.id::bigint, x.codigo::text, x.estado::text, round(agg.share,3), agg.nn
  from agg join lf_ops.reglas x on x.id=agg.r
  where agg.share>=p_min_share
    and (not p_only_vigente or x.estado='VIGENTE')
    and agg.r not in (select r from m where p=p_pantalla_id)
  order by agg.share desc, x.id
$fn$;
comment on function programacion.fn_t_remed_inherited_rules_v1(integer,numeric,boolean) is
  'T-REMED inheritance source (read-only, derived). Rules held by >= p_min_share of the most similar screens that this screen lacks; VIGENTE only by default. Proposals only: linking them is a separate step.';
revoke all on function programacion.fn_t_remed_inherited_rules_v1(integer,numeric,boolean) from public, anon, authenticated;
