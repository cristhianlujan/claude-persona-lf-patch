-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M7.6 / PAULO-145
-- Projection repair only: restore EVIDENCE_LEDGER registry entry guard to its current v1.1.0 manifest.
-- No ledger logic, receipt rows, current pointer, judge, Validator or M7.14 change.

do $$
declare
  v_current_version text;
  v_current_manifest text;
  v_manifest_guard boolean;
  v_manifest_guard_code text;
begin
  select version,manifest_sha256
    into v_current_version,v_current_manifest
  from public.lf_capability_current
  where capability_code='EVIDENCE_LEDGER';

  if v_current_version is distinct from '1.1.0'
     or v_current_manifest is distinct from 'b9c21eaa0cb4eceec3e6a0ae78272ed2da84e408e804c127ed6e43d1360f0982' then
    raise exception 'M7_6_EVIDENCE_LEDGER_CURRENT_DRIFT';
  end if;

  select (manifest#>>'{currentness,entry_guard_required}')::boolean,
         manifest#>>'{currentness,entry_guard_code}'
    into v_manifest_guard,v_manifest_guard_code
  from public.lf_capability_version_registry
  where capability_code='EVIDENCE_LEDGER' and version='1.1.0';

  if v_manifest_guard is distinct from true
     or v_manifest_guard_code is distinct from 'ORCHESTRATOR_EXECUTION_GUARD_V1' then
    raise exception 'M7_6_EVIDENCE_LEDGER_MANIFEST_GUARD_DRIFT';
  end if;

  update public.lf_capability_registry
     set entry_guard_required=true,
         entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
         updated_at=now(),
         updated_by_execution_id='PAULO-145'
   where capability_code='EVIDENCE_LEDGER'
     and status='ACTIVE';

  if not found then raise exception 'M7_6_EVIDENCE_LEDGER_REGISTRY_MISSING'; end if;

  if not exists(
    select 1 from public.lf_capability_registry
    where capability_code='EVIDENCE_LEDGER'
      and status='ACTIVE'
      and entry_guard_required=true
      and entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) then raise exception 'M7_6_EVIDENCE_LEDGER_ENTRY_GUARD_REPAIR_READBACK_FAILED'; end if;
end $$;
