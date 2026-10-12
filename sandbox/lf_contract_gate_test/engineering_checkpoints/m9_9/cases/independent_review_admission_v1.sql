-- M9.9 reviewer admission: authoritative readback, no mutation.
-- Independent review must be provider-bound; a callable or its own flag is not evidence.
WITH capability AS (
 SELECT version,manifest_sha256 FROM public.lf_capability_current
 WHERE capability_code='INDEPENDENT_ASSURANCE'
), ig_review AS (
 SELECT count(*)::integer AS verified_review_receipts
 FROM private.lf_evidence_ledger_v1
 WHERE subject_type='IG_CANARY_OBSERVATION'
   AND capability_code='INDEPENDENT_ASSURANCE'
   AND verification_state='VERIFIED'
), canary_receipts AS (
 SELECT count(*)::integer AS verified_canary_receipts
 FROM programacion.provenance_receipts
 WHERE subject_type='IG_CANARY_OBSERVATION'
   AND payload->>'verification_status'='VERIFIED'
), provenance_source AS (
 SELECT count(*)::integer AS auth_cohorts
 FROM programacion.input_governance_cohort_types
 WHERE status='ACTIVE'
)
SELECT 'IG_M99_INDEPENDENT_ASSURANCE_ADMISSION_V1' AS schema_version,
 c.version AS reviewer_version,c.manifest_sha256 AS reviewer_manifest_sha256,
 r.verified_review_receipts,p.verified_canary_receipts,
 s.auth_cohorts,
 CASE WHEN c.version='2.0.1' AND r.verified_review_receipts>0
  AND p.verified_canary_receipts>0 AND s.auth_cohorts>0
 THEN 'EVIDENCE_EXISTS_REQUIRE_EXACT_RUN_BINDING'
 ELSE 'BLOCKED_MISSING_PROVIDER_BOUND_CANARY_REVIEW' END AS admission
FROM capability c CROSS JOIN ig_review r CROSS JOIN canary_receipts p
CROSS JOIN provenance_source s;
