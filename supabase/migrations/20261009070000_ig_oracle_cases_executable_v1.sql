-- IG package 4 (slice 2): make 8 more CANDIDATO cases executable and activate them:
--   5 cases with oracle private.fn_lf_typed_evidence_payload_valid_v3 (payload already stored in the case)
--   1 positive + 2 negative cases with oracle programacion.fn_input_contract_clause_v1 (inputs completed here)
-- A generic read-only runner programacion.fn_input_oracle_case_run_v1(test_code) executes the stored input against the
-- real function and compares with expected_output. A case is activated only if it passes; the migration aborts otherwise.
-- Deliberately NOT included: the 10 *_SHA_READBACK cases (their claim_scope is BINDING_ONLY_NOT_CORRECTNESS and their
-- pinned hashes/revisions are point-in-time bindings, not regression expectations) and the 4 M7_10 E2E cases
-- (heavy fixtures already executed by the engineering runner). Inputs are Claude's test design.

CREATE OR REPLACE FUNCTION programacion.fn_input_oracle_case_run_v1(p_test_code text)
 RETURNS TABLE(test_code text, expected text, outcome text, error text, passed boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog'
AS $fn$
DECLARE
  v_case record; v_out jsonb; v_err text; v_ok boolean; v_live jsonb; v_path text[]; v_exp text; v_fam text;
BEGIN
  SELECT c.test_code AS tc, c.input_payload AS ip, c.expected_output AS eo, c.metadata->>'oracle' AS oracle INTO v_case
  FROM public.lf_test_suite_cases c WHERE c.test_code=p_test_code;
  IF v_case.tc IS NULL THEN RAISE EXCEPTION 'ORACLE_CASE_NOT_FOUND:%', p_test_code; END IF;

  IF v_case.oracle = 'private.fn_lf_typed_evidence_payload_valid_v3' THEN
    IF NOT (v_case.ip ? 'evidence_schema_version') THEN
      RETURN QUERY SELECT v_case.tc, v_case.eo->>'valid', 'NOT_EXECUTABLE'::text, 'INPUT_SCHEMA_MISSING'::text, false; RETURN;
    END IF;
    v_ok := private.fn_lf_typed_evidence_payload_valid_v3(v_case.ip->>'evidence_schema_version', v_case.ip);
    RETURN QUERY SELECT v_case.tc, v_case.eo->>'valid', v_ok::text, NULL::text, (v_ok::text = v_case.eo->>'valid');
    RETURN;

  ELSIF v_case.oracle = 'programacion.fn_input_contract_clause_v1' THEN
    IF NOT (v_case.ip ? 'contract_code' AND v_case.ip ? 'version_id' AND v_case.ip ? 'path') THEN
      RETURN QUERY SELECT v_case.tc, v_case.eo->>'outcome', 'NOT_EXECUTABLE'::text, 'INPUT_REF_MISSING'::text, false; RETURN;
    END IF;
    SELECT array_agg(x) INTO v_path FROM jsonb_array_elements_text(v_case.ip->'path') x;
    BEGIN
      v_out := programacion.fn_input_contract_clause_v1((v_case.ip->>'version_id')::bigint, v_case.ip->>'contract_code', v_path);
      v_err := NULL;
    EXCEPTION WHEN OTHERS THEN v_out := NULL; v_err := left(SQLERRM,160);
    END;
    v_exp := v_case.eo->>'outcome'; v_fam := v_case.eo->>'error_family';
    IF v_exp = 'FAIL_CLOSED' THEN
      RETURN QUERY SELECT v_case.tc, v_exp, CASE WHEN v_err IS NULL THEN 'RESOLVED' ELSE 'FAIL_CLOSED' END, v_err,
        (v_err IS NOT NULL AND v_fam IS NOT NULL AND v_err LIKE v_fam||'%');
    ELSE
      SELECT c.especificacion #> v_path INTO v_live FROM programacion.contratos c
       WHERE c.version_id=(v_case.ip->>'version_id')::bigint AND c.contrato_codigo=v_case.ip->>'contract_code'
         AND c.estado='defined' AND c.fail_closed ORDER BY c.id DESC LIMIT 1;
      RETURN QUERY SELECT v_case.tc, v_exp,
        CASE WHEN v_err IS NOT NULL THEN 'FAIL_CLOSED' ELSE 'MATCHES_VERSIONED_CONTRACT' END, v_err,
        (v_err IS NULL AND v_exp='MATCHES_VERSIONED_CONTRACT'
         AND nullif(v_out->>'contract_revision','') IS NOT NULL AND nullif(v_out->>'contract_sha256','') IS NOT NULL
         AND v_out->'value' IS NOT DISTINCT FROM v_live AND v_live IS NOT NULL);
    END IF;
    RETURN;
  END IF;
  RAISE EXCEPTION 'ORACLE_NOT_SUPPORTED:%', coalesce(v_case.oracle,'NULL');
END
$fn$;

DO $ig_oracle_inputs$
DECLARE v_bad int; v_n int; v_act int;
BEGIN
  SELECT count(*) INTO v_n FROM public.lf_test_suite_cases
   WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
     AND test_code IN ('M3_7_POSITIVE_CONTROL','M3_7_REJECT_READINESS','M3_7_REJECT_UNKNOWN_ROOT','M3_7_REJECT_UNKNOWN_FINAL_NORMALIZED','M3_7_REJECT_UNKNOWN_TRACE',
                       'M1_A9_CONTRACT_CLAUSE_PARITY_POSITIVE','M1_A9_CONTRACT_VERSION_UNPINNED_NEGATIVE','M1_A9_CONTRACT_CLAUSE_MISSING_NEGATIVE');
  IF v_n <> 8 THEN RAISE EXCEPTION 'IG_ORACLE_CASES_UNEXPECTED_COUNT:%', v_n; END IF;
  IF (SELECT count(*) FROM public.lf_test_suite_cases WHERE test_code LIKE 'M3_7_%' AND metadata->>'oracle'='private.fn_lf_typed_evidence_payload_valid_v3') <> 5
     OR (SELECT count(*) FROM public.lf_test_suite_cases WHERE test_code LIKE 'M1_A9_CONTRACT_%' AND metadata->>'oracle'='programacion.fn_input_contract_clause_v1') <> 3 THEN
    RAISE EXCEPTION 'IG_ORACLE_CASES_ORACLE_SHAPE_UNEXPECTED';
  END IF;

  -- complete the clause inputs (typed-evidence cases already carry their payload)
  UPDATE public.lf_test_suite_cases SET input_payload = input_payload || '{"version_id":19}'::jsonb
   WHERE test_code='M1_A9_CONTRACT_CLAUSE_PARITY_POSITIVE' AND NOT input_payload ? 'version_id';
  UPDATE public.lf_test_suite_cases SET input_payload = input_payload || '{"contract_code":"INPUT_READINESS_CONTRACT","version_id":999999,"path":["family_stage_requirements"]}'::jsonb
   WHERE test_code='M1_A9_CONTRACT_VERSION_UNPINNED_NEGATIVE' AND NOT input_payload ? 'version_id';
  UPDATE public.lf_test_suite_cases SET input_payload = input_payload || '{"contract_code":"INPUT_READINESS_CONTRACT","version_id":19,"path":["no_such_clause_zzz"]}'::jsonb
   WHERE test_code='M1_A9_CONTRACT_CLAUSE_MISSING_NEGATIVE' AND NOT input_payload ? 'version_id';

  SELECT count(*) FILTER (WHERE NOT x.passed) INTO v_bad
  FROM public.lf_test_suite_cases c, LATERAL programacion.fn_input_oracle_case_run_v1(c.test_code) x
  WHERE c.suite_code='INPUT_GOVERNANCE_REGRESSION'
    AND c.metadata->>'oracle' IN ('private.fn_lf_typed_evidence_payload_valid_v3','programacion.fn_input_contract_clause_v1');
  IF v_bad <> 0 THEN RAISE EXCEPTION 'IG_ORACLE_CASES_FAILED:%', v_bad; END IF;

  UPDATE public.lf_test_suite_cases
     SET status='ACTIVE',
         metadata = metadata || jsonb_build_object('activation',jsonb_build_object(
           'basis','ORACLE_CASE_EXECUTED_AND_MATCHED_EXPECTED','runner','programacion.fn_input_oracle_case_run_v1',
           'migration','supabase/migrations/20261009070000_ig_oracle_cases_executable_v1.sql'))
   WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND status='CANDIDATO'
     AND test_code IN ('M3_7_POSITIVE_CONTROL','M3_7_REJECT_READINESS','M3_7_REJECT_UNKNOWN_ROOT','M3_7_REJECT_UNKNOWN_FINAL_NORMALIZED','M3_7_REJECT_UNKNOWN_TRACE',
                       'M1_A9_CONTRACT_CLAUSE_PARITY_POSITIVE','M1_A9_CONTRACT_VERSION_UNPINNED_NEGATIVE','M1_A9_CONTRACT_CLAUSE_MISSING_NEGATIVE');
  SELECT count(*) INTO v_act FROM public.lf_test_suite_cases WHERE metadata->'activation'->>'runner'='programacion.fn_input_oracle_case_run_v1' AND status='ACTIVE';
  IF v_act <> 8 THEN RAISE EXCEPTION 'IG_ORACLE_CASES_READBACK_MISMATCH:%', v_act; END IF;
END
$ig_oracle_inputs$;
