\set ON_ERROR_STOP on
-- Test the actual candidate rebind DDL compiled in this disposable PG instance.
-- Positive (4 families, 3-per-call, separate final proposal phase).
INSERT INTO programacion.input_readiness_runs
 (id,version_id,status,pantalla_id,supersedes_run_id,family_count,curator_identity,scope)
VALUES
 (800,19,'COMPLETED',501,null,4,'INPUT_CURATOR:SQL:ig-governed-dispatch-v1:parent-fixture',
 '{"validator_semantic_mode":"SOURCE_INTEGRITY_ONLY","validator_semantic_comparison_families":[],"semantic_promotion_authorized":false}'),
 (900,19,'CURATING',501,800,4,'INPUT_CURATOR:SQL:ig-governed-dispatch-v1:curator-fixture',
 '{"validator_semantic_mode":"SOURCE_INTEGRITY_ONLY","validator_semantic_comparison_families":[],"semantic_promotion_authorized":false}'),
 (910,19,'CURATING',501,800,1,'INPUT_CURATOR:SQL:ig-governed-dispatch-v1:curator-fixture',
 '{"validator_semantic_mode":"SOURCE_INTEGRITY_ONLY","validator_semantic_comparison_families":[],"semantic_promotion_authorized":false}'),
 (920,19,'CURATING',501,800,1,'INPUT_CURATOR:SQL:ig-governed-dispatch-v1:curator-fixture',
 '{"validator_semantic_mode":"SELECTED_SEMANTIC_COMPARISON","validator_semantic_comparison_families":["F_A"],"semantic_promotion_authorized":false}'),
 (930,19,'CURATING',501,800,1,'INPUT_CURATOR:SQL:ig-governed-dispatch-v1:curator-fixture','{}'::jsonb);
INSERT INTO programacion.input_family_assessments
 (run_id,family_code,validator_outcome,curator_evidence,curator_sha256,semantic_depth_sha256,validator_evidence)
SELECT 800,x.family_code,'PASS','{"execution_id":"fixture-curator-parent"}'::jsonb,
 'h-parent','d-parent','{"assertions":[]}'::jsonb
FROM (VALUES ('F_A'),('F_B'),('F_C'),('F_D')) x(family_code);
INSERT INTO programacion.input_family_assessments
 (run_id,family_code,validator_outcome,curator_evidence,curator_sha256,semantic_depth_sha256,validator_evidence)
SELECT r.run_id,r.family_code,'PENDING','{"execution_id":"fixture-curator"}'::jsonb,'h','d','{}'::jsonb
FROM (VALUES (900,'F_A'),(900,'F_B'),(900,'F_C'),(900,'F_D'),
             (910,'F_B'),(920,'F_A'),(930,'F_A')) r(run_id,family_code);
INSERT INTO programacion.fixture_expected(run_id,family_code,expected)
SELECT x.run_id,x.family_code,case when x.run_id=910 then 'BAD' else 'OK' end
FROM (VALUES (900,'F_A'),(900,'F_B'),(900,'F_C'),(900,'F_D'),
             (910,'F_B'),(920,'F_A'),(930,'F_A')) x(run_id,family_code);

DO $test$
DECLARE v jsonb; v_n int;
DECLARE v_id constant text:='INPUT_VALIDATOR:SQL:ig-governed-dispatch-v1:test-valid-0001';
BEGIN
 v:=programacion.fn_input_governance_validator_rebind_v1(900,v_id);
 IF v->>'status'<>'VALIDATOR_CONTINUE_REQUIRED'
    OR (v->>'validator_pass_count')::int<>3
    OR (v->>'pending_count')::int<>1 THEN
   raise exception 'POSITIVE_CHUNK_1_FAIL:%',v; END IF;
 IF (select status from programacion.input_readiness_runs where id=900)<>'VALIDATING' then
   raise exception 'PREMATURE_FINALIZE_CHUNK_1'; END IF;
 v:=programacion.fn_input_governance_validator_rebind_v1(900,v_id);
 IF v->>'status'<>'VALIDATOR_CONTINUE_REQUIRED'
    OR v->>'next_phase'<>'PROPOSAL_VALIDATION'
    OR (v->>'validator_pass_count')::int<>4
    OR (select count(*) from programacion.fixture_proposal_calls where run_id=900)<>0
 THEN raise exception 'POSITIVE_CHUNK_2_PHASE_FAIL:%',v; END IF;
 v:=programacion.fn_input_governance_validator_rebind_v1(900,v_id);
 IF v->>'status'<>'COMPLETED'
    OR (select status from programacion.input_readiness_runs where id=900)<>'COMPLETED'
    OR (select count(*) from programacion.fixture_proposal_calls where run_id=900)<>1
 THEN raise exception 'POSITIVE_TERMINAL_FAIL:%',v; END IF;
 RAISE NOTICE 'TEST_PASS:BOUND_CHUNKS_AND_ORDERED_PROPOSAL';

 v:=programacion.fn_input_governance_validator_rebind_v1(910,v_id);
 IF v->>'status'<>'VALIDATION_FAILED'
    OR (select validator_outcome from programacion.input_family_assessments where run_id=910)<>'FAIL'
    OR (select status from programacion.input_readiness_runs where id=910)<>'VALIDATING'
    OR (select count(*) from programacion.fixture_proposal_calls where run_id=910)<>0
 THEN raise exception 'NEGATIVE_FALSE_ASSERTION_NOT_BLOCKED:%',v; END IF;
 RAISE NOTICE 'TEST_PASS:FALSE_ASSERTION_FAILS';

 v:=programacion.fn_input_governance_validator_rebind_v1(920,v_id);
 IF v->>'status'<>'VALIDATION_BLOCKED'
    OR (select validator_outcome from programacion.input_family_assessments where run_id=920)<>'BLOCKED'
    OR (select status from programacion.input_readiness_runs where id=920)<>'VALIDATING'
    OR (select count(*) from programacion.fixture_proposal_calls where run_id=920)<>0
 THEN raise exception 'NEGATIVE_ORACLE_NOT_BLOCKED:%',v; END IF;
 RAISE NOTICE 'TEST_PASS:SELECTED_SEMANTIC_ORACLE_BLOCKED';

 BEGIN
   v:=programacion.fn_input_governance_validator_rebind_v1(930,v_id);
   raise exception 'NEGATIVE_UNDECLARED_SCOPE_WRONGLY_ADMITTED';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM not like 'VALIDATOR_SEMANTIC_SCOPE_UNDECLARED:%' THEN
     raise exception 'WRONG_SCOPE_ERROR:%',SQLERRM; END IF;
 END;
 IF (select status from programacion.input_readiness_runs where id=930)<>'CURATING'
 THEN raise exception 'UNDECLARED_SCOPE_MUTATED_RUN'; END IF;
 RAISE NOTICE 'TEST_PASS:UNDECLARED_SEMANTIC_SCOPE_FAIL_CLOSED';
END $test$;
