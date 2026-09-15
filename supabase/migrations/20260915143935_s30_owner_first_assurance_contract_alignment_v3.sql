-- S30-R21 v3: semantic contract/test alignment with the already-enforced owner-first runtime.
-- Independent assurance is post-candidate. Terminal close still requires exact current Strategy + executor qualification.

UPDATE public.lf_operation_contracts
SET allowed=(allowed - 'strategy_qualification_required_for_new_execution') || jsonb_build_object(
      'strategy_qualification_required_for_new_execution',false,
      'strategy_owner_execution_pre_assurance_permission_gate_allowed',false,
      'strategy_independent_assurance_timing','POST_CANDIDATE_TERMINAL_EFFECT',
      'strategy_terminal_effect_requires_current_qualification',true,
      'executor_terminal_effect_requires_current_qualification',true
    ),
    blocked=(SELECT coalesce(jsonb_agg(v),'[]'::jsonb)
             FROM jsonb_array_elements(blocked) v
             WHERE v <> '"NEW_EXECUTION_WITHOUT_CURRENT_STRATEGY_QUALIFICATION"'::jsonb),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-S30-R21-POST-CANDIDATE-ASSURANCE-POLICY-20260915-001'
WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_test_suite_cases
SET title='Owner execution does not require prior Strategy qualification',
    input_payload=jsonb_build_object(
      'probe_code','OP_CONTRACT_BOOL',
      'key','strategy_qualification_required_for_new_execution',
      'expected',false
    ),
    expected_output='{"passed":true}'::jsonb,
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'semantic_revision','R21_OWNER_FIRST_POST_CANDIDATE_ASSURANCE_V3',
      'assurance_timing','POST_CANDIDATE_TERMINAL_EFFECT'
    ),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-S30-R21-POST-CANDIDATE-ASSURANCE-POLICY-20260915-001'
WHERE suite_code='TS-STRATEGY-OP-EXECUTE-V1' AND test_code='E12';

DO $verify$
DECLARE
  prequal boolean;
  timing text;
  terminal_strategy boolean;
  terminal_executor boolean;
  blocked_has_old boolean;
BEGIN
  SELECT
    (allowed->>'strategy_qualification_required_for_new_execution')::boolean,
    allowed->>'strategy_independent_assurance_timing',
    (allowed->>'strategy_terminal_effect_requires_current_qualification')::boolean,
    (allowed->>'executor_terminal_effect_requires_current_qualification')::boolean,
    blocked ? 'NEW_EXECUTION_WITHOUT_CURRENT_STRATEGY_QUALIFICATION'
  INTO prequal,timing,terminal_strategy,terminal_executor,blocked_has_old
  FROM public.lf_operation_contracts
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';

  IF prequal IS DISTINCT FROM false THEN RAISE EXCEPTION 'S30_R21_V3_PREQUAL_CONTRACT_NOT_FALSE'; END IF;
  IF timing IS DISTINCT FROM 'POST_CANDIDATE_TERMINAL_EFFECT' THEN RAISE EXCEPTION 'S30_R21_V3_ASSURANCE_TIMING_MISMATCH:%',timing; END IF;
  IF terminal_strategy IS DISTINCT FROM true OR terminal_executor IS DISTINCT FROM true THEN RAISE EXCEPTION 'S30_R21_V3_TERMINAL_QUAL_CONTRACT_MISSING'; END IF;
  IF blocked_has_old IS TRUE THEN RAISE EXCEPTION 'S30_R21_V3_STALE_BLOCKED_TOKEN_REMAINS'; END IF;
END
$verify$;
