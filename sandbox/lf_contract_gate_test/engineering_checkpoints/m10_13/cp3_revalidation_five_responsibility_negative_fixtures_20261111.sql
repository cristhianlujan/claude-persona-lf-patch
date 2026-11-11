-- LF IG M10.13 CP3 | five responsibilities - negative fixture-only proof
-- Reads persisted run 951. No persisted values are modified.
-- This is a fixture oracle initialized from the existing current run, NOT
-- independent re-execution of classifier/subject/threat functions on mutated data.
-- Test cases intentionally mutate only a CTE copy of persisted family assessments.
WITH
cases(scenario,exp_classifier_drift,exp_missing,exp_semantic_depth) AS (
 VALUES ('BASELINE'::text,0,0,0),
 ('MUTATE_CLASSIFIER_SHA',1,0,0),
 ('MISSING_CLASSIFIER_SHA',0,1,0),
 ('MUTATE_DESIGN_SUBJECT',0,0,1),
 ('MUTATE_SECURITY_THREAT',0,0,1),
 ('COMBINED',1,1,2)
),
persisted AS (
 SELECT family_code,curator_evidence->>'bootstrap_classifier_sha256' AS stored_sha,
        subject_coverage AS stored_subject,threat_coverage AS stored_threat
 FROM programacion.input_family_assessments WHERE run_id=951
),
mutants AS (
 SELECT c.scenario,p.family_code,p.stored_sha,p.stored_subject,p.stored_threat,
 CASE
  WHEN c.scenario IN ('MUTATE_CLASSIFIER_SHA','COMBINED') AND p.family_code='FIELDS'
   THEN repeat('0',64)
  WHEN c.scenario IN ('MISSING_CLASSIFIER_SHA','COMBINED') AND p.family_code='VALIDATIONS'
   THEN NULL::text
  ELSE p.stored_sha END AS candidate_sha,
 CASE WHEN c.scenario IN ('MUTATE_DESIGN_SUBJECT','COMBINED')
             AND p.family_code='DESIGN_SYSTEM'
  THEN p.stored_subject||jsonb_build_array(jsonb_build_object('fixture','NEGATIVE_DESIGN_DRIFT'))
  ELSE p.stored_subject END AS candidate_subject,
 CASE WHEN c.scenario IN ('MUTATE_SECURITY_THREAT','COMBINED')
             AND p.family_code='SECURITY'
  THEN p.stored_threat||jsonb_build_array(jsonb_build_object('fixture','NEGATIVE_SECURITY_THREAT_DRIFT'))
  ELSE p.stored_threat END AS candidate_threat
 FROM cases c CROSS JOIN persisted p
),
measure AS (
 SELECT scenario,
 count(*)::int AS families,
 count(*) FILTER(WHERE NULLIF(candidate_sha,'') IS NULL)::int AS missing_sha,
 count(*) FILTER(WHERE NULLIF(candidate_sha,'') IS NOT NULL
                    AND candidate_sha IS DISTINCT FROM stored_sha)::int AS classifier_drift,
 count(*) FILTER(WHERE
    (family_code='DESIGN_SYSTEM' AND candidate_subject IS DISTINCT FROM stored_subject)
    OR (family_code='SECURITY'
       AND (candidate_subject IS DISTINCT FROM stored_subject
        OR candidate_threat IS DISTINCT FROM stored_threat))
 )::int AS depth_drift
 FROM mutants GROUP BY scenario
),
real_baseline AS (
 SELECT programacion.fn_input_run_semantic_revalidation_v1(951) AS result
)
SELECT c.scenario,m.families,m.classifier_drift,m.missing_sha,m.depth_drift,
 c.exp_classifier_drift,c.exp_missing,c.exp_semantic_depth,
 (m.families=47 AND m.classifier_drift=c.exp_classifier_drift
 AND m.missing_sha=c.exp_missing AND m.depth_drift=c.exp_semantic_depth
 AND (SELECT result->>'required' FROM real_baseline)='false'
 AND (SELECT result->>'classifier_drift_count' FROM real_baseline)='0'
 AND (SELECT result->>'missing_classifier_count' FROM real_baseline)='0'
 AND (SELECT result->>'semantic_depth_drift_count' FROM real_baseline)='0'
 ) AS fixture_test_pass,
 'CTE_FIXTURE_NOT_REAL_MUTATED_LEGACY_RUN'::text AS proof_scope
FROM cases c JOIN measure m USING(scenario) ORDER BY c.scenario;