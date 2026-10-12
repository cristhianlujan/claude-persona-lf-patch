-- T-REMED recommendation queue: one row per (screen x structural family) that has a gap and at least one recommendation, derived on read (no table).
-- Built on fn_t_remed_recommend_v1 (same-channel neighbours). Rolled-back test: 108 rows, 44 screens, ~0.7 s
-- (ERRORS 29, PERMISSIONS 24, PROFILES 21, STATES 9, UI_MESSAGES 25). Proposals for a human decision; the function writes nothing.
create or replace function programacion.fn_t_remed_recommend_queue_v1(p_min_share numeric default 0.3)
 returns table(pantalla_id integer, pantalla_codigo text, app_shell_id integer, family_code text, recomendados integer, mejor_share numeric, codigos text[])
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $q$
  select s.id, s.codigo::text, m.app_shell_id, r.family_code, count(*)::int, max(r.share), array_agg(r.code order by r.share desc, r.code)
  from lf_ops.pantallas s
  left join lf_ops.modulos m on m.module_id=s.module_id
  cross join lateral programacion.fn_t_remed_recommend_v1(s.id,p_min_share,false) r
  group by s.id, s.codigo, m.app_shell_id, r.family_code
$q$;
comment on function programacion.fn_t_remed_recommend_queue_v1(numeric) is
  'T-REMED queue of structural-gap recommendations per screen and family, for human decision. Read-only, derived.';
revoke all on function programacion.fn_t_remed_recommend_queue_v1(numeric) from public, anon, authenticated;
