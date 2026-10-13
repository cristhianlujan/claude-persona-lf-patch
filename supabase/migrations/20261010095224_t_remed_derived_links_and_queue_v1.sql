-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH2-20261013-001
-- source_version=20261010095224
-- source_name=t_remed_derived_links_and_queue_v1
create or replace function programacion.fn_t_remed_effective_links_v1(p_pantalla_id integer)
 returns table(reference_role text, target_table text, target_id bigint, status text, rule_ids jsonb)
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
  select p->>'reference_role', p->>'target_table', (p->>'target_id')::bigint,
         case when p->'rule_states'='["VIGENTE"]'::jsonb and p->>'target_status'='VIGENTE' then 'VIGENTE' else 'CANDIDATO' end,
         p->'rule_ids'
  from jsonb_array_elements(programacion.fn_t_remed_reconcile_v3(p_pantalla_id)->'proposals') p
  where p->>'verdict' in ('LINK_CANDIDATE','ESCALATE:SOURCE_CONFLICT')
$fn$;

create or replace function programacion.fn_t_remed_queue_v1(p_limit integer default 10)
 returns table(pantalla_id integer, codigo text, queue_state text, run_id bigint)
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
  with latest as (
    select distinct on (r.pantalla_id) r.pantalla_id, r.id as run_id, r.invalidated_at
    from programacion.input_readiness_runs r
    order by r.pantalla_id, r.id desc
  ), q as (
    select p.id as pantalla_id, p.codigo, l.run_id,
           case when l.run_id is null then 'SIN_CORRIDA'
                when l.invalidated_at is not null then 'INVALIDADA'
                else 'FUENTE_CAMBIO' end as queue_state
    from lf_ops.pantallas p left join latest l on l.pantalla_id=p.id
  )
  select q.pantalla_id, q.codigo, q.queue_state, q.run_id
  from q
  where q.queue_state in ('SIN_CORRIDA','INVALIDADA')
     or (q.queue_state='FUENTE_CAMBIO' and not programacion.fn_input_run_is_source_current(q.run_id))
  order by case q.queue_state when 'SIN_CORRIDA' then 0 when 'INVALIDADA' then 1 else 2 end, q.pantalla_id
  limit greatest(coalesce(p_limit,10),0)
$fn$;

comment on function programacion.fn_t_remed_effective_links_v1(integer) is
  'T-REMED derived links for one screen. Read-only, computed from rules on every call (never stale). status VIGENTE only if all rules and the target are VIGENTE.';
comment on function programacion.fn_t_remed_queue_v1(integer) is
  'T-REMED work queue, derived (no table): screens without a run, with an invalidated run, or whose latest run is no longer source-current. One screen per job.';
revoke all on function programacion.fn_t_remed_effective_links_v1(integer), programacion.fn_t_remed_queue_v1(integer) from public, anon, authenticated;
