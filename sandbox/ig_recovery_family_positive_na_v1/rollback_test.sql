-- Candidate-only PG test. All schema/function changes are reverted.
-- psql -v ON_ERROR_STOP=1 -f sandbox/ig_recovery_family_positive_na_v1/rollback_test.sql
\set ON_ERROR_STOP on
BEGIN;
\ir ../../supabase/migrations/20261117073400_lf_ig_recovery_family_positive_na_v1.sql
DO $test$
DECLARE
  x record;
  f text;
  r jsonb;
  cached jsonb;
  graph jsonb;
  rev bigint;
  ref_found boolean;
  rows_checked integer:=0;
BEGIN
  SELECT max(version_id) INTO rev FROM programacion.contratos
  WHERE contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY' AND estado='defined';
  IF rev IS NULL THEN RAISE EXCEPTION 'IG_TEST_NO_POLICY_REVISION'; END IF;
  FOR x IN SELECT * FROM (VALUES (52),(56),(53)) AS v(pantalla_id) LOOP
    graph := programacion.fn_input_screen_canonical_graph(x.pantalla_id,rev);
    FOREACH f IN ARRAY ARRAY['PERMISSIONS','SESSION','FEATURE_FLAGS','I18N_FORMATS'] LOOP
      r := programacion.fn_input_governance_bootstrap_classify_v2(x.pantalla_id,f,rev);
      cached := programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(x.pantalla_id,f,rev,graph);
      IF (r->>'applicability') IS DISTINCT FROM (cached->>'applicability') THEN
        RAISE EXCEPTION 'IG_TEST_CACHED_MISMATCH:%:%',x.pantalla_id,f;
      END IF;
      IF f IN ('PERMISSIONS','SESSION') AND r->>'applicability'<>'APPLICABLE' THEN
        RAISE EXCEPTION 'IG_TEST_RECOVERY_OMISSION:%:%',x.pantalla_id,f;
      END IF;
      IF f IN ('FEATURE_FLAGS','I18N_FORMATS') THEN
        IF r->>'applicability'<>'NOT_APPLICABLE' THEN
          RAISE EXCEPTION 'IG_TEST_EXPLICIT_NA_LOST:%:%',x.pantalla_id,f;
        END IF;
        SELECT EXISTS(
          SELECT 1 FROM jsonb_array_elements(r->'source_refs') z
          WHERE z->>'kind'='RULE'
            AND z->>'codigo'='B2B-RULE-INPUT-APPLICABILITY-001'
        ) INTO ref_found;
        IF NOT ref_found THEN RAISE EXCEPTION 'IG_TEST_NA_RULE_SOURCE_MISSING:%:%',x.pantalla_id,f; END IF;
      END IF;
      rows_checked:=rows_checked+1;
    END LOOP;
  END LOOP;
  IF rows_checked<>12 THEN RAISE EXCEPTION 'IG_TEST_WRONG_COUNT'; END IF;
  RAISE NOTICE 'IG_RECOVERY_SELECT_DIRECT_AND_CACHED_12_PASS';
END;
$test$;
ROLLBACK;
