-- S30-R21-POST-CANDIDATE-INDEPENDENT-ASSURANCE
-- Policy: S30-OWNER-FIRST-POST-CANDIDATE-ASSURANCE-v1
-- Independent assurance validates a completed candidate/result; it is not a permission gate for owner execution.
-- Final terminal effects remain fail-closed on current Strategy qualification.

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
  rev text;
  action_code text:=upper(btrim(coalesce(p_terminal_action,'')));
BEGIN
  IF p_snapshot_id IS NULL OR action_code='' OR p_effect_started_at IS NULL THEN
    RAISE EXCEPTION 'LF_STRATEGY_TERMINAL_QUALIFICATION_GUARD_INPUT_INVALID';
  END IF;
  IF action_code NOT IN ('CLOSE_STRATEGY') THEN
    RAISE EXCEPTION 'LF_STRATEGY_TERMINAL_QUALIFICATION_ACTION_UNSUPPORTED:%',action_code;
  END IF;

  SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LF_STRATEGY_TERMINAL_QUALIFICATION_TARGET_MISSING_ID:%',p_snapshot_id;
  END IF;

  gate_from:=public.lf_qualification_gate_effective_from_v1('STRATEGY');
  IF gate_from IS NOT NULL AND p_effect_started_at>=gate_from THEN
    rev:=public.lf_strategy_revision_sha256_v1(s.id);
    IF NOT public.lf_qualification_current_v1('STRATEGY',s.snapshot_code,rev) THEN
      RAISE EXCEPTION 'LF_STRATEGY_TERMINAL_QUALIFICATION_REQUIRED:%:%:%',action_code,s.snapshot_code,rev;
    END IF;
  END IF;
END
$fn$;

COMMENT ON FUNCTION public.lf_strategy_terminal_qualification_guard_v1(bigint,text,timestamptz)
IS 'S30-R21 terminal assurance boundary: owner execution may produce a candidate without snapshot-level independent qualification; terminal Strategy effects fail closed unless the exact current Strategy revision is qualified.';

CREATE OR REPLACE FUNCTION public.lf_strategy_execution_begin_v1(
  p_execution_id text,
  p_snapshot_id bigint,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_manifest jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
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

  -- Operation qualification remains mandatory. Snapshot/content independent assurance is post-candidate.
  PERFORM public.lf_operation_execution_qualification_guard_v1('EJECUCION_ESTRATEGIA_LF',x.started_at);

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
        'target_strategy_ref',target_ref,'target_revision_sha256',target_rev,'next_step','router',
        'snapshot_assurance_timing','POST_CANDIDATE_TERMINAL_EFFECT'
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
    'snapshot_independent_assurance_pre_execution_required',false,
    'snapshot_independent_assurance_timing','POST_CANDIDATE_TERMINAL_EFFECT',
    'snapshot_independent_assurance_terminal_effect_required',true,
    'assertions_checked',jsonb_build_array(
      'r16_quality_bound','c05_reliability_bound','required_evidence_present',
      'authority_currentness_pass','runtime_activation_authorized','business_effect_dispatch_allowed',
      'owner_execution_not_pre_gated_by_snapshot_independent_assurance'
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
    'Initialized transactionally by governed Strategy Execution begin RPC under owner-first/post-candidate-assurance policy.',p_actor_execution_id
  );

  SELECT * INTO existing FROM public.lf_operation_execution_steps
  WHERE execution_id=x.execution_id AND step_order=st.step_order AND step_id='init_execution';
  IF NOT FOUND OR existing.status<>b.clean_result_value
     OR existing.evidence_payload->>'derived_result'<>b.clean_result_value THEN
    RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_BEGIN_READBACK_FAILED';
  END IF;

  RETURN r || jsonb_build_object(
    'init_step','RECORDED','snapshot_id',s.id,'target_path',target_path,
    'target_strategy_ref',target_ref,'target_revision_sha256',target_rev,'next_step','router',
    'snapshot_assurance_timing','POST_CANDIDATE_TERMINAL_EFFECT'
  );
END
$fn$;

CREATE OR REPLACE FUNCTION public.lf_strategy_lifecycle_from_execution_step_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  x public.lf_operation_execution%rowtype;
  s public.lf_strategy_snapshots%rowtype;
  target_state text;
BEGIN
  IF NEW.step_id<>'strategy_resolve' OR NEW.status<>'PASS_CLEAN' THEN RETURN NEW; END IF;
  SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=NEW.execution_id;
  IF NOT FOUND OR x.operation_code<>'EJECUCION_ESTRATEGIA_LF' OR x.target_type<>'STRATEGY' THEN RETURN NEW; END IF;
  SELECT * INTO s FROM public.lf_strategy_snapshots WHERE snapshot_code=x.target_code ORDER BY id DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_TARGET_MISSING:%',x.target_code; END IF;

  -- R21: START_EXECUTION is an owner action, not an independent-assurance terminal effect.
  target_state:=public.lf_lifecycle_resolve_transition_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code,'START_EXECUTION');
  IF target_state IS DISTINCT FROM s.lifecycle_state_code THEN
    UPDATE public.lf_strategy_snapshots
       SET lifecycle_state_code=target_state,updated_at=clock_timestamp(),updated_by_execution_id=x.execution_id
     WHERE id=s.id;
  END IF;
  RETURN NEW;
