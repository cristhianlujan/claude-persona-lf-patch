revoke all on table public.lf_operation_effect_guard from service_role;
grant select, insert, update on table public.lf_operation_effect_guard to service_role;
revoke all on table public.lf_operation_effect_guard from public, anon, authenticated;
