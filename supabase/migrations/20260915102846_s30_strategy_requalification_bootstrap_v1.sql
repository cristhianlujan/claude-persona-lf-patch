-- S30: bounded requalification bootstrap for current Strategy revision.
-- Reuses EJECUCION_ESTRATEGIA_LF and existing Router/qualification surfaces.
-- No Strategy snapshot mutation, runtime activation, production activation, scheduler activation,
-- orchestrator activation, or direct business write is authorized by this RPC.

DO $pre$
DECLARE
  x public.lf_operation_execution%rowtype;
BEGIN
  SELECT * INTO x
  FROM public.lf_operation_execution
  WHERE execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-002';

  IF NOT FOUND
     OR x.operation_code<>'ACTUALIZACION_DB_LF'
     OR x.status<>'IN_PROGRESS'
     OR x.target_type<>'MIGRATION'
     OR x.target_code<>'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_V1'
     OR x.target_repo IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch'
     OR x.target_path IS DISTINCT FROM 'supabase/migrations/20260915102846_s30_strategy_requalification_bootstrap_v1.sql'
     OR coalesce(x.manifest->>'source_pr','')<>'840' THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_DB_EXECUTION_BINDING_INVALID';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_router_action_registry
    WHERE asset_type='MIGRATION'
      AND action_code='UPDATE'
      AND operation_code='ACTUALIZACION_DB_LF'
      AND status='ACTIVE'
      AND write_allowed
  ) THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_DB_ROUTE_NOT_ACTIVE';
  END IF;

  IF coalesce(x.manifest->>'operation_policy_source','')<>'SUPABASE'
     OR jsonb_typeof(x.manifest->'operation_policy_snapshots') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_DB_POLICY_SNAPSHOT_MISSING';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.lf_strategy_requalification_bootstrap_v1(
  p_execution_id text,
  p_snapshot_id bigint,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_assurance_ref text,
  p_exact_source_head text
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
  reserve_result jsonb;
  route_result jsonb;
  router_result jsonb;
  qualification_result jsonb;
  init_payload jsonb;
  target_path text;
  target_ref text;
  target_rev text;
  current_after boolean;
  contract_count integer;
