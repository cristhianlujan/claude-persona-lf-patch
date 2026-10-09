-- Run only inside BEGIN -> candidate migration -> tests -> ROLLBACK.
-- Verify the real permission error using SET LOCAL ROLE, not only ACL metadata.
do $test$
declare
  fn text;
  role_name text;
  denied integer := 0;
begin
  foreach fn in array array[
    'public.lf_runtime_impl_deploy_verification_binding_v1',
    'public.lf_runtime_impl_deploy_receipt_check_v1'
  ] loop
    foreach role_name in array array['anon','authenticated'] loop
      begin
        execute format('SET LOCAL ROLE %I',role_name);
        execute format('SELECT %s(''{}''::jsonb)',fn);
        raise exception 'FAIL_ACL_UNEXPECTED_EXECUTE % %',role_name,fn;
      exception when insufficient_privilege then
        denied := denied + 1;
      end;
    end loop;
  end loop;
  if denied <> 4 then raise exception 'FAIL_ACL_DENIAL_COUNT %',denied; end if;
  if not has_function_privilege('service_role',
      'public.lf_runtime_impl_deploy_verification_binding_v1(jsonb)','EXECUTE')
     or not has_function_privilege('service_role',
      'public.lf_runtime_impl_deploy_receipt_check_v1(jsonb)','EXECUTE')
  then raise exception 'FAIL_ACL_SERVICE_ROLE_EXECUTE'; end if;
  raise notice 'PASS_F07_X03_ACL_4_NEGATIVE_2_SERVICE_ROLE';
end $test$;
