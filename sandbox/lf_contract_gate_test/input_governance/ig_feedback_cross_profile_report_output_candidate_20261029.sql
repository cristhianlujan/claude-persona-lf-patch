-- IG profile-neutral sidecar: SANDBOX/ROLLBACK ONLY, not production.
-- Uses existing execute_profile receipt, report_output trust gate, router_return_prepare_v1.
-- No profile schema, selectors, ACL, queues, or tables are modified.
-- Helper is private.SECURITY INVOKER; anon/authenticated have no private schema USAGE.
BEGIN;
DO $precheck$ BEGIN
  IF md5(pg_get_functiondef('public.lf_profile_execution_trust_validation_v2(text,text,jsonb)'::regprocedure))<>'c71964f030d7c2f9bf90101f541a6e6b'
     OR md5(pg_get_functiondef('public.lf_profile_result_router_return_prepare_v1(text)'::regprocedure))
       <>'8bf503bf17f038a18124783c038d9793'
  THEN RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_TRANSVERSAL_SOURCE_DRIFT'; END IF;
END $precheck$;

CREATE OR REPLACE FUNCTION private.lf_profile_ig_feedback_validate_v1(
 p_execution_id text,p_profile_code text,p_feedback jsonb
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','public','programacion','extensions'
AS $fb$
DECLARE
 e public.lf_operation_execution%rowtype;
 x public.lf_operation_execution_steps%rowtype;
 i public.lf_operation_execution_steps%rowtype;
 g jsonb; k text; expected_sha text;
BEGIN
 IF jsonb_typeof(p_feedback) IS DISTINCT FROM 'object' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_SHAPE_INVALID');
 END IF;
 IF p_feedback->>'schema_version' IS DISTINCT FROM 'IG_PROFILE_FEEDBACK_V1'
  OR p_feedback->>'source_execution_id' IS DISTINCT FROM p_execution_id
  OR p_feedback->>'source_profile_code' IS DISTINCT FROM p_profile_code
  OR jsonb_typeof(p_feedback->'ig') IS DISTINCT FROM 'object'
  OR coalesce(p_feedback->>'source_profile_output_sha256','') !~ '^sha256:[a-f0-9]{64}$'
  OR coalesce(p_feedback->>'kind','') NOT IN
   ('EVIDENCE_CHALLENGE','NONCANONICAL_RULE_PROPOSAL','UNSUPPORTED_DISAGREEMENT')
  OR nullif(btrim(coalesce(p_feedback->>'reason','')),'') IS NULL
 THEN RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_SHAPE_INVALID'); END IF;
 -- Strictly separate shape guards from object iteration: PG SQL need not
 -- short-circuit OR predicates. A JSON null/array must return a typed blocker.
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_feedback) z(k)
   WHERE z.k NOT IN ('schema_version','source_execution_id','source_profile_code',
     'source_profile_output_sha256','ig','kind','reason','evidence_refs',
     'requested_resolution','canonical_status','proposed_change'))
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_feedback->'ig') z(k)
   WHERE z.k NOT IN ('run_id','pantalla_id','family_code','source_snapshot_sha256'))
 THEN RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_FORBIDDEN_KEYS'); END IF;
 g:=p_feedback->'ig'; k:=p_feedback->>'kind';
 IF coalesce(g->>'run_id','') !~ '^[1-9][0-9]{0,15}$'
  OR coalesce(g->>'pantalla_id','') !~ '^[1-9][0-9]{0,8}$'
  OR coalesce(g->>'source_snapshot_sha256','') !~ '^[0-9a-f]{64}$'
  OR nullif(btrim(coalesce(g->>'family_code','')),'') IS NULL
 THEN RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_IG_REF_INVALID'); END IF;
 IF k='EVIDENCE_CHALLENGE' THEN
   IF p_feedback->>'requested_resolution' IS DISTINCT FROM 'FOCAL_REVIEW_ONLY'
    OR jsonb_typeof(p_feedback->'evidence_refs') IS DISTINCT FROM 'array'
   THEN RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_CHALLENGE_INVALID'); END IF;
   IF jsonb_array_length(p_feedback->'evidence_refs')=0 OR EXISTS(
     SELECT 1 FROM jsonb_array_elements(p_feedback->'evidence_refs') z(v)
     WHERE jsonb_typeof(z.v)<>'string' OR nullif(btrim(z.v#>>'{}'),'') IS NULL
   ) THEN RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_EVIDENCE_MISSING'); END IF;
 ELSIF k='NONCANONICAL_RULE_PROPOSAL' THEN
   IF p_feedback->>'requested_resolution' IS DISTINCT FROM 'OWNER_DECISION_REQUIRED'
    OR p_feedback->>'canonical_status' IS DISTINCT FROM 'PROPOSED_NOT_CANONICAL'
    OR nullif(btrim(coalesce(p_feedback->>'proposed_change','')),'') IS NULL
   THEN RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_PROPOSAL_INVALID'); END IF;
 ELSE
   IF p_feedback->>'requested_resolution' IS DISTINCT FROM 'NO_RERUN'
   THEN RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_UNSUPPORTED_RERUN_FORBIDDEN'); END IF;
 END IF;
 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id AND operation_code='EJECUCION_PERFIL_LF'
  AND target_type='PERFIL' AND target_code=p_profile_code
  AND status IN ('IN_PROGRESS','COMPLETED');
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_EXECUTION_INVALID'); END IF;
 SELECT * INTO x FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='execute_profile'
  AND status='STEP_PASS_WITH_EVIDENCE';
 IF NOT FOUND OR jsonb_typeof(x.evidence_payload->'profile_output')<>'object'
 THEN RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_OUTPUT_MISSING'); END IF;
 -- The feedback must originate in the same execute_profile receipt as the
 -- specialist's validated native output. A report-stage caller cannot invent
 -- a new opinion and attribute it to the specialist after the judge.
 IF x.evidence_payload->'ig_profile_feedback_candidate' IS DISTINCT FROM p_feedback
   OR nullif(x.evidence_ref,'') IS NULL
 THEN
   RETURN jsonb_build_object('status','BLOCKED',
     'code','PROFILE_IG_FEEDBACK_SPECIALIST_ORIGIN_NOT_PROVEN');
 END IF;
 expected_sha:='sha256:'||encode(extensions.digest(
   convert_to((x.evidence_payload->'profile_output')::text,'UTF8'),'sha256'),'hex');
 IF expected_sha IS DISTINCT FROM p_feedback->>'source_profile_output_sha256'
 THEN RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_OUTPUT_SHA_MISMATCH'); END IF;
 SELECT * INTO i FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='input_validate'
  AND status='STEP_PASS_WITH_EVIDENCE';
 IF NOT FOUND OR i.evidence_payload#>>'{input_governance,status}' IS DISTINCT FROM 'READY'
 THEN RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_IG_NOT_CONSUMED'); END IF;
 IF NOT EXISTS(
   SELECT 1 FROM programacion.input_readiness_runs r
   JOIN programacion.input_family_assessments a ON a.run_id=r.id
   WHERE r.id=(g->>'run_id')::bigint
     AND r.pantalla_id=(g->>'pantalla_id')::integer
     AND r.status='COMPLETED'
     AND r.source_snapshot_sha256=g->>'source_snapshot_sha256'
     AND a.family_code=g->>'family_code'
     AND i.evidence_payload#>>'{input_governance,run_id}'=r.id::text
     AND i.evidence_payload#>>'{input_governance,pantalla_id}'=r.pantalla_id::text
     AND i.evidence_payload#>>'{input_governance,context_manifest,run,source_snapshot_sha256}'=r.source_snapshot_sha256
 ) THEN RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_IG_FEEDBACK_RUN_BINDING_INVALID'); END IF;
 RETURN jsonb_build_object('status','VALID','code','PROFILE_IG_FEEDBACK_BOUND',
   'execution_id',p_execution_id,'profile_code',p_profile_code,
   'profile_output_sha256',expected_sha,'run_id',g->>'run_id',
   'family_code',g->>'family_code','feedback_sha256',
   'sha256:'||encode(extensions.digest(convert_to(p_feedback::text,'UTF8'),'sha256'),'hex'),
   'rerun_authorized',false,'promotion_authorized',false,
   'evidence_authenticity_verified',false);
END
$fb$;

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

  -- Verify the optional feedback at report gate, but read it from the
  -- ORIGINAL execute_profile evidence; never accept a report-only insertion.
  IF p_step_id='report_output' THEN
    IF p_evidence_payload ? 'ig_profile_feedback' THEN
      hard:=hard||jsonb_build_array('ig_profile_feedback_report_injection_forbidden');
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=p_execution_id
        AND s.step_id='execute_profile'
        AND s.status='STEP_PASS_WITH_EVIDENCE'
        AND s.evidence_payload ? 'ig_profile_feedback_candidate'
    ) AND (
      SELECT private.lf_profile_ig_feedback_validate_v1(
        p_execution_id,e.target_code,
        s.evidence_payload->'ig_profile_feedback_candidate'
      )->>'status'
      FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=p_execution_id
        AND s.step_id='execute_profile'
        AND s.status='STEP_PASS_WITH_EVIDENCE'
    ) IS DISTINCT FROM 'VALID' THEN
      hard:=hard||jsonb_build_array('ig_profile_feedback_binding_invalid');
    END IF;
  END IF;

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
  v_ig_feedback jsonb;
  v_ig_feedback_validation jsonb;
  v_ig_payload jsonb;
  v_ig_literal text;
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
    -- A sidecar must not silently bypass a disabled Router return contract.
    -- Authorization is checked before the optional feedback is considered.
    IF EXISTS (
      SELECT 1 FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=p_execution_id
        AND s.step_id='execute_profile'
        AND s.status='STEP_PASS_WITH_EVIDENCE'
        AND s.evidence_payload ? 'ig_profile_feedback_candidate'
    ) THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_PREPARE_V1',
        'status','BLOCKED',
        'code','PROFILE_IG_FEEDBACK_ROUTER_RETURN_NOT_AUTHORIZED',
        'execution_id',p_execution_id);
    END IF;
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

  -- The response's optional feedback is sealed with the original
  -- execute_profile step, never injected in a later report-only payload.
  SELECT s.evidence_payload->'ig_profile_feedback_candidate' INTO v_ig_feedback
  FROM public.lf_operation_execution_steps s
  WHERE s.execution_id=p_execution_id AND s.step_id='execute_profile'
    AND s.status='STEP_PASS_WITH_EVIDENCE'
  LIMIT 1;
  IF v_ig_feedback IS NOT NULL THEN
    v_ig_feedback_validation:=private.lf_profile_ig_feedback_validate_v1(
      p_execution_id,e.target_code,v_ig_feedback);
    IF v_ig_feedback_validation->>'status'<>'VALID' THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_PREPARE_V1',
        'status','BLOCKED','code','PROFILE_IG_FEEDBACK_INVALID',
        'feedback_validation',v_ig_feedback_validation);
    END IF;
    IF v_ig_feedback->>'kind'<>'UNSUPPORTED_DISAGREEMENT' THEN
      IF v_decision->>'status'='COMPLETE' THEN
        v_decision:=public.lf_profile_result_router_return_classify_v1(
          jsonb_build_object(
            'status','PASS_WITH_RESTRICTIONS',
            'routing',jsonb_build_object('via','ORCHESTRATOR',
              'pipeline_action','CONTINUE_WITH_RESTRICTIONS',
              'resolution_target','AUTHORITY_OR_CONTEXT_RESOLUTION')
          ),v_original_request,p_execution_id,e.target_code);
      END IF;
      IF v_decision->>'status'='RETURN_TO_ROUTER' THEN
        v_ig_payload:=coalesce(
          v_decision#>'{router_return_request,unresolved_payload}','{}'::jsonb
        ) || jsonb_build_object(
          'ig_profile_feedback',v_ig_feedback,
          'ig_profile_feedback_validation',v_ig_feedback_validation,
          'upstream_profile_output',v_profile_output,
          'upstream_profile_output_sha256',
            'sha256:'||encode(extensions.digest(
              convert_to(v_profile_output::text,'UTF8'),'sha256'),'hex')
        );
        v_ig_literal:='Solicitud original: '||v_original_request
          ||E'\n\nRetorno gobernado del perfil '||e.target_code||': '||v_ig_payload::text;
        v_decision:=jsonb_set(
          jsonb_set(v_decision,
            '{router_return_request,unresolved_payload}',v_ig_payload),
          '{router_return_request,stage1_literal}',to_jsonb(v_ig_literal));
      END IF;
    END IF;
  END IF;

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

