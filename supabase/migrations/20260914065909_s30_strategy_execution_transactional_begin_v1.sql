DO $pre$
DECLARE v text;
BEGIN
  SELECT max(version) INTO v FROM supabase_migrations.schema_migrations;
  IF v IS DISTINCT FROM '20260914065154' THEN
    RAISE EXCEPTION 'S30_STRATEGY_EXEC_BEGIN_LEDGER_DRIFT:%',v;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id='EXEC-S30-STRATEGY-EXEC-BEGIN-REPAIR-20260914-001'
      AND operation_code='ACTUALIZACION_DB_LF' AND status='IN_PROGRESS'
  ) THEN RAISE EXCEPTION 'S30_STRATEGY_EXEC_BEGIN_DB_EXECUTION_BINDING_INVALID'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id='EXEC-S30-EXEC-STRATEGY-QUAL-HARDEN-20260914-001'
      AND operation_code='EJECUCION_ESTRATEGIA_LF'
  ) THEN RAISE EXCEPTION 'S30_STRATEGY_EXEC_BEGIN_EXECUTOR_PROVENANCE_MISSING'; END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.lf_operation_execution_qualification_guard_v1(
  p_operation_code text,
  p_execution_started_at timestamptz
) RETURNS void
LANGUAGE plpgsql STABLE
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE gate_from timestamptz; rev text;
BEGIN
  IF btrim(coalesce(p_operation_code,''))='' OR p_execution_started_at IS NULL THEN
    RAISE EXCEPTION 'LF_OPERATION_EXECUTION_QUALIFICATION_GUARD_INPUT_INVALID';
  END IF;
  gate_from:=public.lf_qualification_gate_effective_from_v1('OPERATION');
  IF gate_from IS NOT NULL AND p_execution_started_at>=gate_from THEN
    rev:=public.lf_operation_revision_sha256_v1(p_operation_code);
    IF NOT public.lf_qualification_current_v1('OPERATION',p_operation_code,rev) THEN
      RAISE EXCEPTION 'LF_OPERATION_EXECUTION_QUALIFICATION_REQUIRED:%:%',p_operation_code,rev;
    END IF;
  END IF;
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_strategy_execution_begin_v1(
  p_execution_id text,
  p_snapshot_id bigint,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_manifest jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  s public.lf_strategy_snapshots%rowtype;
  x public.lf_operation_execution%rowtype;
  st public.lf_operation_steps%rowtype;
  b public.lf_operation_step_judge_bindings%rowtype;
  c public.lf_operation_contracts%rowtype;
  existing public.lf_operation_execution_steps%rowtype;
  r jsonb;
  ep jsonb;
  target_path text;
  target_ref text;
  target_rev text;
  contract_count int;
BEGIN
  IF p_snapshot_id IS NULL OR btrim(coalesce(p_execution_id,''))='' OR coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$'
     OR btrim(coalesce(p_idempotency_key,''))='' OR btrim(coalesce(p_actor_execution_id,''))=''
     OR p_manifest IS NULL OR jsonb_typeof(p_manifest)<>'object' THEN
    RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_INPUT_INVALID';
  END IF;

  SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_TARGET_NOT_FOUND:%',p_snapshot_id; END IF;
  IF public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code) THEN
    RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_TERMINAL_TARGET:%:%',s.snapshot_code,s.lifecycle_state_code;
  END IF;
  IF s.id IS DISTINCT FROM (SELECT max(z.id) FROM public.lf_strategy_snapshots z WHERE z.snapshot_code=s.snapshot_code) THEN
    RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_STALE_SNAPSHOT:%:%',s.snapshot_code,s.id;
  END IF;

  target_path:=format('supabase://public/lf_strategy_snapshots/%s',s.id);
  target_ref:=format('snapshot:%s/%s@%s',s.id,s.snapshot_code,s.version);
  target_rev:=public.lf_strategy_revision_sha256_v1(s.id);

  r:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,'EJECUCION_ESTRATEGIA_LF','STRATEGY',s.snapshot_code,
    p_idempotency_key,p_request_sha256,p_actor_execution_id,null,target_path,p_manifest
  );

  SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=(r->>'execution_id') FOR UPDATE;
  IF NOT FOUND OR x.operation_code<>'EJECUCION_ESTRATEGIA_LF' OR x.target_type<>'STRATEGY'
     OR x.target_code IS DISTINCT FROM s.snapshot_code OR x.target_path IS DISTINCT FROM target_path THEN
    RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_EXECUTION_BINDING_MISMATCH';
  END IF;
  IF x.status<>'IN_PROGRESS' THEN
    RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_EXECUTION_NOT_IN_PROGRESS:%',x.status;
  END IF;

  PERFORM public.lf_operation_execution_qualification_guard_v1('EJECUCION_ESTRATEGIA_LF',x.started_at);
  PERFORM public.lf_strategy_execution_qualification_guard_v1(s.id,x.started_at);

  IF s.updated_at>x.started_at THEN
    RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_TARGET_CHANGED_AFTER_RESERVATION:%:%:%',s.snapshot_code,s.updated_at,x.started_at;
  END IF;

  SELECT count(*) INTO contract_count FROM public.lf_operation_contracts oc
  WHERE oc.operation_code='EJECUCION_ESTRATEGIA_LF' AND oc.status='ACTIVE_ENFORCEMENT';
  IF contract_count<>1 THEN RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_ACTIVE_CONTRACT_NOT_EXACT:%',contract_count; END IF;
  SELECT * INTO c FROM public.lf_operation_contracts oc
  WHERE oc.operation_code='EJECUCION_ESTRATEGIA_LF' AND oc.status='ACTIVE_ENFORCEMENT' LIMIT 1;

  IF coalesce((c.allowed->>'r16_quality_binding_required')::boolean,false) IS NOT TRUE
     OR coalesce((c.allowed->>'c05_reliability_required')::boolean,false) IS NOT TRUE
     OR coalesce((c.allowed->>'business_effect_dispatch_allowed')::boolean,false) IS NOT TRUE
     OR coalesce((c.allowed->>'runtime_activation')::boolean,false) IS NOT TRUE
     OR coalesce((c.allowed->>'direct_business_write_allowed')::boolean,true) IS NOT FALSE
     OR coalesce((c.allowed->>'scheduler_activation')::boolean,true) IS NOT FALSE
     OR coalesce((c.allowed->>'production_activation')::boolean,true) IS NOT FALSE
     OR coalesce((c.allowed->>'orchestrator_activation')::boolean,true) IS NOT FALSE THEN
    RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_CONTRACT_SAFETY_FLAGS_INVALID';
  END IF;

  IF coalesce(x.manifest->>'contract_code','')<>c.contract_code THEN
    RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_SOURCE_CONTRACT_MISMATCH:%:%',x.manifest->>'contract_code',c.contract_code;
  END IF;
  IF jsonb_typeof(x.manifest->'operation_policy_snapshots') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_POLICY_SNAPSHOT_MISSING';
  END IF;

  SELECT * INTO st FROM public.lf_operation_steps
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND step_id='init_execution' AND active=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_INIT_STEP_NOT_ACTIVE'; END IF;
  SELECT * INTO b FROM public.lf_operation_step_judge_bindings
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND step_id='init_execution'
    AND step_order=st.step_order AND status='ACTIVE_ENFORCEMENT';
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_INIT_BINDING_NOT_ACTIVE'; END IF;

  SELECT * INTO existing FROM public.lf_operation_execution_steps
  WHERE execution_id=x.execution_id AND step_order=st.step_order;
  IF FOUND THEN
    IF existing.step_id='init_execution' AND existing.status=b.clean_result_value THEN
      RETURN r || jsonb_build_object(
        'init_step','ALREADY_RECORDED_IDEMPOTENT','snapshot_id',s.id,'target_path',target_path,
        'target_strategy_ref',target_ref,'target_revision_sha256',target_rev,'next_step','router'
      );
    END IF;
    RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_INIT_STEP_CONFLICT:%:%',existing.step_id,existing.status;
  END IF;

  ep:=jsonb_build_object(
    'execution_id',x.execution_id,
    'idempotency_key',x.idempotency_key,
    'request_sha256',x.request_sha256,
    'target_strategy_ref',target_ref,
    'target_strategy_revision_sha256',target_rev,
    'target_path',target_path,
    'runtime_mode','GOVERNED_OPERATIONAL_OR_START_PINNED',
    'source_contract',c.contract_code,
    'assertions_checked',jsonb_build_array(
      'r16_quality_bound','c05_reliability_bound','required_evidence_present',
      'authority_currentness_pass','runtime_activation_authorized','business_effect_dispatch_allowed'
    ),
    'hard_fails_checked','[]'::jsonb,
    'blocking_findings','[]'::jsonb,
    'blocking_codes','[]'::jsonb,
    'return_to_worker_reasons','[]'::jsonb,
    'step_result',b.clean_result_value,
    'mini_judge_code',b.judge_code,
    'mini_judge_result',b.clean_result_value,
    'attempt_history','[]'::jsonb,
    'recorded_by_rpc','lf_strategy_execution_begin_v1'
  );

  INSERT INTO public.lf_operation_execution_steps(
    execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id
  ) VALUES(
    x.execution_id,st.step_order,'init_execution',b.clean_result_value,target_path,ep,
    'Initialized transactionally by governed Strategy Execution begin RPC.',p_actor_execution_id
  );

  SELECT * INTO existing FROM public.lf_operation_execution_steps
  WHERE execution_id=x.execution_id AND step_order=st.step_order AND step_id='init_execution';
  IF NOT FOUND OR existing.status<>b.clean_result_value
     OR existing.evidence_payload->>'derived_result'<>b.clean_result_value THEN
    RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_READBACK_FAILED';
  END IF;

  RETURN r || jsonb_build_object(
    'init_step','RECORDED','snapshot_id',s.id,'target_path',target_path,
    'target_strategy_ref',target_ref,'target_revision_sha256',target_rev,'next_step','router'
  );
