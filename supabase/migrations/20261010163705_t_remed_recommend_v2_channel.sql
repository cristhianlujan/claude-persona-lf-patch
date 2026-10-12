-- T-REMED recommendations v2: neighbours must belong to the SAME app shell (channel), so a B2C screen is never recommended B2B codes.
-- Replaces the body of fn_t_remed_recommend_v1 (same signature). Leave-one-out (min_share 0.3), precision / recall: PROFILES 0.86 / 0.99,
-- STATES 0.50 / 0.88, ERRORS 0.49 / 0.49, PERMISSIONS 0.25 / 0.52, UI_MESSAGES 0.24 / 0.52. Coverage of real gaps: PROFILES 21/22, STATES 9/32 (few same-channel
-- neighbours have states), ERRORS 14/17, PERMISSIONS 24/25, UI_MESSAGES 25/28. Recommendations only; the function writes nothing.
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
    select s.id p, split_part(s.codigo,'-',1) pf, s.module_code mc, s.flujo fl, m.app_shell_id sh,
      (select array_agg(distinct w) from regexp_split_to_table(lower(coalesce(s.nombre,'')||' '||coalesce(s.descripcion,'')||' '||coalesce(s.objective,'')),'[^a-záéíóúñ0-9]+') w where length(w)>3) words
    from lf_ops.pantallas s left join lf_ops.modulos m on m.module_id=s.module_id
  ), sim as (
    select y.p,
      (x.pf=y.pf)::int + (x.mc is not distinct from y.mc)::int + (x.fl is not null and x.fl is not distinct from y.fl)::int +
      coalesce((select count(*) from unnest(x.words) w where w=any(y.words))::numeric
        / nullif(cardinality(x.words)+cardinality(y.words)-(select count(*) from unnest(x.words) w where w=any(y.words)),0),0) score
    from pa x join pa y on y.p<>x.p and y.sh is not distinct from x.sh where x.p=p_pantalla_id
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
