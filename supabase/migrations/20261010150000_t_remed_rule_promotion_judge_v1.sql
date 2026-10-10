-- T-REMED layer 3 (promotion) for general rules: independent judge, read-only and derived (no table, never stale).
-- fn_t_remed_rule_promotion_verdicts_v1(min_screens, regla_id): one row per CANDIDATO rule with its criteria and verdict.
--   NO_PENDING_DECISION       : the rule is not flagged pendiente_decision
--   NO_PENDING_MARKER         : no pending marker in its config; measured by fn_input_bootstrap_rule_probe_v1 itself (single source of truth)
--   HAS_STATED_REASON         : the rule states a reason (razon)
--   USED_BY_ENOUGH_SCREENS    : linked to >= p_min_screens screens (default 5; consensus)
--   NO_DUPLICATE_ACTIVE_RULE  : no other active rule of the same category with identical config
--   verdict PASS only if every criterion holds, otherwise HOLD with the failed criteria. Writes nothing and promotes nothing:
--   changing a rule to VIGENTE is a separate step that must read this verdict.
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
    select r.id, programacion.fn_input_bootstrap_rule_probe_v1(
      jsonb_build_array(jsonb_build_object('rule_code',r.codigo,'title',r.titulo,'description',r.descripcion,'config',r.valor_config,
        'status',r.estado,'category',r.categoria,'pending_decision',coalesce(r.pendiente_decision,false))),null,null) p
    from r
  ), dup as (
    select r.id, (r.valor_config is not null and r.valor_config<>'{}'::jsonb and exists(
      select 1 from lf_ops.reglas o where o.id<>r.id and o.estado in ('VIGENTE','CANDIDATO')
        and o.categoria is not distinct from r.categoria and o.valor_config=r.valor_config)) d
    from r
  ), c as (
    select r.id, r.codigo, coalesce(n.c,0) screens,
      jsonb_build_object(
        'NO_PENDING_DECISION', not coalesce(r.pendiente_decision,false),
        'NO_PENDING_MARKER', coalesce((pr.p->>'pending_marker_count')::int,0)=0,
        'HAS_STATED_REASON', nullif(btrim(coalesce(r.razon,'')),'') is not null,
        'USED_BY_ENOUGH_SCREENS', coalesce(n.c,0)>=p_min_screens,
        'NO_DUPLICATE_ACTIVE_RULE', not dup.d) crit
    from r left join n on n.rid=r.id join pr on pr.id=r.id join dup on dup.id=r.id
  )
  select c.id::bigint, c.codigo::text, c.screens, c.crit,
    case when exists(select 1 from jsonb_each(c.crit) e where e.value='false'::jsonb) then 'HOLD' else 'PASS' end,
    array(select e.key::text from jsonb_each(c.crit) e where e.value='false'::jsonb order by e.key)
  from c order by c.id
$fn$;
comment on function programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint) is
  'T-REMED rule promotion judge (read-only, derived). PASS only if all criteria hold; HOLD lists the failed ones. Does not promote.';
revoke all on function programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint) from public, anon, authenticated;
