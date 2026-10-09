-- IG M9.3 evidence route, sandbox-only. Declares a checkpoint-specific
-- workflow as an additional scoped authored test artifact. No automatic runtime
-- activation and no changes to terminal PASS criteria.
DO $m93$
DECLARE s jsonb; w jsonb := jsonb_build_object(
  'path','cristhianlujan/claude-persona-lf-patch:.github/workflows/ig-m93-shadow-readonly.yml',
  'role','MUTATION_TARGET',
  'purpose','M93_SANDBOX_DIAGNOSTIC_TEST_WORKFLOW',
  'target_kind','EXACT_NEW_OR_UPDATE_FILE');
BEGIN
 SELECT unit_metadata#>'{action_specs_v1,FULL_PIPELINE_CANDIDATE}'
 INTO STRICT s FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.3' FOR UPDATE;
 IF s#>>'{evidence_acquisition_contract,runner_path}' <>
   'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_3/full_pipeline_shadow_runner.py'
   OR s->>'contract_family'<>'BOUNDED_CHECKPOINT_TEST'
 THEN RAISE EXCEPTION 'M93_SANDBOX_DIAGNOSTIC_CONTRACT_DRIFT';
 END IF;
 IF NOT coalesce(s#>'{target,mutation_artifacts}','[]'::jsonb) @> jsonb_build_array(w) THEN
   s:=jsonb_set(s,'{target,mutation_artifacts}',
       coalesce(s#>'{target,mutation_artifacts}','[]'::jsonb)||jsonb_build_array(w),true);
   s:=jsonb_set(s,'{target,declared_artifacts}',
       coalesce(s#>'{target,declared_artifacts}','[]'::jsonb)||jsonb_build_array(w),true);
 END IF;
 s:=jsonb_set(s,'{evidence_acquisition_contract,sandbox_workflow}',
   to_jsonb('.github/workflows/ig-m93-shadow-readonly.yml'::text),true);
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,FULL_PIPELINE_CANDIDATE}',s,true)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.3';
END $m93$;
