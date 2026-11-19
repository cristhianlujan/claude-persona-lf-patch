-- LF IG 12:37 | Existing governed promotion request for B2B VALID-ONLY ...002.
-- Authorized scope: register actual observed PG17/PG18 fixture test CI,
-- re-score via deployed scorer, request MANUAL promotion only.
-- CI source exact: PR #4409, test-specific real postgres 17.6/18.7 markers
-- in GitHub Actions run 44539240378, attempt 2 (case PASS on both PG;
-- suite overall FAILURE from unrelated UI02 Docker/psql container crash).
-- This registry certifies only the named PG17/18 test-case, not global CI.
-- This test checks DB constraints + rollback, not full upload E2E or production.
-- PR #4409 Train 44539103035 applied PG17 config equivalence proof.
-- Product Director NEW RUN EXEC-PROFILE-GATE2-8B455BD3FABBC952FFD3CB43
-- completed 11/11 with CURRENT_CONTEXT_REVIEW, not independent model call.
-- Absolutely NO human decision, promotion apply, guard change, relink, delete.
BEGIN;
DO $lf_ig_b2b_002_real_behavior_manual_request$
DECLARE
  v_new CONSTANT text:='B2B-RULE-VALIDATION-VALID-ONLY-002';
  v_old CONSTANT text:='B2B-RULE-VALIDATION-VALID-ONLY-001';
  v_parent CONSTANT text:='EXEC-PROFILE-GATE2-8B455BD3FABBC952FFD3CB43';
  v_test CONSTANT text:='sandbox/lf_contract_gate_test/edge_function_operation/test_b2b_validation_valid_only_002_pgdual_v1.py';
  v_ci CONSTANT text:='actions://cristhianlujan/claude-persona-lf-patch/runs/44539240378';
  v_expected_sha CONSTANT text:='1adef350e722c2b8a596ee0c137a5e473e13feb5f2ad94d7d9888c71d0ec2734';
  v_old_id integer; v_new_id integer;
  v_old_before jsonb; v_old_after jsonb;
  v_old_cfg jsonb; v_new_cfg jsonb;
  v_sha text; v_score jsonb; v_req jsonb;
