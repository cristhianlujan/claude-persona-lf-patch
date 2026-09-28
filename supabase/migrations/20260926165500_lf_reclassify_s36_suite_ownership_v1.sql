-- Reclassify historical S36 suite ownership without copying or renaming suites.
-- EKB: S36-ASSURANCE-BOUNDARY-CONTAMINATION-001
-- Source-first candidate only. Historical suite codes/matrix refs remain lineage.

DO $pre$
DECLARE
  v_bad jsonb;
BEGIN
  WITH expected(suite_code, source_owner) AS (
    VALUES
      ('TS-S36-WP3-ASSET-RETIRE-V1','S29_ASSET_LIFECYCLE_GOVERNANCE'),
      ('TS-S36-WP3-PROFILE-TRANSITION-V1','S26_PROFILE_RUNTIME'),
      ('TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1','CARD_OPERATIONS'),
      ('TS-S36-S26-PR-MERGE-BASE-DRIFT-V1','S26')
  ), observed AS (
    SELECT e.suite_code,e.source_owner AS expected_source_owner,
           s.metadata->>'source_owner' AS observed_source_owner,
           s.metadata->>'assurance_owner' AS observed_assurance_owner
    FROM expected e
    LEFT JOIN public.lf_test_suites s USING (suite_code)
  )
  SELECT jsonb_agg(to_jsonb(o) ORDER BY suite_code)
    INTO v_bad
  FROM observed o
  WHERE observed_source_owner IS DISTINCT FROM expected_source_owner
     OR observed_assurance_owner IS DISTINCT FROM 'S36';

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'LF_S36_SUITE_OWNERSHIP_PRESTATE_MISMATCH:%',v_bad::text;
  END IF;
END
$pre$;

UPDATE public.lf_test_suites s
SET metadata =
    (s.metadata - 'assurance_owner')
    || jsonb_build_object(
         'legacy_assurance_owner','S36',
         'canonical_owner',s.metadata->>'source_owner',
         'ownership_model','DOMAIN_SOURCE_OWNER',
         's36_umbrella_status','RETIRED_AS_OWNER_PRESERVED_AS_LINEAGE'
       )
WHERE s.suite_code IN (
  'TS-S36-WP3-ASSET-RETIRE-V1',
  'TS-S36-WP3-PROFILE-TRANSITION-V1',
  'TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1',
  'TS-S36-S26-PR-MERGE-BASE-DRIFT-V1'
);

DO $post$
DECLARE
  v_bad jsonb;
BEGIN
  WITH expected(suite_code, canonical_owner) AS (
    VALUES
      ('TS-S36-WP3-ASSET-RETIRE-V1','S29_ASSET_LIFECYCLE_GOVERNANCE'),
      ('TS-S36-WP3-PROFILE-TRANSITION-V1','S26_PROFILE_RUNTIME'),
      ('TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1','CARD_OPERATIONS'),
      ('TS-S36-S26-PR-MERGE-BASE-DRIFT-V1','S26')
  )
  SELECT jsonb_agg(jsonb_build_object(
           'suite_code',e.suite_code,
           'canonical_owner',s.metadata->>'canonical_owner',
           'source_owner',s.metadata->>'source_owner',
           'legacy_assurance_owner',s.metadata->>'legacy_assurance_owner',
           'assurance_owner_present',s.metadata ? 'assurance_owner',
           'ownership_model',s.metadata->>'ownership_model'
         ) ORDER BY e.suite_code)
    INTO v_bad
  FROM expected e
  JOIN public.lf_test_suites s USING (suite_code)
  WHERE s.metadata->>'canonical_owner' IS DISTINCT FROM e.canonical_owner
     OR s.metadata->>'source_owner' IS DISTINCT FROM e.canonical_owner
     OR s.metadata->>'legacy_assurance_owner' IS DISTINCT FROM 'S36'
     OR s.metadata ? 'assurance_owner'
     OR s.metadata->>'ownership_model' IS DISTINCT FROM 'DOMAIN_SOURCE_OWNER'
     OR s.metadata->>'s36_umbrella_status' IS DISTINCT FROM 'RETIRED_AS_OWNER_PRESERVED_AS_LINEAGE';

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'LF_S36_SUITE_OWNERSHIP_POSTSTATE_MISMATCH:%',v_bad::text;
  END IF;
END
$post$;
