-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH1-20261013-001
-- source_version=20261011001609
-- source_name=t_remed_open_decisions_v1
-- T-REMED open decisions: VIGENTE rules with an open definition dependency (canonical source, legal/business validation, copy, other pending),
-- grouped by the decision that unblocks them (path without array indexes) so ONE human decision clears several rules. Derived, read-only.
-- STATE_WORD (a state name, not a dependency) and /implementation_status (stage readiness, handled by IG resolvers) are excluded, same as the promotion judge.
-- Rolled-back test: 74 decisions affecting 59 rules; top: /provider_binding (6 rules), /canonical_screen (3), /payment_ledger (3), /route_pattern (2).
create or replace function programacion.fn_t_remed_open_decisions_v1(p_include_state_words boolean default false)
 returns table(kind text, decision_key text, rules integer, rule_codes text[], sample_values text[])
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
  select d.kind, regexp_replace(d.path,'/[0-9]+','','g') dk, count(distinct d.regla_id)::int,
         array_agg(distinct d.regla_codigo order by d.regla_codigo),
         (array_agg(distinct left(d.value,120)))[1:3]
  from lf_ops.reglas r
  cross join lateral programacion.fn_t_remed_pending_deps_v1(r.id) d
  where r.estado='VIGENTE' and (p_include_state_words or d.kind<>'STATE_WORD') and d.path not like '/implementation_status%'
  group by d.kind, regexp_replace(d.path,'/[0-9]+','','g')
  order by 3 desc, 1, 2
$fn$;
comment on function programacion.fn_t_remed_open_decisions_v1(boolean) is
  'T-REMED open decisions grouped by what unblocks them. Read-only, derived; the decision itself is human.';
revoke all on function programacion.fn_t_remed_open_decisions_v1(boolean) from public, anon, authenticated;