END
$fn$;

CREATE OR REPLACE FUNCTION public.lf_strategy_close_write_v1(
  p_execution_id text,
  p_snapshot_id bigint,
  p_expected_revision_sha256 text,
  p_reason text,
  p_disposition text,
  p_evidence jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  x public.lf_operation_execution%rowtype;
  s public.lf_strategy_snapshots%rowtype;
  a public.lf_strategy_snapshots%rowtype;
  bh text;
  ah text;
  cl jsonb;
  nowv timestamptz:=clock_timestamp();
  sw int;
  oc int;
  spec jsonb;
  target_state text;
BEGIN
  IF btrim(coalesce(p_execution_id,''))='' OR p_snapshot_id IS NULL OR p_expected_revision_sha256 !~ '^[0-9a-f]{64}$'
     OR btrim(coalesce(p_reason,''))='' OR p_disposition NOT IN ('TERMINAL_COMPLETE','TERMINAL_BLOCKED')
     OR jsonb_typeof(p_evidence)<>'object' THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_INPUT_INVALID';
  END IF;
  SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  IF NOT FOUND OR x.operation_code<>'CIERRE_ESTRATEGIA_LF' OR x.status<>'IN_PROGRESS' OR x.target_type<>'STRATEGY' THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_EXECUTION_BINDING_MISMATCH';
  END IF;
  SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id FOR UPDATE;
  IF NOT FOUND OR x.target_code<>s.snapshot_code THEN RAISE EXCEPTION 'LF_STRATEGY_CLOSE_TARGET_MISMATCH'; END IF;
  IF public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code)
     OR coalesce(s.metadata->'strategy_close'->>'status','')='CLOSED' THEN
    IF s.metadata->'strategy_close'->>'execution_id'=p_execution_id THEN
      RETURN jsonb_build_object('result','ALREADY_CLOSED_IDEMPOTENT','snapshot_id',s.id,'close_receipt',s.metadata->'strategy_close');
    END IF;
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_ALREADY_TERMINAL';
  END IF;

  spec:=public.lf_lifecycle_transition_spec_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code,'CLOSE_STRATEGY');
  target_state:=spec->>'to_state_code';
  bh:=encode(extensions.digest(to_jsonb(s)::text,'sha256'),'hex');
  IF bh<>p_expected_revision_sha256 THEN RAISE EXCEPTION 'LF_STRATEGY_CLOSE_STALE_REVISION'; END IF;

  IF coalesce(p_evidence->>'safe_work_remaining_count','') !~ '^[0-9]+$'
     OR coalesce(p_evidence->>'open_executable_causal_chains','') !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_ELIGIBILITY_COUNTS_REQUIRED';
  END IF;
  sw:=(p_evidence->>'safe_work_remaining_count')::int;
  oc:=(p_evidence->>'open_executable_causal_chains')::int;
  IF sw<>0 OR oc<>0 OR coalesce((p_evidence->>'no_supersede_requested')::boolean,false) IS NOT TRUE
     OR jsonb_typeof(p_evidence->'backlog_disposition_map')<>'object'
     OR jsonb_typeof(p_evidence->'risk_disposition_map')<>'object' THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_NOT_ELIGIBLE';
  END IF;
  IF p_evidence ? 'open_blockers' AND jsonb_typeof(p_evidence->'open_blockers')<>'array' THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_BLOCKERS_INVALID';
  END IF;
  IF p_disposition='TERMINAL_COMPLETE' AND jsonb_array_length(coalesce(p_evidence->'open_blockers','[]'::jsonb))>0 THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_FALSE_COMPLETE';
  END IF;
  IF p_disposition='TERMINAL_BLOCKED' AND jsonb_array_length(coalesce(p_evidence->'open_blockers','[]'::jsonb))=0 THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_BLOCKED_REQUIRES_BLOCKER';
  END IF;

  -- R21 terminal boundary: only now is exact-revision independent qualification required.
  PERFORM public.lf_strategy_terminal_qualification_guard_v1(s.id,'CLOSE_STRATEGY',x.started_at);

  cl:=jsonb_build_object(
    'status','CLOSED','disposition',p_disposition,'reason_code',p_reason,'execution_id',p_execution_id,
    'closed_at',nowv,'safe_work_remaining_count',sw,'open_executable_causal_chains',oc,
    'open_blockers',coalesce(p_evidence->'open_blockers','[]'::jsonb),
    'backlog_disposition_map',p_evidence->'backlog_disposition_map','risk_disposition_map',p_evidence->'risk_disposition_map',
    'baseline_revision_sha256',bh,'superseded',false,
    'independent_assurance_boundary','POST_CANDIDATE_TERMINAL_EFFECT'
  );
  UPDATE public.lf_strategy_snapshots
     SET lifecycle_state_code=target_state,
         metadata=jsonb_set(coalesce(metadata,'{}'::jsonb),'{strategy_close}',cl,true),
         evidence_refs=coalesce(evidence_refs,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('type','STRATEGY_CLOSE','execution_id',p_execution_id,'refs',coalesce(p_evidence->'evidence_refs','[]'::jsonb))),
         change_log=coalesce(change_log,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('change_type','STRATEGY_CLOSE','execution_id',p_execution_id,'closed_at',nowv,'reason_code',p_reason,'disposition',p_disposition,'superseded',false)),
         runtime_state='NO_HABILITADO',impact_policy='BLOQUEADO',visibility='READ_ONLY_INTERNAL',updated_at=nowv,updated_by_execution_id=p_execution_id
   WHERE id=s.id RETURNING * INTO a;
  ah:=encode(extensions.digest(to_jsonb(a)::text,'sha256'),'hex');
  IF a.lifecycle_state_code<>target_state OR a.status IS DISTINCT FROM s.status OR a.archived_at IS DISTINCT FROM s.archived_at
     OR a.archived_reason IS DISTINCT FROM s.archived_reason OR a.runtime_state<>'NO_HABILITADO'
     OR a.impact_policy<>'BLOQUEADO' OR a.visibility<>'READ_ONLY_INTERNAL' THEN
    RAISE EXCEPTION 'LF_STRATEGY_CLOSE_POSTWRITE_INVARIANT';
  END IF;
  RETURN jsonb_build_object(
    'result','STRATEGY_CLOSED_WITH_EVIDENCE','snapshot_id',a.id,'snapshot_code',a.snapshot_code,
    'close_receipt',a.metadata->'strategy_close','before_revision_sha256',bh,'after_revision_sha256',ah,
    'changed_paths',jsonb_build_array('lifecycle_state_code','metadata.strategy_close','evidence_refs.append','change_log.append','runtime_state','impact_policy','visibility','updated_at','updated_by_execution_id')
  );
