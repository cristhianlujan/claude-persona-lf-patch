-- S30 INTERNAL RPC ACL HARDENING source candidate.
-- NON-MIGRATION / DO NOT APPLY FROM THIS BRANCH.
-- This candidate changes privileges only; it does not recreate function bodies.

revoke execute on function public.lf_profile_creation_begin_v1(text,text,text,text,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.lf_profile_creation_begin_v1(text,text,text,text,text,text,text,jsonb) to service_role;

revoke execute on function public.lf_strategy_execution_begin_v1(text,bigint,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.lf_strategy_execution_begin_v1(text,bigint,text,text,text,jsonb) to service_role;

revoke execute on function public.lf_operation_execution_qualification_guard_v1(text,timestamptz) from public, anon, authenticated;
grant execute on function public.lf_operation_execution_qualification_guard_v1(text,timestamptz) to service_role;

revoke execute on function public.lf_apply_independent_strategy_review_v1(uuid,uuid,uuid,bigint,text,jsonb,text) from public, anon, authenticated;
grant execute on function public.lf_apply_independent_strategy_review_v1(uuid,uuid,uuid,bigint,text,jsonb,text) to service_role;

-- Reference functions already follow the target pattern and are intentionally untouched:
-- public.fn_lf_operation_reserve_execution_v1
-- public.lf_strategy_update_begin_v1
