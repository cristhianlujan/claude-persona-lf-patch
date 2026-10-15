-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH1-20261013-001
-- source_version=20261008104324
-- source_name=ig_sql_worker_batch_margin_v1
-- IG SQL queue worker: advance in measured bounded subbatches.
-- The previous 95s post-chunk check allowed 116.615s job duration.
-- Stop requesting new chunks after 30s elapsed, leaving room for a single
-- slow chunk; preserve durable QUEUED status and OIDC-bound request identity.
do $patch$
declare
 v_def text;
 v_before constant text := 'exit when clock_timestamp()-v_t0 > interval ''95 seconds'';';
 v_after constant text := 'exit when clock_timestamp()-v_t0 > interval ''30 seconds'';';
begin
 select pg_get_functiondef(p.oid) into v_def
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='programacion' and p.proname='fn_input_governance_queue_worker_v1';
 if v_def is null or position(v_before in v_def)=0 then
  raise exception 'IG_WORKER_BUDGET_BASELINE_DRIFT';
 end if;
 execute replace(v_def,v_before,v_after);
end;
$patch$;

do $guard$
declare v_def text;
begin
 select pg_get_functiondef(p.oid) into v_def
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='programacion' and p.proname='fn_input_governance_queue_worker_v1';
 if v_def not like '%interval ''30 seconds''%'
   or v_def like '%interval ''95 seconds''%'
 then raise exception 'IG_WORKER_BUDGET_READBACK_FAILED';end if;
end;
$guard$;
