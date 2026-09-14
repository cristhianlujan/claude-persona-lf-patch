-- S30 transversal remediation: restore previously validated Strategy Executor sandbox activation.
-- Safety ceiling: control-state only; no business effects, scheduler, orchestrator or production activation.

DO $pre$
DECLARE
  v_exec public.lf_operation_execution%rowtype;
  c integer;
BEGIN
  SELECT * INTO v_exec FROM public.lf_operation_execution
  WHERE execution_id='EXEC-S30-REMEDIATION-ACTIVATE-STRATEGY-EXECUTOR-20260914-001';
  IF NOT FOUND
     OR v_exec.operation_code<>'VULNERABILITY_COVERAGE_REPAIR_LF'
     OR v_exec.status<>'IN_PROGRESS'
     OR v_exec.target_type<>'OPERATION'
     OR v_exec.target_code<>'EJECUCION_ESTRATEGIA_LF'
     OR coalesce((v_exec.manifest->>'governance_bootstrap')::boolean,false) IS NOT TRUE
     OR v_exec.manifest->>'bootstrap_operation_code'<>'EJECUCION_ESTRATEGIA_LF'
     OR v_exec.manifest->>'bootstrap_status_ceiling'<>'SANDBOX_ACTIVE' THEN
    RAISE EXCEPTION 'S30_REMEDIATION_EXECUTION_BINDING_INVALID';
  END IF;

  SELECT count(*) INTO c FROM public.lf_operation_registry
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
    AND status='CANDIDATO_READ_ONLY'
    AND version='v0.1-candidate';
  IF c<>1 THEN RAISE EXCEPTION 'S30_EXECUTOR_PRE_REGISTRY_DRIFT:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_contracts
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
    AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v0.1-candidate'
    AND status='CANDIDATO_READ_ONLY';
  IF c<>1 THEN RAISE EXCEPTION 'S30_EXECUTOR_PRE_CONTRACT_DRIFT:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_steps
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF';
  IF c<>15 THEN RAISE EXCEPTION 'S30_EXECUTOR_PRE_STEP_COUNT:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_steps
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND active;
  IF c<>0 THEN RAISE EXCEPTION 'S30_EXECUTOR_PRE_ACTIVE_STEPS:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_step_contracts
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='CANDIDATO_READ_ONLY';
  IF c<>15 THEN RAISE EXCEPTION 'S30_EXECUTOR_PRE_STEP_CONTRACTS:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_step_judge_bindings
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='CANDIDATO_READ_ONLY';
  IF c<>15 THEN RAISE EXCEPTION 'S30_EXECUTOR_PRE_JUDGE_BINDINGS:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_router_action_registry
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF';
  IF c<>0 THEN RAISE EXCEPTION 'S30_EXECUTOR_PRE_ROUTER_ROWS:%',c; END IF;

  SELECT count(*) INTO c FROM public.v_lf_operation_policy_snapshot
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND required AND policy_sha IS NOT NULL;
  IF c<>4 THEN RAISE EXCEPTION 'S30_EXECUTOR_POLICY_SNAPSHOT_INCOMPLETE:%',c; END IF;
END
$pre$;

UPDATE public.lf_operation_registry
SET version='v0.1',
    status='SANDBOX_ACTIVE',
    notes='S30 transversal remediation: restored the R19-validated sandbox-active Strategy executor after successful controlled canary/rollback proof. Control-state only; no business effects, scheduler, orchestrator or production activation.',
    updated_by_execution_id='EXEC-S30-REMEDIATION-ACTIVATE-STRATEGY-EXECUTOR-20260914-001',
    updated_at=now()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF';

UPDATE public.lf_operation_contracts
SET status='ACTIVE_ENFORCEMENT',
    allowed = coalesce(allowed,'{}'::jsonb) || jsonb_build_object(
      'sandbox_runtime_activation',true,
      'runtime_activation',true,
      'business_effect_dispatch_allowed',false,
      'production_activation',false,
      'scheduler_activation',false,
      'orchestrator_activation',false
    ),
    updated_by_execution_id='EXEC-S30-REMEDIATION-ACTIVATE-STRATEGY-EXECUTOR-20260914-001',
    updated_at=now()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
  AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v0.1-candidate';