END
$fn$;

-- Keep the legacy probe code/function name for matrix compatibility, but change its semantics to R21:
-- owner execution must not be pre-gated; terminal close must be qualification-gated.
CREATE OR REPLACE FUNCTION public.lf_canary_strategy_unqualified_execution_block_v1(p_snapshot_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  s public.lf_strategy_snapshots%rowtype;
  qstate text;
  terminal_blocked boolean:=false;
  owner_begin_pre_gate_absent boolean:=false;
  owner_lifecycle_pre_gate_absent boolean:=false;
  terminal_gate_bound boolean:=false;
  msg text;
  begin_def text;
  lifecycle_def text;
  close_def text;
BEGIN
  SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id;
  IF NOT FOUND OR public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code) THEN
    RETURN jsonb_build_object('passed',false,'reason','INVALID_CANARY_FIXTURE');
  END IF;

  SELECT pg_get_functiondef('public.lf_strategy_execution_begin_v1(text,bigint,text,text,text,jsonb)'::regprocedure) INTO begin_def;
  SELECT pg_get_functiondef('public.lf_strategy_lifecycle_from_execution_step_v1()'::regprocedure) INTO lifecycle_def;
  SELECT pg_get_functiondef('public.lf_strategy_close_write_v1(text,bigint,text,text,text,jsonb)'::regprocedure) INTO close_def;
  owner_begin_pre_gate_absent:=strpos(begin_def,'lf_strategy_execution_qualification_guard_v1')=0;
  owner_lifecycle_pre_gate_absent:=strpos(lifecycle_def,'lf_strategy_execution_qualification_guard_v1')=0;
  terminal_gate_bound:=strpos(close_def,'lf_strategy_terminal_qualification_guard_v1')>0;

  qstate:=public.lf_lifecycle_action_target_state_v1('QUALIFICATION_LIFECYCLE','PASS_QUALIFICATION');
  BEGIN
    UPDATE public.lf_qualification_receipts q
       SET lifecycle_state_code=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',q.lifecycle_state_code,'INVALIDATE_QUALIFICATION'),
           invalidated_at=clock_timestamp()
     WHERE q.subject_type='STRATEGY' AND q.subject_code=s.snapshot_code
       AND q.lifecycle_state_code=qstate AND q.invalidated_at IS NULL;

    BEGIN
      PERFORM public.lf_strategy_terminal_qualification_guard_v1(s.id,'CLOSE_STRATEGY',clock_timestamp());
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
      IF msg LIKE 'LF_STRATEGY_TERMINAL_QUALIFICATION_REQUIRED:%' THEN
        terminal_blocked:=true;
      ELSE
        RAISE;
      END IF;
    END;
    RAISE EXCEPTION USING ERRCODE='P0Q21',MESSAGE='S30_R21_CANARY_ROLLBACK';
  EXCEPTION WHEN SQLSTATE 'P0Q21' THEN NULL;
  END;

  RETURN jsonb_build_object(
    'passed',owner_begin_pre_gate_absent AND owner_lifecycle_pre_gate_absent AND terminal_gate_bound AND terminal_blocked,
    'snapshot_id',s.id,
    'snapshot_code',s.snapshot_code,
    'policy_code','S30-OWNER-FIRST-POST-CANDIDATE-ASSURANCE-v1',
    'owner_begin_pre_gate_absent',owner_begin_pre_gate_absent,
    'owner_lifecycle_pre_gate_absent',owner_lifecycle_pre_gate_absent,
    'terminal_gate_bound',terminal_gate_bound,
    'terminal_unqualified_close_blocked',terminal_blocked,
    'expected_terminal_block','LF_STRATEGY_TERMINAL_QUALIFICATION_REQUIRED',
    'persistent_mutation',false
  );
