revoke execute on function public.fn_lf_router_preflight_v1(text) from public;
revoke execute on function public.fn_lf_router_preflight_v1(text) from anon;
revoke execute on function public.fn_lf_router_preflight_v1(text) from authenticated;
grant execute on function public.fn_lf_router_preflight_v1(text) to service_role;