UPDATE public.lf_operation_steps
SET active=true,
    updated_by_execution_id='EXEC-S30-REMEDIATION-ACTIVATE-STRATEGY-EXECUTOR-20260914-001',
    updated_at=now()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF';

UPDATE public.lf_operation_step_contracts
SET status='ACTIVE_ENFORCEMENT',
    pass_condition=jsonb_build_object(
      'effect_class',pass_condition->>'effect_class',
      'source_contract','S30_STRATEGY_EXECUTOR_BOOTSTRAP_V1',
      'runtime_mode','SANDBOX_CONTROLLED',
      'runtime_activation_authorized',true,
      'required_evidence_present',true,
      'authority_currentness_pass',true
    ),
    block_condition=jsonb_build_object(
      'source_contract_mismatch',true,
      'missing_required_evidence',true,
      'runtime_mode_not_sandbox_controlled',true,
      'target_strategy_binding_missing',true,
      'target_strategy_currentness_missing',true,
      'canary_scope_violation',true
    ),
    notes='S30 remediation: live sandbox-control projection from S30_STRATEGY_EXECUTOR_SANDBOX_ACTIVATION_V3. execution_sql intentionally remains NULL; execution is contract/evidence driven and business effects remain disabled.',
    updated_by_execution_id='EXEC-S30-REMEDIATION-ACTIVATE-STRATEGY-EXECUTOR-20260914-001',
    updated_at=now()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF';

UPDATE public.lf_operation_judges
SET status='ACTIVE_ENFORCEMENT',
    pass_if=jsonb_build_object(
      'operation_code','EJECUCION_ESTRATEGIA_LF',
      'source_contract','S30_STRATEGY_EXECUTOR_BOOTSTRAP_V1',
      'runtime_mode','SANDBOX_CONTROLLED',
      'runtime_activation_authorized',true,
      'required_evidence_present',true,
      'authority_currentness_pass',true,
      'r16_quality_bound',true,
      'c05_reliability_bound',true,
      'business_effect_dispatch_allowed',false,
      'production_activation',false,
      'scheduler_activation',false,
      'orchestrator_activation',false
    ),
    fail_if=coalesce(fail_if,'{}'::jsonb) || jsonb_build_object(
      'source_contract_mismatch',true,
      'missing_required_evidence',true,
      'runtime_mode_not_sandbox_controlled',true,
      'target_strategy_binding_missing',true,
      'target_strategy_currentness_missing',true,
      'canary_scope_violation',true,
      'business_effect_dispatch_attempt',true,
      'production_activation_attempt',true,
      'scheduler_activation_attempt',true,
      'orchestrator_activation_attempt',true
    ),
    updated_by_execution_id='EXEC-S30-REMEDIATION-ACTIVATE-STRATEGY-EXECUTOR-20260914-001',
    updated_at=now()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF';

UPDATE public.lf_operation_step_judge_bindings
SET status='ACTIVE_ENFORCEMENT',
    updated_by_execution_id='EXEC-S30-REMEDIATION-ACTIVATE-STRATEGY-EXECUTOR-20260914-001',
    updated_at=now()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF';

INSERT INTO public.lf_router_action_registry(
  asset_type,action_code,operation_code,operation_resolution,
  requires_existing_target,requires_missing_target,write_allowed,status,notes,
  created_by_execution_id
) VALUES (
  'STRATEGY','STRATEGY_EXECUTION','EJECUCION_ESTRATEGIA_LF','STATIC',
  false,false,false,'ACTIVE',
  'Canonical S30 transversal Strategy execution route. Exact strategy snapshot is resolved inside EJECUCION_ESTRATEGIA_LF; sandbox control-state only and no business-effect dispatch.',
  'EXEC-S30-REMEDIATION-ACTIVATE-STRATEGY-EXECUTOR-20260914-001'
);

DO $router_patch$
DECLARE
  v_def text;
  v_old text := $p$elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(cierra|cerrar|cierre|finaliza|finalizar)( |$)' then v_action:='STRATEGY_CLOSE';$p$;
  v_new text := $p$elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(ejecuta|ejecutar|corre|correr|continua|continuar|retoma|retomar)( |$)' then v_action:='STRATEGY_EXECUTION';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(cierra|cerrar|cierre|finaliza|finalizar)( |$)' then v_action:='STRATEGY_CLOSE';$p$;
