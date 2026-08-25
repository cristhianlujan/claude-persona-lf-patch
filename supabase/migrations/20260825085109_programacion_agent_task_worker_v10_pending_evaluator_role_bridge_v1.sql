do $patch$
declare
  vdef text;
  vold text := 'if v_independence_required then';
  vnew text := $replacement$if v_independence_required and not exists(
     select 1
     from programacion.objetivos_ejecucion o_worker
     join programacion.gates g_worker on g_worker.id=o_worker.gate_id
     where o_worker.id=new.objetivo_id
       and g_worker.gate_codigo in('G_WORKER_SOURCE_IDENTITY','G_WORKER_PATCH_POLICY','G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY')
   ) then$replacement$;
begin
  select pg_get_functiondef('programacion.fn_guard_evaluation()'::regprocedure) into vdef;
  if position(vold in vdef)=0 then
    raise exception 'WORKER_V10_EVALUATION_GUARD_PATCH_POINT_MISSING';
  end if;
  vdef:=replace(vdef,vold,vnew);
  execute vdef;
end;
$patch$;

do $selftest$
declare
  vdef text;
begin
  select pg_get_functiondef('programacion.fn_guard_evaluation()'::regprocedure) into vdef;
  if position('G_WORKER_SOURCE_IDENTITY' in vdef)=0
     or position('G_WORKER_PATCH_POLICY' in vdef)=0
     or position('G_WORKER_ACCEPTANCE' in vdef)=0
     or position('G_WORKER_DELIVERY_BOUNDARY' in vdef)=0 then
    raise exception 'SELFTEST_WORKER_V10_PENDING_ROLE_BRIDGE_MISSING';
  end if;
  if not exists(
    select 1 from pg_trigger tg join pg_class c on c.oid=tg.tgrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='programacion' and c.relname='evaluaciones'
      and tg.tgname='trg_evaluaciones_worker_v10_authority_guard' and tg.tgenabled<>'D'
  ) then
    raise exception 'SELFTEST_WORKER_V10_TERMINAL_AUTHORITY_GUARD_REQUIRED';
  end if;
end;
$selftest$;

comment on function programacion.fn_guard_evaluation()
is 'Generic evaluation integrity guard. Worker v10 gates may be produced by evaluator_tipo=worker; their independent terminal authority is enforced separately by trg_evaluaciones_worker_v10_authority_guard using OIDC-backed origin verification and F03 hidden authority.';
