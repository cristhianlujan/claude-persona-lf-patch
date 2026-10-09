-- IG M4.12 / R11 novation (owner-authorized 2026-10-09 08:16 Lima; lf_eventos 20635, schema IG_R11_NOVATION_V1).
-- CORRELATION_RERUN no longer measures structural shared-conclusion dependencies (unattainable while the Validator reuses the
-- Curator classifier). It measures three behavioral controls: facts, logic (severity invariant), correlation by defect injection.
-- The original criterion stays recorded as NOT met by design; the Validator is NOT declared independent of the Curator.
UPDATE programacion.engineering_plan_units u
   SET unit_metadata = jsonb_set(
         unit_metadata,
         '{action_specs_v1,CORRELATION_RERUN,test_scope_contract}',
         jsonb_build_object(
           'subject','CURRENT_VALIDATOR',
           'authority','R11_NOVATION_EVENT_20635',
           'pass_condition','BEHAVIORAL_CONTROLS_V1',
           'controls',jsonb_build_array('FACTS_INVARIANTS','LOGIC_SEVERITY_INVARIANT','CORRELATION_DEFECT_INJECTION'),
           'original_criterion','ZERO_SHARED_CONCLUSION_DEPENDENCIES',
           'original_criterion_met',false,
           'validator_independent_of_curator',false,
           'novation_event_id',20635),
         true)
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M4.12'
   AND u.unit_metadata #> '{action_specs_v1,CORRELATION_RERUN,test_scope_contract,pass_condition}' = '"ZERO_SHARED_CONCLUSION_DEPENDENCIES"'::jsonb;