BEGIN
  SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO v_def;
  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'S30_EXECUTOR_ROUTER_SOURCE_DRIFT';
  END IF;
  IF strpos(v_def,'STRATEGY_EXECUTION')>0 THEN
    RAISE EXCEPTION 'S30_EXECUTOR_ROUTER_INFERENCE_ALREADY_PRESENT_UNEXPECTED';
  END IF;
  EXECUTE replace(v_def,v_old,v_new);
END
$router_patch$;

DO $post$
DECLARE
  c integer;
  v jsonb;
BEGIN
  SELECT count(*) INTO c FROM public.lf_operation_registry
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='SANDBOX_ACTIVE' AND version='v0.1';
  IF c<>1 THEN RAISE EXCEPTION 'S30_EXECUTOR_POST_REGISTRY_FAIL:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_contracts
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';
  IF c<>1 THEN RAISE EXCEPTION 'S30_EXECUTOR_POST_CONTRACT_FAIL:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_steps
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND active;
  IF c<>15 THEN RAISE EXCEPTION 'S30_EXECUTOR_POST_ACTIVE_STEPS_FAIL:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_step_contracts
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';
  IF c<>15 THEN RAISE EXCEPTION 'S30_EXECUTOR_POST_ACTIVE_STEP_CONTRACTS_FAIL:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_step_judge_bindings
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';
  IF c<>15 THEN RAISE EXCEPTION 'S30_EXECUTOR_POST_ACTIVE_JUDGE_BINDINGS_FAIL:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_judges
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';
  IF c<>1 THEN RAISE EXCEPTION 'S30_EXECUTOR_POST_ACTIVE_JUDGE_FAIL:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_router_action_registry
  WHERE asset_type='STRATEGY' AND action_code='STRATEGY_EXECUTION'
    AND operation_code='EJECUCION_ESTRATEGIA_LF' AND status='ACTIVE' AND write_allowed=false;
  IF c<>1 THEN RAISE EXCEPTION 'S30_EXECUTOR_POST_ROUTER_BINDING_FAIL:%',c; END IF;

  v:=public.lf_router_resolve_v1('ejecutar estrategia',null,null,null,'ROUTER');
  IF v->>'status'<>'READY_TO_EXECUTE'
     OR v->>'asset_type'<>'STRATEGY'
     OR v->>'action_code'<>'STRATEGY_EXECUTION'
     OR v->>'operation_code'<>'EJECUCION_ESTRATEGIA_LF'
     OR (v->>'step_count')::int<>15 THEN
    RAISE EXCEPTION 'S30_EXECUTOR_POST_NATURAL_ROUTE_FAIL:%',v;
  END IF;

  v:=public.lf_router_resolve_v1('ejecutar estrategia',null,'STRATEGY_EXECUTION','STRATEGY','ROUTER');
  IF v->>'status'<>'READY_TO_EXECUTE' OR v->>'operation_code'<>'EJECUCION_ESTRATEGIA_LF' THEN
    RAISE EXCEPTION 'S30_EXECUTOR_POST_EXPLICIT_ROUTE_FAIL:%',v;
  END IF;
END
$post$;

UPDATE public.lf_operation_execution
SET manifest=manifest || jsonb_build_object(
      'result','SANDBOX_ACTIVATION_RESTORED_AND_ROUTER_BOUND',
      'router_rows',1,
      'active_steps',15,
      'active_step_contracts',15,
      'active_judge_bindings',15,
      'runtime_mode','SANDBOX_CONTROLLED',
      'business_effect_dispatch_allowed',false,
      'production_activation',false,
      'scheduler_activation',false,
      'orchestrator_activation',false,
      'natural_language_router_binding',true
    ),
    status='COMPLETED',
    completed_at=clock_timestamp(),
    updated_by_execution_id='EXEC-S30-REMEDIATION-ACTIVATE-STRATEGY-EXECUTOR-20260914-001',
    updated_at=clock_timestamp()
WHERE execution_id='EXEC-S30-REMEDIATION-ACTIVATE-STRATEGY-EXECUTOR-20260914-001';