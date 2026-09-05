-- Q9 UPDATE STEP60 DEDICATED JUDGE MATERIALIZATION V1
-- SOURCE ONLY / NOT APPLIED
-- Operation: ACTUALIZACION_PERFIL_LF
-- Step: pre_write_execution_binding_gate (60)
-- This judge classifies caller attestations only. It is NOT deterministic currentness authority.
-- Deterministic authority remains SERVER_DERIVED_TRUST_CONTEXT_REQUIRED.

begin;

insert into public.lf_operation_judges(
  operation_code,
  judge_code,
  judge_path,
  judge_sha,
  pass_if,
  fail_if,
  result_values,
  status,
  created_by_execution_id,
  updated_by_execution_id
)
values (
  'ACTUALIZACION_PERFIL_LF',
  'JUDGE-ACTUALIZACION-PERFIL-LF-PREWRITE-BINDING-v1',
  'skills/profile_creator/contracts/update_judge_semantics_source_v1.json',
  'SOURCE_DERIVED_AT_MATERIALIZATION_TIME',
  '["execution_id_matches_current_execution","target_code_matches_execution_target","target_path_matches_execution_target","execution_bound_to_target_before_change_is_true","bound_revision_is_structured","bound_revision_matches_current_resolved_revision","stale_revision_has_reread_and_explicit_rebind_when_applicable","required_exact_target_identity_fields_match_target_type"]'::jsonb,
  '["execution_binding_missing_or_false","bound_revision_missing_or_unstructured","target_identity_mismatch","bound_revision_mismatch","stale_revision_without_reread","stale_revision_without_explicit_rebind","raster_artifact_sha_or_dimensions_mismatch_when_applicable","shell_receipt_bound_revision_mismatch_when_shell_applies","required_authorized_delta_missing_for_remediate_existing"]'::jsonb,
  '{"pass":"STEP_PASS_WITH_EVIDENCE","blocked":"BLOCKED_STEP_NOT_CLEAN","return":"RETURN_TO_ROUTER"}'::jsonb,
  'CANDIDATE_NOT_AUTHORITY',
  null,
  null
)
on conflict (operation_code,judge_code) do update
set judge_path=excluded.judge_path,
    judge_sha=excluded.judge_sha,
    pass_if=excluded.pass_if,
    fail_if=excluded.fail_if,
    result_values=excluded.result_values,
    status=excluded.status,
    updated_at=now();

-- Exact single binding only. Existing seven required evidence keys are preserved.
update public.lf_operation_step_judge_bindings
set judge_code='JUDGE-ACTUALIZACION-PERFIL-LF-PREWRITE-BINDING-v1',
    updated_at=now()
where operation_code='ACTUALIZACION_PERFIL_LF'
  and step_id='pre_write_execution_binding_gate'
  and step_order=60
  and status='ACTIVE_ENFORCEMENT'
  and required_evidence_keys = '["execution_id","target_code","target_path","write_plan","pre_write_gate_passed","bound_revision","execution_bound_to_target_before_change"]'::jsonb;

-- Guard: exactly one active step60 binding must point to the dedicated judge.
do $q9$
declare v_count integer;
begin
  select count(*) into v_count
  from public.lf_operation_step_judge_bindings
  where operation_code='ACTUALIZACION_PERFIL_LF'
    and step_id='pre_write_execution_binding_gate'
    and step_order=60
    and status='ACTIVE_ENFORCEMENT'
    and judge_code='JUDGE-ACTUALIZACION-PERFIL-LF-PREWRITE-BINDING-v1';
  if v_count <> 1 then
    raise exception 'Q9_DEDICATED_STEP60_BINDING_CARDINALITY_INVALID:%',v_count;
  end if;
end;
$q9$;

rollback;

-- IMPORTANT: rollback is intentional. This file is a materialization candidate and must remain source-only
-- until explicit live authorization. The production mutation must use a governed provenance execution that
-- remains in an allowed state, and must be followed by live readback + negative/positive tests.
