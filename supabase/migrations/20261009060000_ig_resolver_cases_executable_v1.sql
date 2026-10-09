-- IG package 4 (first slice): make the 64 fn_input_resolve_source_ref cases executable and activate them.
-- The 64 CANDIDATO cases declared only source_kind + polarity/scenario, with no concrete reference, so none could run.
-- This migration (1) stores a concrete, reproducible input in each case (ref, pantalla_id, version_id),
-- (2) adds a read-only runner programacion.fn_input_resolver_case_run_v1(test_code) that executes the stored input
-- against the real resolver and compares the outcome with expected_output.resolver_outcome,
-- (3) activates a case only if it passes; the whole migration aborts if any of the 64 does not.
-- No other case, suite or run record is touched. The inputs are Claude's test design (owner delegated criteria).
--   positive  -> real ids/codes taken from live catalogs; negative -> absent ids/codes or a malformed ref
--   cardinality negative -> the same id twice (expected count mismatch); empty positive -> []

CREATE OR REPLACE FUNCTION programacion.fn_input_resolver_case_run_v1(p_test_code text)
 RETURNS TABLE(test_code text, expected text, outcome text, error text, passed boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog'
AS $fn$
DECLARE
  v_case record; v_out jsonb; v_err text; v_exp text;
BEGIN
  SELECT c.test_code AS tc, c.input_payload AS ip, c.expected_output->>'resolver_outcome' AS exp INTO v_case
  FROM public.lf_test_suite_cases c
  WHERE c.test_code=p_test_code AND c.metadata->>'oracle'='programacion.fn_input_resolve_source_ref';
  IF v_case.tc IS NULL THEN RAISE EXCEPTION 'RESOLVER_CASE_NOT_FOUND:%', p_test_code; END IF;
  IF NOT (v_case.ip ? 'ref' AND v_case.ip ? 'pantalla_id' AND v_case.ip ? 'version_id') THEN
    RETURN QUERY SELECT v_case.tc, v_case.exp, 'NOT_EXECUTABLE'::text, 'INPUT_REF_MISSING'::text, false; RETURN;
  END IF;
  BEGIN
    v_out := programacion.fn_input_resolve_source_ref(v_case.ip->'ref', (v_case.ip->>'pantalla_id')::integer, (v_case.ip->>'version_id')::bigint);
    v_err := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_out := NULL; v_err := left(SQLERRM,120);
  END;
  v_exp := v_case.exp;
  RETURN QUERY SELECT v_case.tc, v_exp,
    CASE WHEN v_err IS NOT NULL THEN 'REJECTS'
         WHEN v_out->'observed' = '[]'::jsonb THEN 'RESOLVES_EMPTY'
         WHEN v_out->'observed' IS NULL OR v_out->'observed' = 'null'::jsonb THEN 'UNEXPECTED_EMPTY_OBSERVED'
         ELSE 'RESOLVES' END,
    v_err,
    CASE WHEN v_err IS NOT NULL THEN v_exp='REJECTS'
         WHEN v_out->'observed' = '[]'::jsonb THEN v_exp='RESOLVES_EMPTY'
         WHEN v_out->'observed' IS NULL OR v_out->'observed' = 'null'::jsonb THEN false
         ELSE v_exp='RESOLVES' END;
END
$fn$;

DO $ig_resolver_inputs$
DECLARE
  r record; v_ref jsonb; v_pant int; v_key text; v_list jsonb; v_neg boolean; v_kind text; v_sc text;
  v_bad int; v_n int; v_act int;
  c_ver constant bigint := 19;
  ids jsonb := '{"ERROR_SET":[1,2],"MESSAGE_SET":[1,2],"ROUTE_SET":[1,2],"SECURITY_POLICY_SET":[1,2],"TRANSITION_SET":[1,2]}';
  codes jsonb := '{"EKB_ERROR_SET":["AB-PROFILE-QUALITY-GATE-001","ARC-001"],"EKB_PREVENTION_SET":["KB-PROD-R001","PR-AUD-021"],"EKB_DECISION_SET":["ADR-CANDIDATE-DETERMINISM-TAXONOMY-001","ADR-CLIENT-HOME-LIFECYCLE-001"]}';
BEGIN
  SELECT count(*) INTO v_n FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND metadata->>'oracle'='programacion.fn_input_resolve_source_ref';
  IF v_n <> 64 THEN RAISE EXCEPTION 'IG_RESOLVER_CASES_UNEXPECTED_COUNT:%', v_n; END IF;
  IF EXISTS (SELECT 1 FROM public.lf_test_suite_cases WHERE metadata->>'oracle'='programacion.fn_input_resolve_source_ref' AND input_payload ? 'ref') THEN RETURN; END IF;

  FOR r IN SELECT test_code, input_payload FROM public.lf_test_suite_cases
           WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND metadata->>'oracle'='programacion.fn_input_resolve_source_ref' LOOP
    v_kind := r.input_payload->>'source_kind';
    v_sc := coalesce(r.input_payload->>'scenario', r.input_payload->>'polarity');
    v_neg := v_sc IN ('NEGATIVE','CARDINALITY_NEGATIVE','MISSING_REF_NEGATIVE');
    v_pant := 1;
    IF ids ? v_kind OR codes ? v_kind THEN
      v_key := CASE WHEN ids ? v_kind THEN 'ids' WHEN v_kind='EKB_DECISION_SET' THEN 'adrs' ELSE 'codes' END;
      v_list := CASE WHEN ids ? v_kind THEN ids->v_kind ELSE codes->v_kind END;
      v_ref := CASE v_sc
        WHEN 'POSITIVE' THEN jsonb_build_object('kind',v_kind,v_key,v_list)
        WHEN 'NONEMPTY_POSITIVE' THEN jsonb_build_object('kind',v_kind,v_key,v_list)
        WHEN 'EMPTY_POSITIVE' THEN jsonb_build_object('kind',v_kind,v_key,'[]'::jsonb)
        WHEN 'NEGATIVE' THEN jsonb_build_object('kind',v_kind)
        WHEN 'CARDINALITY_NEGATIVE' THEN jsonb_build_object('kind',v_kind,v_key,jsonb_build_array(v_list->0,v_list->0))
        WHEN 'MISSING_REF_NEGATIVE' THEN jsonb_build_object('kind',v_kind,v_key,
             CASE WHEN v_key='ids' THEN jsonb_build_array(v_list->0,999999999) ELSE jsonb_build_array(v_list->0,'NO_SUCH_CODE_ZZZ') END)
      END;
    ELSIF v_kind='RULE' THEN
      v_ref := jsonb_build_object('kind','RULE','codigo',CASE WHEN v_neg THEN 'NO_SUCH_RULE_ZZZ' ELSE 'REG_ONB_001' END);
    ELSIF v_kind='CONTRACT' THEN
      v_ref := jsonb_build_object('kind','CONTRACT','codigo',CASE WHEN v_neg THEN 'NO_SUCH_CONTRACT_ZZZ' ELSE 'INPUT_FAMILY_POLICY_REGISTRY' END);
    ELSIF v_kind='CAPABILITY_ABSENCE' THEN
      v_ref := jsonb_build_object('kind','CAPABILITY_ABSENCE','capability',CASE WHEN v_neg THEN 'NO_SUCH_CAPABILITY' ELSE 'I18N_FORMATS' END);
    ELSIF v_kind='SCREEN_CANONICAL_GRAPH' THEN
      v_ref := jsonb_build_object('kind',v_kind,'pantalla_id',CASE WHEN v_neg THEN 2 ELSE 1 END);
    ELSE
      v_ref := jsonb_build_object('kind',v_kind);
      IF v_neg THEN v_pant := 999999; ELSIF v_kind='SCREEN_STATE_SET' THEN v_pant := 45; END IF;
    END IF;
    UPDATE public.lf_test_suite_cases
       SET input_payload = input_payload || jsonb_build_object('ref',v_ref,'pantalla_id',v_pant,'version_id',c_ver)
     WHERE test_code = r.test_code;
  END LOOP;

  SELECT count(*) FILTER (WHERE NOT x.passed) INTO v_bad
  FROM public.lf_test_suite_cases c, LATERAL programacion.fn_input_resolver_case_run_v1(c.test_code) x
  WHERE c.suite_code='INPUT_GOVERNANCE_REGRESSION' AND c.metadata->>'oracle'='programacion.fn_input_resolve_source_ref';
  IF v_bad <> 0 THEN RAISE EXCEPTION 'IG_RESOLVER_CASES_FAILED:%', v_bad; END IF;

  UPDATE public.lf_test_suite_cases
     SET status='ACTIVE',
         metadata = metadata || jsonb_build_object('activation',jsonb_build_object(
           'basis','RESOLVER_CASE_EXECUTED_AND_MATCHED_EXPECTED','runner','programacion.fn_input_resolver_case_run_v1',
           'migration','supabase/migrations/20261009060000_ig_resolver_cases_executable_v1.sql','claim_scope','STRUCTURAL_ONLY_NOT_SEMANTIC_OR_READINESS'))
   WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND metadata->>'oracle'='programacion.fn_input_resolve_source_ref' AND status='CANDIDATO';

  SELECT count(*) INTO v_act FROM public.lf_test_suite_cases
   WHERE metadata->>'oracle'='programacion.fn_input_resolve_source_ref' AND status='ACTIVE' AND input_payload ? 'ref';
  IF v_act <> 64 THEN RAISE EXCEPTION 'IG_RESOLVER_CASES_READBACK_MISMATCH:%', v_act; END IF;
END
$ig_resolver_inputs$;
