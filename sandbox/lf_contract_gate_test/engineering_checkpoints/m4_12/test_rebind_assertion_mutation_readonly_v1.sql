-- M4.12 / PAULO-138: READONLY negative test of reused source assertion evaluator.
-- Required: -v selected_run_id=<run ID> from the already selected screen.
-- Mutate only an in-memory EXPECTED count; never update input data/contract.
WITH live_assertions AS (
 SELECT a.run_id,a.family_code,
        x.value assertion
 FROM programacion.input_family_assessments a
 CROSS JOIN LATERAL jsonb_array_elements(
   programacion.fn_input_validator_evidence_rehydrate_v1(a.validator_evidence)->'assertions'
 ) x(value)
 WHERE a.run_id=:selected_run_id
   AND x.value->>'operator'='ARRAY_LENGTH_EQ'
   AND jsonb_typeof(x.value->'expected')='number'
), selected AS (
 SELECT run_id,family_code,assertion
 FROM live_assertions
 ORDER BY family_code
 LIMIT 1
), probe AS (
 SELECT run_id,family_code,
   (programacion.fn_input_evaluate_assertion(run_id,family_code,assertion)->>'passed')::boolean original_pass,
   (programacion.fn_input_evaluate_assertion(run_id,family_code,
     jsonb_set(assertion,'{expected}',
       to_jsonb((assertion->>'expected')::integer+1),false))->>'passed')::boolean mutated_pass
 FROM selected
)
SELECT jsonb_build_object(
 'contract','IG_REBIND_ASSERTION_MUTATION_READONLY_V1',
 'run_id',:selected_run_id,
 'status',CASE WHEN NOT EXISTS(SELECT 1 FROM probe) THEN 'NOT_COVERED'
   WHEN EXISTS(SELECT 1 FROM probe WHERE original_pass IS TRUE AND mutated_pass IS FALSE)
     THEN 'NEGATIVE_MUTATION_DETECTED'
   ELSE 'UNEXPECTED_RESULT' END,
 'observations',(SELECT coalesce(jsonb_agg(jsonb_build_object(
   'family_code',family_code,'original_pass',original_pass,
   'mutated_pass',mutated_pass)),'[]'::jsonb) FROM probe),
 'read_only',true,
 'semantic_independence_proven',false
) AS negative_control;
