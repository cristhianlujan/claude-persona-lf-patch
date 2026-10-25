BEGIN;

CREATE OR REPLACE FUNCTION public.lf_profile_result_router_return_classify_v1(
  p_profile_output jsonb,
  p_original_request text,
  p_execution_id text,
  p_profile_code text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  v_output_type text:=upper(coalesce(p_profile_output->>'output_type',''));
  v_pipeline_action text:=upper(coalesce(p_profile_output->>'pipeline_action',''));
  v_verdict text:=upper(coalesce(p_profile_output->>'verdict',''));
  v_status text:=upper(coalesce(p_profile_output->>'status',''));
  v_self_verdict text:=upper(coalesce(p_profile_output->>'self_verdict',''));
  v_routing jsonb:=coalesce(p_profile_output->'routing','null'::jsonb);
  v_redirect_kind text;
  v_payload jsonb;
  v_stage1_literal text;
  v_untyped_unresolved boolean:=false;
BEGIN
  IF jsonb_typeof(p_profile_output)<>'object'
     OR nullif(btrim(coalesce(p_original_request,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_ROUTER_RETURN_INPUT_INVALID'
    );
  END IF;

  IF p_profile_output ? 'target_profile'
     OR (
       jsonb_typeof(v_routing)='object'
       AND v_routing ? 'target_profile'
     )
     OR (
       jsonb_typeof(p_profile_output->'safe_next_gate')='object'
       AND (p_profile_output->'safe_next_gate') ? 'target_profile'
     )
     OR (
       jsonb_typeof(p_profile_output->'handoff_to_next')='object'
       AND (p_profile_output->'handoff_to_next') ? 'target_profile'
     )
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_DIRECT_TARGET_PROFILE_FORBIDDEN',
      'source_execution_id',p_execution_id,
      'source_profile_code',p_profile_code
    );
  END IF;

  IF v_output_type='PRODUCT_MISSING_INPUT_STATE' THEN
    IF jsonb_typeof(p_profile_output->'missing_fields')<>'array'
       OR jsonb_array_length(p_profile_output->'missing_fields')=0
       OR jsonb_typeof(p_profile_output->'why_required')<>'array'
       OR jsonb_array_length(p_profile_output->'why_required')=0
       OR jsonb_typeof(p_profile_output->'risk_if_assumed')<>'array'
       OR jsonb_array_length(p_profile_output->'risk_if_assumed')=0
       OR jsonb_typeof(p_profile_output->'safe_next_gate')<>'object'
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_PRODUCT_MISSING_INPUT_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:='PRODUCT_MISSING_INPUT_STATE';
    v_payload:=jsonb_build_object(
      'missing_fields',p_profile_output->'missing_fields',
      'why_required',p_profile_output->'why_required',
      'risk_if_assumed',p_profile_output->'risk_if_assumed',
      'safe_next_gate',p_profile_output->'safe_next_gate'
    );

  ELSIF v_output_type='FRONTEND_MISSING_INPUT_STATE'
        OR v_pipeline_action='RETURN_TO_ORCHESTRATOR' THEN

    IF v_pipeline_action<>'RETURN_TO_ORCHESTRATOR'
       OR nullif(btrim(coalesce(p_profile_output->>'question_to_orchestrator','')),'') IS NULL
       OR jsonb_typeof(p_profile_output->'missing_fields')<>'array'
       OR jsonb_array_length(p_profile_output->'missing_fields')=0
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_RETURN_TO_ORCHESTRATOR_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:=case
      when v_output_type<>'' then v_output_type
      else 'GENERIC_RETURN_TO_ORCHESTRATOR'
    end;

    v_payload:=jsonb_build_object(
      'missing_fields',p_profile_output->'missing_fields',
      'resolved_from_context',coalesce(p_profile_output->'resolved_from_context','[]'::jsonb),
      'conflicts_detected',coalesce(p_profile_output->'conflicts_detected','[]'::jsonb),
      'why_required',coalesce(p_profile_output->'why_required','[]'::jsonb),
      'risk_if_assumed',coalesce(p_profile_output->'risk_if_assumed','[]'::jsonb),
      'resolution_target',p_profile_output->>'resolution_target',
      'question_to_orchestrator',p_profile_output->>'question_to_orchestrator'
    );

  ELSIF jsonb_typeof(v_routing)='object'
        AND upper(coalesce(v_routing->>'pipeline_action',''))='RETURN_TO_ORCHESTRATOR' THEN

    IF upper(coalesce(v_routing->>'via',''))<>'ORCHESTRATOR'
       OR upper(coalesce(v_routing->>'resolution_target','')) NOT IN (
         'PRODUCER_REPAIR',
         'AUTHORITY_OR_CONTEXT_RESOLUTION'
       )
       OR v_verdict NOT IN (
         'RETURN_TO_WORKER_FOR_SELF_REPAIR',
         'RETURN_TO_ORCHESTRATOR'
       )
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_QUALITY_ROUTING_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:='QUALITY_ROUTING_REDIRECT';
    v_payload:=jsonb_build_object(
      'verdict',v_verdict,
      'routing',v_routing,
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'repair_actions',coalesce(p_profile_output->'repair_actions','[]'::jsonb),
      'remaining_risks',coalesce(p_profile_output->'remaining_risks','[]'::jsonb),
      'next_gate',p_profile_output->>'next_gate'
    );
  END IF;

  IF v_redirect_kind IS NOT NULL THEN
    v_stage1_literal:=
      'Solicitud original: '||p_original_request
      ||E'\n\nRetorno gobernado del perfil '
      ||p_profile_code
      ||': '
      ||v_payload::text;

    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','RETURN_TO_ROUTER',
      'code','PROFILE_RESULT_TYPED_RETURN_TO_ORCHESTRATOR',
      'source_execution_id',p_execution_id,
      'source_profile_code',p_profile_code,
      'redirect_kind',v_redirect_kind,
      'router_return_request',jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_REQUEST_V1',
        'pipeline_action','RETURN_TO_ORCHESTRATOR',
        'route_policy','REPEAT_FULL_ROUTER_FLOW',
        'next_entrypoint','ACT-0001_STAGE1',
        'stage1_required',true,
        'reuse_prior_profile_selection',false,
        'prior_profile_is_advisory_only',true,
        'direct_profile_invocation_allowed',false,
        'original_request',p_original_request,
        'stage1_literal',v_stage1_literal,
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code,
        'unresolved_contract_type',v_redirect_kind,
        'unresolved_payload',v_payload,
        'advisory_profiles',coalesce(
          p_profile_output#>'{deliverable_created,profiles_to_activate}',
          '[]'::jsonb
        )
      ),
      'next_action','REENTER_ROUTER_STAGE1'
    );
  END IF;

  v_untyped_unresolved:=
       v_self_verdict IN ('NEEDS_INPUT','NEEDS_ADJUSTMENT','BLOCKED')
    OR v_status IN ('NEEDS_INPUT','BLOCKED','NEEDS_REPAIR')
    OR coalesce((p_profile_output->>'blocked')::boolean,false) IS TRUE
    OR (
      jsonb_typeof(p_profile_output->'missing_inputs')='array'
      AND jsonb_array_length(p_profile_output->'missing_inputs')>0
    )
    OR nullif(btrim(coalesce(p_profile_output->>'blocking_reason','')),'') IS NOT NULL;

  IF v_untyped_unresolved THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_UNTYPED_ROUTING_SIGNAL',
      'source_execution_id',p_execution_id,
      'source_profile_code',p_profile_code,
      'next_action','FIX_PROFILE_ROUTING_CONTRACT'
    );
  END IF;

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
    'status','COMPLETE',
    'code','PROFILE_RESULT_NO_ROUTER_RETURN_REQUIRED',
    'source_execution_id',p_execution_id,
    'source_profile_code',p_profile_code,
    'next_action','EMIT_PROFILE_RESULT'
  );
