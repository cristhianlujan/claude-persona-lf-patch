-- T-REMED: derived links (no storage) and a derived work queue (no storage).
-- Both are read-only STABLE functions: they cannot be stale because they are computed from the source rows on every call.
--
-- fn_t_remed_effective_links_v1(pantalla): the screen -> policy links implied by its rules, one row per (reference_role, target).
--   status VIGENTE when the rules and the target are all VIGENTE, otherwise CANDIDATO (weakest-state inheritance).
--   Built only on fn_t_remed_reconcile_v3 proposals (LINK_CANDIDATE and ESCALATE:SOURCE_CONFLICT). Writes nothing.
-- fn_t_remed_queue_v1(limit): screens that need a turn, one screen per job.
--   SIN_CORRIDA  : no readiness run exists
--   INVALIDADA   : the latest run was invalidated
--   FUENTE_CAMBIO: the latest run is no longer current against its sources (fn_input_run_is_source_current)
--   Screens whose latest run is current are not listed. Order: SIN_CORRIDA, INVALIDADA, FUENTE_CAMBIO, then pantalla_id.

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
