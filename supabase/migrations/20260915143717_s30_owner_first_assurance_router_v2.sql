-- S30-R21 v2: close the remaining pre-candidate permission loop in Router and Strategy Execution begin.
-- Safety is moved, not removed: exact Strategy + exact EJECUCION_ESTRATEGIA_LF operation qualification are required at terminal close.

CREATE OR REPLACE FUNCTION public.lf_strategy_terminal_qualification_guard_v1(
  p_snapshot_id bigint,
  p_terminal_action text,
  p_effect_started_at timestamptz
)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  s public.lf_strategy_snapshots%rowtype;
  gate_from timestamptz;
  strategy_rev text;
  executor_rev text;
  action_code text:=upper(btrim(coalesce(p_terminal_action,'')));
BEGIN
  IF p_snapshot_id IS NULL OR action_code='' OR p_effect_started_at IS NULL THEN
    RAISE EXCEPTION 'LF_STRATEGY_TERMINAL_QUALIFICATION_GUARD_INPUT_INVALID';
  END IF;
  IF action_code NOT IN ('CLOSE_STRATEGY') THEN
    RAISE EXCEPTION 'LF_STRATEGY_TERMINAL_QUALIFICATION_ACTION_UNSUPPORTED:%',action_code;
  END IF;
  SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_STRATEGY_TERMINAL_QUALIFICATION_TARGET_MISSING_ID:%',p_snapshot_id; END IF;

  gate_from:=public.lf_qualification_gate_effective_from_v1('STRATEGY');
  IF gate_from IS NOT NULL AND p_effect_started_at>=gate_from THEN
    strategy_rev:=public.lf_strategy_revision_sha256_v1(s.id);
    IF NOT public.lf_qualification_current_v1('STRATEGY',s.snapshot_code,strategy_rev) THEN
      RAISE EXCEPTION 'LF_STRATEGY_TERMINAL_QUALIFICATION_REQUIRED:%:%:%',action_code,s.snapshot_code,strategy_rev;
    END IF;

    executor_rev:=public.lf_operation_revision_sha256_v1('EJECUCION_ESTRATEGIA_LF');
    IF NOT public.lf_qualification_current_v1('OPERATION','EJECUCION_ESTRATEGIA_LF',executor_rev) THEN
      RAISE EXCEPTION 'LF_STRATEGY_TERMINAL_EXECUTOR_QUALIFICATION_REQUIRED:%:%',action_code,executor_rev;
    END IF;
  END IF;
END
$fn$;

DO $patch_begin$
DECLARE
  d text;
  needle text:=$x$  PERFORM public.lf_operation_execution_qualification_guard_v1('EJECUCION_ESTRATEGIA_LF',x.started_at);$x$;
  replacement text:=$x$  -- S30-R21 v2: executor operation assurance is post-candidate/terminal, never permission to begin owner work.$x$;
BEGIN
  SELECT pg_get_functiondef('public.lf_strategy_execution_begin_v1(text,bigint,text,text,text,jsonb)'::regprocedure) INTO d;
  IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'S30_R21_V2_BEGIN_OPERATION_GATE_SOURCE_DRIFT'; END IF;
  EXECUTE replace(d,needle,replacement);
END
$patch_begin$;

DO $patch_router$
DECLARE
  d text;
  needle text:=$x$    if not public.lf_qualification_current_v1('OPERATION',v_operation.operation_code,public.lf_operation_revision_sha256_v1(v_operation.operation_code)) then
      return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_QUALIFICATION_REQUIRED','router','ACT-0001','operation_code',v_operation.operation_code,'operation_revision_sha256',public.lf_operation_revision_sha256_v1(v_operation.operation_code));
    end if;$x$;
  replacement text:=$x$    if v_operation.operation_code<>'EJECUCION_ESTRATEGIA_LF'
       and not public.lf_qualification_current_v1('OPERATION',v_operation.operation_code,public.lf_operation_revision_sha256_v1(v_operation.operation_code)) then
      return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_QUALIFICATION_REQUIRED','router','ACT-0001','operation_code',v_operation.operation_code,'operation_revision_sha256',public.lf_operation_revision_sha256_v1(v_operation.operation_code));
    end if;$x$;
BEGIN
  SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO d;
  IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'S30_R21_V2_ROUTER_OPERATION_GATE_SOURCE_DRIFT'; END IF;
  EXECUTE replace(d,needle,replacement);
END
$patch_router$;

