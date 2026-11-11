-- LF M10.13 CP3 | controlled read-only functional overlap check for frozen legacy consumer
-- Requires an existing current RUN 951; invokes STABLE legacy read-only revalidator.
-- Does NOT invoke Curator/Validator writers or create a new IG RUN.
-- No conclusion of behavioral equivalence is permitted from zero old drift + validator PASS.
WITH
run_state AS (
 SELECT r.id AS run_id,r.status,r.version_id,r.pantalla_id,r.family_count,
        programacion.fn_input_run_is_source_current(r.id) AS source_current
 FROM programacion.input_readiness_runs r WHERE r.id=951
),
legacy AS (
 SELECT programacion.fn_input_run_semantic_revalidation_v1(r.run_id) AS output
 FROM run_state r
),
validator_live AS (
 SELECT count(*)::int AS assessment_count,
        count(*) FILTER (WHERE a.validator_outcome='PASS')::int AS validator_pass_count,
        count(*) FILTER (WHERE a.validator_evidence->>'semantic_conclusion_independence'='UNPROVEN')::int AS independence_unproven_count,
        count(*) FILTER (WHERE a.validator_evidence->>'semantic_independence_credited'='true')::int AS independence_credited_count,
        count(*) FILTER (WHERE a.validator_evidence->>'bootstrap_classifier_sha256' IS NULL)::int AS validator_sha_null_count,
        count(*) FILTER (WHERE a.curator_evidence->>'bootstrap_classifier_sha256' IS NULL)::int AS curator_sha_null_count,
        count(*) FILTER (WHERE a.validator_evidence->>'semantic_comparison_requested'='true')::int AS semantic_comparison_requested_count
 FROM programacion.input_family_assessments a WHERE a.run_id=951
),
snapshot AS (
 SELECT rs.run_id,rs.status,rs.version_id,rs.pantalla_id,rs.family_count,rs.source_current,l.output AS legacy,v.*
 FROM run_state rs CROSS JOIN legacy l CROSS JOIN validator_live v
)
SELECT
 run_id,status AS ig_run_status,version_id,pantalla_id,family_count,
 source_current,
 legacy->>'schema_version' AS legacy_schema,
 legacy->>'eligible' AS legacy_eligible,
 legacy->>'required' AS legacy_required,
 (legacy->>'classifier_drift_count')::int AS legacy_classifier_drift,
 (legacy->>'missing_classifier_count')::int AS legacy_missing_classifier,
 (legacy->>'semantic_depth_drift_count')::int AS legacy_semantic_depth_drift,
 assessment_count,validator_pass_count,
 independence_unproven_count,independence_credited_count,
 validator_sha_null_count,curator_sha_null_count,
 semantic_comparison_requested_count,
 CASE
 WHEN validator_pass_count=assessment_count
      AND independence_unproven_count>0
      AND independence_credited_count=0
 THEN 'NO_FUNCTIONAL_EQUIVALENCE_ATTESTED'
 ELSE 'NO_FULL_FUNCTIONAL_EQUIVALENCE_RECEIPT'
 END AS parity_disposition,
 (validator_pass_count=assessment_count
  AND independence_unproven_count=assessment_count
  AND independence_credited_count=0
  AND curator_sha_null_count=0
  AND validator_sha_null_count=assessment_count
  AND semantic_comparison_requested_count=0
 ) AS expected_no_false_parity_test,
 (SELECT status FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS') AS cp3_state
FROM snapshot;
