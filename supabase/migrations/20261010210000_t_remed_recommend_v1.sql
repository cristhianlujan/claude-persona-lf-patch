-- T-REMED recommendations for structural gaps (STATES, ERRORS, UI_MESSAGES, PROFILES, PERMISSIONS), derived and read-only (no table, never stale).
-- fn_t_remed_recommend_v1(pantalla, min_share): for each family where the screen has NO link at all, the catalog codes that >= min_share of the
-- k most similar screens (same similarity signals as fn_t_remed_inherited_rules_v1: code prefix, module, flow, text overlap) that DO have links use.
-- p_holdout=true ignores the screen's own links so the function can be scored against what the screen really has (leave-one-out).
-- Measured leave-one-out on the existing links (min_share 0.3), precision / recall: PROFILES 0.76 / 0.93, STATES 0.50 / 0.88, ERRORS 0.47 / 0.51,
-- PERMISSIONS 0.20 / 0.45, UI_MESSAGES 0.21 / 0.44. Coverage of real gaps: at least one recommendation for 22/22 PROFILES, 30/32 STATES, 15/17 ERRORS, 23/25 PERMISSIONS, 26/28 UI_MESSAGES.
-- These are RECOMMENDATIONS for a human decision, never links: the system writes nothing. k = round(sqrt(#candidate neighbours)).
create or replace function programacion.fn_t_remed_recommend_v1(p_pantalla_id integer, p_min_share numeric default 0.3, p_holdout boolean default false)
 returns table(family_code text, code text, share numeric, neighbor_count integer)
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
  with lk as (
    select 'STATES'::text kind, pantalla_id p, state_code::text code from lf_ops.pantallas_estados where status is distinct from 'INACTIVO'
    union all select 'ERRORS', pantalla_id, error_code::text from lf_ops.errores_pantallas where status is distinct from 'INACTIVO'
    union all select 'UI_MESSAGES', pantalla_id, message_code::text from lf_ops.mensajes_pantallas where status is distinct from 'INACTIVO'
    union all select 'PROFILES', pantalla_id, profile_code::text from lf_ops.pantallas_perfiles where status is distinct from 'INACTIVO'
    union all select 'PERMISSIONS', pantalla_id, permission_code::text from lf_ops.pantallas_permisos where status is distinct from 'INACTIVO'
  ), pa as (
    select s.id p, split_part(s.codigo,'-',1) pf, s.module_code mc, s.flujo fl,
      (select array_agg(distinct w) from regexp_split_to_table(lower(coalesce(s.nombre,'')||' '||coalesce(s.descripcion,'')||' '||coalesce(s.objective,'')),'[^a-záéíóúñ0-9]+') w where length(w)>3) words
    from lf_ops.pantallas s
  ), sim as (
    select y.p,
      (x.pf=y.pf)::int + (x.mc is not distinct from y.mc)::int + (x.fl is not null and x.fl is not distinct from y.fl)::int +
      coalesce((select count(*) from unnest(x.words) w where w=any(y.words))::numeric
        / nullif(cardinality(x.words)+cardinality(y.words)-(select count(*) from unnest(x.words) w where w=any(y.words)),0),0) score
    from pa x join pa y on y.p<>x.p where x.p=p_pantalla_id
  ), kinds as (select distinct kind from lk), gap as (
    select k.kind from kinds k where p_holdout or not exists(select 1 from lk where lk.kind=k.kind and lk.p=p_pantalla_id)
  ), nb as (
    select g.kind, s.p, s.score, row_number() over (partition by g.kind order by s.score desc, md5(s.p::text||p_pantalla_id::text)) rn
    from gap g join sim s on s.score>0 and exists(select 1 from lk where lk.kind=g.kind and lk.p=s.p)
  ), kk as (
    select kind, greatest(1,round(sqrt(count(*)))::int) k from nb group by kind
  ), top as (
    select nb.kind, nb.p from nb join kk on kk.kind=nb.kind where nb.rn<=kk.k
  ), agg as (
    select lk.kind, lk.code, count(distinct lk.p)::numeric / (select count(*) from top t2 where t2.kind=lk.kind) share,
           (select count(*) from top t2 where t2.kind=lk.kind)::int nn
    from top join lk on lk.kind=top.kind and lk.p=top.p group by lk.kind, lk.code
  )
  select kind::text, code::text, round(share,3), nn from agg where share>=p_min_share order by kind, share desc, code
$fn$;
comment on function programacion.fn_t_remed_recommend_v1(integer,numeric,boolean) is
  'T-REMED recommendations for structural gaps, derived from the most similar screens. Read-only; proposals for a decision, not links.';
revoke all on function programacion.fn_t_remed_recommend_v1(integer,numeric,boolean) from public, anon, authenticated;
