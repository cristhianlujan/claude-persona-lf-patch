-- D2 read-only interoperability probe against the ACTUAL Supabase planner.
-- Synthetic refs are test fixtures only. This does NOT authorize source reads.
WITH fixtures(case_code,payload) AS (
 VALUES
 ('WITH_MATERIAL_CANDIDATE',jsonb_build_object(
   'consumer_ref','synthetic://d1d2/planner-probe',
   'unresolved_reasons',jsonb_build_array('SOURCE_NOT_IDENTIFIED'),
   'current_evidence',jsonb_build_array(),
   'candidates',jsonb_build_array(jsonb_build_object(
       'candidate_ref','synthetic://d1d2/proof/1',
       'source_ref','synthetic://source/1',
       'covers_reasons',jsonb_build_array('SOURCE_NOT_IDENTIFIED'),
       'acquisition_cost_rank',1,
       'available',true,'material',true))
 )),
 ('NO_ADMITTED_CANDIDATES',jsonb_build_object(
   'consumer_ref','synthetic://d1d2/planner-probe',
   'unresolved_reasons',jsonb_build_array('SOURCE_NOT_IDENTIFIED'),
   'current_evidence',jsonb_build_array(),
   'candidates',jsonb_build_array()
 ))
), planner AS (
 SELECT case_code, public.lf_targeted_evidence_acquisition_plan_v1(payload) result
 FROM fixtures
)
SELECT case_code,
 result->>'state' AS planner_state,
 result->>'code' AS planner_code,
 (result->>'automation_options_exhausted')::boolean AS planner_exhausted_local_options,
 (result->>'effects_executed')::boolean AS effects_executed,
 CASE WHEN case_code='WITH_MATERIAL_CANDIDATE'
             AND result->>'state'='CONTINUE'
             AND result->>'code'='NEXT_MINIMAL_EVIDENCE_SELECTED'
             AND (result->>'effects_executed')::boolean IS FALSE
           THEN 'PASS'
      WHEN case_code='NO_ADMITTED_CANDIDATES'
             AND result->>'state'='STOP'
             AND result->>'code'='STOP_NO_DECISION_CHANGING_EVIDENCE'
             AND (result->>'effects_executed')::boolean IS FALSE
           THEN 'PASS'
      ELSE 'FAIL' END AS contract_result
FROM planner ORDER BY case_code;

-- IMPORTANT: STOP_NO_DECISION_CHANGING_EVIDENCE means only that the existing
-- targeted-acquisition planner has no currently admitted material candidate.
-- Its automation_options_exhausted=true is LOCAL to this candidate list.
-- D1 must NOT transform it into global discovery exhaustion or a final answer.
