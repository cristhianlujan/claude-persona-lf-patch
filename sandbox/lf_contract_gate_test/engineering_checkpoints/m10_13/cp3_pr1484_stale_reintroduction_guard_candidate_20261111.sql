-- LF IG M10.13 CP3 | PR #1484 stale-precondition + anti-reintroduction candidate
-- No writes. This is a deterministic risk check, NOT a deployed CI guard.
-- The PR #1484 migration MD5 precondition is a literal inspected from its DRAFT HEAD.
WITH live_validator AS (
 SELECT md5(p.prosrc) AS live_md5,
        p.prosrc ILIKE '%fn_input_governance_bootstrap_classify_v2_cached_v2%' AS already_calls_legacy
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='programacion' AND p.proname='fn_input_governance_validate_v2'
), live_registry AS (
 SELECT EXISTS(
  SELECT 1 FROM public.lf_activos a
  CROSS JOIN LATERAL jsonb_array_elements_text(
    CASE WHEN jsonb_typeof(a.raw_payload->'members')='array'
      THEN a.raw_payload->'members' ELSE '[]'::jsonb END
  ) member_name
  WHERE a.codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET'
    AND member_name ILIKE '%fn_input_governance_bootstrap_classify_v2_cached_v2%'
 ) AS legacy_classifier_member_present
), cases(scenario,candidate_legacy_call,pinned_md5,expected_verdict) AS (
 VALUES
 ('ACTUAL_MAIN'::text,false,NULL::text,'PASS_NO_NEW_VALIDATOR_LEGACY_CALL'),
 ('PR1484_UNREBASED',true,'b4b186c5a832d1f83bcb6db45230c0d7','BLOCK_STALE_SOURCE_PIN'),
 ('PR1484_HYPOTHETICAL_REBASED',true,NULL::text,'BLOCK_LEGACY_REINTRODUCTION'),
 ('REGISTRY_RETIREMENT_CLAIM',false,NULL::text,'BLOCK_ASSET_MEMBERSHIP')
), actual AS (
 SELECT c.scenario,v.live_md5,v.already_calls_legacy,r.legacy_classifier_member_present,
 c.candidate_legacy_call,c.pinned_md5,
 CASE
  WHEN c.scenario='REGISTRY_RETIREMENT_CLAIM' AND r.legacy_classifier_member_present
    THEN 'BLOCK_ASSET_MEMBERSHIP'
  WHEN c.pinned_md5 IS NOT NULL AND c.pinned_md5<>v.live_md5
    THEN 'BLOCK_STALE_SOURCE_PIN'
  WHEN c.candidate_legacy_call
    THEN 'BLOCK_LEGACY_REINTRODUCTION'
  WHEN v.already_calls_legacy
    THEN 'BLOCK_ALREADY_REFERENCED'
  ELSE 'PASS_NO_NEW_VALIDATOR_LEGACY_CALL' END AS verdict,c.expected_verdict
 FROM cases c CROSS JOIN live_validator v CROSS JOIN live_registry r
)
SELECT *,verdict=expected_verdict AS test_pass,
 'CANDIDATE_TEST_NOT_DEPLOYED_ENFORCEMENT'::text AS proof_scope FROM actual
ORDER BY scenario;