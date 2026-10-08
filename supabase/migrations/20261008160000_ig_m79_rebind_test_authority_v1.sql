
-- M7.9: repair behavioral test-authoring contract, not production runtime.
DO $p$ BEGIN IF NOT EXISTS (
 SELECT 1 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M7.9'
 AND c.checkpoint_code='REBIND_CASES' AND c.status='IN_PROGRESS'
 AND u.unit_metadata#>>'{action_specs_v1,REBIND_CASES,action_kind}'='MATERIALIZE_DECLARED_DELIVERABLE'
) THEN RAISE EXCEPTION 'M79_REBIND_CONTRACT_DRIFT'; END IF; END;$p$;
WITH base AS (
 SELECT id,unit_metadata m,unit_metadata->'action_specs_v1'->'LINEAGE_DAG_CASES' s
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M7.9' FOR UPDATE
), candidate AS (
 SELECT id,m,s||jsonb_build_object(
 'checkpoint_code','REBIND_CASES',
 'checkpoint_title','4 propios: elegible, no elegible, RESOLUTION_ERROR, copia + PENDING',
 'target',jsonb_build_object('checkpoint','REBIND_CASES',
 'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,
 'declared_objects','["programacion.fn_input_governance_curator_plan_v1","programacion.fn_input_governance_curator_materialize_v1","programacion.fn_input_governance_curator_rebind_v1","programacion.input_readiness_runs","programacion.input_family_assessments"]'::jsonb,
 'declared_artifacts','[{"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m7_9/rebind_cases.sql","role":"MUTATION_TARGET","purpose":"CHECKPOINT_TEST_ARTIFACT","target_kind":"EXACT_NEW_OR_UPDATE_FILE"}]'::jsonb,
 'evidence_artifacts','[]'::jsonb,'mutation_artifacts','[{"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m7_9/rebind_cases.sql","role":"MUTATION_TARGET","purpose":"CHECKPOINT_TEST_ARTIFACT","target_kind":"EXACT_NEW_OR_UPDATE_FILE"}]'::jsonb),
 'verification_queries','["select r.id,r.pantalla_id,programacion.fn_input_governance_curator_plan_v1(r.pantalla_id,true,r.id) as forced_rebind_plan from programacion.input_readiness_runs r where r.status=''COMPLETED'' order by r.id desc limit 1","select count(*) prior_completed from programacion.input_readiness_runs where status=''COMPLETED''"]'::jsonb,
 'test_execution_contract',(s->'test_execution_contract')||jsonb_build_object(
 'test_code','ENG_M7_9_REBIND_CASES','test_path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m7_9/rebind_cases.sql',
 'declared_objects','["programacion.fn_input_governance_curator_plan_v1","programacion.fn_input_governance_curator_materialize_v1","programacion.fn_input_governance_curator_rebind_v1","programacion.input_readiness_runs","programacion.input_family_assessments"]'::jsonb,
 'declared_queries','["select r.id,r.pantalla_id,programacion.fn_input_governance_curator_plan_v1(r.pantalla_id,true,r.id) as forced_rebind_plan from programacion.input_readiness_runs r where r.status=''COMPLETED'' order by r.id desc limit 1","select count(*) prior_completed from programacion.input_readiness_runs where status=''COMPLETED''"]'::jsonb,'negative_required',true,
 'canonical_exit_criterion','Independent four-case REBIND behavior without M5.7/M5.8 inherited execution',
 'scenarios',jsonb_build_array('ELIGIBLE','INELIGIBLE','RESOLUTION_ERROR','COPY_PENDING')),
 'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET',
 'pass_when',jsonb_build_object('test_passed',true,'test_exit_code',0,'semantic_authority_bound',true,'four_scenarios_passed',true)),
 'handler_requirement',(s->'handler_requirement')||jsonb_build_object(
 'existing_exact_case_set_found',true,'next_action','EXECUTE_OWN_REBIND_TEST'),
 'reclassified_by','M79_INDEPENDENT_TEST_AUTHORITY_V1') spec
 FROM base)
UPDATE programacion.engineering_plan_units u
 SET unit_metadata=jsonb_set(candidate.m,'{action_specs_v1,REBIND_CASES}',candidate.spec,true)
 FROM candidate WHERE u.id=candidate.id;
SELECT programacion.fn_engineering_checkpoint_input_upsert_v1(
'IG_CURATOR_VALIDATOR_REFACTOR_V2','M7.9','REBIND_CASES',
'["select r.id,r.pantalla_id,programacion.fn_input_governance_curator_plan_v1(r.pantalla_id,true,r.id) as forced_rebind_plan from programacion.input_readiness_runs r where r.status=''COMPLETED'' order by r.id desc limit 1","select count(*) prior_completed from programacion.input_readiness_runs where status=''COMPLETED''"]'::jsonb,'["programacion.fn_input_governance_curator_plan_v1","programacion.fn_input_governance_curator_materialize_v1","programacion.fn_input_governance_curator_rebind_v1","programacion.input_readiness_runs","programacion.input_family_assessments"]'::jsonb,'[]'::jsonb,'[]'::jsonb,
'[{"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m7_9/rebind_cases.sql","role":"MUTATION_TARGET","purpose":"CHECKPOINT_TEST_ARTIFACT","target_kind":"EXACT_NEW_OR_UPDATE_FILE"}]'::jsonb);
DO $v$ DECLARE x jsonb; BEGIN
x:=programacion.fn_engineering_checkpoint_action_spec_v3(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M7.9','REBIND_CASES');
IF x->>'action_kind'<>'BOUNDED_CHECKPOINT_TEST_AUTHORING'
 OR x#>>'{target,declared_artifacts,0,purpose}'<>'CHECKPOINT_TEST_ARTIFACT'
 OR x#>>'{assertion_contract,pass_when,four_scenarios_passed}'<>'true'
 OR x::text LIKE '%fn_input_v58_build_assertions%'
THEN RAISE EXCEPTION 'M79_TEST_CONTRACT_READBACK_FAILED'; END IF;
END;$v$;