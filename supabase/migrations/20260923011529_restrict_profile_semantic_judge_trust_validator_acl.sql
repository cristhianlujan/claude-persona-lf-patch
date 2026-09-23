begin;

-- LF_PROFILE_SEMANTIC_JUDGE_TRUST_VALIDATOR_ACL_V1
-- Keep the SECURITY DEFINER trust validator internal to the service-role recorder.

do $pre$
declare
  v_security_definer boolean;
begin
  select p.prosecdef
    into v_security_definer
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'lf_profile_execution_trust_validation_v2'
    and pg_catalog.pg_get_function_identity_arguments(p.oid) =
      'p_execution_id text, p_step_id text, p_evidence_payload jsonb';

  if not found then
    raise exception 'PROFILE_SEMANTIC_JUDGE_TRUST_VALIDATOR_MISSING';
  end if;
  if not v_security_definer then
    raise exception 'PROFILE_SEMANTIC_JUDGE_TRUST_VALIDATOR_SECURITY_MODE_UNEXPECTED';
  end if;
end
$pre$;

revoke all on function public.lf_profile_execution_trust_validation_v2(text,text,jsonb)
  from public;
revoke all on function public.lf_profile_execution_trust_validation_v2(text,text,jsonb)
  from anon;
revoke all on function public.lf_profile_execution_trust_validation_v2(text,text,jsonb)
  from authenticated;
grant execute on function public.lf_profile_execution_trust_validation_v2(text,text,jsonb)
  to service_role;

do $post$
declare
  v_oid oid;
begin
  select p.oid
    into v_oid
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'lf_profile_execution_trust_validation_v2'
    and pg_catalog.pg_get_function_identity_arguments(p.oid) =
      'p_execution_id text, p_step_id text, p_evidence_payload jsonb';

  if v_oid is null
     or pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE')
     or not pg_catalog.has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'PROFILE_SEMANTIC_JUDGE_TRUST_VALIDATOR_ACL_POSTCHECK_FAILED';
  end if;
end
$post$;

comment on function public.lf_profile_execution_trust_validation_v2(text,text,jsonb) is
'LF_PROFILE_SEMANTIC_JUDGE_RUNTIME_WIRING_V1 internal trust validator. SECURITY DEFINER execution is restricted to service_role; anon/authenticated/PUBLIC access is forbidden.';

commit;
