-- Reconcile IG worker/Router readback to the actual SQL queue runtime.
-- Retain historical Edge assets for rollback, but never advertise them as
-- the active execution binding after direct SQL dispatch cutover.
do $patch$
declare
 rec record;
 v_after text;
 v_changed integer:=0;
begin
 if to_regprocedure('programacion.fn_input_governance_direct_step_v1(integer,text)') is null
    or to_regclass('programacion.ig_direct_requests_v1') is null then
   raise exception 'IG_DIRECT_SQL_RUNTIME_NOT_INSTALLED';
 end if;
 for rec in
  select n.nspname,p.proname,pg_get_functiondef(p.oid) as def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname in (
    'fn_input_governance_worker_spec',
    'fn_input_governance_worker_spec_known_current_v1',
    'fn_input_governance_worker_spec_known_no_current_v1',
    'fn_lf_router_input_governance_resolve_v1')
 loop
   v_after:=replace(rec.def,
     'SUPABASE_EDGE_FUNCTION:input-governance-curator-v1',
     'POSTGRES_SQL_WORKER:ig-direct-sql-worker-v1:CURATOR');
   v_after:=replace(v_after,
     'SUPABASE_EDGE_FUNCTION:input-governance-validator-v1',
     'POSTGRES_SQL_WORKER:ig-direct-sql-worker-v1:VALIDATOR');
   v_after:=replace(v_after,
     'SUPABASE_EDGE_FUNCTION:input-governance-agent-v1',
     'POSTGRES_SQL_WORKER:ig-direct-sql-worker-v1');
   if rec.proname='fn_lf_router_input_governance_resolve_v1' then
     v_after:=replace(v_after,
       '''governance_agent'', ''input-governance-agent-v1''',
       '''governance_agent'', ''ig-direct-sql-worker-v1''');
   end if;
   if v_after=rec.def then
     raise exception 'IG_DIRECT_BINDING_STRING_MISSING:%',rec.proname;
   end if;
   execute v_after;
   v_changed:=v_changed+1;
 end loop;
 if v_changed<>4 then
   raise exception 'IG_DIRECT_WORKER_BINDING_PATCH_COUNT:%',v_changed;
 end if;
end;
$patch$;

do $guard$
declare n integer;
begin
 select count(*) into n
 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
 where ns.nspname='programacion'
   and p.proname in (
    'fn_input_governance_worker_spec',
    'fn_input_governance_worker_spec_known_current_v1',
    'fn_input_governance_worker_spec_known_no_current_v1',
    'fn_lf_router_input_governance_resolve_v1')
   and p.prosrc like '%SUPABASE_EDGE_FUNCTION:input-governance-%';
 if n<>0 then raise exception 'IG_DIRECT_BINDING_STALE_EDGE_REFERENCES:%',n; end if;
end;
$guard$;
