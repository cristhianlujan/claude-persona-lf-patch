-- T-REMED selftest: 8 read-only invariants over the derived functions (global rules, scope judge, recommendations, queue, open decisions, derived links, promotion log).
-- Rolled-back run: 8/8 true (queue 721 = recommendations 721; 0 foreign-channel recommendations). Writes nothing.
create or replace function programacion.fn_t_remed_selftest_v1()
 returns table(check_code text, passed boolean, detail text)
 language plpgsql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare n bigint; m bigint; s int;
begin
  -- 1. every USAGE global meets the threshold; every DECLARED global passed the scope judge; only VIGENTE rules are global
  select count(*) into n from programacion.fn_t_remed_global_rules_v1(0.25) g
   where g.regla_estado<>'VIGENTE'
      or (g.basis='USAGE' and g.share < 0.25)
      or (g.basis='DECLARED' and not exists(select 1 from programacion.fn_t_remed_scope_judge_v1(0.25) j where j.regla_id=g.regla_id and j.verdict='PASS_GLOBAL'));
  return query select 'GLOBAL_RULES_CONSISTENT', n=0, 'violations='||n;
  -- 2. judge: PASS never has a pending decision; MANUAL rules are never global; verdicts are in the closed set
  select count(*) into n from programacion.fn_t_remed_scope_judge_v1(0.25) j
   where (j.verdict='PASS_GLOBAL' and j.pendiente) or j.verdict not in ('PASS_GLOBAL','MANUAL')
      or (j.verdict='MANUAL' and exists(select 1 from programacion.fn_t_remed_global_rules_v1(0.25) g where g.regla_id=j.regla_id));
  return query select 'SCOPE_JUDGE_CONSISTENT', n=0, 'violations='||n;
  -- 3. recommendations never come from another channel: every recommended code is linked to at least one same-shell screen
  select count(*) into n from lf_ops.pantallas p
   cross join lateral programacion.fn_t_remed_recommend_v1(p.id,0.3,false) r
   where not exists (
     select 1 from lf_ops.pantallas q
       left join lf_ops.modulos mq on mq.module_id=q.module_id
       left join lf_ops.modulos mp on mp.module_id=p.module_id
     where q.id<>p.id and mq.app_shell_id is not distinct from mp.app_shell_id and (
       (r.family_code='STATES' and exists(select 1 from lf_ops.pantallas_estados x where x.pantalla_id=q.id and x.state_code::text=r.code)) or
       (r.family_code='ERRORS' and exists(select 1 from lf_ops.errores_pantallas x where x.pantalla_id=q.id and x.error_code::text=r.code)) or
       (r.family_code='UI_MESSAGES' and exists(select 1 from lf_ops.mensajes_pantallas x where x.pantalla_id=q.id and x.message_code::text=r.code)) or
       (r.family_code='PROFILES' and exists(select 1 from lf_ops.pantallas_perfiles x where x.pantalla_id=q.id and x.profile_code::text=r.code)) or
       (r.family_code='PERMISSIONS' and exists(select 1 from lf_ops.pantallas_permisos x where x.pantalla_id=q.id and x.permission_code::text=r.code))));
  return query select 'RECOMMEND_SAME_CHANNEL_ONLY', n=0, 'foreign_recommendations='||n;
  -- 4. recommendations are monotonic in min_share (a stricter threshold never adds codes)
  select count(*) into n from lf_ops.pantallas p cross join lateral programacion.fn_t_remed_recommend_v1(p.id,0.6,false) r
   where not exists(select 1 from programacion.fn_t_remed_recommend_v1(p.id,0.3,false) r2 where r2.family_code=r.family_code and r2.code=r.code);
  return query select 'RECOMMEND_MONOTONIC', n=0, 'violations='||n;
  -- 5. queue equals the recommendations grouped per screen and family
  select coalesce(sum(recomendados),0) into n from programacion.fn_t_remed_recommend_queue_v1(0.3);
  select count(*) into m from lf_ops.pantallas p cross join lateral programacion.fn_t_remed_recommend_v1(p.id,0.3,false) r;
  return query select 'QUEUE_MATCHES_RECOMMENDATIONS', n=m, 'queue='||n||' recommendations='||m;
  -- 6. open decisions exclude state words and implementation status
  select count(*) into n from programacion.fn_t_remed_open_decisions_v1() d where d.kind='STATE_WORD' or d.decision_key like '/implementation_status%';
  return query select 'OPEN_DECISIONS_EXCLUSIONS', n=0, 'violations='||n;
  -- 7. DERIVED_GLOBAL links are a subset of the global rules and never duplicate an own link (sample: first 5 screens)
  n:=0;
  for s in select id from lf_ops.pantallas order by id limit 5 loop
    select n + count(*) into n from programacion.fn_input_effective_rule_links_v1(s,'INPUT_GOVERNANCE') l
     where l.binding_source='DERIVED_GLOBAL'
       and (not exists(select 1 from programacion.fn_t_remed_global_rules_v1(0.25) g where g.regla_id=l.regla_id)
            or exists(select 1 from lf_ops.reglas_pantallas z where z.pantalla_id=s and z.regla_id=l.regla_id));
  end loop;
  return query select 'DERIVED_GLOBAL_LINKS_VALID', n=0, 'violations='||n;
  -- 8. every promotion in the change log is reversible or already reverted (no orphan log rows)
  select count(*) into n from programacion.t_remed_change_log c where c.layer='PROMOTE' and c.subject_kind='REGLA' and not exists(select 1 from lf_ops.reglas r where r.id::text=c.subject_id::text);
  return query select 'PROMOTION_LOG_TARGETS_EXIST', n=0, 'orphans='||n;
end
$fn$;
comment on function programacion.fn_t_remed_selftest_v1() is 'T-REMED invariants, read-only. Run: select * from programacion.fn_t_remed_selftest_v1(); every row must have passed=true.';
revoke all on function programacion.fn_t_remed_selftest_v1() from public, anon, authenticated;
