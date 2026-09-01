do $migration$
declare
  v_def text;
  v_sha text;
begin
  select pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure) into v_def;
  v_sha:=encode(digest(v_def,'sha256'),'hex');
  if v_sha<>'93b2138879fda16c9f7996c14991c9294f3550a623c4662ddecdde9da1e7e7c0' then
    raise exception 'INPUT_GOVERNANCE_DISPATCH_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;
  if (length(v_def)-length(replace(v_def,'programacion.fn_input_readiness_run_is_current(r.id)','')))/length('programacion.fn_input_readiness_run_is_current(r.id)')<>1 then
    raise exception 'INPUT_GOVERNANCE_DISPATCH_CURRENTNESS_CALL_COUNT_MISMATCH';
  end if;
  v_def:=replace(v_def,
    'programacion.fn_input_readiness_run_is_current(r.id)',
    'programacion.fn_input_readiness_run_is_current_cached_v1(r.id)');
  execute v_def;
end;
$migration$;