CREATE OR REPLACE FUNCTION public.lf_canary_strategy_owner_first_assurance_boundary_v2(p_snapshot_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  s public.lf_strategy_snapshots%rowtype;
  begin_def text;
  lifecycle_def text;
  router_def text;
  terminal_def text;
  route jsonb;
  terminal_blocked boolean:=false;
  terminal_msg text;
  begin_strategy_gate_absent boolean;
  begin_operation_gate_absent boolean;
  lifecycle_strategy_gate_absent boolean;
  router_executor_exception_bound boolean;
  terminal_strategy_gate_bound boolean;
  terminal_executor_gate_bound boolean;
BEGIN
  SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id;
  IF NOT FOUND OR public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code) THEN
    RETURN jsonb_build_object('passed',false,'reason','INVALID_CANARY_FIXTURE');
  END IF;

  SELECT pg_get_functiondef('public.lf_strategy_execution_begin_v1(text,bigint,text,text,text,jsonb)'::regprocedure) INTO begin_def;
  SELECT pg_get_functiondef('public.lf_strategy_lifecycle_from_execution_step_v1()'::regprocedure) INTO lifecycle_def;
  SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO router_def;
  SELECT pg_get_functiondef('public.lf_strategy_terminal_qualification_guard_v1(bigint,text,timestamptz)'::regprocedure) INTO terminal_def;

  begin_strategy_gate_absent:=strpos(begin_def,'lf_strategy_execution_qualification_guard_v1')=0;
  begin_operation_gate_absent:=strpos(begin_def,'lf_operation_execution_qualification_guard_v1')=0;
  lifecycle_strategy_gate_absent:=strpos(lifecycle_def,'lf_strategy_execution_qualification_guard_v1')=0;
  router_executor_exception_bound:=strpos(router_def,$x$v_operation.operation_code<>'EJECUCION_ESTRATEGIA_LF'$x$)>0;
  terminal_strategy_gate_bound:=strpos(terminal_def,$x$lf_qualification_current_v1('STRATEGY'$x$)>0;
  terminal_executor_gate_bound:=strpos(terminal_def,$x$lf_qualification_current_v1('OPERATION','EJECUCION_ESTRATEGIA_LF'$x$)>0;

  route:=public.lf_router_resolve_v1('ejecutar estrategia',s.snapshot_code,'STRATEGY_EXECUTION','STRATEGY','ROUTER');

  BEGIN
    PERFORM public.lf_strategy_terminal_qualification_guard_v1(s.id,'CLOSE_STRATEGY',clock_timestamp());
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS terminal_msg=MESSAGE_TEXT;
    IF terminal_msg LIKE 'LF_STRATEGY_TERMINAL_QUALIFICATION_REQUIRED:%'
       OR terminal_msg LIKE 'LF_STRATEGY_TERMINAL_EXECUTOR_QUALIFICATION_REQUIRED:%' THEN
      terminal_blocked:=true;
    ELSE
      RAISE;
    END IF;
  END;

  RETURN jsonb_build_object(
    'passed',begin_strategy_gate_absent AND begin_operation_gate_absent AND lifecycle_strategy_gate_absent
      AND router_executor_exception_bound AND coalesce(route->>'blocking_code','')<>'BLOCK_OPERATION_QUALIFICATION_REQUIRED'
      AND terminal_strategy_gate_bound AND terminal_executor_gate_bound AND terminal_blocked,
    'policy_code','S30-OWNER-FIRST-POST-CANDIDATE-ASSURANCE-v1',
    'snapshot_id',s.id,
    'begin_strategy_gate_absent',begin_strategy_gate_absent,
    'begin_operation_gate_absent',begin_operation_gate_absent,
    'lifecycle_strategy_gate_absent',lifecycle_strategy_gate_absent,
    'router_executor_exception_bound',router_executor_exception_bound,
    'router_status',route->>'status',
    'router_blocking_code',route->>'blocking_code',
    'terminal_strategy_gate_bound',terminal_strategy_gate_bound,
    'terminal_executor_gate_bound',terminal_executor_gate_bound,
    'terminal_unqualified_effect_blocked',terminal_blocked,
    'terminal_block_message',terminal_msg
  );
END
$fn$;

CREATE OR REPLACE FUNCTION public.lf_canary_strategy_unqualified_execution_block_v1(p_snapshot_id bigint)
RETURNS jsonb
LANGUAGE sql
VOLATILE
SET search_path TO 'pg_catalog','public'
AS $fn$
  SELECT public.lf_canary_strategy_owner_first_assurance_boundary_v2(p_snapshot_id);
$fn$;

UPDATE public.lf_test_suite_cases
SET title='Owner Strategy execution/router are not pre-gated; terminal effect requires current Strategy and executor qualification',
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('semantic_revision','R21_OWNER_FIRST_POST_CANDIDATE_ASSURANCE_V2'),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-S30-R21-POST-CANDIDATE-ASSURANCE-POLICY-20260915-001'
WHERE suite_code='TS-STRATEGY-BASE-V1' AND test_code='S11';

DO $verify$
DECLARE
  b text;
  r text;
  t text;
  c jsonb;
BEGIN
  SELECT pg_get_functiondef('public.lf_strategy_execution_begin_v1(text,bigint,text,text,text,jsonb)'::regprocedure) INTO b;
  SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO r;
  SELECT pg_get_functiondef('public.lf_strategy_terminal_qualification_guard_v1(bigint,text,timestamptz)'::regprocedure) INTO t;
  IF strpos(b,'lf_strategy_execution_qualification_guard_v1')>0 OR strpos(b,'lf_operation_execution_qualification_guard_v1')>0 THEN
    RAISE EXCEPTION 'S30_R21_V2_VERIFY_PRE_CANDIDATE_GATE_STILL_BOUND';
  END IF;
  IF strpos(r,$x$v_operation.operation_code<>'EJECUCION_ESTRATEGIA_LF'$x$)=0 THEN
    RAISE EXCEPTION 'S30_R21_V2_VERIFY_ROUTER_EXCEPTION_MISSING';
  END IF;
  IF strpos(t,$x$lf_qualification_current_v1('STRATEGY'$x$)=0 OR strpos(t,$x$lf_qualification_current_v1('OPERATION','EJECUCION_ESTRATEGIA_LF'$x$)=0 THEN
    RAISE EXCEPTION 'S30_R21_V2_VERIFY_TERMINAL_GATES_MISSING';
  END IF;
  c:=public.lf_canary_strategy_owner_first_assurance_boundary_v2(35);
  IF coalesce((c->>'passed')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'S30_R21_V2_CANARY_FAIL:%',c; END IF;
END
$verify$;
