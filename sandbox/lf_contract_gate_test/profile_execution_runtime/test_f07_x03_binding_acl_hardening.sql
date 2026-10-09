-- Run only inside BEGIN -> candidate migration -> tests -> ROLLBACK.
do $test$
declare fn regprocedure; role_name text;
begin
  foreach fn in array array[
    'public.lf_runtime_impl_deploy_verification_binding_v1(jsonb)'::regprocedure,
    'public.lf_runtime_impl_deploy_receipt_check_v1(jsonb)'::regprocedure
  ] loop
    foreach role_name in array array['anon','authenticated'] loop
      if has_function_privilege(role_name,fn,'EXECUTE') then
        raise exception 'FAIL_ACL_NEGATIVE % has EXECUTE on %',role_name,fn;
      end if;
    end loop;
    if not has_function_privilege('service_role',fn,'EXECUTE') then
      raise exception 'FAIL_ACL_SERVICE_ROLE_NO_EXECUTE %',fn;
    end if;
  end loop;
  raise notice 'PASS_F07_X03_ACL_NEGATIVE_4_SERVICE_POSITIVE_2';
end $test$;
