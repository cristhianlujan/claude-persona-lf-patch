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
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'semantic_revision','R21_OWNER_FIRST_POST_CANDIDATE_ASSURANCE_V3',
      'terminal_assurance_preserved',true
    ),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-S30-R21-POST-CANDIDATE-ASSURANCE-POLICY-20260915-001'
WHERE suite_code='TS-STRATEGY-OP-EXECUTE-V1' AND test_code='E12';

DO $verify$
DECLARE
  c public.lf_operation_contracts%rowtype;
  e12 public.lf_test_suite_cases%rowtype;
  route jsonb;
  canary jsonb;
BEGIN
  SELECT * INTO c FROM public.lf_operation_contracts
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';
  IF NOT FOUND THEN RAISE EXCEPTION 'S30_R21_V3_ACTIVE_EXECUTOR_CONTRACT_MISSING'; END IF;
  IF coalesce((c.allowed->>'strategy_qualification_required_for_new_execution')::boolean,true) IS NOT FALSE THEN
    RAISE EXCEPTION 'S30_R21_V3_CONTRACT_PREQUAL_FLAG_NOT_FALSE';
  END IF;
  IF coalesce((c.allowed->>'strategy_owner_execution_pre_assurance_permission_gate_allowed')::boolean,true) IS NOT FALSE THEN
    RAISE EXCEPTION 'S30_R21_V3_PERMISSION_GATE_FLAG_NOT_FALSE';
  END IF;
  IF c.allowed->>'strategy_independent_assurance_timing' IS DISTINCT FROM 'POST_CANDIDATE_TERMINAL_EFFECT' THEN
    RAISE EXCEPTION 'S30_R21_V3_ASSURANCE_TIMING_MISMATCH';
  END IF;
  IF coalesce((c.allowed->>'strategy_terminal_effect_requires_current_qualification')::boolean,false) IS NOT TRUE
     OR coalesce((c.allowed->>'executor_terminal_effect_requires_current_qualification')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'S30_R21_V3_TERMINAL_QUALIFICATION_FLAGS_MISSING';
  END IF;
  IF c.blocked @> jsonb_build_array('NEW_EXECUTION_WITHOUT_CURRENT_STRATEGY_QUALIFICATION') THEN
    RAISE EXCEPTION 'S30_R21_V3_LEGACY_BLOCK_REMAINS';
  END IF;

  SELECT * INTO e12 FROM public.lf_test_suite_cases
  WHERE suite_code='TS-STRATEGY-OP-EXECUTE-V1' AND test_code='E12';
  IF NOT FOUND OR e12.input_payload->>'key'<>'strategy_qualification_required_for_new_execution'
     OR coalesce((e12.input_payload->>'expected')::boolean,true) IS NOT FALSE THEN
    RAISE EXCEPTION 'S30_R21_V3_E12_NOT_ALIGNED';
  END IF;

  route:=public.lf_router_resolve_v1('ejecutar estrategia','LF_OPERATING_CONSTITUTION_POLICY_AUTONOMOUS_OPERATIONS_20260906','STRATEGY_EXECUTION','STRATEGY','ROUTER');
  IF route->>'status'<>'READY_TO_EXECUTE' OR route->>'operation_code'<>'EJECUCION_ESTRATEGIA_LF' THEN
    RAISE EXCEPTION 'S30_R21_V3_ROUTER_NOT_READY:%',route;
  END IF;

  canary:=public.lf_canary_strategy_owner_first_assurance_boundary_v2(35);
  IF coalesce((canary->>'passed')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'S30_R21_V3_RUNTIME_CANARY_FAIL:%',canary;
  END IF;
END
$verify$;
