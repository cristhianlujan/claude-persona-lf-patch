-- PR93 · Production readiness P0 · post-migration grant assertions
-- Read-only verification. Expected to be executed after
-- 20260806033000_pr93_p0_revoke_public_definer_mutations.sql.

begin;
set local transaction read only;

create temporary table expected_rpc_signatures(
  function_name text not null,
  identity_arguments text not null,
  primary key(function_name, identity_arguments)
) on commit drop;

insert into expected_rpc_signatures(function_name, identity_arguments) values
  ('lf_archivar_activo', 'p_codigo_activo text, p_motivo text'),
  ('lf_archivar_activo_demo', 'p_codigo_activo text, p_motivo text'),
  ('lf_cambiar_estado_activo', 'p_codigo_activo text, p_estado_documental text, p_estado_operativo text, p_motivo text'),
  ('lf_cambiar_estado_activo_demo', 'p_codigo_activo text, p_estado_documental text, p_estado_operativo text, p_motivo text'),
  ('lf_log_activar', 'p_log_key text, p_enabled boolean, p_motivo text'),
  ('lf_log_registrar', 'p_log_key text, p_evento_tipo text, p_entidad_tipo text, p_entidad_codigo text, p_accion text, p_descripcion text, p_severidad text, p_payload jsonb, p_session_ref text, p_migration_batch_id uuid'),
  ('lf_prod_enforcement_precheck_step_v01', 'p_execution_id text, p_step_order integer, p_step_id text, p_status text, p_evidence_ref text, p_evidence_payload jsonb'),
  ('lf_prod_enforcement_record_observation_v01', 'p_observation_source text, p_execution_id text, p_operation_code text, p_target_table text, p_attempted_action text, p_decision text, p_reason_code text, p_reason_detail text, p_payload jsonb'),
  ('lf_registrar_deuda', 'p_codigo_activo text, p_deuda_tipo text, p_descripcion text, p_prioridad text, p_metadata jsonb'),
  ('lf_registrar_evento', 'p_evento_tipo text, p_entidad_tipo text, p_entidad_codigo text, p_descripcion text, p_severidad text, p_payload jsonb, p_migration_batch_id uuid'),
  ('lf_registrar_evento_demo', 'p_evento_tipo text, p_entidad_tipo text, p_entidad_codigo text, p_descripcion text, p_payload jsonb');

do $assertions$
declare
  v_expected integer;
  v_observed integer;
  v_invalid integer;
begin
  select count(*) into v_expected from expected_rpc_signatures;

  select count(*) into v_observed
  from expected_rpc_signatures e
  join pg_proc p
    on p.proname=e.function_name
   and pg_get_function_identity_arguments(p.oid)=e.identity_arguments
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public';

  if v_observed <> v_expected then
    raise exception 'P0_RPC_SIGNATURE_SET_MISMATCH expected=% observed=%', v_expected, v_observed;
  end if;

  select count(*) into v_invalid
  from expected_rpc_signatures e
  join pg_proc p
    on p.proname=e.function_name
   and pg_get_function_identity_arguments(p.oid)=e.identity_arguments
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and (
      p.prosecdef is not true
      or has_function_privilege('anon', p.oid, 'EXECUTE')
      or has_function_privilege('authenticated', p.oid, 'EXECUTE')
      or not has_function_privilege('service_role', p.oid, 'EXECUTE')
      or p.proconfig is null
    );

  if v_invalid <> 0 then
    raise exception 'P0_RPC_GRANT_ASSERTION_FAILED invalid=%', v_invalid;
  end if;
end
$assertions$;

select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  p.prosecdef as security_definer,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
  has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_execute,
  p.proconfig as fixed_configuration
from expected_rpc_signatures e
join pg_proc p
  on p.proname=e.function_name
 and pg_get_function_identity_arguments(p.oid)=e.identity_arguments
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
order by p.proname, identity_arguments;

rollback;
