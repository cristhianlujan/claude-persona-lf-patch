-- Read-only regression: specialist feedback MUST bind to IG receipt consumed by the
-- same governed profile execution. Fixture run 949 is historical audit-only.
-- No DDL, DML, source promotion, new IG run or direct profile invocation.
WITH base AS MATERIALIZED (
 SELECT e.execution_id AS id,e.target_code AS profile_code,
        r.id::bigint AS run_id,r.pantalla_id,
        r.source_snapshot_sha256 AS sha
 FROM public.lf_operation_execution e
 JOIN public.lf_operation_execution_steps s ON s.execution_id=e.execution_id
 JOIN programacion.input_readiness_runs r
 ON r.id=(s.evidence_payload#>>'{input_governance,run_id}')::bigint
 WHERE s.step_id='input_validate'
   AND s.status='STEP_PASS_WITH_EVIDENCE'
   AND r.id=949
   AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
 LIMIT 1
), cases AS MATERIALIZED (
 SELECT 'VALID_EXACT_BINDING'::text test,id execution_id,profile_code,
        run_id,pantalla_id,sha,'SESSION'::text family_code,true expected FROM base
 UNION ALL SELECT 'REJECT_UNKNOWN_EXECUTION','UNKNOWN-EXECUTION',
   profile_code,run_id,pantalla_id,sha,'SESSION',false FROM base
 UNION ALL SELECT 'REJECT_WRONG_PROFILE',id,'PERFIL-UI-ARCHITECT',
   run_id,pantalla_id,sha,'SESSION',false FROM base
 UNION ALL SELECT 'REJECT_WRONG_RUN',id,profile_code,833,
   pantalla_id,sha,'SESSION',false FROM base
 UNION ALL SELECT 'REJECT_WRONG_SCREEN',id,profile_code,run_id,
   41,sha,'SESSION',false FROM base
 UNION ALL SELECT 'REJECT_WRONG_SHA',id,profile_code,run_id,
   pantalla_id,repeat('a',64),'SESSION',false FROM base
 UNION ALL SELECT 'REJECT_MISSING_FAMILY',id,profile_code,run_id,
   pantalla_id,sha,'FAKE_FAMILY',false FROM base
), checks AS MATERIALIZED (
 SELECT c.test,c.expected,
 EXISTS(
  SELECT 1 FROM programacion.input_readiness_runs r
  JOIN programacion.input_family_assessments a ON a.run_id=r.id
  JOIN public.lf_operation_execution e
   ON e.execution_id=c.execution_id
   AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.target_type='PERFIL'
   AND e.target_code=c.profile_code
   AND e.status IN ('IN_PROGRESS','COMPLETED')
  JOIN public.lf_operation_execution_steps s
   ON s.execution_id=e.execution_id
   AND s.step_id='input_validate'
   AND s.status='STEP_PASS_WITH_EVIDENCE'
   AND s.evidence_payload#>>'{input_governance,run_id}'=r.id::text
   AND s.evidence_payload#>>'{input_governance,pantalla_id}'=r.pantalla_id::text
   AND s.evidence_payload#>>'{input_governance,context_manifest,run,source_snapshot_sha256}'=r.source_snapshot_sha256
  WHERE r.id=c.run_id AND r.pantalla_id=c.pantalla_id
   AND r.source_snapshot_sha256=c.sha
   AND a.family_code=c.family_code
   AND r.status='COMPLETED'
 ) AS observed FROM cases c
)
SELECT test,expected,observed,
  CASE WHEN expected IS NOT DISTINCT FROM observed THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM checks
UNION ALL
SELECT 'FIXTURE_PRESENT',true,(SELECT count(*)=1 FROM base),
  CASE WHEN (SELECT count(*)=1 FROM base) THEN 'PASS' ELSE 'FAIL' END
ORDER BY test;