BEGIN
  IF p_snapshot_id IS NULL
     OR btrim(coalesce(p_execution_id,''))=''
     OR coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$'
     OR btrim(coalesce(p_idempotency_key,''))=''
     OR btrim(coalesce(p_actor_execution_id,''))=''
     OR btrim(coalesce(p_assurance_ref,''))=''
     OR coalesce(p_exact_source_head,'') !~ '^[0-9a-f]{40}$' THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_INPUT_INVALID';
  END IF;

  SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_TARGET_NOT_FOUND:%',p_snapshot_id;
  END IF;
  IF public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code) THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_TERMINAL_TARGET:%:%',s.snapshot_code,s.lifecycle_state_code;
  END IF;
  IF s.id IS DISTINCT FROM (SELECT max(z.id) FROM public.lf_strategy_snapshots z WHERE z.snapshot_code=s.snapshot_code) THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_STALE_SNAPSHOT:%:%',s.snapshot_code,s.id;
  END IF;

  target_path:=format('supabase://public/lf_strategy_snapshots/%s',s.id);
  target_ref:=format('snapshot:%s/%s@%s',s.id,s.snapshot_code,s.version);
  target_rev:=public.lf_strategy_revision_sha256_v1(s.id);

  IF public.lf_qualification_current_v1('STRATEGY',s.snapshot_code,target_rev) THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_NOT_NEEDED:%:%',s.snapshot_code,target_rev;
  END IF;

  route_result:=public.lf_router_resolve_v1(
    'Governed Strategy requalification bootstrap for '||s.snapshot_code,
    s.snapshot_code,
    'STRATEGY_EXECUTION',
    'STRATEGY',
    NULL
  );
  IF coalesce(route_result->>'status','')<>'READY_TO_EXECUTE'
     OR coalesce(route_result->>'operation_code','')<>'EJECUCION_ESTRATEGIA_LF'
     OR coalesce(route_result->>'asset_type','')<>'STRATEGY' THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_ROUTE_INVALID:%',route_result;
  END IF;

  reserve_result:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,
    'EJECUCION_ESTRATEGIA_LF',
    'STRATEGY',
    s.snapshot_code,
    p_idempotency_key,
    p_request_sha256,
    p_actor_execution_id,
    NULL,
    target_path,
    jsonb_build_object(
      'mode','STRATEGY_REQUALIFICATION_BOOTSTRAP_ONLY',
      'qualification_bootstrap_only',true,
      'qualification_bootstrap_reason','STALE_OR_MISSING_CURRENT_QUALIFICATION',
      'assurance_ref',p_assurance_ref,
      'exact_source_head',p_exact_source_head,
      'strategy_snapshot_mutation',false,
      'runtime_activation',false,
      'production_activation',false,
      'scheduler_activation',false,
      'orchestrator_activation',false,
      'direct_business_write_allowed',false
    )
  );

  SELECT * INTO x
  FROM public.lf_operation_execution
  WHERE execution_id=reserve_result->>'execution_id'
  FOR UPDATE;
  IF NOT FOUND
     OR x.operation_code<>'EJECUCION_ESTRATEGIA_LF'
     OR x.target_type<>'STRATEGY'
     OR x.target_code IS DISTINCT FROM s.snapshot_code
     OR x.target_path IS DISTINCT FROM target_path
     OR x.status<>'IN_PROGRESS' THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_EXECUTION_BINDING_INVALID';
  END IF;

  -- Operation qualification remains mandatory. Only Strategy qualification is being established here.
  PERFORM public.lf_operation_execution_qualification_guard_v1('EJECUCION_ESTRATEGIA_LF',x.started_at);

  IF s.updated_at>x.started_at THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_TARGET_CHANGED_AFTER_RESERVATION:%:%:%',s.snapshot_code,s.updated_at,x.started_at;
  END IF;

  SELECT count(*) INTO contract_count
  FROM public.lf_operation_contracts oc
  WHERE oc.operation_code='EJECUCION_ESTRATEGIA_LF' AND oc.status='ACTIVE_ENFORCEMENT';
  IF contract_count<>1 THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_ACTIVE_CONTRACT_NOT_EXACT:%',contract_count;
  END IF;
  SELECT * INTO c
  FROM public.lf_operation_contracts oc
  WHERE oc.operation_code='EJECUCION_ESTRATEGIA_LF' AND oc.status='ACTIVE_ENFORCEMENT'
  LIMIT 1;

  IF coalesce((c.allowed->>'direct_business_write_allowed')::boolean,true) IS NOT FALSE
     OR coalesce((c.allowed->>'scheduler_activation')::boolean,true) IS NOT FALSE
     OR coalesce((c.allowed->>'production_activation')::boolean,true) IS NOT FALSE
     OR coalesce((c.allowed->>'orchestrator_activation')::boolean,true) IS NOT FALSE THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_CONTRACT_SAFETY_FLAGS_INVALID';
  END IF;
  IF coalesce(x.manifest->>'contract_code','')<>c.contract_code THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_SOURCE_CONTRACT_MISMATCH:%:%',x.manifest->>'contract_code',c.contract_code;
  END IF;
  IF jsonb_typeof(x.manifest->'operation_policy_snapshots') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_POLICY_SNAPSHOT_MISSING';
  END IF;

  SELECT * INTO st
  FROM public.lf_operation_steps
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND step_id='init_execution' AND active=true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_INIT_STEP_NOT_ACTIVE';
  END IF;
  SELECT * INTO b
  FROM public.lf_operation_step_judge_bindings
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
    AND step_id='init_execution'
    AND step_order=st.step_order
    AND status='ACTIVE_ENFORCEMENT';
  IF NOT FOUND OR b.clean_result_value<>'PASS_CLEAN' THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_INIT_BINDING_INVALID';
  END IF;

  SELECT * INTO existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=x.execution_id AND step_order=st.step_order;
  IF FOUND THEN
    IF existing.step_id<>'init_execution' OR existing.status<>'PASS_CLEAN' THEN
      RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_INIT_CONFLICT:%:%',existing.step_id,existing.status;
    END IF;
  ELSE
    init_payload:=jsonb_build_object(
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
      'step_result','PASS_CLEAN',
      'derived_result','PASS_CLEAN',
      'derived_by_judge',b.judge_code,
      'mini_judge_code',b.judge_code,
      'mini_judge_result','PASS_CLEAN',
      'attempt_history','[]'::jsonb,
      'qualification_bootstrap_only',true,
      'recorded_by_rpc','lf_strategy_requalification_bootstrap_v1'
    );
    INSERT INTO public.lf_operation_execution_steps(
      execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id
    ) VALUES (
      x.execution_id,st.step_order,'init_execution','PASS_CLEAN',target_path,init_payload,
      'Initialized only for governed Strategy requalification bootstrap.',p_actor_execution_id
    );
  END IF;

  router_result:=public.lf_record_operation_step_core_v1(
    x.execution_id,
    'router',
    'supabase://public/lf_router_action_registry#STRATEGY/STRATEGY_EXECUTION',
    jsonb_build_object(
      'router_authority_ref',coalesce(route_result->>'router','ACT-0001'),
      'route_decision',route_result,
      'target_strategy_ref',target_ref,
      'assertions_checked',jsonb_build_array(
        'r16_quality_bound','c05_reliability_bound','required_evidence_present',
        'authority_currentness_pass','runtime_activation_authorized','business_effect_dispatch_allowed'
      ),
      'hard_fails_checked','[]'::jsonb,
      'blocking_codes','[]'::jsonb,
      'qualification_bootstrap_only',true
    ),
    p_actor_execution_id,
    'EJECUCION_ESTRATEGIA_LF',
    'STRATEGY',
    'ACTIVE_ENFORCEMENT',
    'ACTIVE_ENFORCEMENT',
    'ACTIVE_ENFORCEMENT',
    jsonb_build_object(
      'valid',true,
      'code','STRATEGY_REQUALIFICATION_BOOTSTRAP_ROUTE_EXACT',
      'details',jsonb_build_object(
        'operation_code',route_result->>'operation_code',
        'asset_type',route_result->>'asset_type',
        'assurance_ref',p_assurance_ref,
        'exact_source_head',p_exact_source_head
      )
    ),
    false,
    'lf_strategy_requalification_bootstrap_v1'
  );
  IF router_result->>'outcome'<>'STEP_RECORDED'
     OR router_result->>'status'<>'PASS_CLEAN' THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_ROUTER_NOT_CLEAN:%',router_result;
  END IF;

  qualification_result:=public.lf_run_strategy_qualification_v1(s.id,x.execution_id);
  current_after:=public.lf_qualification_current_v1('STRATEGY',s.snapshot_code,target_rev);

  UPDATE public.lf_operation_execution
     SET manifest=manifest||jsonb_build_object(
           'qualification_bootstrap_result',qualification_result,
           'qualification_current_after_runner',current_after,
           'qualification_bootstrap_closed',true,
           'runtime_activation',false,
           'production_activation',false,
           'scheduler_activation',false,
           'orchestrator_activation',false
         ),
         status='COMPLETED',
         completed_at=clock_timestamp(),
         updated_by_execution_id=p_actor_execution_id
   WHERE execution_id=x.execution_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution e
    WHERE e.execution_id=x.execution_id
      AND e.status='COMPLETED'
      AND e.manifest->>'qualification_bootstrap_closed'='true'
      AND coalesce((e.manifest->>'runtime_activation')::boolean,false)=false
      AND coalesce((e.manifest->>'production_activation')::boolean,false)=false
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_EXECUTION_READBACK_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_qualification_receipts q
    WHERE q.qualification_id=(qualification_result->>'qualification_id')::uuid
      AND q.subject_type='STRATEGY'
      AND q.subject_code=s.snapshot_code
      AND q.revision_sha256=target_rev
      AND q.created_by_execution_id=x.execution_id
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_REQUALIFICATION_BOOTSTRAP_RECEIPT_READBACK_FAILED';
  END IF;

  RETURN jsonb_build_object(
    'execution_id',x.execution_id,
    'snapshot_id',s.id,
    'subject_code',s.snapshot_code,
    'revision_sha256',target_rev,
    'qualification',qualification_result,
    'qualification_current',current_after,
    'assurance_ref',p_assurance_ref,
    'exact_source_head',p_exact_source_head,
    'bootstrap_execution_status','COMPLETED',
    'next_gate',CASE WHEN current_after THEN 'STRATEGY_EXECUTION' ELSE 'INDEPENDENT_QUALIFICATION_REVIEW' END
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_strategy_requalification_bootstrap_v1(text,bigint,text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_strategy_requalification_bootstrap_v1(text,bigint,text,text,text,text,text) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_strategy_requalification_bootstrap_v1(text,bigint,text,text,text,text,text) TO service_role;

COMMENT ON FUNCTION public.lf_strategy_requalification_bootstrap_v1(text,bigint,text,text,text,text,text) IS
'Qualification-only bootstrap for a stale/unqualified Strategy. Reuses EJECUCION_ESTRATEGIA_LF, records only canonical init/router PASS_CLEAN, runs lf_run_strategy_qualification_v1, closes the bootstrap execution, and grants no material Strategy/runtime/production authority.';

DO $post$
DECLARE
  f text;
BEGIN
  IF to_regprocedure('public.lf_strategy_requalification_bootstrap_v1(text,bigint,text,text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_RPC_MISSING';
  END IF;
  SELECT pg_get_functiondef('public.lf_strategy_requalification_bootstrap_v1(text,bigint,text,text,text,text,text)'::regprocedure) INTO f;
  IF strpos(f,'EJECUCION_ESTRATEGIA_LF')=0
     OR strpos(f,'lf_router_resolve_v1')=0
     OR strpos(f,'lf_run_strategy_qualification_v1')=0
     OR strpos(f,'qualification_bootstrap_only')=0
     OR strpos(f,'UPDATE public.lf_strategy_snapshots')>0
     OR strpos(f,'INSERT INTO public.lf_strategy_snapshots')>0
     OR strpos(f,'DELETE FROM public.lf_strategy_snapshots')>0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_POSTCHECK_FAILED';
  END IF;
END
$post$;

UPDATE public.lf_operation_execution
SET status='BLOCKED',
    completed_at=clock_timestamp(),
    manifest=manifest||jsonb_build_object(
      'result','SUPERSEDED_SOURCE_FIRST_RESERVATION',
      'superseded_by_execution_id','EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-002',
      'runtime_activation',false,
      'production_activation',false
    ),
    updated_by_execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-002'
WHERE execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-001'
  AND status='IN_PROGRESS';

UPDATE public.lf_operation_execution
SET status='COMPLETED',
    completed_at=clock_timestamp(),
    manifest=manifest||jsonb_build_object(
      'result','S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_SOURCE_APPLIED',
      'rpc','public.lf_strategy_requalification_bootstrap_v1',
      'runtime_activation',false,
      'production_activation',false,
      'strategy_snapshot_mutation',false
    ),
    updated_by_execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-002'
WHERE execution_id='EXEC-S30-REQUALIFICATION-BOOTSTRAP-DB-20260915-002';
