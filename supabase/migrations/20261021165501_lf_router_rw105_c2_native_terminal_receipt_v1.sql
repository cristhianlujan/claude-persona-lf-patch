-- RW1-05_C2: make the canonical profile terminal receipt transport-neutral.
-- REMOTE_API keeps the existing queue contract. GPT_NATIVE / CLAUDE_NATIVE
-- use the same EJECUCION_PERFIL_LF operation ledger without pretending that
-- a queue transport exists. This migration prepares, but does not execute or
-- close, the required real native canary.
BEGIN;

DO $pre$
DECLARE
  v_receipt_md5 text;
  v_resolver_md5 text;
  v_metadata_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef(
           'public.lf_profile_execution_terminal_authority_receipt_v1(text)'::regprocedure
         ))
    INTO v_receipt_md5;
  IF v_receipt_md5 <> '17c12b9ed28b9c64bb997e57a0871a7c' THEN
    RAISE EXCEPTION 'RW105_C2_TERMINAL_RECEIPT_SOURCE_DRIFT:%',v_receipt_md5;
  END IF;

  SELECT md5(pg_get_functiondef(
           'programacion.fn_engineering_test_executor_resolve_v1(jsonb)'::regprocedure
         ))
    INTO v_resolver_md5;
  IF v_resolver_md5 <> 'd7abe3d7fcc666e171d15dd39beab646' THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_EXECUTOR_RESOLVER_DRIFT:%',v_resolver_md5;
  END IF;

  SELECT md5(unit_metadata::text)
    INTO STRICT v_metadata_md5
  FROM programacion.engineering_plan_units
  WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1'
    AND unit_code='RW1-05'
    AND work_item_id=1131
    AND disposition='ASSIGNED';

  IF v_metadata_md5 <> '8abca45b5ba7bf66bc2f83ffa151fa0e' THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_TERMINAL_METADATA_DRIFT:%',v_metadata_md5;
  END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1131 AND checkpoint_code='RW1-05_C2')
     IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_TERMINAL_CHECKPOINT_NOT_PENDING';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_terminal_authority_receipt_v1(
  p_execution_id text
) RETURNS jsonb
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

  v_router:=v_steps#>'{router,evidence_payload,router_result}';
  v_scope:=v_steps#>'{input_validate,evidence_payload,scope_authority_packet}';
  v_source:=v_steps#>'{profile_source_read,evidence_payload}';
  v_context:=v_steps#>'{context_admission,evidence_payload}';
  v_execute:=v_steps#>'{execute_profile,evidence_payload}';
  v_output:=v_steps#>'{output_validate,evidence_payload}';
  v_semantic:=v_steps#>'{semantic_judge,evidence_payload}';
  v_report:=v_steps#>'{report_output,evidence_payload}';
  v_literal:=v_scope#>>'{authorized_requirements,0,statement}';

  IF jsonb_typeof(v_router)<>'object'
     OR v_router->>'status'<>'READY_TO_EXECUTE'
     OR v_router->>'operation_code'<>'EJECUCION_PERFIL_LF'
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
      'code','PROFILE_TERMINAL_RECEIPT_AUTHORITY_CHAIN_INCOMPLETE'
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
        extensions.digest(convert_to((v_execute->'profile_output')::text,'UTF8'),'sha256'
      ),'hex'),
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

COMMENT ON FUNCTION public.lf_profile_execution_terminal_authority_receipt_v1(text) IS
'Canonical EJECUCION_PERFIL_LF terminal authority receipt. Transport-neutral across GPT_NATIVE, CLAUDE_NATIVE and REMOTE_API. Queue identity is required only for REMOTE_API; native modes require their canonical native provider and forbid remote queue/target substitution.';

DO $metadata$
DECLARE
  v_old jsonb;
  v_new jsonb;
  v_spec jsonb;
  v_source jsonb;
  v_route jsonb;
  v_resolved jsonb;
  v_declared jsonb;
  v_count integer;
