-- Exact-baseline patch after current-summary fastpath.
do $migration$
declare
  v_def text;
  v_sha text;
  v_new text;
begin
  select pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure),
         encode(digest(pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure),'sha256'),'hex')
    into v_def,v_sha;
  if v_sha<>'9de6f4f71c6e7fe4bcab05b471f45df81c9f30b7839b0cca25e57043afa70bf1' then
    raise exception 'INPUT_GOV_DISPATCH_WORKER_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;
  if position('v_worker:=programacion.fn_input_governance_worker_spec(p_pantalla_id,p_consumer);' in v_def)=0 then
    raise exception 'INPUT_GOV_DISPATCH_WORKER_CALL_NOT_FOUND';
  end if;
  v_new:=replace(v_def,
    'v_worker:=programacion.fn_input_governance_worker_spec(p_pantalla_id,p_consumer);',
    'v_worker:=programacion.fn_input_governance_worker_spec_known_current_v1(p_pantalla_id,p_consumer,v_run);');
  execute v_new;
end;
$migration$;
