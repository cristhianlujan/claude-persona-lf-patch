-- READ ONLY: profile-neutral Router-return authority and no-feedback regressions.
-- Do NOT invoke the candidate DDL or alter persisted execution receipts.
WITH cohort AS MATERIALIZED(
 SELECT e.execution_id,e.target_code,
   e.manifest#>>'{router_profile_handoff,return_to_router_after_profile_result}' AS declared_return,
   public.lf_profile_execution_terminal_authority_receipt_v1(e.execution_id) terminal
 FROM public.lf_operation_execution e
 WHERE e.operation_code='EJECUCION_PERFIL_LF' AND e.status='COMPLETED'
), ready AS MATERIALIZED(
 SELECT c.*,public.lf_profile_result_router_return_prepare_v1(c.execution_id) prepared,
  x.evidence_payload->'profile_output' output,
  r.evidence_payload report
 FROM cohort c
 JOIN public.lf_operation_execution_steps x
  ON x.execution_id=c.execution_id AND x.step_id='execute_profile'
 JOIN public.lf_operation_execution_steps r
  ON r.execution_id=c.execution_id AND r.step_id='report_output'
 WHERE c.terminal->>'status'='READY'
), tests AS MATERIALIZED(
 SELECT 'READY_TERMINAL_COHORT_SIZE_2' name,(SELECT count(*)=2 FROM ready) pass
 UNION ALL SELECT 'NO_LEGACY_PROMOTED',
  (SELECT count(*)=14 FROM cohort WHERE terminal->>'status'<>'READY')
 UNION ALL SELECT 'NO_SIDE_CAR_ALREADY_LIVE',
  (SELECT count(*)=0 FROM ready WHERE report ? 'ig_profile_feedback')
 UNION ALL SELECT 'RAW_OUTPUT_SHA_RELIABLE_WHEN_RETURN_ENABLED',
  (SELECT bool_and(
    prepared->>'profile_output_sha256'=
      'sha256:'||encode(extensions.digest(convert_to(output::text,'UTF8'),'sha256'),'hex')
  ) FROM ready WHERE declared_return='true')
 UNION ALL SELECT 'DISABLED_RETURN_REMAINS_COMPLETE',
  (SELECT count(*)=1 FROM ready
    WHERE declared_return='false'
      AND prepared->>'status'='COMPLETE'
      AND prepared->>'code'='PROFILE_RESULT_ROUTER_RETURN_DISABLED')
 UNION ALL SELECT 'ENABLED_TERMINAL_PROFILE_CAN_FINISH_WITHOUT_REENTRY',
  (SELECT count(*)=1 FROM ready
    WHERE declared_return='true'
      AND prepared->>'status'='COMPLETE'
      AND prepared->>'next_action'='EMIT_PROFILE_RESULT')
 UNION ALL SELECT 'LIVE_ROUTER_PREPARE_SOURCE_UNCHANGED',
  md5(pg_get_functiondef('public.lf_profile_result_router_return_prepare_v1(text)'::regprocedure))
   ='8bf503bf17f038a18124783c038d9793'
 UNION ALL SELECT 'LIVE_TRUST_VALIDATOR_SOURCE_UNCHANGED',
  md5(pg_get_functiondef('public.lf_profile_execution_trust_validation_v2(text,text,jsonb)'::regprocedure))
   ='c71964f030d7c2f9bf90101f541a6e6b'
 UNION ALL SELECT 'RUN_949_FAMILIES_NOT_MUTATED',
  (SELECT count(*)=47 FROM programacion.input_family_assessments WHERE run_id=949)
)
SELECT name,CASE WHEN pass IS TRUE THEN 'PASS' ELSE 'FAIL' END result FROM tests ORDER BY name;