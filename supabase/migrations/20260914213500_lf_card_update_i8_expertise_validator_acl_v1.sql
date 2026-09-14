-- LF_CARD_UPDATE_I8_EXPERTISE_VALIDATOR_ACL_V1
-- Purpose: restrict the I8 expertise validator to service_role only.
-- Scope: ACL hardening only. No Card content write, Router, runtime, production or Golden activation.

begin;

revoke execute on function public.lf_validate_card_expertise_gate_v1(text,text,jsonb) from public, anon, authenticated;
grant execute on function public.lf_validate_card_expertise_gate_v1(text,text,jsonb) to service_role;

do $$
begin
  if has_function_privilege('anon','public.lf_validate_card_expertise_gate_v1(text,text,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','public.lf_validate_card_expertise_gate_v1(text,text,jsonb)','EXECUTE')
     or not has_function_privilege('service_role','public.lf_validate_card_expertise_gate_v1(text,text,jsonb)','EXECUTE') then
    raise exception 'CARD_UPDATE_I8_EXPERTISE_VALIDATOR_ACL_ASSERTION_FAILED';
  end if;
end $$;

commit;
