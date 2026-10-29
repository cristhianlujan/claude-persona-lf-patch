-- SELECT-only baseline for proposed IG sidecar at report_output.
-- Tests the real current production-readable facts, not the uninstalled patch.
WITH completed AS MATERIALIZED (
 SELECT e.execution_id,e.target_code,e.status,
   output_step.evidence_payload->'profile_output' raw_output,
   report_step.evidence_payload report_payload,
   judge_step.evidence_payload judge_payload
 FROM public.lf_operation_execution e
 JOIN public.lf_operation_execution_steps output_step
   ON output_step.execution_id=e.execution_id
  AND output_step.step_id='execute_profile'
  AND output_step.status='STEP_PASS_WITH_EVIDENCE'
 JOIN public.lf_operation_execution_steps report_step
   ON report_step.execution_id=e.execution_id
  AND report_step.step_id='report_output'
  AND report_step.status='STEP_PASS_WITH_EVIDENCE'
 JOIN public.lf_operation_execution_steps judge_step
   ON judge_step.execution_id=e.execution_id
  AND judge_step.step_id='semantic_judge'
  AND judge_step.status='STEP_PASS_WITH_EVIDENCE'
 WHERE e.operation_code='EJECUCION_PERFIL_LF'
 AND e.target_type='PERFIL'
 AND e.status='COMPLETED'
), checked AS MATERIALIZED (
 SELECT c.*,
  ('sha256:'||encode(extensions.digest(
     convert_to(c.raw_output::text,'UTF8'),'sha256'),'hex')) AS raw_sha
 FROM completed c
), totals AS MATERIALIZED(
 SELECT count(*) n,
  count(*) FILTER(WHERE jsonb_typeof(raw_output)='object') raw_object,
  count(*) FILTER(WHERE report_payload->>'profile_code'=target_code) profile_match,
  count(*) FILTER(WHERE report_payload->>'execution_id'=execution_id) execution_match,
  count(*) FILTER(WHERE report_payload->>'result'='PASS_INDEPENDENT_SEMANTIC') report_pass,
  count(*) FILTER(WHERE report_payload->>'candidate_sha256'=substr(raw_sha,8)) digest_match,
  count(*) FILTER(WHERE judge_payload#>>'{semantic_judge_result,status}'='PASS') judge_pass,
  count(*) FILTER(WHERE report_payload ? 'ig_profile_feedback') existing_sidecar
 FROM checked
), tests AS MATERIALIZED(
 SELECT 'COMPLETED_SAMPLE_EXISTS' name,n>0 pass FROM totals
 UNION ALL SELECT 'ALL_RAW_OUTPUTS_OBJECTS',raw_object=n FROM totals
 UNION ALL SELECT 'ALL_REPORT_PROFILE_CODES_MATCH',profile_match=n FROM totals
 UNION ALL SELECT 'ALL_REPORT_EXECUTION_IDS_MATCH',execution_match=n FROM totals
 UNION ALL SELECT 'ALL_REPORTS_SEMANTIC_PASS',report_pass=n FROM totals
 UNION ALL SELECT 'ALL_REPORT_HASHES_MATCH_RAW_OUTPUTS',digest_match=n FROM totals
 UNION ALL SELECT 'ALL_JUDGES_PASS',judge_pass=n FROM totals
 UNION ALL SELECT 'LEGACY_REPORTS_NO_SIDECAR',existing_sidecar=0 FROM totals
 UNION ALL SELECT 'LIVE_PREPARE_UNCHANGED',
   md5(pg_get_functiondef('public.lf_profile_result_router_return_prepare_v1(text)'::regprocedure))
      ='8bf503bf17f038a18124783c038d9793'
 UNION ALL SELECT 'RUN_949_UNIVERSE_UNCHANGED',
   (SELECT count(*)=47 FROM programacion.input_family_assessments WHERE run_id=949)
)
SELECT name,CASE WHEN pass IS TRUE THEN 'PASS' ELSE 'FAIL' END verdict
FROM tests ORDER BY name;