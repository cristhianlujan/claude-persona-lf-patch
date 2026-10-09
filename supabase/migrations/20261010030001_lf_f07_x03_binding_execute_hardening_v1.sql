-- F07-X03: restrict sensitive runtime verification APIs to service_role.
-- Managed LF migration, source-first via canonical Merge Train only.
revoke execute on function public.lf_runtime_impl_deploy_verification_binding_v1(jsonb) from public, anon, authenticated;
revoke execute on function public.lf_runtime_impl_deploy_receipt_check_v1(jsonb) from public, anon, authenticated;
grant execute on function public.lf_runtime_impl_deploy_verification_binding_v1(jsonb) to service_role;
grant execute on function public.lf_runtime_impl_deploy_receipt_check_v1(jsonb) to service_role;
