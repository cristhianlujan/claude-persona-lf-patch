-- EJECUCION_PERFIL_LF -> Input Governance internal runtime continuation.
-- Scope: connect the already-approved RETURN_TO_WORKER contract to the existing
-- IG direct SQL worker. Router and IG Curator/Validator internals are unchanged.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'programacion.fn_input_governance_queue_submit_v1(integer,text)'::regprocedure
     )) <> 'c7134df7002db1bfc4f9dc3d28ad838f' THEN
    RAISE EXCEPTION 'PROFILE_IG_CONTEXT_PACK_QUEUE_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure
     )) <> '5b1f19f5260deef2a0c095366240224a' THEN
    RAISE EXCEPTION 'PROFILE_IG_INPUT_VALIDATE_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
     )) <> '2f680818cac7939deedb168d995ac9d4' THEN
    RAISE EXCEPTION 'PROFILE_IG_NATIVE_BRIDGE_SOURCE_DRIFT';
  END IF;
END
$precheck$;

DO $patch_queue$
DECLARE
  d text;
  old_text text := $old$p_consumer not in ('STORY_CREATOR','MANUAL')$old$;
  new_text text := $new$p_consumer not in ('STORY_CREATOR','CONTEXT_PACK','MANUAL')$new$;
BEGIN
  d:=pg_get_functiondef(
    'programacion.fn_input_governance_queue_submit_v1(integer,text)'::regprocedure
  );

  IF (length(d)-length(replace(d,old_text,'')))/length(old_text)<>1 THEN
    RAISE EXCEPTION 'PROFILE_IG_CONTEXT_PACK_QUEUE_ANCHOR_DRIFT';
  END IF;

  d:=replace(d,old_text,new_text);
  EXECUTE d;
END
$patch_queue$;

DO $patch_input_validate$
DECLARE
  d text;
  old_block text := $old$
  IF coalesce((v_ig->>'applicable')::boolean,false)
     AND coalesce((v_ig->>'continuation_allowed')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
$old$;
  new_block text := $new$
  IF coalesce((v_ig->>'applicable')::boolean,false)
     AND coalesce((v_ig->>'continuation_allowed')::boolean,false) IS NOT TRUE THEN

    IF v_ig->>'status'='INPUT_GOVERNANCE_REQUIRED'
       AND v_ig->>'decision'='PENDING'
       AND v_ig->>'consumer'='CONTEXT_PACK'
       AND coalesce(v_ig->>'pantalla_id','') ~ '^[0-9]+$'
    THEN
      v_ig:=v_ig||jsonb_build_object(
        'dispatch',
        programacion.fn_input_governance_queue_submit_v1(
          (v_ig->>'pantalla_id')::integer,
          'CONTEXT_PACK'
        ),
        'dispatch_owner','INPUT_GOVERNANCE_INTERNAL_RUNTIME',
        'dispatch_transport','POSTGRES_SQL_WORKER:ig-direct-sql-worker-v1'
      );
    END IF;

    RETURN jsonb_build_object(
$new$;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure
  );

  IF (length(d)-length(replace(d,old_block,'')))/length(old_block)<>1 THEN
    RAISE EXCEPTION 'PROFILE_IG_INPUT_VALIDATE_ANCHOR_DRIFT';
  END IF;

  d:=replace(d,old_block,new_block);
  EXECUTE d;
END
$patch_input_validate$;

DO $patch_native_bridge$
DECLARE
  d text;
  old_block text := $old$
    IF v_input->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status',coalesce(v_input->>'status','BLOCKED'),
        'blocking_code',coalesce(
          v_input->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_INPUT_VALIDATE_NOT_READY'
        ),
        'execution_id',p_execution_id,
        'input_validate',v_input,
        'router_reentry_required',false
      );
    END IF;
$old$;
  new_block text := $new$
    IF v_input->>'status'<>'READY' THEN
      IF v_input->>'status'='INPUT_GOVERNANCE_REQUIRED'
         AND v_input->>'next_action'='RETRY_INPUT_VALIDATE_AFTER_INPUT_GOVERNANCE'
         AND v_input#>>'{input_governance,dispatch,status}'='QUEUED'
      THEN
        RETURN jsonb_build_object(
          'status','INPUT_GOVERNANCE_PENDING',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'input_validate',v_input,
          'input_governance_request_id',
            v_input#>'{input_governance,dispatch,request_id}',
          'input_governance_transport',
            v_input#>>'{input_governance,dispatch_transport}',
          'next_action','RETRY_SAME_NATIVE_BRIDGE_PREPARE',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        );
      END IF;

      RETURN jsonb_build_object(
        'status',coalesce(v_input->>'status','BLOCKED'),
        'blocking_code',coalesce(
          v_input->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_INPUT_VALIDATE_NOT_READY'
        ),
        'execution_id',p_execution_id,
        'input_validate',v_input,
        'router_reentry_required',false
      );
    END IF;