END
$function$;

COMMENT ON FUNCTION public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text) IS
'Classifies only typed post-profile routing signals. Direct target_profile is forbidden; suggestions such as profiles_to_activate remain advisory and never authorize routing.';

REVOKE ALL ON FUNCTION public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)
  TO service_role, supabase_read_only_user;


CREATE OR REPLACE FUNCTION public.lf_profile_execution_terminal_authority_receipt_v1(
  p_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  j record;
  v_steps jsonb;
  v_step_count int;
  v_router jsonb;
  v_router_kind text;
  v_scope jsonb;
  v_source jsonb;
  v_context jsonb;
  v_execute jsonb;
  v_output jsonb;
  v_semantic jsonb;
  v_report jsonb;
  v_literal text;
  v_body jsonb;
  v_sha text;
  v_queue_request_id text;
  v_executor_mode text;
  v_executor_provider text;
  v_transport_kind text;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_INPUT_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_EXECUTION_INVALID'
    );
  END IF;

  IF e.status<>'COMPLETED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_EXECUTION_NOT_COMPLETED',
      'canonical_status',e.status
    );
  END IF;

  SELECT required_steps,required_steps_pass,fail_count,blocked_count,judge_result
    INTO j
  FROM public.v_lf_operation_execution_judge
  WHERE execution_id=p_execution_id;

  IF j IS NULL
     OR j.judge_result IS DISTINCT FROM 'PASS'
     OR j.required_steps IS DISTINCT FROM 11
     OR j.required_steps_pass IS DISTINCT FROM j.required_steps
     OR coalesce(j.fail_count,0)<>0
     OR coalesce(j.blocked_count,0)<>0
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_JUDGE_NOT_CLEAN',
      'judge_result',coalesce(j.judge_result,'MISSING'),
      'required_steps',j.required_steps,
      'required_steps_pass',j.required_steps_pass,
      'fail_count',j.fail_count,
      'blocked_count',j.blocked_count
    );
  END IF;

  SELECT count(*),
         jsonb_object_agg(
           s.step_id,
           jsonb_build_object(
             'status',s.status,
             'evidence_ref',s.evidence_ref,
             'evidence_payload',s.evidence_payload
           )
           ORDER BY os.step_order
         )
    INTO v_step_count,v_steps
  FROM public.lf_operation_execution_steps s
  JOIN public.lf_operation_steps os
    ON os.operation_code='EJECUCION_PERFIL_LF'
   AND os.step_id=s.step_id
   AND os.active
  WHERE s.execution_id=p_execution_id
    AND s.status='STEP_PASS_WITH_EVIDENCE';

  IF v_step_count<>11 OR jsonb_typeof(v_steps)<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_STEP_SET_INCOMPLETE',
      'clean_steps',v_step_count
    );
  END IF;

  v_router:=coalesce(
    v_steps#>'{router,evidence_payload,router_authorization_receipt}',
    v_steps#>'{router,evidence_payload,router_result}'
  );

  IF v_steps#>'{router,evidence_payload,router_authorization_receipt}' IS NOT NULL THEN
    v_router_kind:='CARRIED_AUTHORIZATION_RECEIPT';
  ELSE
    v_router_kind:='LEGACY_ROUTER_RESULT';
  END IF;

  v_scope:=v_steps#>'{input_validate,evidence_payload,scope_authority_packet}';
  v_source:=v_steps#>'{profile_source_read,evidence_payload}';
  v_context:=v_steps#>'{context_admission,evidence_payload}';
  v_execute:=v_steps#>'{execute_profile,evidence_payload}';
  v_output:=v_steps#>'{output_validate,evidence_payload}';
  v_semantic:=v_steps#>'{semantic_judge,evidence_payload}';
  v_report:=v_steps#>'{report_output,evidence_payload}';
  v_literal:=v_scope#>>'{authorized_requirements,0,statement}';

  IF jsonb_typeof(v_router)<>'object'
     OR (
       v_router_kind='CARRIED_AUTHORIZATION_RECEIPT'
       AND (
         v_router->>'schema_version'<>'LF_ROUTER_PROFILE_AUTHORIZATION_RECEIPT_V1'
         OR v_router->>'router'<>'ACT-0001'
         OR v_router->>'profile_code' IS DISTINCT FROM e.target_code
         OR v_router->>'action_code'<>'PROFILE_EXECUTION'
         OR v_router->>'operation_code'<>'EJECUCION_PERFIL_LF'
         OR coalesce((v_router->>'profile_execution_allowed')::boolean,false) IS NOT TRUE
         OR coalesce((v_router->>'router_reentry_before_execution')::boolean,true) IS NOT FALSE
       )
     )
     OR (
       v_router_kind='LEGACY_ROUTER_RESULT'
       AND (
         v_router->>'status'<>'READY_TO_EXECUTE'
         OR v_router->>'operation_code'<>'EJECUCION_PERFIL_LF'
       )
     )
     OR jsonb_typeof(v_scope)<>'object'
     OR v_scope->>'packet_version'<>'LF_SCOPE_AUTHORITY_PACKET_V1'
     OR coalesce(v_scope->>'sha256','') !~ '^sha256:[0-9a-f]{64}$'
     OR jsonb_typeof(v_source)<>'object'
     OR coalesce(v_source->>'profile_source_digest','') !~ '^sha256:[0-9a-f]{64}$'
     OR jsonb_typeof(v_context)<>'object'
     OR coalesce(v_context->>'context_receipt_digest','') !~ '^sha256:[0-9a-f]{64}$'
     OR jsonb_typeof(v_execute)<>'object'
     OR jsonb_typeof(v_execute->'profile_output')<>'object'
     OR jsonb_typeof(v_output)<>'object'
     OR jsonb_typeof(v_semantic)<>'object'
     OR v_semantic#>>'{semantic_judge_result,status}' IS DISTINCT FROM 'PASS'
     OR jsonb_typeof(v_report)<>'object'
     OR v_report->>'result' IS DISTINCT FROM 'PASS_INDEPENDENT_SEMANTIC'
     OR nullif(v_literal,'') IS NULL
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_AUTHORITY_CHAIN_INCOMPLETE',
      'router_authority_kind',v_router_kind
    );
  END IF;

  v_queue_request_id:=nullif(btrim(coalesce(e.manifest->>'queue_request_id','')),'');
  v_executor_mode:=upper(nullif(btrim(coalesce(e.manifest->>'executor_mode','')),''));
  v_executor_provider:=nullif(btrim(coalesce(e.manifest->>'executor_provider','')),'');

  IF v_executor_mode IS NULL AND v_queue_request_id IS NOT NULL THEN
    v_executor_mode:='REMOTE_API';
  END IF;

  IF v_executor_mode IS NULL
     OR v_executor_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE','REMOTE_API') THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_EXECUTOR_MODE_INVALID',
      'executor_mode',v_executor_mode
    );
  END IF;

  IF v_executor_mode='REMOTE_API' THEN
    IF v_queue_request_id IS NULL THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'code','PROFILE_TERMINAL_RECEIPT_TRANSPORT_BINDING_INVALID',
        'executor_mode',v_executor_mode,
        'reason','QUEUE_REQUEST_ID_REQUIRED_FOR_REMOTE_API'
      );
    END IF;
    v_transport_kind:='REMOTE_API_QUEUE';

  ELSIF v_executor_mode='GPT_NATIVE' THEN
    IF v_queue_request_id IS NOT NULL
       OR v_executor_provider IS DISTINCT FROM 'OPENAI_CHATGPT_NATIVE'
       OR nullif(btrim(coalesce(e.manifest->>'runtime_target','')),'') IS NOT NULL
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'code','PROFILE_TERMINAL_RECEIPT_TRANSPORT_BINDING_INVALID',
        'executor_mode',v_executor_mode,
        'reason','GPT_NATIVE_REQUIRES_NATIVE_PROVIDER_AND_NO_REMOTE_QUEUE'
      );
    END IF;
    v_transport_kind:='NATIVE_CURRENT_CONTEXT';

  ELSIF v_executor_mode='CLAUDE_NATIVE' THEN
    IF v_queue_request_id IS NOT NULL
       OR v_executor_provider IS DISTINCT FROM 'ANTHROPIC_CLAUDE_NATIVE'
       OR nullif(btrim(coalesce(e.manifest->>'runtime_target','')),'') IS NOT NULL
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'code','PROFILE_TERMINAL_RECEIPT_TRANSPORT_BINDING_INVALID',
        'executor_mode',v_executor_mode,
        'reason','CLAUDE_NATIVE_REQUIRES_NATIVE_PROVIDER_AND_NO_REMOTE_QUEUE'
      );
    END IF;
    v_transport_kind:='NATIVE_CURRENT_CONTEXT';
  END IF;

  IF e.manifest->>'input_sha256' IS NULL
     OR v_scope->>'execution_id' IS DISTINCT FROM p_execution_id
     OR v_report->>'execution_id' IS DISTINCT FROM p_execution_id
     OR v_report->>'profile_code' IS DISTINCT FROM e.target_code
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_IDENTITY_MISMATCH'
    );
  END IF;

  v_body:=jsonb_build_object(
    'schema_version','LF_PROFILE_RUNTIME_TERMINAL_AUTHORITY_RECEIPT_V1',
    'queue_request_id',v_queue_request_id,
    'canonical_execution_id',e.execution_id,
    'operation_code',e.operation_code,
    'profile_code',e.target_code,
    'executor_mode',v_executor_mode,
    'execution_transport',v_transport_kind,
    'executor_provider',v_executor_provider,
    'input_literal',v_literal,
    'input_literal_sha256',e.manifest->>'input_sha256',
    'router_authority_kind',v_router_kind,
    'router_authority_receipt',v_router,
    'scope_authority_packet',v_scope,
    'scope_authority_packet_sha256',
      v_steps#>>'{input_validate,evidence_payload,scope_authority_packet_sha256}',
    'profile_source_receipt',v_source,
    'context_receipt',jsonb_build_object(
      'ref',v_context->>'context_receipt_ref',
      'digest',v_context->>'context_receipt_digest',
      'server_validated',v_context->'server_validated'
    ),
    'raw_output_receipt',jsonb_build_object(
      'profile_output_sha256','sha256:'||encode(
        extensions.digest(
          convert_to((v_execute->'profile_output')::text,'UTF8'),
          'sha256'
        ),
        'hex'
      ),
      'execute_evidence_ref',v_steps#>>'{execute_profile,evidence_ref}'
    ),
    'validator_receipt',jsonb_build_object(
      'output_contract_result',v_output->>'output_contract_result',
      'deterministic_validation',v_output->'deterministic_validation',
      'evidence_ref',v_steps#>>'{output_validate,evidence_ref}'
    ),
    'semantic_judge_receipt',v_semantic,
    'report_output_receipt',v_report,
    'canonical_judge_readback',jsonb_build_object(
      'required_steps',j.required_steps,
      'required_steps_pass',j.required_steps_pass,
      'fail_count',j.fail_count,
      'blocked_count',j.blocked_count,
      'judge_result',j.judge_result
    ),
    'source_refs',jsonb_build_array(
      v_steps#>>'{router,evidence_ref}',
      v_steps#>>'{input_validate,evidence_ref}',
      v_steps#>>'{profile_source_read,evidence_ref}',
      v_steps#>>'{context_admission,evidence_ref}',
      v_steps#>>'{execute_profile,evidence_ref}',
      v_steps#>>'{output_validate,evidence_ref}',
      v_steps#>>'{semantic_judge,evidence_ref}',
      v_steps#>>'{report_output,evidence_ref}'
    ),
    'authority_rule','ROUTER_AND_OPERATION_EVIDENCE_ONLY_NO_SPECIALIST_EFFECT_AUTHORITY'
  );

  v_sha:='sha256:'||encode(
    extensions.digest(convert_to(v_body::text,'UTF8'),'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'status','READY',
    'terminal_authority_receipt',
      v_body||jsonb_build_object('sha256',v_sha),
    'terminal_authority_receipt_sha256',v_sha
  );
END
$function$;


CREATE OR REPLACE FUNCTION public.lf_profile_result_router_return_prepare_v1(
  p_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_terminal jsonb;
  v_profile_output jsonb;
  v_original_request text;
  v_decision jsonb;
  v_output_sha text;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_PREPARE_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_ROUTER_RETURN_EXECUTION_ID_REQUIRED'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'COMPLETED'
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_PREPARE_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_ROUTER_RETURN_EXECUTION_NOT_COMPLETED'
    );
  END IF;

  IF coalesce(
       (e.manifest#>>'{router_profile_handoff,return_to_router_after_profile_result}')::boolean,
       false
     ) IS NOT TRUE
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_PREPARE_V1',
      'status','COMPLETE',
      'code','PROFILE_RESULT_ROUTER_RETURN_DISABLED',
      'execution_id',p_execution_id,
      'profile_code',e.target_code,
      'next_action','EMIT_PROFILE_RESULT'
    );
  END IF;

  v_terminal:=public.lf_profile_execution_terminal_authority_receipt_v1(
    p_execution_id
  );

  IF v_terminal->>'status'<>'READY' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_PREPARE_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_TERMINAL_AUTHORITY_NOT_READY',
      'terminal_authority',v_terminal
    );
  END IF;

  SELECT s.evidence_payload->'profile_output'
    INTO v_profile_output
  FROM public.lf_operation_execution_steps s
  WHERE s.execution_id=p_execution_id
    AND s.step_id='execute_profile'
    AND s.status='STEP_PASS_WITH_EVIDENCE'
  LIMIT 1;

  IF jsonb_typeof(v_profile_output)<>'object' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_PREPARE_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_OUTPUT_NOT_AVAILABLE'
    );
  END IF;

  v_original_request:=coalesce(
    nullif(e.manifest#>>'{router_profile_handoff,literal_request}',''),
    v_terminal#>>'{terminal_authority_receipt,input_literal}'
  );

  v_decision:=public.lf_profile_result_router_return_classify_v1(
    v_profile_output,
    v_original_request,
    p_execution_id,
    e.target_code
  );

  v_output_sha:='sha256:'||encode(
    extensions.digest(convert_to(v_profile_output::text,'UTF8'),'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_PREPARE_V1',
    'status',v_decision->>'status',
    'code',v_decision->>'code',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'profile_output_sha256',v_output_sha,
    'terminal_authority_receipt_sha256',
      v_terminal->>'terminal_authority_receipt_sha256',
    'decision',v_decision,
    'router_return_request',v_decision->'router_return_request',
    'next_action',v_decision->>'next_action'
  );
END
$function$;

COMMENT ON FUNCTION public.lf_profile_result_router_return_prepare_v1(text) IS
'At terminal profile completion, converts only a typed RETURN_TO_ORCHESTRATOR output into a request for a fresh ACT-0001 Stage1 pass. It never honors a direct target_profile.';

REVOKE ALL ON FUNCTION public.lf_profile_result_router_return_prepare_v1(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_result_router_return_prepare_v1(text)
  TO service_role, supabase_read_only_user;


CREATE OR REPLACE FUNCTION public.lf_profile_execution_attach_terminal_authority_receipt_v1(
  p_execution_id text,
  p_actor_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  r jsonb;
  v_post jsonb;
  v_sha text;
  v_existing text;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR p_actor_execution_id IS DISTINCT FROM p_execution_id THEN
    RETURN jsonb_build_object(
      'result','INPUT_OR_ACTOR_INVALID',
      'blocking_code','PROFILE_TERMINAL_RECEIPT_ATTACH_FAILED'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id
  FOR UPDATE;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.status<>'COMPLETED'
  THEN
    RETURN jsonb_build_object(
      'result','EXECUTION_NOT_ATTACHABLE',
      'blocking_code','PROFILE_TERMINAL_RECEIPT_ATTACH_FAILED'
    );
  END IF;

  r:=public.lf_profile_execution_terminal_authority_receipt_v1(
    p_execution_id
  );

  IF r->>'status'<>'READY' THEN
    RETURN r||jsonb_build_object('result','RECEIPT_NOT_READY');
  END IF;

  v_post:=public.lf_profile_result_router_return_prepare_v1(
    p_execution_id
  );

  v_sha:=r->>'terminal_authority_receipt_sha256';
  v_existing:=e.manifest->>'terminal_authority_receipt_sha256';

  IF v_existing IS NOT NULL THEN
    IF v_existing=v_sha THEN
      RETURN jsonb_build_object(
        'result','TERMINAL_AUTHORITY_RECEIPT_ALREADY_ATTACHED',
        'terminal_authority_receipt',r->'terminal_authority_receipt',
        'terminal_authority_receipt_sha256',v_sha,
        'post_profile_route',
          coalesce(e.manifest->'post_profile_router_return',v_post),
        'next_action',
          coalesce(
            e.manifest#>>'{post_profile_router_return,next_action}',
            v_post->>'next_action'
          )
      );
    END IF;

    RETURN jsonb_build_object(
      'result','TERMINAL_AUTHORITY_RECEIPT_CONFLICT',
      'blocking_code','PROFILE_TERMINAL_RECEIPT_ATTACH_FAILED',
      'existing_sha256',v_existing,
      'candidate_sha256',v_sha
    );
  END IF;

  UPDATE public.lf_operation_execution
     SET manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object(
           'terminal_authority_receipt',
             r->'terminal_authority_receipt',
           'terminal_authority_receipt_sha256',v_sha,
           'post_profile_router_return',v_post
         ),
         updated_by_execution_id=p_actor_execution_id,
         updated_at=now()
   WHERE execution_id=p_execution_id
     AND status='COMPLETED'
     AND manifest->>'terminal_authority_receipt_sha256' IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'result','TERMINAL_AUTHORITY_RECEIPT_COMPARE_AND_SET_FAILED',
      'blocking_code','PROFILE_TERMINAL_RECEIPT_ATTACH_FAILED'
    );
  END IF;

  RETURN jsonb_build_object(
    'result','TERMINAL_AUTHORITY_RECEIPT_ATTACHED',
    'terminal_authority_receipt',r->'terminal_authority_receipt',
    'terminal_authority_receipt_sha256',v_sha,
    'post_profile_route',v_post,
    'next_action',v_post->>'next_action'
  );
END
$function$;

COMMENT ON FUNCTION public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text) IS
'Attaches terminal authority and the post-profile routing decision. Typed RETURN_TO_ORCHESTRATOR produces a fresh Router Stage1 request; no profile is invoked directly.';

REVOKE ALL ON FUNCTION public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text)
  FROM PUBLIC, anon, authenticated, supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text)
  TO service_role;


DO $postcheck$
DECLARE
  v_product jsonb;
  v_frontend jsonb;
  v_quality jsonb;
  v_direct jsonb;
  v_complete jsonb;
  v_existing text;
  v_existing_prepare jsonb;
  v_src text;
BEGIN
  v_product:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'worker','product_director_lf',
      'output_type','PRODUCT_MISSING_INPUT_STATE',
      'missing_fields',jsonb_build_array('target_user_state'),
      'why_required',jsonb_build_array('Changes product scope and acceptance.'),
      'risk_if_assumed',jsonb_build_array('Would invent product truth.'),
      'safe_next_gate',jsonb_build_object(
        'action','RESOLVE_MATERIAL_PRODUCT_INPUT',
        'source_type','CURRENT_PRODUCT_AUTHORITY'
      )
    ),
    'Define el onboarding.',
    'EXEC-SYNTH-PRODUCT',
    'PERFIL-PRODUCT-DIRECTOR-LF'
  );

  IF v_product->>'status'<>'RETURN_TO_ROUTER'
     OR v_product#>>'{router_return_request,route_policy}'<>'REPEAT_FULL_ROUTER_FLOW'
     OR coalesce(
       (v_product#>>'{router_return_request,direct_profile_invocation_allowed}')::boolean,
       true
     )
     OR v_product#>>'{router_return_request,next_entrypoint}'<>'ACT-0001_STAGE1'
  THEN
    RAISE EXCEPTION 'PROFILE_RESULT_PRODUCT_RETURN_POSTCHECK_FAILED:%',
      left(v_product::text,1800);
  END IF;

  v_frontend:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'worker','frontend_prototype_architect_lf',
      'output_type','FRONTEND_MISSING_INPUT_STATE',
      'blocked',true,
      'missing_fields',jsonb_build_array('approved_ui_hierarchy'),
      'resolved_from_context','[]'::jsonb,
      'conflicts_detected','[]'::jsonb,
      'why_required',jsonb_build_array('Hierarchy is owned upstream.'),
      'risk_if_assumed',jsonb_build_array('Would invent UI authority.'),
      'pipeline_action','RETURN_TO_ORCHESTRATOR',
      'resolution_target','UI_ARCHITECT',
      'question_to_orchestrator','Resolve the approved UI hierarchy before frontend implementation.'
    ),
    'Construye el prototipo.',
    'EXEC-SYNTH-FRONTEND',
    'ACT-0051'
  );

  IF v_frontend->>'status'<>'RETURN_TO_ROUTER'
     OR v_frontend#>>'{router_return_request,unresolved_contract_type}'
          <>'FRONTEND_MISSING_INPUT_STATE'
  THEN
    RAISE EXCEPTION 'PROFILE_RESULT_FRONTEND_RETURN_POSTCHECK_FAILED:%',
      left(v_frontend::text,1800);
  END IF;

  v_quality:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'review_id','Q-SYNTH',
      'reviewed_artifact','artifact://synthetic',
      'verdict','RETURN_TO_ORCHESTRATOR',
      'score_breakdown',jsonb_build_object('total',10),
      'evidence_map','[]'::jsonb,
      'blocking_codes',jsonb_build_array('MISSING_CURRENT_AUTHORITY'),
      'repair_actions','[]'::jsonb,
      'remaining_risks','[]'::jsonb,
      'next_gate','AUTHORITY_RESOLUTION',
      'routing',jsonb_build_object(
        'activation_path','ROUTER',
        'via','ORCHESTRATOR',
        'pipeline_action','RETURN_TO_ORCHESTRATOR',
        'resolution_target','AUTHORITY_OR_CONTEXT_RESOLUTION'
      )
    ),
    'Revisa el entregable.',
    'EXEC-SYNTH-QUALITY',
    'PERFIL-QUALITY-PACK'
  );

  IF v_quality->>'status'<>'RETURN_TO_ROUTER'
     OR v_quality#>>'{router_return_request,unresolved_contract_type}'
          <>'QUALITY_ROUTING_REDIRECT'
  THEN
    RAISE EXCEPTION 'PROFILE_RESULT_QUALITY_RETURN_POSTCHECK_FAILED:%',
      left(v_quality::text,1800);
  END IF;

  v_direct:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'pipeline_action','RETURN_TO_ORCHESTRATOR',
      'target_profile','PERFIL-UI-ARCHITECT',
      'missing_fields',jsonb_build_array('ui'),
      'question_to_orchestrator','Resolve UI.'
    ),
    'Haz la pantalla.',
    'EXEC-SYNTH-DIRECT',
    'ACT-0051'
  );

  IF v_direct->>'status'<>'BLOCKED'
     OR v_direct->>'code'<>'PROFILE_RESULT_DIRECT_TARGET_PROFILE_FORBIDDEN'
  THEN
    RAISE EXCEPTION 'PROFILE_RESULT_DIRECT_TARGET_FALSE_PASS:%',
      left(v_direct::text,1400);
  END IF;

  v_complete:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'worker','product_director_lf',
      'output_type','PRODUCT_DIRECTION_SPEC',
      'self_verdict','PASS',
      'deliverable_created',jsonb_build_object(
        'profiles_to_activate',jsonb_build_array('PERFIL-UI-ARCHITECT')
      ),
      'handoff_to_next',jsonb_build_object(
        'target','Orchestrator'
      )
    ),
    'Dame las reglas.',
    'EXEC-SYNTH-COMPLETE',
    'PERFIL-PRODUCT-DIRECTOR-LF'
  );

  IF v_complete->>'status'<>'COMPLETE'
     OR v_complete->>'next_action'<>'EMIT_PROFILE_RESULT'
  THEN
    RAISE EXCEPTION 'PROFILE_RESULT_ADVISORY_PROFILE_FALSE_ROUTE:%',
      left(v_complete::text,1400);
  END IF;

  SELECT execution_id INTO v_existing
  FROM public.lf_operation_execution
  WHERE operation_code='EJECUCION_PERFIL_LF'
    AND target_type='PERFIL'
    AND status='COMPLETED'
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    v_existing_prepare:=
      public.lf_profile_result_router_return_prepare_v1(v_existing);

    IF v_existing_prepare->>'status' NOT IN ('COMPLETE','RETURN_TO_ROUTER','BLOCKED') THEN
      RAISE EXCEPTION 'PROFILE_RESULT_EXISTING_EXECUTION_PREPARE_INVALID:%',
        left(v_existing_prepare::text,1600);
    END IF;
  END IF;

  v_src:=pg_get_functiondef(
    'public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text)'::regprocedure
  );

  IF position('lf_router_route_v1' in v_src)>0
     OR position('lf_router_resolve_v1' in v_src)>0
     OR position('target_profile' in
       pg_get_functiondef(
         'public.lf_profile_result_router_return_prepare_v1(text)'::regprocedure
       ))>0
  THEN
    RAISE EXCEPTION 'PROFILE_RESULT_ROUTER_RETURN_BYPASS_OR_DIRECT_TARGET_DETECTED';
  END IF;

  IF has_function_privilege(
       'anon',
       'public.lf_profile_result_router_return_prepare_v1(text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.lf_profile_result_router_return_prepare_v1(text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_result_router_return_prepare_v1(text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION 'PROFILE_RESULT_ROUTER_RETURN_ACL_POSTCHECK_FAILED';
  END IF;
END
$postcheck$;

COMMIT;