BEGIN
  IF current_setting('server_version_num')::integer/10000<>17
  THEN RAISE EXCEPTION 'LF_IG_B2B002_PG17_REQUIRED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE name='lf_b2b_valid_only_002_pgdual_config_contract_pg17_v1')
  THEN RAISE EXCEPTION 'LF_IG_B2B002_PREVIOUS_SOURCE_BOUND_PG17_TRAIN_MISSING'; END IF;
  IF (SELECT status FROM public.lf_operation_execution WHERE execution_id=v_parent) <> 'COMPLETED'
  OR (SELECT count(*) FROM public.lf_operation_execution_steps WHERE execution_id=v_parent) <> 11
  OR (SELECT count(*) FROM public.lf_operation_execution_steps WHERE execution_id=v_parent
      AND status='STEP_PASS_WITH_EVIDENCE')<>11
  OR NOT EXISTS(SELECT 1 FROM public.lf_profile_write_authority_v1 WHERE profile_code='PERFIL-PRODUCT-DIRECTOR-LF'
      AND operation_code='PROMOCION_REGLA_LF' AND status='ACTIVE')
  THEN RAISE EXCEPTION 'LF_IG_B2B002_PARENT_OR_ROLE_NOT_ATTESTED'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.lf_operation_execution_steps s70
    JOIN public.lf_operation_execution_steps s50 ON s50.execution_id=s70.execution_id AND s50.step_id='execute_profile'
    JOIN public.lf_operation_execution_steps s60 ON s60.execution_id=s70.execution_id AND s60.step_id='output_validate'
    JOIN public.lf_operation_execution_steps s40 ON s40.execution_id=s70.execution_id AND s40.step_id='input_validate'
    WHERE s70.execution_id=v_parent AND s70.step_id='semantic_judge'
    AND s70.status='STEP_PASS_WITH_EVIDENCE' AND s50.status='STEP_PASS_WITH_EVIDENCE'
    AND s60.status='STEP_PASS_WITH_EVIDENCE' AND s40.status='STEP_PASS_WITH_EVIDENCE'
    AND s70.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_REVIEWED_CURRENT_CONTEXT'
    AND s70.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW'
    AND s70.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'=s50.evidence_payload->>'raw_output_sha256'
    AND s70.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'=s60.evidence_payload->>'raw_output_sha256'
    AND s40.evidence_payload->>'scope_authority_packet_sha256'=
      'sha256:'||(s70.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}')
    AND s70.evidence_payload#>>'{semantic_judge_result,judge_v3_evidence,producer_independence_proven}'='false'
    AND s70.evidence_payload#>>'{semantic_judge_result,judge_v3_evidence,model_call_count}'='0'
    AND s70.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}'='[]'::jsonb
    AND EXISTS(SELECT 1 FROM jsonb_array_elements(s50.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}') x
      WHERE x->>'source_ref'='supabase://lf_ops.reglas/'||v_new)
  ) THEN RAISE EXCEPTION 'LF_IG_B2B002_CURRENT_CONTEXT_STEP70_HASH_OR_SOURCE_MISMATCH'; END IF;
  SELECT id,to_jsonb(r),valor_config INTO STRICT v_old_id,v_old_before,v_old_cfg
    FROM lf_ops.reglas r WHERE codigo=v_old AND estado='VIGENTE' AND pendiente_decision=false;
  SELECT id,valor_config INTO STRICT v_new_id,v_new_cfg
    FROM lf_ops.reglas WHERE codigo=v_new AND estado='CANDIDATO' AND pendiente_decision=true;
  v_sha:=encode(extensions.digest(convert_to(v_old_cfg::text,'UTF8'),'sha256'),'hex');
  IF v_sha<>v_expected_sha
  OR encode(extensions.digest(convert_to(
     (v_new_cfg-'lf_rule_scope'-'lf_screen_ids'-'lf_applicability'-'lf_replaces_rule_code'-'lf_promotion_authorized')::text,'UTF8'),'sha256'),'hex')<>v_expected_sha
  OR (SELECT array_agg(pantalla_id ORDER BY pantalla_id) FROM lf_ops.reglas_pantallas WHERE regla_id=v_old_id)
     IS DISTINCT FROM ARRAY[44,66,67]::integer[]
  OR (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE regla_id=v_new_id)<>0
  OR (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_old)<>1
  OR EXISTS(SELECT 1 FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_new)
  OR EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 WHERE rule_code=v_new)
  THEN RAISE EXCEPTION 'LF_IG_B2B002_BASELINE_CONFIG_OR_DEPENDENCY_DRIFT'; END IF;

  -- Exact real GitHub CI run attempt 2 contains PG17.6 and PG18.7 PASS
  -- for this named test. Global suite failure is recorded above and in PR.
  -- The scorer considers test-specific PASS; DO NOT claim global CI GREEN.
  INSERT INTO lf_ops.regla_behavior_tests(regla_codigo,test_ref,ci_run,pg17,pg18,source_sha)
    VALUES(v_new,v_test,v_ci,'PASS','PASS',v_expected_sha);

  SELECT public.lf_rule_promotion_score_v1(v_parent,v_new) INTO v_score;
  IF v_score->>'A'<>'40' OR v_score->>'B'<>'30'
    OR v_score->>'C'<>'0' OR v_score->>'D'<>'10'
    OR v_score->>'score'<>'80' OR v_score->>'decision'<>'MANUAL'
    OR v_score->>'hard_block'<>'true'
  THEN RAISE EXCEPTION 'LF_IG_B2B002_EXPECTED_MANUAL_SCORE_NOT_REACHED:%',v_score; END IF;

  v_req:=public.lf_rule_promotion_request_v1(v_parent,v_new,
    'LF IG piloto B2B, Owner 2026-11-19 12:37: PG17/18 source bound + Step70 PASS_REVIEWED_CURRENT_CONTEXT; score 80 MANUAL; únicamente petición para decisión humana del dueño, sin apply ni migración ni producción');
  IF v_req->>'status'<>'PENDING_HUMAN_APPROVAL'
    OR v_req->>'score_decision'<>'MANUAL'
    OR (v_req->>'snapshot_sha256') !~ '^[0-9a-f]{64}$'
    OR nullif(v_req->>'promotion_id','') IS NULL
  THEN RAISE EXCEPTION 'LF_IG_B2B002_REQUEST_NOT_PENDING_HUMAN:%',v_req; END IF;

  IF NOT EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 p
    WHERE p.promotion_id=v_req->>'promotion_id' AND p.rule_code=v_new
    AND p.request_execution_id=v_parent AND p.status='PENDING'
    AND p.request_snapshot_sha256=v_req->>'snapshot_sha256'
    AND p.decided_by IS NULL AND p.decided_at IS NULL AND p.applied_at IS NULL)
  OR (SELECT count(*) FROM lf_ops.regla_behavior_tests
      WHERE regla_codigo=v_new AND test_ref=v_test AND ci_run=v_ci
      AND pg17='PASS' AND pg18='PASS' AND source_sha=v_expected_sha)<>1
  OR (SELECT estado FROM lf_ops.reglas WHERE codigo=v_new)<>'CANDIDATO'
  OR (SELECT pendiente_decision FROM lf_ops.reglas WHERE codigo=v_new) IS DISTINCT FROM true
  OR (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE regla_id=v_new_id)<>0
  OR (SELECT count(*) FROM lf_ops.reglas)<>587
  THEN RAISE EXCEPTION 'LF_IG_B2B002_REQUEST_OR_TEST_READBACK_FAILED'; END IF;

  SELECT to_jsonb(r) INTO STRICT v_old_after FROM lf_ops.reglas r WHERE id=v_old_id;
  IF v_old_after IS DISTINCT FROM v_old_before
    OR (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE regla_id=v_old_id)<>3
    OR (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_old)<>1
  THEN RAISE EXCEPTION 'LF_IG_B2B002_ACTIVE_RULE_TOUCHED'; END IF;
  RAISE NOTICE 'LF_IG_B2B002_MANUAL_PENDING_PASS:score=% A=% B=% C=% D=% promotion_id=% request_snapshot_sha256=% ci_run=% old=VIGENTE new=CANDIDATO no_decision=true',
    v_score->>'score',v_score->>'A',v_score->>'B',v_score->>'C',v_score->>'D',
    v_req->>'promotion_id',v_req->>'snapshot_sha256',v_ci;
END;
$lf_ig_b2b_002_real_behavior_manual_request$;
COMMIT;