-- Test the actual newly compiled helper inside the same rollback transaction.
-- No test creates an IG run, overrides a profile output, or grants privileges.
DO $postcheck$
DECLARE
  a jsonb;
  f jsonb:=jsonb_build_object(
    'schema_version','IG_PROFILE_FEEDBACK_V1',
    'source_execution_id','UNKNOWN-EXECUTION-TEST-01',
    'source_profile_code','PERFIL-UI-ARCHITECT',
    'source_profile_output_sha256','sha256:'||repeat('a',64),
    'ig',jsonb_build_object(
      'run_id',949,'pantalla_id',51,'family_code','SESSION',
      'source_snapshot_sha256',repeat('b',64)),
    'kind','EVIDENCE_CHALLENGE','reason','Test of hypothetical evidence',
    'requested_resolution','FOCAL_REVIEW_ONLY',
    'evidence_refs',jsonb_build_array('supabase://example/receipt')
  );
BEGIN
  a:=private.lf_profile_ig_feedback_validate_v1(
    'UNKNOWN-EXECUTION-TEST-01','PERFIL-UI-ARCHITECT','null'::jsonb);
  IF a->>'code'<>'PROFILE_IG_FEEDBACK_SHAPE_INVALID' THEN
    RAISE EXCEPTION 'IG_FB_POSTCHECK_JSON_NULL:%',a; END IF;

  a:=private.lf_profile_ig_feedback_validate_v1(
    'UNKNOWN-EXECUTION-TEST-01','PERFIL-UI-ARCHITECT',
    jsonb_set(f,'{ig}','[]'::jsonb));
  IF a->>'code'<>'PROFILE_IG_FEEDBACK_SHAPE_INVALID' THEN
    RAISE EXCEPTION 'IG_FB_POSTCHECK_BAD_IG_SHAPE:%',a; END IF;

  a:=private.lf_profile_ig_feedback_validate_v1(
    'UNKNOWN-EXECUTION-TEST-01','PERFIL-UI-ARCHITECT',
    f||jsonb_build_object('target_profile','PERFIL-PRODUCT-DIRECTOR-LF'));
  IF a->>'code'<>'PROFILE_IG_FEEDBACK_FORBIDDEN_KEYS' THEN
    RAISE EXCEPTION 'IG_FB_POSTCHECK_DIRECT_TARGET:%',a; END IF;

  a:=private.lf_profile_ig_feedback_validate_v1(
    'UNKNOWN-EXECUTION-TEST-01','PERFIL-UI-ARCHITECT',
    f-'evidence_refs');
  IF a->>'code'<>'PROFILE_IG_FEEDBACK_CHALLENGE_INVALID' THEN
    RAISE EXCEPTION 'IG_FB_POSTCHECK_MISSING_EVIDENCE:%',a; END IF;

  a:=private.lf_profile_ig_feedback_validate_v1(
    'UNKNOWN-EXECUTION-TEST-01','PERFIL-UI-ARCHITECT',
    jsonb_set(f,'{evidence_refs}','null'::jsonb));
  IF a->>'code'<>'PROFILE_IG_FEEDBACK_CHALLENGE_INVALID' THEN
    RAISE EXCEPTION 'IG_FB_POSTCHECK_NULL_EVIDENCE:%',a; END IF;

  a:=private.lf_profile_ig_feedback_validate_v1(
    'UNKNOWN-EXECUTION-TEST-01','PERFIL-UI-ARCHITECT',
    jsonb_set(f,'{evidence_refs}','[]'::jsonb));
  IF a->>'code'<>'PROFILE_IG_FEEDBACK_EVIDENCE_MISSING' THEN
    RAISE EXCEPTION 'IG_FB_POSTCHECK_EMPTY_EVIDENCE:%',a; END IF;

  a:=private.lf_profile_ig_feedback_validate_v1(
    'UNKNOWN-EXECUTION-TEST-01','PERFIL-UI-ARCHITECT',
    jsonb_set(f,'{evidence_refs}','{"bad":"object"}'::jsonb));
  IF a->>'code'<>'PROFILE_IG_FEEDBACK_CHALLENGE_INVALID' THEN
    RAISE EXCEPTION 'IG_FB_POSTCHECK_EVIDENCE_SHAPE:%',a; END IF;

  a:=private.lf_profile_ig_feedback_validate_v1(
    'UNKNOWN-EXECUTION-TEST-01','PERFIL-UI-ARCHITECT',
    jsonb_set(f,'{requested_resolution}','"FULL_RECURATE"'::jsonb));
  IF a->>'code'<>'PROFILE_IG_FEEDBACK_CHALLENGE_INVALID' THEN
    RAISE EXCEPTION 'IG_FB_POSTCHECK_FORCE_FULL_RECURATE:%',a; END IF;

  a:=private.lf_profile_ig_feedback_validate_v1(
    'UNKNOWN-EXECUTION-TEST-01','PERFIL-UI-ARCHITECT',
    jsonb_set(f,'{kind}','"NONCANONICAL_RULE_PROPOSAL"'::jsonb));
  IF a->>'code'<>'PROFILE_IG_FEEDBACK_PROPOSAL_INVALID' THEN
    RAISE EXCEPTION 'IG_FB_POSTCHECK_PROPOSAL_AUTHORITY:%',a; END IF;

  a:=private.lf_profile_ig_feedback_validate_v1(
    'UNKNOWN-EXECUTION-TEST-01','PERFIL-UI-ARCHITECT',
    jsonb_set(f,'{kind}','"UNSUPPORTED_DISAGREEMENT"'::jsonb));
  IF a->>'code'<>'PROFILE_IG_FEEDBACK_UNSUPPORTED_RERUN_FORBIDDEN' THEN
    RAISE EXCEPTION 'IG_FB_POSTCHECK_UNSUPPORTED_LOOP:%',a; END IF;

  a:=private.lf_profile_ig_feedback_validate_v1(
    'UNKNOWN-EXECUTION-TEST-01','PERFIL-UI-ARCHITECT',f);
  IF a->>'code'<>'PROFILE_IG_FEEDBACK_EXECUTION_INVALID' THEN
    RAISE EXCEPTION 'IG_FB_POSTCHECK_FAKE_EXECUTION:%',a; END IF;
END
$postcheck$;

-- No promotion: rollback always. Tests require isolated PostgreSQL clone.
ROLLBACK;
