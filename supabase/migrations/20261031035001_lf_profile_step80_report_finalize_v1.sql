-- Governed finalizer for EJECUCION_PERFIL_LF report_output and current step-80 materialization.
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_report_v1(
  p_execution_id text,
  p_evidence_ref text,
  p_actor_execution_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_semantic public.lf_operation_execution_steps%rowtype;
  v_existing text;
  v_actor text;
  v_candidate text;
  v_scope text;
  v_semantic_receipt text;
  v_step jsonb;
  v_clean integer;
  v_terminal jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_INPUT_INVALID');
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status NOT IN ('IN_PROGRESS','COMPLETED')
     OR NOT COALESCE(
       (e.manifest->>'executor_mode'='GPT_NATIVE'
        AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE')
       OR
       (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false
     )
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXECUTION_INVALID');
  END IF;

  SELECT * INTO v_semantic
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='semantic_judge'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_semantic.step_id IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_SEMANTIC_NOT_CLEAN');
  END IF;

  v_candidate:=v_semantic.evidence_payload#>>'{semantic_judge_result,candidate_sha256}';
  v_scope:=v_semantic.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}';
  v_semantic_receipt:=v_semantic.evidence_payload->>'independent_semantic_receipt_ref';

  IF coalesce(v_candidate,'') !~ '^[0-9a-f]{64}$'
     OR coalesce(v_scope,'') !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_SEMANTIC_BINDING_INVALID');
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='report_output';

  IF v_existing IS NULL THEN
    IF e.status<>'IN_PROGRESS' THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXECUTION_ALREADY_CLOSED_WITHOUT_REPORT');
    END IF;
    v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'report_output',
      p_evidence_ref,
      jsonb_build_object(
        'result','PASS_INDEPENDENT_SEMANTIC',
        'execution_id',p_execution_id,
        'profile_code',e.target_code,
        'no_write_performed',true,
        'candidate_sha256',v_candidate,
        'scope_packet_sha256',v_scope,
        'independent_semantic_receipt_ref',v_semantic_receipt,
        'next_gate','RETURN_TO_ROUTER'
      ),
      v_actor
    );
    IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_RECORD_REJECTED',
        'recorder_result',v_step
      );
    END IF;
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXISTING_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF v_clean<>11 OR e.status<>'COMPLETED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_COMPLETION_NOT_CLEAN',
      'clean_step_count',v_clean,
      'execution_status',e.status
    );
  END IF;

  v_terminal:=public.lf_profile_execution_terminal_authority_receipt_v1(p_execution_id);
  IF v_terminal->>'status' IS DISTINCT FROM 'READY' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_TERMINAL_RECEIPT_NOT_READY',
      'terminal_result',v_terminal
    );
  END IF;

  RETURN jsonb_build_object(
    'status','PROFILE_EXECUTION_COMPLETED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'clean_step_count',v_clean,
    'last_completed_step','report_output',
    'execution_status',e.status,
    'terminal_authority_receipt_sha256',v_terminal->>'terminal_authority_receipt_sha256',
    'next_gate','RETURN_TO_ROUTER'
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_native_bridge_record_report_v1(text,text,text)
FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_native_bridge_record_report_v1(text,text,text)
TO service_role;

COMMENT ON FUNCTION public.lf_profile_native_bridge_record_report_v1(text,text,text) IS
'Governed finalizer for EJECUCION_PERFIL_LF report_output. Derives semantic hashes from the persisted semantic_judge, delegates to the canonical recorder, requires 11/11 clean steps, COMPLETED execution, and READY terminal authority receipt.';

DO $step80$
DECLARE
  v_execution_id text := 'EXEC-PROFILE-GATE2-103C8E016D6F6B6ACABEA975';
  v_ref text := 'supabase://public.lf_operation_execution_steps/EXEC-PROFILE-GATE2-103C8E016D6F6B6ACABEA975/report_output';
  v_result jsonb;
  v_status text;
  v_execution_status text;
  v_terminal jsonb;
BEGIN
  v_result:=public.lf_profile_native_bridge_record_report_v1(
    v_execution_id,v_ref,v_execution_id
  );

  IF v_result->>'status' IS DISTINCT FROM 'PROFILE_EXECUTION_COMPLETED'
     OR coalesce((v_result->>'clean_step_count')::integer,0)<>11
     OR v_result->>'execution_status' IS DISTINCT FROM 'COMPLETED' THEN
    RAISE EXCEPTION 'PROFILE_STEP80_FINALIZE_FAILED:%',v_result;
  END IF;

  SELECT status INTO v_status
  FROM public.lf_operation_execution_steps
  WHERE execution_id=v_execution_id AND step_id='report_output';

  SELECT status INTO v_execution_status
  FROM public.lf_operation_execution
  WHERE execution_id=v_execution_id;

  IF v_status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
     OR v_execution_status IS DISTINCT FROM 'COMPLETED' THEN
    RAISE EXCEPTION 'PROFILE_STEP80_READBACK_FAILED:step=% execution=%',
      coalesce(v_status,'<missing>'),coalesce(v_execution_status,'<missing>');
  END IF;

  v_terminal:=public.lf_profile_execution_terminal_authority_receipt_v1(v_execution_id);
  IF v_terminal->>'status' IS DISTINCT FROM 'READY'
     OR nullif(v_terminal->>'terminal_authority_receipt_sha256','') IS NULL THEN
    RAISE EXCEPTION 'PROFILE_STEP80_TERMINAL_RECEIPT_FAILED:%',v_terminal;
  END IF;
END
$step80$;
