-- Reconcile Story Agent EKB hardening migration into the existing governed programacion_agent_task_* family.
-- No runtime object changes; source-ledger classification only.
do $$
declare v_rows integer;
begin
  update supabase_migrations.schema_migrations
  set name='programacion_agent_task_story_ekb_preaudit_guards_v1'
  where version='20260826040306'
    and name='programacion_story_agent_ekb_preaudit_guards_v1';
  get diagnostics v_rows = row_count;
  if v_rows<>1 then
    raise exception 'STORY_AGENT_EKB_MIGRATION_NAME_RECONCILE_EXPECTED_ONE_ROW:%',v_rows;
  end if;
end $$;
