-- S30 transversal remediation: Strategy Update must not require runtime_state=NO_HABILITADO.
-- Keep fail-closed: only candidate/read-only strategies, safe runtime/impact envelope, and no state mutation.

DO $pre$
DECLARE
  v_exec public.lf_operation_execution%rowtype;
  v_def text;
  c integer;
BEGIN
  SELECT * INTO v_exec FROM public.lf_operation_execution
  WHERE execution_id='EXEC-S30-REMEDIATION-STRATEGY-UPDATE-STATE-ENVELOPE-20260914-001';
  IF NOT FOUND
     OR v_exec.operation_code<>'ACTUALIZACION_DB_LF'
     OR v_exec.status<>'IN_PROGRESS'
     OR v_exec.target_type<>'FUNCTION'
     OR v_exec.target_code<>'LF_STRATEGY_UPDATE_WRITE_V1_STATE_ENVELOPE_V2' THEN
    RAISE EXCEPTION 'S30_STRATEGY_UPDATE_REMEDIATION_EXECUTION_BINDING_INVALID';
  END IF;

  SELECT count(*) INTO c FROM public.lf_operation_registry
  WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND status='SANDBOX_ACTIVE';
  IF c<>1 THEN RAISE EXCEPTION 'S30_STRATEGY_UPDATE_OPERATION_NOT_SANDBOX_ACTIVE:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_router_action_registry
  WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND status='ACTIVE' AND write_allowed;
  IF c<1 THEN RAISE EXCEPTION 'S30_STRATEGY_UPDATE_ROUTER_NOT_ACTIVE'; END IF;

  SELECT pg_get_functiondef('public.lf_strategy_update_write_v1(text,bigint,text,jsonb)'::regprocedure) INTO v_def;
  IF strpos(v_def,$old$s.runtime_state<>'NO_HABILITADO' or s.impact_policy<>'BLOQUEADO'$old$)=0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_UPDATE_SOURCE_DRIFT_OLD_CEILING_NOT_FOUND';
  END IF;
  IF strpos(v_def,$new$s.runtime_state not in ('NO_HABILITADO','PLAN_ONLY')$new$)>0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_UPDATE_STATE_ENVELOPE_ALREADY_PRESENT_UNEXPECTED';
  END IF;
END
$pre$;

DO $function_patch$
DECLARE
  v_def text;
  v_new text;
  v_old_fragment text := $old$s.runtime_state<>'NO_HABILITADO' or s.impact_policy<>'BLOQUEADO'$old$;
  v_new_fragment text := $new$s.runtime_state not in ('NO_HABILITADO','PLAN_ONLY') or s.impact_policy not in ('BLOQUEADO','NO_AUTOMATIC_PROMOTION')$new$;
BEGIN
  SELECT pg_get_functiondef('public.lf_strategy_update_write_v1(text,bigint,text,jsonb)'::regprocedure) INTO v_def;
  IF strpos(v_def,v_old_fragment)=0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_UPDATE_FUNCTION_PATCH_SOURCE_DRIFT';
  END IF;
  v_new:=replace(v_def,v_old_fragment,v_new_fragment);
  EXECUTE v_new;
END
$function_patch$;

UPDATE public.lf_operation_contracts
SET allowed=(coalesce(allowed,'{}'::jsonb)
      || jsonb_build_object(
          'candidate_read_only_only',true,
          'allowed_runtime_states',jsonb_build_array('NO_HABILITADO','PLAN_ONLY'),
          'allowed_impact_policies',jsonb_build_array('BLOQUEADO','NO_AUTOMATIC_PROMOTION'),
          'state_mutation',false,
          'runtime_change',false,
          'production_change',false,
          'plan_only_progress_update',true
      )),
    updated_by_execution_id='EXEC-S30-REMEDIATION-STRATEGY-UPDATE-STATE-ENVELOPE-20260914-001',
    updated_at=now()
WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF'
  AND status='ACTIVE_ENFORCEMENT';

DO $rollback_canary$
DECLARE
  s public.lf_strategy_snapshots%rowtype;
  v_result jsonb;
  v_reserve jsonb;
  v_before_sha text;
  v_after_sha text;
