-- ISOLATED SYNTHETIC FIXTURE ONLY; DOES NOT CONNECT TO LF PROD.
-- Use PostgreSQL 17.6 to match Supabase server major/minor.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS programacion;
CREATE SCHEMA IF NOT EXISTS private;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text,target_type text,
 target_code text,status text,manifest jsonb DEFAULT '{}'::jsonb
);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text,step_id text,status text,
 evidence_ref text,evidence_payload jsonb DEFAULT '{}'::jsonb,
 PRIMARY KEY(execution_id,step_id)
);
CREATE TABLE public.lf_operation_step_judge_bindings(
 operation_code text,step_id text,status text,clean_result_value text
);
CREATE TABLE programacion.input_readiness_runs(
 id bigint PRIMARY KEY,pantalla_id integer,status text,
 source_snapshot_sha256 text
);
CREATE TABLE programacion.input_family_assessments(
 run_id bigint,family_code text
);
CREATE VIEW public.v_lf_operation_execution_judge AS
 SELECT execution_id,11::int required_steps,11::int required_steps_pass,
  0::int fail_count,0::int blocked_count,'PASS'::text judge_result
 FROM public.lf_operation_execution;
CREATE FUNCTION public.lf_profile_execution_trust_validation_v1(text,text,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT '{"valid":true}'::jsonb $$;
CREATE FUNCTION public.lf_profile_execution_canonical_read_judge_v1(text)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT '{"status":"PASS"}'::jsonb $$;
CREATE FUNCTION public.lf_profile_execution_terminal_authority_receipt_v1(text)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT '{"status":"READY","terminal_authority_receipt_sha256":"sha256:synthetic"}'::jsonb $$;
CREATE FUNCTION public.lf_record_profile_execution_step_v1(
 text,text,text,jsonb,text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT '{"outcome":"STEP_RECORDED"}'::jsonb $$;

-- ORIGINAL DEFINITIONS frozen from live pg_get_functiondef. They are used
-- exclusively for source-drift guards and compiling the patched SQL.
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_output_v1(p_execution_id text, p_profile_output jsonb, p_validation jsonb, p_raw_evidence_ref text, p_validator_evidence_ref text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_actor text;
  v_context public.lf_operation_execution_steps%rowtype;
  v_baseline public.lf_operation_execution_steps%rowtype;
  v_source public.lf_operation_execution_steps%rowtype;
  v_existing text;
  v_candidate_digest text;
  v_raw_sha text;
  v_step jsonb;
  v_clean integer;
  v_source_refs jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR jsonb_typeof(p_profile_output)<>'object'
     OR jsonb_typeof(p_validation)<>'object'
     OR coalesce((p_validation->>'valid')::boolean,false) IS NOT TRUE
     OR (
       jsonb_typeof(p_validation->'blocking_codes')='array'
       AND jsonb_array_length(p_validation->'blocking_codes')<>0
     )
     OR nullif(btrim(coalesce(p_raw_evidence_ref,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_validator_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_INPUT_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
     OR e.manifest->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE'
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_EXECUTION_INVALID'
    );
  END IF;

  SELECT * INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO v_baseline
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='research_baseline_freeze'
    AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO v_source
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='profile_source_read'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_context.step_id IS NULL
     OR v_baseline.step_id IS NULL
     OR v_source.step_id IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_PREDECESSOR_NOT_CLEAN'
    );
  END IF;

  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
  v_candidate_digest:='sha256:'||encode(
    extensions.digest(convert_to(p_profile_output::text,'UTF8'),'sha256'),
    'hex'
  );
  v_raw_sha=substr(v_candidate_digest,8);
  v_source_refs:=jsonb_build_array(
    v_source.evidence_payload->>'profile_source_ref',
    v_context.evidence_payload->>'context_receipt_ref'
  );

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='execute_profile';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'execute_profile',
      p_raw_evidence_ref,
      jsonb_build_object(
        'context_receipt_digest',v_context.evidence_payload->>'context_receipt_digest',
        'context_receipt_ref',v_context.evidence_payload->>'context_receipt_ref',
        'context_transport',jsonb_build_object(
          'profile_source_mode','JIT_BY_REF',
          'jit_resolver_ref','supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY',
          'jit_only',true,
          'policy_payloads',false,
          'full_ekb_entries',false,
          'full_readmes',false,
          'full_prefetch_count',0,
          'hydrated_refs','[]'::jsonb
        ),
        'profile_output',p_profile_output,
        'candidate_digest',v_candidate_digest,
        'raw_output_sha256',v_raw_sha,
        'research_baseline_digest',
          v_baseline.evidence_payload#>>'{research_baseline_binding,baseline_digest}',
        'research_baseline_ref',v_baseline.evidence_payload->>'baseline_receipt_ref',
        'source_refs',v_source_refs
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTE_PROFILE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='output_validate';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'output_validate',
      p_validator_evidence_ref,
      jsonb_build_object(
        'output_contract_result','PASS',
        'deterministic_validation',
          p_validation||jsonb_build_object(
            'status','PASS',
            'candidate_digest',v_candidate_digest
          ),
        'raw_output_sha256',v_raw_sha
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_VALIDATE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>9 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_POST_MODEL_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',9
    );
  END IF;

  RETURN jsonb_build_object(
    'status','NATIVE_PRODUCER_VALIDATED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'candidate_digest',v_candidate_digest,
    'raw_output_sha256',v_raw_sha,
    'clean_step_count',v_clean,
    'next_step','semantic_judge',
    'next_action','RUN_INDEPENDENT_SEMANTIC_JUDGE',
    'independent_semantic_judge_required',true,
    'producer_may_self_authorize',false,
    'terminal_authority_ready',false,
    'router_reentry_required',false
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_trust_validation_v2(p_execution_id text, p_step_id text, p_evidence_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  base jsonb;
  e public.lf_operation_execution%rowtype;
  input_step public.lf_operation_execution_steps%rowtype;
  execute_step public.lf_operation_execution_steps%rowtype;
  semantic_step public.lf_operation_execution_steps%rowtype;
  input_binding public.lf_operation_step_judge_bindings%rowtype;
  execute_binding public.lf_operation_step_judge_bindings%rowtype;
  semantic_binding public.lf_operation_step_judge_bindings%rowtype;
  packet jsonb;
  packet_body jsonb;
  expected_digest text;
  scope_digest text;
  candidate_digest text;
  semantic_result jsonb;
  canonical_read_judge jsonb;
  hard jsonb := '[]'::jsonb;
begin
  base:=public.lf_profile_execution_trust_validation_v1(
    p_execution_id,p_step_id,p_evidence_payload
  );
  if coalesce((base->>'valid')::boolean,false) is not true then
    return base;
  end if;

  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;
  if not found then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_EXECUTION_V2_BINDING_INVALID',
      'details',jsonb_build_object('execution_id',p_execution_id),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  if p_step_id='input_validate' then
    packet:=p_evidence_payload->'scope_authority_packet';
    scope_digest:=p_evidence_payload->>'scope_authority_packet_sha256';
    if jsonb_typeof(packet)<>'object'
       or coalesce(packet->>'packet_version','')<>'LF_SCOPE_AUTHORITY_PACKET_V1'
       or packet->>'execution_id' is distinct from p_execution_id
       or packet->>'subject_ref' is distinct from
          'supabase://public.lf_operation_execution/'||p_execution_id||'#manifest'
       or packet->>'canonicalization_rule' is distinct from
          'POSTGRES_JSONB_TEXT_UTF8_SHA256_V1'
       or jsonb_typeof(packet->'authorized_requirements')<>'array'
       or jsonb_array_length(packet->'authorized_requirements')=0
       or jsonb_typeof(packet->'constraints')<>'array'
       or jsonb_typeof(packet->'forbidden_changes')<>'array'
       or coalesce(scope_digest,'') !~ '^sha256:[0-9a-f]{64}$'
    then
      hard:=hard||jsonb_build_array('scope_authority_packet_shape_invalid');
    else
      packet_body:=packet-'sha256';
      expected_digest:='sha256:'||
        encode(extensions.digest(convert_to(packet_body::text,'UTF8'),'sha256'),'hex');
      if scope_digest is distinct from expected_digest
         or packet->>'sha256' is distinct from expected_digest then
        hard:=hard||jsonb_build_array('scope_authority_packet_digest_mismatch');
      end if;
    end if;

  elsif p_step_id='semantic_judge' then
    select * into input_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='input_validate'
      and status='ACTIVE_ENFORCEMENT';
    select * into input_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='input_validate';

    select * into execute_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='execute_profile'
      and status='ACTIVE_ENFORCEMENT';
    select * into execute_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='execute_profile';

    if input_step.step_id is null
       or input_step.status<>input_binding.clean_result_value then
      hard:=hard||jsonb_build_array('input_validate_predecessor_not_clean');
    end if;
    if execute_step.step_id is null
       or execute_step.status<>execute_binding.clean_result_value then
      hard:=hard||jsonb_build_array('execute_profile_predecessor_not_clean');
    end if;

    scope_digest:=input_step.evidence_payload->>'scope_authority_packet_sha256';
    candidate_digest:=execute_step.evidence_payload->>'candidate_digest';
    semantic_result:=p_evidence_payload->'semantic_judge_result';
    canonical_read_judge:=public.lf_profile_execution_canonical_read_judge_v1(p_execution_id);

    if jsonb_typeof(semantic_result)<>'object'
       or semantic_result->>'status' is distinct from 'PASS'
       or semantic_result->>'verdict' is distinct from 'PASS_INDEPENDENT_SEMANTIC'
       or semantic_result->>'validator_status' is distinct from 'PASS'
       or coalesce((semantic_result->>'producer_independence_proven')::boolean,false) is not true
       or not (
         coalesce((semantic_result->>'model_call_count')::integer,0)=1
         or (
           coalesce((semantic_result->>'model_call_count')::integer,-1)=0
           and semantic_result->>'judge_mode'='DETERMINISTIC_CANONICAL_READ_V1'
           and canonical_read_judge->>'status'='PASS'
           and semantic_result is not distinct from canonical_read_judge
         )
       )
       or coalesce(candidate_digest,'') !~ '^sha256:[0-9a-f]{64}$'
       or coalesce(scope_digest,'') !~ '^sha256:[0-9a-f]{64}$'
       or 'sha256:'||coalesce(semantic_result->>'candidate_sha256','')
          is distinct from candidate_digest
       or 'sha256:'||coalesce(semantic_result->>'scope_packet_sha256','')
          is distinct from scope_digest
       or jsonb_typeof(semantic_result->'result')<>'object'
       or semantic_result#>>'{result,verdict}'
          is distinct from 'PASS_INDEPENDENT_SEMANTIC'
       or semantic_result#>>'{result,candidate_sha256}'
          is distinct from semantic_result->>'candidate_sha256'
       or semantic_result#>>'{result,scope_packet_sha256}'
          is distinct from semantic_result->>'scope_packet_sha256'
       or jsonb_typeof(p_evidence_payload->'unsupported_claims')<>'array'
       or jsonb_array_length(p_evidence_payload->'unsupported_claims')<>0
       or jsonb_typeof(semantic_result#>'{result,unsupported_claims}')<>'array'
       or jsonb_array_length(semantic_result#>'{result,unsupported_claims}')<>0
       or jsonb_typeof(semantic_result#>'{result,blocking_codes}')<>'array'
       or jsonb_array_length(semantic_result#>'{result,blocking_codes}')<>0
    then
      hard:=hard||jsonb_build_array('semantic_judge_v2_not_pass');
    end if;

  elsif p_step_id='report_output' then
    select * into semantic_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='semantic_judge'
      and status='ACTIVE_ENFORCEMENT';
    select * into semantic_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='semantic_judge';

    if semantic_step.step_id is null
       or semantic_step.status<>semantic_binding.clean_result_value then
      hard:=hard||jsonb_build_array('semantic_judge_predecessor_not_clean');
    end if;

    if p_evidence_payload->>'result' is distinct from 'PASS_INDEPENDENT_SEMANTIC'
       or p_evidence_payload->>'profile_code' is distinct from e.target_code
       or p_evidence_payload->>'execution_id' is distinct from p_execution_id
       or coalesce((p_evidence_payload->>'no_write_performed')::boolean,false) is not true
       or p_evidence_payload->>'candidate_sha256'
          is distinct from semantic_step.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
       or p_evidence_payload->>'scope_packet_sha256'
          is distinct from semantic_step.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}'
    then
      hard:=hard||jsonb_build_array('report_output_semantic_binding_invalid');
    end if;
  end if;

  if jsonb_array_length(hard)>0 then
    return jsonb_build_object(
      'valid',false,
      'code','PROFILE_EXECUTION_SERVER_VALIDATION_V2_FAILED',
      'details',jsonb_build_object('step_id',p_step_id,'hard_fails',hard),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','PROFILE_EXECUTION_SERVER_VALIDATED_V2',
    'details',jsonb_build_object('step_id',p_step_id,'execution_id',p_execution_id),
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.lf_profile_result_router_return_prepare_v1(p_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
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

CREATE OR REPLACE FUNCTION public.lf_profile_result_router_return_classify_v1(p_profile_output jsonb, p_original_request text, p_execution_id text, p_profile_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_output_type text:=upper(coalesce(p_profile_output->>'output_type',''));
  v_pipeline_action text:=upper(coalesce(p_profile_output->>'pipeline_action',''));
  v_verdict text:=upper(coalesce(p_profile_output->>'verdict',''));
  v_status text:=upper(coalesce(p_profile_output->>'status',''));
  v_self_verdict text:=upper(coalesce(p_profile_output->>'self_verdict',''));
  v_routing jsonb:=coalesce(p_profile_output->'routing','null'::jsonb);
  v_repair_execution jsonb:=coalesce(p_profile_output->'repair_execution','null'::jsonb);
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

  IF jsonb_typeof(v_repair_execution)='object'
     AND upper(coalesce(v_repair_execution->>'mode',''))='EXECUTED_WITH_READBACK'
  THEN
    IF p_profile_code<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
       OR coalesce((v_repair_execution->>'returned_to_router')::boolean,false) IS NOT TRUE
       OR coalesce((v_repair_execution->>'promotion_performed')::boolean,true) IS NOT FALSE
       OR nullif(btrim(coalesce(v_repair_execution->>'authority_ref','')),'') IS NULL
       OR jsonb_typeof(v_repair_execution->'changes')<>'array'
       OR jsonb_array_length(v_repair_execution->'changes')=0
       OR jsonb_typeof(v_repair_execution->'preserved_constraints')<>'array'
       OR jsonb_array_length(v_repair_execution->'preserved_constraints')=0
       OR jsonb_typeof(v_repair_execution->'readback_refs')<>'array'
       OR jsonb_array_length(v_repair_execution->'readback_refs')=0
       OR nullif(btrim(coalesce(v_repair_execution->>'rollback_ref','')),'') IS NULL
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_SRCR_EXECUTED_REPAIR_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:='SYSTEMIC_REPAIR_EXECUTED_WITH_READBACK';
    v_payload:=jsonb_build_object(
      'profile_status',p_profile_output->>'status',
      'profile_pack_id',p_profile_output->>'profile_pack_id',
      'repair_execution',v_repair_execution,
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'next_gate',p_profile_output->'next_gate'
    );

  ELSIF v_output_type='PRODUCT_MISSING_INPUT_STATE' THEN
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

  ELSIF jsonb_typeof(v_routing)='object'
        AND upper(coalesce(v_routing->>'pipeline_action','')) IN (
          'CONTINUE',
          'CONTINUE_WITH_RESTRICTIONS'
        ) THEN

    IF upper(coalesce(v_routing->>'via',''))<>'ORCHESTRATOR'
       OR nullif(btrim(coalesce(v_routing->>'resolution_target','')),'') IS NULL
       OR upper(coalesce(v_routing->>'resolution_target',''))='NONE'
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_CONTINUE_ROUTING_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:=case
      when upper(v_routing->>'pipeline_action')='CONTINUE_WITH_RESTRICTIONS'
        then 'PROFILE_CONTINUE_WITH_RESTRICTIONS'
      else 'PROFILE_CONTINUE'
    end;

    v_payload:=jsonb_build_object(
      'profile_status',p_profile_output->>'status',
      'verdict',p_profile_output->>'verdict',
      'routing',v_routing,
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'repair_actions',coalesce(p_profile_output->'repair_actions','[]'::jsonb),
      'remaining_risks',coalesce(p_profile_output->'remaining_risks','[]'::jsonb),
      'next_gate',p_profile_output->>'next_gate',
      'upstream_profile_output_sha256',
        'sha256:'||encode(
          extensions.digest(convert_to(p_profile_output::text,'UTF8'),'sha256'),
          'hex'
        ),
      'upstream_profile_output',p_profile_output
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


-- Source hashes MUST match exact live function source before test patch.
DO $assert$
BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)'::regprocedure)) <> 'e16131b4a542c71867e59730ca14b253'
  OR md5(pg_get_functiondef('public.lf_profile_execution_trust_validation_v2(text,text,jsonb)'::regprocedure)) <> 'c71964f030d7c2f9bf90101f541a6e6b'
  OR md5(pg_get_functiondef('public.lf_profile_result_router_return_prepare_v1(text)'::regprocedure)) <> '8bf503bf17f038a18124783c038d9793'
 THEN RAISE EXCEPTION 'ISOLATED_PREIMAGE_DOES_NOT_MATCH_LIVE_BASELINE'; END IF;
END $assert$;