END
$fn$;

UPDATE public.lf_test_suite_cases
SET title='Owner Strategy execution is not pre-gated; terminal close requires current qualification',
    input_payload=jsonb_build_object(
      'probe_code','STRATEGY_UNQUALIFIED_EXECUTION_BLOCK',
      'policy_code','S30-OWNER-FIRST-POST-CANDIDATE-ASSURANCE-v1',
      'owner_execution_pre_assurance_permission_gate_allowed',false,
      'terminal_close_requires_current_qualification',true
    ),
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'semantic_revision','R21_OWNER_FIRST_POST_CANDIDATE_ASSURANCE',
      'legacy_probe_name_preserved',true
    ),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-S30-R21-POST-CANDIDATE-ASSURANCE-POLICY-20260915-001'
WHERE suite_code='TS-STRATEGY-BASE-V1' AND test_code='S11';

DO $verify$
DECLARE
  begin_def text;
  lifecycle_def text;
  close_def text;
  s11_count int;
BEGIN
  SELECT pg_get_functiondef('public.lf_strategy_execution_begin_v1(text,bigint,text,text,text,jsonb)'::regprocedure) INTO begin_def;
  SELECT pg_get_functiondef('public.lf_strategy_lifecycle_from_execution_step_v1()'::regprocedure) INTO lifecycle_def;
  SELECT pg_get_functiondef('public.lf_strategy_close_write_v1(text,bigint,text,text,text,jsonb)'::regprocedure) INTO close_def;

  IF strpos(begin_def,'lf_strategy_execution_qualification_guard_v1')>0 THEN
    RAISE EXCEPTION 'S30_R21_VERIFY_PRE_EXECUTION_QUALIFICATION_GATE_STILL_BOUND';
  END IF;
  IF strpos(begin_def,'lf_operation_execution_qualification_guard_v1')=0 THEN
    RAISE EXCEPTION 'S30_R21_VERIFY_OPERATION_QUALIFICATION_GUARD_MISSING';
  END IF;
  IF strpos(lifecycle_def,'lf_strategy_execution_qualification_guard_v1')>0 THEN
    RAISE EXCEPTION 'S30_R21_VERIFY_LIFECYCLE_PRE_ASSURANCE_GATE_STILL_BOUND';
  END IF;
  IF strpos(close_def,'lf_strategy_terminal_qualification_guard_v1')=0 THEN
    RAISE EXCEPTION 'S30_R21_VERIFY_TERMINAL_QUALIFICATION_GATE_MISSING';
  END IF;

  SELECT count(*) INTO s11_count
  FROM public.lf_test_suite_cases
  WHERE suite_code='TS-STRATEGY-BASE-V1' AND test_code='S11'
    AND input_payload->>'policy_code'='S30-OWNER-FIRST-POST-CANDIDATE-ASSURANCE-v1'
    AND coalesce((input_payload->>'owner_execution_pre_assurance_permission_gate_allowed')::boolean,true)=false
    AND coalesce((input_payload->>'terminal_close_requires_current_qualification')::boolean,false)=true;
  IF s11_count<>1 THEN RAISE EXCEPTION 'S30_R21_VERIFY_S11_SEMANTICS_MISSING:%',s11_count; END IF;
END
$verify$;
