-- PR93 · Production readiness P0
-- Remove public execution from privileged SECURITY DEFINER mutation RPCs.
--
-- Scope is intentionally limited to functions that mutate governed state or
-- write operational evidence. Read-only RPCs are not changed in this lot.
--
-- Rollback, only after an explicit security decision:
-- GRANT EXECUTE ON FUNCTION <signature> TO anon, authenticated;

begin;

revoke execute on function public.lf_archivar_activo(text, text)
  from public, anon, authenticated;
revoke execute on function public.lf_archivar_activo_demo(text, text)
  from public, anon, authenticated;

revoke execute on function public.lf_cambiar_estado_activo(text, text, text, text)
  from public, anon, authenticated;
revoke execute on function public.lf_cambiar_estado_activo_demo(text, text, text, text)
  from public, anon, authenticated;

revoke execute on function public.lf_log_activar(text, boolean, text)
  from public, anon, authenticated;
revoke execute on function public.lf_log_registrar(
  text, text, text, text, text, text, text, jsonb, text, uuid
) from public, anon, authenticated;

revoke execute on function public.lf_prod_enforcement_precheck_step_v01(
  text, integer, text, text, text, jsonb
) from public, anon, authenticated;
revoke execute on function public.lf_prod_enforcement_record_observation_v01(
  text, text, text, text, text, text, text, text, jsonb
) from public, anon, authenticated;

revoke execute on function public.lf_registrar_deuda(
  text, text, text, text, jsonb
) from public, anon, authenticated;
revoke execute on function public.lf_registrar_evento(
  text, text, text, text, text, jsonb, uuid
) from public, anon, authenticated;
revoke execute on function public.lf_registrar_evento_demo(
  text, text, text, text, jsonb
) from public, anon, authenticated;

-- Preserve the server-side caller used by controlled Edge Functions and
-- administrative connectors. Function owners retain their inherent rights.
grant execute on function public.lf_archivar_activo(text, text)
  to service_role;
grant execute on function public.lf_archivar_activo_demo(text, text)
  to service_role;
grant execute on function public.lf_cambiar_estado_activo(text, text, text, text)
  to service_role;
grant execute on function public.lf_cambiar_estado_activo_demo(text, text, text, text)
  to service_role;
grant execute on function public.lf_log_activar(text, boolean, text)
  to service_role;
grant execute on function public.lf_log_registrar(
  text, text, text, text, text, text, text, jsonb, text, uuid
) to service_role;
grant execute on function public.lf_prod_enforcement_precheck_step_v01(
  text, integer, text, text, text, jsonb
) to service_role;
grant execute on function public.lf_prod_enforcement_record_observation_v01(
  text, text, text, text, text, text, text, text, jsonb
) to service_role;
grant execute on function public.lf_registrar_deuda(
  text, text, text, text, jsonb
) to service_role;
grant execute on function public.lf_registrar_evento(
  text, text, text, text, text, jsonb, uuid
) to service_role;
grant execute on function public.lf_registrar_evento_demo(
  text, text, text, text, jsonb
) to service_role;

commit;
