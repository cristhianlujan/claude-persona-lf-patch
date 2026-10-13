-- IG M10.4 CP3 ADVERSARIAL CANDIDATE ONLY.
-- Expected: trusted independent admission FAIL_M104_FROZEN_LEGACY_MUTATION.
-- Never label ready-to-merge; never merge or apply this fixture.
COMMENT ON FUNCTION programacion.fn_input_actionable_remediation_summary_v1(bigint)
IS 'M104_NEGATIVE_CI_DRILL_MUST_BE_REJECTED';
