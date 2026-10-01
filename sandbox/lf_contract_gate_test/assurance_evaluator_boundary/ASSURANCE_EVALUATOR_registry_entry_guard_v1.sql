-- ASSURANCE_EVALUATOR registry/entry-guard cutover only.
-- The semantic evaluator remains NOT CURRENT and cannot execute.
-- No subject binding activation, no evaluator runtime, no deploy or production effect.

do $$
declare
  v_active_bindings integer;
  v_versions integer;
  v_current integer;
begin
  select count(*)::integer into v_active_bindings
  from public.lf_assurance_subject_bindings
  where status='ACTIVE';

  if v_active_bindings <> 0 then
    raise exception 'ASSURANCE_EVALUATOR_REGISTRY_CUTOVER_ACTIVE_BINDINGS:%',v_active_bindings;
  end if;

  insert into public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) values (
    'ASSURANCE_EVALUATOR','Assurance Evaluator','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Material-claim evidence-sufficiency evaluator. Registry entry only: Router owns applicability; exact subject binding is required; semantic evaluator remains not-current until separately qualified.',
    'EXEC-SADM-ASSURANCE-EVALUATOR-ENTRY-GUARD-20260930',
    'EXEC-SADM-ASSURANCE-EVALUATOR-ENTRY-GUARD-20260930',
    true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  )
  on conflict (capability_code) do update set
    capability_name=excluded.capability_name,
    capability_kind=excluded.capability_kind,
    owner_scope=excluded.owner_scope,
    status=excluded.status,
    description=excluded.description,
    entry_guard_required=true,
    entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
    updated_at=now(),
    updated_by_execution_id=excluded.updated_by_execution_id;

  select count(*)::integer into v_versions
  from public.lf_capability_version_registry
  where capability_code='ASSURANCE_EVALUATOR';

  select count(*)::integer into v_current
  from public.lf_capability_current
  where capability_code='ASSURANCE_EVALUATOR';

  if v_versions <> 0 then
    raise exception 'ASSURANCE_EVALUATOR_UNEXPECTED_VERSION_PREMATURE:%',v_versions;
  end if;

  if v_current <> 0 then
    raise exception 'ASSURANCE_EVALUATOR_UNEXPECTED_CURRENT_POINTER:%',v_current;
  end if;
end;
$$;
