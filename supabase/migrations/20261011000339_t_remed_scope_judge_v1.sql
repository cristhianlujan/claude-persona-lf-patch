-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH1-20261013-001
-- source_version=20261011000339
-- source_name=t_remed_scope_judge_v1
-- T-REMED scope judge: a rule declared transversal (es_transversal) is inherited by every screen only if the judge passes it.
-- PASS_GLOBAL = not pending a decision AND (linked in >= 2 distinct app shells, or other VIGENTE rules of the same category are). Otherwise MANUAL: not inherited, listed for a human decision.
-- Measured (rolled back): 66 declared -> 37 PASS_GLOBAL, 29 MANUAL (6 pending decision, 23 without cross-channel evidence); coverage identical on 8 screens; judge 8.7 ms/call.
create or replace function programacion.fn_t_remed_scope_judge_v1(p_min_share numeric default 0.25)
 returns table(regla_id bigint, regla_codigo text, categoria text, real_shells integer, category_shells integer, pendiente boolean, verdict text, reason text)
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
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
$fn$;
comment on function programacion.fn_t_remed_scope_judge_v1(numeric) is
  'T-REMED scope judge for rules declared transversal (es_transversal) but not widely used. PASS_GLOBAL: not pending a decision AND (the rule, or other VIGENTE rules of its category, are linked in >= 2 distinct app shells). Everything else is MANUAL (human decision, not inherited meanwhile). Derived, read-only, nothing hardcoded.';
revoke all on function programacion.fn_t_remed_scope_judge_v1(numeric) from public, anon, authenticated;

create or replace function programacion.fn_t_remed_global_rules_v1(p_min_share numeric default 0.25)
 returns table(regla_id bigint, regla_codigo text, regla_estado text, screens integer, share numeric, basis text)
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
  with tot as (select count(*)::numeric n from lf_ops.pantallas),
  use as (select z.regla_id rid, count(distinct z.pantalla_id)::int c from lf_ops.reglas_pantallas z group by 1),
  pj as (select j.regla_id rid from programacion.fn_t_remed_scope_judge_v1(p_min_share) j where j.verdict='PASS_GLOBAL')
  select r.id::bigint, r.codigo::text, r.estado::text, coalesce(u.c,0), round(coalesce(u.c,0)/t.n,4),
         case when coalesce(u.c,0) >= coalesce(p_min_share,0.25)*t.n then 'USAGE' else 'DECLARED' end
  from lf_ops.reglas r left join use u on u.rid=r.id cross join tot t
  where r.estado='VIGENTE' and (coalesce(u.c,0) >= coalesce(p_min_share,0.25)*t.n or r.id in (select rid from pj)) order by r.id
$fn$;
