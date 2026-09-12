do $migration$
declare
  v_def text;
  v_old text := $$and ((s.step_id='init_execution' and es.status <> 'STEP_CLEAN_PASS')
      or (s.step_id <> 'init_execution' and (pb.clean_result_value is null or es.status <> pb.clean_result_value)))$$;
  v_new text := $$and (pb.clean_result_value is null or es.status <> pb.clean_result_value)$$;
begin
  select pg_get_functiondef('public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text)'::regprocedure) into v_def;
  if position(v_old in v_def) = 0 then
    raise exception 'LF_COMMON_RECORDER_PRIOR_CLEAN_EXPECTED_SOURCE_NOT_FOUND';
  end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end;
$migration$;

revoke all on function public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text) from public;
revoke all on function public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text) from anon;
revoke all on function public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text) from authenticated;
grant execute on function public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text) to service_role;