BEGIN
  SELECT unit_metadata
    INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1'
    AND unit_code='RW1-05'
    AND work_item_id=1131
    AND disposition='ASSIGNED'
    AND md5(unit_metadata::text)='8abca45b5ba7bf66bc2f83ffa151fa0e'
  FOR UPDATE;

  v_spec:=v_old#>'{action_specs_v1,RW1-05_C2}';
  v_source:=v_old#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2}';

  IF v_spec IS NULL OR v_source IS NULL THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_TERMINAL_CONTRACT_MISSING';
  END IF;

  v_route:=jsonb_build_object(
    'provider','GPT_NATIVE',
    'adapter_id','chatgpt-native-current-context-v1',
    'conversation_scope','EXISTING_CONVERSATION_ONLY'
  );

  v_spec:=jsonb_set(
    v_spec,
    '{test_execution_contract}',
    jsonb_build_object(
      'operation_code','EJECUCION_PERFIL_LF',
      'canary_kind','REAL_ZERO_COST_READ_ONLY',
      'required_executor_mode','GPT_NATIVE',
      'execution_route',v_route,
      'native_capture_required',true,
      'terminal_receipt_required',true,
      'remote_api_fallback','FORBIDDEN',
      'host_execution','FORBIDDEN',
      'synthetic_pass','FORBIDDEN',
      'historical_run_substitution','FORBIDDEN'
    ),
    true
  );

  v_spec:=jsonb_set(
    v_spec,
    '{executor_mode_contract,terminal_receipt_transport_contract}',
    jsonb_build_object(
      'queue_request_id_required_modes',
        jsonb_build_array('REMOTE_API'),
      'queue_request_id_forbidden_modes',
        jsonb_build_array('GPT_NATIVE','CLAUDE_NATIVE'),
      'native_provider_by_mode',
        jsonb_build_object(
          'GPT_NATIVE','OPENAI_CHATGPT_NATIVE',
          'CLAUDE_NATIVE','ANTHROPIC_CLAUDE_NATIVE'
        ),
      'native_runtime_target_required',false,
      'remote_api_queue_contract_preserved',true,
      'same_operation_ledger_all_modes',true
    ),
    true
  );

  v_declared:=coalesce(v_spec#>'{target,declared_objects}','[]'::jsonb);
  IF NOT (v_declared @> '["programacion.fn_engineering_test_executor_resolve_v1"]'::jsonb) THEN
    v_declared:=v_declared||jsonb_build_array(
      'programacion.fn_engineering_test_executor_resolve_v1'
    );
    v_spec:=jsonb_set(v_spec,'{target,declared_objects}',v_declared,true);
  END IF;

  v_source:=jsonb_set(
    v_source,
    '{native_canary_preparation}',
    jsonb_build_object(
      'status','READY_FOR_REAL_EXECUTION',
      'operation_code','EJECUCION_PERFIL_LF',
      'executor_mode','GPT_NATIVE',
      'provider','OPENAI_CHATGPT_NATIVE',
      'adapter_id','chatgpt-native-current-context-v1',
      'conversation_scope','EXISTING_CONVERSATION_ONLY',
      'zero_cost',true,
      'read_only',true,
      'native_capture_required',true,
      'terminal_receipt_required',true,
      'remote_api_fallback','FORBIDDEN',
      'host_execution','FORBIDDEN',
      'historical_run_substitution','FORBIDDEN'
    ),
    true
  );

  v_new:=jsonb_set(
    v_old,
    '{action_specs_v1,RW1-05_C2}',
    v_spec,
    false
  );
  v_new:=jsonb_set(
    v_new,
    '{source_pack_v2,checkpoint_inputs,RW1-05_C2}',
    v_source,
    false
  );

  v_resolved:=programacion.fn_engineering_test_executor_resolve_v1(v_spec);
  IF v_resolved->>'status' IS DISTINCT FROM 'READY'
     OR v_resolved->>'provider' IS DISTINCT FROM 'GPT_NATIVE'
     OR v_resolved#>>'{runner_contract,executor_mode}' IS DISTINCT FROM 'GPT_NATIVE'
     OR v_resolved#>>'{runner_contract,adapter_id}'
          IS DISTINCT FROM 'chatgpt-native-current-context-v1'
     OR v_resolved#>>'{runner_contract,native_conversation_scope}'
          IS DISTINCT FROM 'EXISTING_CONVERSATION_ONLY'
     OR coalesce((v_resolved#>>'{runner_contract,native_api_invocation}')::boolean,true)
          IS NOT FALSE
     OR coalesce((v_resolved#>>'{runner_contract,native_session_creation}')::boolean,true)
          IS NOT FALSE
     OR v_resolved#>>'{runner_contract,remote_api_fallback}'
          IS DISTINCT FROM 'FORBIDDEN'
     OR v_resolved#>>'{runner_contract,host_execution}'
          IS DISTINCT FROM 'FORBIDDEN'
     OR coalesce((v_resolved#>>'{runner_contract,native_capture_required}')::boolean,false)
          IS NOT TRUE
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CANARY_ROUTE_NOT_READY:%',v_resolved::text;
  END IF;

  IF jsonb_array_length(
       coalesce(v_new#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}',
                '[]'::jsonb)
     ) <> 2
     OR NOT EXISTS (
       SELECT 1
       FROM jsonb_array_elements(
         v_new#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
       ) x(item)
       WHERE x.item->>'code'='REAL_SEMANTIC_SHADOW_RUN_PENDING'
         AND coalesce((x.item->>'blocking')::boolean,false)=true
     )
     OR NOT EXISTS (
       SELECT 1
       FROM jsonb_array_elements(
         v_new#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
       ) x(item)
       WHERE x.item->>'code'='REAL_PROFILE_RUNTIME_CANARY_PENDING'
         AND coalesce((x.item->>'blocking')::boolean,false)=true
     )
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_TERMINAL_BLOCKER_SET_CHANGED';
  END IF;

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1'
     AND unit_code='RW1-05'
     AND work_item_id=1131
     AND disposition='ASSIGNED'
     AND md5(unit_metadata::text)='8abca45b5ba7bf66bc2f83ffa151fa0e';

  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_TERMINAL_METADATA_UPDATE_COUNT:%',v_count;
  END IF;
END
$metadata$;

DO $post$
DECLARE
  v_def text;
  v_spec jsonb;
  v_route jsonb;
  v_queue_ck text;
BEGIN
  v_def:=pg_get_functiondef(
    'public.lf_profile_execution_terminal_authority_receipt_v1(text)'::regprocedure
  );

  IF strpos(v_def,'QUEUE_REQUEST_ID_REQUIRED_FOR_REMOTE_API')=0
     OR strpos(v_def,'GPT_NATIVE_REQUIRES_NATIVE_PROVIDER_AND_NO_REMOTE_QUEUE')=0
     OR strpos(v_def,'CLAUDE_NATIVE_REQUIRES_NATIVE_PROVIDER_AND_NO_REMOTE_QUEUE')=0
     OR strpos(v_def,'''execution_transport'',v_transport_kind')=0
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_TERMINAL_FUNCTION_POSTCHECK_FAILED';
  END IF;

  SELECT unit_metadata#>'{action_specs_v1,RW1-05_C2}'
    INTO STRICT v_spec
  FROM programacion.engineering_plan_units
  WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1'
    AND unit_code='RW1-05'
    AND work_item_id=1131
    AND disposition='ASSIGNED';

  v_route:=programacion.fn_engineering_test_executor_resolve_v1(v_spec);
  IF v_route->>'status' IS DISTINCT FROM 'READY'
     OR v_route->>'provider' IS DISTINCT FROM 'GPT_NATIVE'
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_TERMINAL_ROUTE_POSTCHECK_FAILED:%',v_route::text;
  END IF;

  SELECT pg_get_constraintdef(c.oid)
    INTO STRICT v_queue_ck
  FROM pg_constraint c
  JOIN pg_class t ON t.oid=c.conrelid
  JOIN pg_namespace n ON n.oid=t.relnamespace
  WHERE n.nspname='private'
    AND t.relname='lf_profile_runtime_queue_v1'
    AND c.conname='lf_profile_runtime_queue_runtime_target_ck';

  IF v_queue_ck NOT LIKE '%GITHUB_ACTIONS%'
     OR v_queue_ck NOT LIKE '%HETZNER%'
     OR v_queue_ck LIKE '%GPT_NATIVE%'
     OR v_queue_ck LIKE '%CLAUDE_NATIVE%'
  THEN
    RAISE EXCEPTION 'RW105_C2_REMOTE_QUEUE_CONTRACT_CHANGED:%',v_queue_ck;
  END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1131 AND checkpoint_code='RW1-05_C2')
     IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_TERMINAL_CHECKPOINT_CHANGED';
  END IF;
END
$post$;

COMMIT;