BEGIN
  SELECT * INTO s
  FROM public.lf_strategy_snapshots
  WHERE id=35
    AND status='CANDIDATO_READ_ONLY'
    AND visibility='READ_ONLY_INTERNAL'
    AND runtime_state='PLAN_ONLY'
    AND impact_policy='BLOQUEADO'
    AND jsonb_typeof(metadata->'progress')='object'
    AND metadata->'progress'->>'contract_version'='STRATEGY_PROGRESS_CONTRACT_V1'
    AND coalesce(metadata->'strategy_close'->>'status','')<>'CLOSED';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'S30_STRATEGY_UPDATE_PLAN_ONLY_CANARY_FIXTURE_INVALID';
  END IF;

  v_before_sha:=encode(extensions.digest(to_jsonb(s)::text,'sha256'),'hex');

  BEGIN
    v_reserve:=public.fn_lf_operation_reserve_execution_v1(
      'EXEC-S30-REMEDIATION-STRATEGY-UPDATE-PLANONLY-CANARY-20260914-001',
      'ACTUALIZACION_ESTRATEGIA_LF',
      'STRATEGY',
      s.snapshot_code,
      'S30:REMEDIATION:STRATEGY_UPDATE:PLAN_ONLY:ROLLBACK_CANARY:20260914:001',
      encode(extensions.digest('S30_STRATEGY_UPDATE_PLAN_ONLY_ROLLBACK_CANARY_V1','sha256'),'hex'),
      'EXEC-S30-REMEDIATION-STRATEGY-UPDATE-PLANONLY-CANARY-20260914-001',
      'cristhianlujan/claude-persona-lf-patch',
      format('supabase://public/lf_strategy_snapshots/%s',s.id),
      jsonb_build_object(
        'scope','ROLLBACK_CANARY_PLAN_ONLY_STATE_ENVELOPE',
        'production_allowed',false,
        'runtime_activation',false,
        'persistent_strategy_mutation_allowed',false
      )
    );

    IF v_reserve->>'result'<>'RESERVED_NEW_EXECUTION' THEN
      RAISE EXCEPTION 'S30_STRATEGY_UPDATE_PLAN_ONLY_CANARY_RESERVATION_FAIL:%',v_reserve;
    END IF;

    v_result:=public.lf_strategy_update_write_v1(
      'EXEC-S30-REMEDIATION-STRATEGY-UPDATE-PLANONLY-CANARY-20260914-001',
      s.id,
      v_before_sha,
      jsonb_build_object(
        'progress',s.metadata->'progress',
        'metadata_merge','{}'::jsonb,
        'backlog',coalesce(s.backlog,'[]'::jsonb),
        'evidence_refs_append',jsonb_build_array(jsonb_build_object(
          'type','S30_STRATEGY_UPDATE_PLAN_ONLY_ROLLBACK_CANARY',
          'persistent',false
        )),
        'change_log_append',jsonb_build_array(jsonb_build_object(
          'change_type','S30_STRATEGY_UPDATE_PLAN_ONLY_ROLLBACK_CANARY',
          'persistent',false
        ))
      )
    );

    IF v_result->>'result'<>'STRATEGY_UPDATED_WITH_EVIDENCE'
       OR coalesce((v_result->>'status_runtime_impact_preserved')::boolean,false) IS NOT TRUE THEN
      RAISE EXCEPTION 'S30_STRATEGY_UPDATE_PLAN_ONLY_CANARY_RESULT_FAIL:%',v_result;
    END IF;

    RAISE EXCEPTION USING ERRCODE='P0C01', MESSAGE='S30_INTENTIONAL_PLAN_ONLY_CANARY_ROLLBACK';
  EXCEPTION WHEN SQLSTATE 'P0C01' THEN
    NULL;
  END;

  IF v_result IS NULL OR v_result->>'result'<>'STRATEGY_UPDATED_WITH_EVIDENCE' THEN
    RAISE EXCEPTION 'S30_STRATEGY_UPDATE_PLAN_ONLY_CANARY_NO_SUCCESS_RECEIPT';
  END IF;

  SELECT encode(extensions.digest(to_jsonb(x)::text,'sha256'),'hex') INTO v_after_sha
  FROM public.lf_strategy_snapshots x WHERE x.id=s.id;
  IF v_after_sha IS DISTINCT FROM v_before_sha THEN
    RAISE EXCEPTION 'S30_STRATEGY_UPDATE_PLAN_ONLY_CANARY_ROLLBACK_FAILED:%:%',v_before_sha,v_after_sha;
  END IF;
END
$rollback_canary$;

DO $post$
DECLARE
  v_def text;
  c integer;
  v_allowed jsonb;
BEGIN
  SELECT pg_get_functiondef('public.lf_strategy_update_write_v1(text,bigint,text,jsonb)'::regprocedure) INTO v_def;
  IF strpos(v_def,$new$s.runtime_state not in ('NO_HABILITADO','PLAN_ONLY') or s.impact_policy not in ('BLOQUEADO','NO_AUTOMATIC_PROMOTION')$new$)=0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_UPDATE_POST_FUNCTION_ENVELOPE_MISSING';
  END IF;
  IF strpos(v_def,$old$s.runtime_state<>'NO_HABILITADO' or s.impact_policy<>'BLOQUEADO'$old$)>0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_UPDATE_POST_OLD_SINGLE_STATE_CEILING_REMAINS';
  END IF;

  SELECT count(*) INTO c
  FROM public.lf_operation_contracts
  WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';
  IF c<>1 THEN RAISE EXCEPTION 'S30_STRATEGY_UPDATE_POST_ACTIVE_CONTRACT_COUNT:%',c; END IF;

  SELECT allowed INTO v_allowed
  FROM public.lf_operation_contracts
  WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT'
  LIMIT 1;
  IF v_allowed->'allowed_runtime_states'<>jsonb_build_array('NO_HABILITADO','PLAN_ONLY')
     OR v_allowed->'allowed_impact_policies'<>jsonb_build_array('BLOQUEADO','NO_AUTOMATIC_PROMOTION')
     OR coalesce((v_allowed->>'state_mutation')::boolean,true) IS NOT FALSE THEN
    RAISE EXCEPTION 'S30_STRATEGY_UPDATE_POST_CONTRACT_ENVELOPE_FAIL:%',v_allowed;
  END IF;
END
$post$;

UPDATE public.lf_operation_execution
SET manifest=manifest || jsonb_build_object(
      'result','STRATEGY_UPDATE_SAFE_STATE_ENVELOPE_APPLIED',
      'allowed_runtime_states',jsonb_build_array('NO_HABILITADO','PLAN_ONLY'),
      'allowed_impact_policies',jsonb_build_array('BLOQUEADO','NO_AUTOMATIC_PROMOTION'),
      'state_mutation_allowed',false,
      'plan_only_rollback_canary','PASS_NO_PERSISTENT_MUTATION',
      'production_allowed',false,
      'runtime_activation',false
    ),
    status='COMPLETED',
    completed_at=clock_timestamp(),
    updated_by_execution_id='EXEC-S30-REMEDIATION-STRATEGY-UPDATE-STATE-ENVELOPE-20260914-001',
    updated_at=clock_timestamp()
WHERE execution_id='EXEC-S30-REMEDIATION-STRATEGY-UPDATE-STATE-ENVELOPE-20260914-001';