END $fn$;

REVOKE ALL ON FUNCTION public.lf_operation_execution_qualification_guard_v1(text,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_strategy_execution_begin_v1(text,bigint,text,text,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_operation_execution_qualification_guard_v1(text,timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_strategy_execution_begin_v1(text,bigint,text,text,text,jsonb) TO service_role;

UPDATE public.lf_operation_contracts
SET allowed = allowed || jsonb_build_object(
      'transactional_begin_required',true,
      'transactional_begin_rpc','lf_strategy_execution_begin_v1',
      'init_step_core_recorder_forbidden',true
    ),
    required_before_write = CASE
      WHEN required_before_write @> '["TRANSACTIONAL_BEGIN_INIT_REQUIRED"]'::jsonb THEN required_before_write
      ELSE required_before_write || '["TRANSACTIONAL_BEGIN_INIT_REQUIRED"]'::jsonb
    END,
    updated_by_execution_id='EXEC-S30-EXEC-STRATEGY-QUAL-HARDEN-20260914-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';

INSERT INTO public.lf_test_suite_cases(
  suite_code,test_code,test_order,title,test_type,execution_mode,severity,input_payload,expected_output,prohibited_output,status,metadata,created_by_execution_id
) VALUES
('TS-STRATEGY-OP-EXECUTE-V1','E13',130,'Transactional begin is required by execution contract','CONTRACT','AUTOMATED','CRITICAL',jsonb_build_object('probe_code','OP_CONTRACT_BOOL','key','transactional_begin_required','expected',true),jsonb_build_object('passed',true),'{}'::jsonb,'CANDIDATO',jsonb_build_object('scope','EXECUTION_BEGIN_GOVERNANCE'),'EXEC-S30-STRATEGY-EXEC-BEGIN-REPAIR-20260914-001'),
('TS-STRATEGY-OP-EXECUTE-V1','E14',140,'Core recorder remains forbidden for init_execution','CONTRACT','AUTOMATED','CRITICAL',jsonb_build_object('probe_code','OP_CONTRACT_BOOL','key','init_step_core_recorder_forbidden','expected',true),jsonb_build_object('passed',true),'{}'::jsonb,'CANDIDATO',jsonb_build_object('scope','EXECUTION_BEGIN_GOVERNANCE'),'EXEC-S30-STRATEGY-EXEC-BEGIN-REPAIR-20260914-001')
ON CONFLICT (suite_code,test_code) DO UPDATE SET
  title=excluded.title,test_order=excluded.test_order,input_payload=excluded.input_payload,expected_output=excluded.expected_output,
  prohibited_output=excluded.prohibited_output,status=excluded.status,metadata=excluded.metadata,
  updated_by_execution_id='EXEC-S30-STRATEGY-EXEC-BEGIN-REPAIR-20260914-001',updated_at=clock_timestamp();

DO $canary$
DECLARE x public.lf_operation_execution%rowtype; before_count int; during_count int; after_count int; rr jsonb; guard_rr jsonb;
BEGIN
  SELECT * INTO x FROM public.lf_operation_execution
  WHERE execution_id='EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001';
  IF NOT FOUND OR x.operation_code<>'EJECUCION_ESTRATEGIA_LF' OR x.status<>'IN_PROGRESS' THEN
    RAISE EXCEPTION 'S30_STRATEGY_EXEC_BEGIN_CANARY_FIXTURE_INVALID';
  END IF;
  SELECT count(*) INTO before_count FROM public.lf_operation_execution_steps WHERE execution_id=x.execution_id;
  IF before_count<>0 THEN RAISE EXCEPTION 'S30_STRATEGY_EXEC_BEGIN_CANARY_FIXTURE_NOT_ZERO:%',before_count; END IF;
  guard_rr:=public.lf_record_operation_step_core_v1(
    x.execution_id,'init_execution','canary',jsonb_build_object('x',true),x.execution_id,
    'EJECUCION_ESTRATEGIA_LF','STRATEGY','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    jsonb_build_object('valid',true),false,'S30_CANARY'
  );
  IF guard_rr->>'code'<>'INIT_STEP_IMMUTABLE' THEN RAISE EXCEPTION 'S30_STRATEGY_EXEC_BEGIN_CORE_GUARD_FAILED:%',guard_rr; END IF;
  BEGIN
    rr:=public.lf_strategy_execution_begin_v1(
      x.execution_id,56,x.request_sha256,x.idempotency_key,x.execution_id,x.manifest
    );
    IF rr->>'init_step'<>'RECORDED' THEN RAISE EXCEPTION 'S30_STRATEGY_EXEC_BEGIN_CANARY_NOT_RECORDED:%',rr; END IF;
    SELECT count(*) INTO during_count FROM public.lf_operation_execution_steps
    WHERE execution_id=x.execution_id AND step_id='init_execution' AND status='PASS_CLEAN';
    IF during_count<>1 THEN RAISE EXCEPTION 'S30_STRATEGY_EXEC_BEGIN_CANARY_STEP_READBACK_FAIL:%',during_count; END IF;
    RAISE EXCEPTION USING ERRCODE='P0B01',MESSAGE='S30_STRATEGY_EXEC_BEGIN_CANARY_INTENTIONAL_ROLLBACK';
  EXCEPTION WHEN SQLSTATE 'P0B01' THEN NULL;
  END;
  SELECT count(*) INTO after_count FROM public.lf_operation_execution_steps WHERE execution_id=x.execution_id;
  IF after_count<>before_count THEN RAISE EXCEPTION 'S30_STRATEGY_EXEC_BEGIN_CANARY_ROLLBACK_FAIL:%:%',before_count,after_count; END IF;
END $canary$;

UPDATE public.lf_operation_execution
SET manifest=manifest||jsonb_build_object(
      'migration_result','STRATEGY_EXECUTION_TRANSACTIONAL_BEGIN_APPLIED',
      'rollback_canary','PASS_NO_PERSISTENT_MUTATION',
      'core_recorder_init_guard','PASS_INIT_STEP_IMMUTABLE',
      'target_rpc','lf_strategy_execution_begin_v1'
    ),updated_at=clock_timestamp(),updated_by_execution_id=execution_id
WHERE execution_id='EXEC-S30-STRATEGY-EXEC-BEGIN-REPAIR-20260914-001';

DO $post$
BEGIN
  IF to_regprocedure('public.lf_strategy_execution_begin_v1(text,bigint,text,text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'S30_STRATEGY_EXEC_BEGIN_RPC_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT'
      AND coalesce((allowed->>'transactional_begin_required')::boolean,false)
      AND coalesce((allowed->>'init_step_core_recorder_forbidden')::boolean,false)
  ) THEN RAISE EXCEPTION 'S30_STRATEGY_EXEC_BEGIN_CONTRACT_NOT_HARDENED'; END IF;
END $post$;