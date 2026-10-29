-- Read-only baseline for optional IG sidecar on existing report_output.
-- Legacy COMPLETED executions may lack today's terminal-authority chain.
-- DO NOT report legacy receipts as if they passed current strict contract.
WITH completed AS MATERIALIZED(
 SELECT e.execution_id,e.target_code,e.status,
   x.evidence_payload->'profile_output' raw_output,
   y.evidence_payload report_payload,
   j.evidence_payload judge_payload,
   public.lf_profile_execution_terminal_authority_receipt_v1(e.execution_id) terminal
 FROM public.lf_operation_execution e
 JOIN public.lf_operation_execution_steps x
   ON x.execution_id=e.execution_id AND x.step_id='execute_profile'
   AND x.status='STEP_PASS_WITH_EVIDENCE'
 JOIN public.lf_operation_execution_steps y
   ON y.execution_id=e.execution_id AND y.step_id='report_output'
   AND y.status='STEP_PASS_WITH_EVIDENCE'
 JOIN public.lf_operation_execution_steps j
   ON j.execution_id=e.execution_id AND j.step_id='semantic_judge'
   AND j.status='STEP_PASS_WITH_EVIDENCE'
 WHERE e.operation_code='EJECUCION_PERFIL_LF'
   AND e.target_type='PERFIL' AND e.status='COMPLETED'
), eligible AS MATERIALIZED(
 SELECT c.*,
   substr('sha256:'||encode(extensions.digest(convert_to(raw_output::text,'UTF8'),'sha256'),'hex'),8)
   AS raw_sha
 FROM completed c WHERE c.terminal->>'status'='READY'
), totals AS MATERIALIZED(
 SELECT (SELECT count(*) FROM completed) AS all_completed,
   (SELECT count(*) FROM completed WHERE terminal->>'status'<>'READY') AS legacy_blocked,
   count(*) AS n,
   count(*) FILTER(WHERE jsonb_typeof(raw_output)='object') raw_object,
   count(*) FILTER(WHERE report_payload->>'profile_code'=target_code) profile_match,
   count(*) FILTER(WHERE report_payload->>'execution_id'=execution_id) execution_match,
   count(*) FILTER(WHERE report_payload->>'result'='PASS_INDEPENDENT_SEMANTIC') report_pass,
   count(*) FILTER(WHERE report_payload->>'candidate_sha256'=raw_sha) digest_match,
   count(*) FILTER(WHERE judge_payload#>>'{semantic_judge_result,status}'='PASS') judge_pass,
   count(*) FILTER(WHERE report_payload ? 'ig_profile_feedback') existing_sidecar
 FROM eligible
), tests AS MATERIALIZED(
 SELECT 'CURRENT_TERMINAL_AUTHORITY_SAMPLE_EXISTS' name,n>0 pass FROM totals
 UNION ALL SELECT 'READY_AND_LEGACY_COHORTS_DISTINCT',
   n+legacy_blocked=all_completed FROM totals
 UNION ALL SELECT 'ALL_READY_RAW_OUTPUTS_OBJECTS',raw_object=n FROM totals
 UNION ALL SELECT 'ALL_READY_REPORT_PROFILE_MATCH',profile_match=n FROM totals
 UNION ALL SELECT 'ALL_READY_REPORT_EXECUTION_MATCH',execution_match=n FROM totals
 UNION ALL SELECT 'ALL_READY_REPORTS_PASS',report_pass=n FROM totals
 UNION ALL SELECT 'ALL_READY_RAW_OUTPUT_SHA_MATCH',digest_match=n FROM totals
 UNION ALL SELECT 'ALL_READY_SEMANTIC_JUDGES_PASS',judge_pass=n FROM totals
 UNION ALL SELECT 'CURRENT_REPORTS_NO_SIDECAR',existing_sidecar=0 FROM totals
 UNION ALL SELECT 'LIVE_ROUTER_PREPARE_PREIMAGE_UNCHANGED',
  md5(pg_get_functiondef('public.lf_profile_result_router_return_prepare_v1(text)'::regprocedure))
   ='8bf503bf17f038a18124783c038d9793'
 UNION ALL SELECT 'RUN_949_UNIVERSE_UNCHANGED',
  (SELECT count(*)=47 FROM programacion.input_family_assessments WHERE run_id=949)
)
SELECT name,CASE WHEN pass IS TRUE THEN 'PASS' ELSE 'FAIL' END verdict,
 CASE WHEN name='READY_AND_LEGACY_COHORTS_DISTINCT'
 THEN (SELECT 'eligible='||n||', legacy_not_READY='||legacy_blocked FROM totals)
 ELSE NULL END observation
FROM tests ORDER BY name;