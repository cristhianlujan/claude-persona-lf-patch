-- LIVE prepatch pg_get_functiondef captured for E10/E3 PG dual source-bound behavior.
CREATE OR REPLACE FUNCTION public.lf_profile_execution_begin_from_handoff_v1(p_handoff jsonb, p_executor_mode text, p_execution_id text, p_idempotency_key text, p_actor_execution_id text, p_target_repo text, p_target_path text, p_manifest jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_valid jsonb;
  v_admission jsonb;
  v_begin jsonb;
  v_step jsonb;
  v_profile text:=p_handoff->>'profile_code';
  v_literal text:=p_handoff->>'literal_request';
  v_mode text:=upper(nullif(btrim(coalesce(p_executor_mode,'')),'')); 
  v_provider text;
  v_existing text;
  v_repair_write boolean:=false;
BEGIN
  v_valid:=public.lf_router_profile_execution_handoff_validate_v1(
    p_handoff,v_literal,v_profile
  );

  IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_EXECUTION_HANDOFF_INVALID',
      'handoff_validation',v_valid
    );
  END IF;

  v_admission:=public.lf_profile_execution_executor_admission_v1(
    v_profile,v_mode
  );

  IF coalesce((v_admission->>'admitted')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_EXECUTOR_NOT_ADMITTED',
      'executor_admission',v_admission
    );
  END IF;

  v_repair_write:=coalesce(
    (v_valid->>'governed_repair_write_allowed')::boolean,
    false
  );

  v_provider:=case v_mode
    when 'GPT_NATIVE' then 'OPENAI_CHATGPT_NATIVE'
    when 'CLAUDE_NATIVE' then 'ANTHROPIC_CLAUDE_NATIVE'
    else null
  end;

  v_begin:=public.lf_profile_execution_begin_v1(
    p_execution_id,
    p_idempotency_key,
    p_handoff->>'request_sha256',
    p_actor_execution_id,
    v_profile,
    p_target_repo,
    p_target_path,
    coalesce(p_manifest,'{}'::jsonb)
      ||jsonb_build_object(
        'executor_mode',v_mode,
        'executor_provider',v_provider,
        'router_profile_handoff',p_handoff,
        'router_authority_receipt',
          p_handoff->'router_authorization_receipt',
        'repair_execution_authority',
          p_handoff->'repair_execution_authority',
        'input_sha256','sha256:'||(p_handoff->>'request_sha256'),
        'read_only',not v_repair_write,
        'no_write',not v_repair_write,
        'governed_repair_write',v_repair_write,
        'readback_required',v_repair_write,
        'rollback_required',v_repair_write,
        'no_promotion',true,
        'automatic_impact',false
      )
  );

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='router';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'router',
      'router-authorization://'
        ||(p_handoff#>>'{router_authorization_receipt,fingerprint_sha256}'),
      jsonb_build_object(
        'router_read','AUTHORIZED_HANDOFF_RECEIPT_VALIDATED',
        'action','PROFILE_EXECUTION',
        'router_authorization_receipt',
          p_handoff->'router_authorization_receipt',
        'repair_execution_authority',
          p_handoff->'repair_execution_authority',
        'governed_repair_write',v_repair_write,
        'semantic_request',p_handoff->'semantic_request',
        'semantic_result',p_handoff->'semantic_result',
        'handoff_fingerprint_sha256',
          p_handoff->>'fingerprint_sha256',
        'channel',p_handoff->>'channel',
        'business',p_handoff->>'business',
        'reentered_router',false
      ),
      p_actor_execution_id
    );
  ELSE
    v_step:=jsonb_build_object(
      'outcome','STEP_ALREADY_PRESENT',
      'status',v_existing
    );
  END IF;

  RETURN v_begin||jsonb_build_object(
    'status','READY',
    'router_handoff_validated',true,
    'router_authorization_carried_forward',true,
    'governed_repair_write',v_repair_write,
    'repair_execution_authority',
      p_handoff->'repair_execution_authority',
    'router_step',v_step,
    'next_step','profile_resolve',
    'reentered_router',false
  );
END
$function$
;