$new$;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
  );

  IF (length(d)-length(replace(d,old_block,'')))/length(old_block)<>1 THEN
    RAISE EXCEPTION 'PROFILE_IG_NATIVE_BRIDGE_ANCHOR_DRIFT';
  END IF;

  d:=replace(d,old_block,new_block);
  EXECUTE d;
END
$patch_native_bridge$;

COMMENT ON FUNCTION programacion.fn_input_governance_queue_submit_v1(integer,text) IS
'Internal Input Governance direct-worker queue. Accepts STORY_CREATOR, CONTEXT_PACK and MANUAL consumers authorized by INPUT_GOVERNANCE_EXECUTION_CONTRACT. Curator/Validator orchestration remains owned by Input Governance.';

COMMENT ON FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb) IS
'Validates authorized profile input. When task-bound CONTEXT_PACK Input Governance requires its own runtime, this step dispatches the existing IG internal worker and remains inside EJECUCION_PERFIL_LF; it never re-enters ACT-0001 for that continuation.';

COMMENT ON FUNCTION public.lf_profile_native_bridge_prepare_v1(text,text,text,text) IS
'Prepares governed GPT_NATIVE profile execution. If Input Governance is internally queued, returns INPUT_GOVERNANCE_PENDING and asks the same native bridge to retry; Router is not re-entered and IG Curator/Validator remain internal to Input Governance.';

DO $postcheck$
DECLARE
  q jsonb;
  qid bigint;
  queue_src text;
  validate_src text;
  bridge_src text;
BEGIN
  -- Prove CONTEXT_PACK is accepted by the existing IG queue without leaving residue.
  BEGIN
    q:=programacion.fn_input_governance_queue_submit_v1(51,'CONTEXT_PACK');
    qid:=nullif(q->>'request_id','')::bigint;

    IF q->>'status' IS DISTINCT FROM 'QUEUED'
       OR q->>'consumer' IS DISTINCT FROM 'CONTEXT_PACK'
       OR qid IS NULL
       OR NOT EXISTS(
         SELECT 1
         FROM programacion.ig_direct_requests_v1
         WHERE id=qid
           AND pantalla_id=51
           AND consumer='CONTEXT_PACK'
           AND status='QUEUED'
       )
    THEN
      RAISE EXCEPTION 'PROFILE_IG_CONTEXT_PACK_QUEUE_POSTCHECK_FAIL:%',q;
    END IF;

    RAISE EXCEPTION USING
      ERRCODE='PZ171',
      MESSAGE='PROFILE_IG_CONTEXT_PACK_QUEUE_ROLLBACK_SENTINEL';
  EXCEPTION
    WHEN SQLSTATE 'PZ171' THEN
      NULL;
  END;

  IF EXISTS(
    SELECT 1
    FROM programacion.ig_direct_requests_v1
    WHERE id=qid
  ) THEN
    RAISE EXCEPTION 'PROFILE_IG_CONTEXT_PACK_QUEUE_ROLLBACK_RESIDUE:%',qid;
  END IF;

  queue_src:=pg_get_functiondef(
    'programacion.fn_input_governance_queue_submit_v1(integer,text)'::regprocedure
  );
  validate_src:=pg_get_functiondef(
    'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure
  );
  bridge_src:=pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
  );

  IF strpos(queue_src,'''CONTEXT_PACK''')=0
     OR strpos(validate_src,'fn_input_governance_queue_submit_v1')=0
     OR strpos(validate_src,'''dispatch_owner'',''INPUT_GOVERNANCE_INTERNAL_RUNTIME''')=0
     OR strpos(validate_src,'''router_reentry_required'',false')=0
     OR strpos(bridge_src,'''INPUT_GOVERNANCE_PENDING''')=0
     OR strpos(bridge_src,'''RETRY_SAME_NATIVE_BRIDGE_PREPARE''')=0
     OR strpos(bridge_src,'''EJECUCION_PERFIL_LF/input_validate''')=0
  THEN
    RAISE EXCEPTION 'PROFILE_IG_CONTEXT_PACK_SOURCE_POSTCHECK_FAIL';
  END IF;

  IF strpos(validate_src,'lf_router_resolve_v1')>0
     OR strpos(bridge_src,'lf_router_resolve_v1')>0
  THEN
    RAISE EXCEPTION 'PROFILE_IG_CONTEXT_PACK_ROUTER_REENTRY_REGRESSION';
  END IF;
END
$postcheck$;

COMMIT;
