-- LF Input Governance / Router consumer persistence regression.
-- AUDIT ONLY: historical persisted run, no new run, no DDL/DML.
-- Never select a run dynamically as operational authority.
WITH router_intake AS MATERIALIZED (
 SELECT public.lf_router_pipeline_context_begin_v2(
  'Revisar login b2b para ver las reglas que le faltan'
 ) AS result
), consumer_step AS MATERIALIZED (
 SELECT e.execution_id, e.operation_code, e.status AS caller_status,
        s.status AS step_status,s.evidence_payload->'input_governance' AS ig
 FROM public.lf_operation_execution e
 JOIN public.lf_operation_execution_steps s USING(execution_id)
 WHERE e.operation_code='EJECUCION_PERFIL_LF'
   AND s.step_id='input_validate'
   AND s.status='STEP_PASS_WITH_EVIDENCE'
   AND s.evidence_payload->'input_governance'->>'run_id'='949'
), linked_run AS MATERIALIZED (
 SELECT p.*,r.id AS ig_run_id,r.pantalla_id,r.status AS ig_run_status,
        r.invalidated_at,r.source_snapshot_sha256,
        r.curator_identity,r.validator_identity,r.supersedes_run_id
 FROM consumer_step p
 JOIN programacion.input_readiness_runs r
 ON r.id=(p.ig->>'run_id')::bigint
), families AS MATERIALIZED (
 SELECT family_code,validator_outcome
 FROM programacion.input_family_assessments WHERE run_id=949
), proposals AS MATERIALIZED (
 SELECT family_code,gap_code,validator_outcome
 FROM programacion.input_gap_proposals WHERE run_id=949
), chunks AS MATERIALIZED (
 SELECT chunk_no,families_processed,pending_count,result_status,validator_identity
 FROM programacion.input_validator_chunk_timings WHERE run_id=949
), checks AS MATERIALIZED (
 SELECT 'ROUTER_INTAKE_HAS_NO_EFFECT_AUTHORITY'::text AS control,
  (SELECT result->>'status'='STAGE1_REQUIRED'
   AND result->>'next_step'='stage1_seal'
   AND result->>'effect_authority'='false'
   FROM router_intake) AS passed
 UNION ALL SELECT 'CALLER_HAS_ONE_IG_RUN_REFERENCE',
  (SELECT count(*)=1 FROM linked_run)
 UNION ALL SELECT 'CALLER_IG_IDS_AND_SOURCE_HASH_MATCH',
  (SELECT count(*)=1 AND bool_and(ig->>'run_id'=ig_run_id::text
   AND ig->>'pantalla_id'=pantalla_id::text
   AND ig#>>'{context_manifest,run,run_id}'=ig_run_id::text
   AND ig#>>'{context_manifest,run,source_snapshot_sha256}'=source_snapshot_sha256)
   FROM linked_run)
 UNION ALL SELECT 'IG_RUN_TERMINAL_CURRENT',
  (SELECT count(*)=1 AND bool_and(ig_run_status='COMPLETED' AND invalidated_at IS NULL)
   FROM linked_run)
 UNION ALL SELECT 'CURATOR_VALIDATOR_DISTINCT',
  (SELECT count(*)=1 AND bool_and(curator_identity IS NOT NULL
     AND validator_identity IS NOT NULL
     AND curator_identity IS DISTINCT FROM validator_identity)
   FROM linked_run)
 UNION ALL SELECT 'FAMILY_UNIQUE_AND_COMPLETE',
  (SELECT count(*)=47 AND count(DISTINCT family_code)=47
   AND count(*) FILTER(WHERE validator_outcome='PASS')=47
   FROM families)
 UNION ALL SELECT 'PROPOSALS_UNIQUE_AND_VALIDATED',
  (SELECT count(*)>0 AND count(*)=count(DISTINCT (family_code,gap_code))
   AND count(*) FILTER (WHERE validator_outcome='PASS')=count(*)
   FROM proposals)
 UNION ALL SELECT 'VALIDATOR_CHUNKS_KEEP_RUN_AND_RESUME',
  (SELECT count(*)>1 AND count(DISTINCT chunk_no)=count(*)
   AND sum(families_processed)=47
   AND count(DISTINCT validator_identity)=1
   AND count(*) FILTER (WHERE result_status='COMPLETED')=1
   FROM chunks)
 UNION ALL SELECT 'CALLER_RESUME_NO_ROUTER_REENTRY',
  (SELECT count(*)=1 AND bool_and(ig->>'resume_via'='EJECUCION_PERFIL_LF/input_validate')
    FROM linked_run)
 UNION ALL SELECT 'RUN_HISTORY_HAS_SUPERSESSION',
  (SELECT count(*)=1 AND bool_and(supersedes_run_id IS NOT NULL)
    FROM linked_run)
)
SELECT control, CASE WHEN passed IS TRUE THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM checks ORDER BY control;