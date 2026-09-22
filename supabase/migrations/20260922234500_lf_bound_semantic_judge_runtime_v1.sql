begin;

create or replace function public.lf_profile_semantic_judge_trust_v1(
  p_execution_id text,
  p_evidence_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','extensions'
as $function$
declare
  e public.lf_operation_execution%rowtype;
  ep public.lf_operation_execution_steps%rowtype;
  ov public.lf_operation_execution_steps%rowtype;
  result jsonb;
  validation jsonb;
  scope_packet jsonb;
  evidence_manifest jsonb;
  expected_candidate text;
  expected_scope_fp text;
  expected_evidence_fp text;
  reviewer_id text;
  reviewer_provider text;
  source_prefix text;
  hard jsonb := '[]'::jsonb;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or p_evidence_payload is null
     or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object('valid',false,'code','BOUND_SEMANTIC_TRUST_INPUT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  select * into e from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or e.operation_code<>'EJECUCION_PERFIL_LF' or e.target_type<>'PERFIL' or e.status<>'IN_PROGRESS' then
    hard:=hard||jsonb_build_array('execution_binding_invalid');
  end if;

  if jsonb_array_length(hard)=0 then
    select * into ep from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='execute_profile';
    if not found or ep.status<>'STEP_PASS_WITH_EVIDENCE' then hard:=hard||jsonb_build_array('execute_profile_predecessor_not_clean'); end if;
    select * into ov from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='output_validate';
    if not found or ov.status<>'STEP_PASS_WITH_EVIDENCE' then hard:=hard||jsonb_build_array('output_validate_predecessor_not_clean'); end if;
  end if;

  scope_packet:=e.manifest->'semantic_scope_authority_packet';
  evidence_manifest:=ep.evidence_payload->'evidence_manifest';
  result:=p_evidence_payload->'semantic_judge_result';
  validation:=p_evidence_payload->'semantic_result_validation';
  reviewer_id:=p_evidence_payload->>'reviewer_execution_id';
  reviewer_provider:=p_evidence_payload->>'reviewer_runtime_provider';

  if jsonb_typeof(scope_packet)<>'object' then hard:=hard||jsonb_build_array('scope_authority_packet_missing'); end if;
  if jsonb_typeof(evidence_manifest)<>'object' then hard:=hard||jsonb_build_array('evidence_manifest_missing'); end if;
  if jsonb_typeof(result)<>'object' then hard:=hard||jsonb_build_array('semantic_result_missing'); end if;
  if jsonb_typeof(validation)<>'object' then hard:=hard||jsonb_build_array('semantic_result_validation_missing'); end if;

  if reviewer_id is null or btrim(reviewer_id)='' or reviewer_id=p_execution_id then
    hard:=hard||jsonb_build_array('reviewer_execution_not_independent');
  end if;
  if reviewer_provider is null or btrim(reviewer_provider)='' then hard:=hard||jsonb_build_array('reviewer_provider_missing'); end if;
  if p_evidence_payload->>'producer_execution_id' is distinct from p_execution_id then hard:=hard||jsonb_build_array('producer_execution_binding_mismatch'); end if;

  if jsonb_typeof(result)='object' then
    if result->>'status' is distinct from 'PASS'
       or result->>'verdict' is distinct from 'PASS_INDEPENDENT_SEMANTIC'
       or result->>'reviewer_execution_id' is distinct from reviewer_id
       or result->>'reviewer_context_mode' is distinct from 'ISOLATED_NO_PRODUCER_PRIVATE_CONTEXT'
       or jsonb_typeof(result->'review_input_classes')<>'array'
       or not ((result->'review_input_classes') @> '["SCOPE_AUTHORITY_PACKET","EXACT_CANDIDATE","EVIDENCE_MANIFEST","CURRENT_AUTHORITY_REFS"]'::jsonb)
       or not ((result->'review_input_classes') <@ '["SCOPE_AUTHORITY_PACKET","EXACT_CANDIDATE","EVIDENCE_MANIFEST","CURRENT_AUTHORITY_REFS"]'::jsonb)
       or jsonb_array_length(result->'review_input_classes')<>4 then
      hard:=hard||jsonb_build_array('semantic_result_independence_invalid');
    end if;
    if coalesce(result->>'candidate_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(result->>'scope_packet_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(result->>'evidence_manifest_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(result->>'review_input_sha256','') !~ '^[0-9a-f]{64}$' then
      hard:=hard||jsonb_build_array('semantic_result_digest_shape_invalid');
    end if;
  end if;

  expected_candidate:=regexp_replace(coalesce(ep.evidence_payload->>'candidate_digest',''),'^sha256:','');
  if jsonb_typeof(result)='object' and result->>'candidate_sha256' is distinct from expected_candidate then
    hard:=hard||jsonb_build_array('candidate_digest_mismatch');
  end if;

  if jsonb_typeof(scope_packet)='object' then
    expected_scope_fp:='sha256:'||encode(extensions.digest(convert_to(scope_packet::text,'UTF8'),'sha256'),'hex');
    if p_evidence_payload->>'scope_packet_server_fingerprint' is distinct from expected_scope_fp then
      hard:=hard||jsonb_build_array('scope_packet_server_readback_mismatch');
    end if;
  end if;
  if jsonb_typeof(evidence_manifest)='object' then
    expected_evidence_fp:='sha256:'||encode(extensions.digest(convert_to(evidence_manifest::text,'UTF8'),'sha256'),'hex');
    if p_evidence_payload->>'evidence_manifest_server_fingerprint' is distinct from expected_evidence_fp then
      hard:=hard||jsonb_build_array('evidence_manifest_server_readback_mismatch');
    end if;
  end if;

  if jsonb_typeof(validation)='object' then
    if validation->>'status' is distinct from 'PASS'
       or coalesce((validation->>'exit_code')::integer,-1)<>0
       or jsonb_typeof(validation->'blocking_codes')<>'array'
       or jsonb_array_length(validation->'blocking_codes')<>0 then
      hard:=hard||jsonb_build_array('semantic_result_validator_not_pass');
    end if;
  end if;

  if jsonb_typeof(p_evidence_payload->'unsupported_claims')<>'array'
     or jsonb_array_length(p_evidence_payload->'unsupported_claims')<>0 then
    hard:=hard||jsonb_build_array('unsupported_claims_not_empty');
  end if;

  source_prefix:='github://'||coalesce(e.target_repo,'')||'@'||coalesce(e.manifest->>'profile_source_revision','')||'/';
  if coalesce(p_evidence_payload->>'judge_source_ref','') not like source_prefix||'%/judges/%'
     or coalesce(p_evidence_payload->>'validator_source_ref','') not like source_prefix||'%/validators/%' then
    hard:=hard||jsonb_build_array('semantic_source_revision_binding_invalid');
  end if;

  if jsonb_array_length(hard)>0 then
    return jsonb_build_object('valid',false,'code','BOUND_SEMANTIC_JUDGE_SERVER_VALIDATION_FAILED','details',jsonb_build_object('execution_id',p_execution_id,'hard_fails',hard),'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;
  return jsonb_build_object('valid',true,'code','BOUND_SEMANTIC_JUDGE_SERVER_VALIDATED','details',jsonb_build_object('execution_id',p_execution_id,'reviewer_execution_id',reviewer_id,'scope_packet_server_fingerprint',expected_scope_fp,'evidence_manifest_server_fingerprint',expected_evidence_fp),'server_assertions',jsonb_build_array('server_validated','reviewer_execution_distinct','scope_packet_readback','evidence_manifest_readback','exact_profile_revision_bound'),'server_hard_fails','[]'::jsonb);
end
$function$;

create or replace function public.lf_record_profile_semantic_judge_step_v1(
  p_execution_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','extensions'
as $function$
declare
  v_trust jsonb;
  v_event_id bigint;
  v_payload jsonb;
  v_result jsonb;
begin
  v_trust:=public.lf_profile_semantic_judge_trust_v1(p_execution_id,p_evidence_payload);
  v_payload:=coalesce(p_evidence_payload,'{}'::jsonb);
  if coalesce((v_trust->>'valid')::boolean,false) then
    insert into public.lf_eventos(evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id)
    values(
      'PROFILE_SEMANTIC_JUDGE_RECEIPT','PROFILE_EXECUTION',p_execution_id,
      'Independent bound semantic judge receipt validated server-side.','INFO',
      jsonb_build_object(
        'receipt_version','BOUND_SEMANTIC_JUDGE_RECEIPT_V1',
        'execution_id',p_execution_id,
        'reviewer_execution_id',p_evidence_payload->>'reviewer_execution_id',
        'reviewer_runtime_provider',p_evidence_payload->>'reviewer_runtime_provider',
        'candidate_sha256',p_evidence_payload#>>'{semantic_judge_result,candidate_sha256}',
        'scope_packet_sha256',p_evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}',
        'evidence_manifest_sha256',p_evidence_payload#>>'{semantic_judge_result,evidence_manifest_sha256}',
        'review_input_sha256',p_evidence_payload#>>'{semantic_judge_result,review_input_sha256}',
        'judge_source_ref',p_evidence_payload->>'judge_source_ref',
        'validator_source_ref',p_evidence_payload->>'validator_source_ref',
        'server_validation',v_trust
      ),
      'BOUND_SEMANTIC_JUDGE',p_actor_execution_id
    ) returning id into v_event_id;
    v_payload:=v_payload||jsonb_build_object(
      'semantic_review_receipt_ref','supabase://public.lf_eventos/'||v_event_id::text||'#payload',
      'semantic_review_receipt_event_id',v_event_id
    );
  end if;

  v_result:=public.lf_record_operation_step_core_v1(
    p_execution_id,'semantic_judge',p_evidence_ref,v_payload,p_actor_execution_id,
    'EJECUCION_PERFIL_LF','PERFIL',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    v_trust,true,'lf_record_profile_semantic_judge_step_v1'
  );
  return v_result||jsonb_build_object('semantic_review_receipt_event_id',v_event_id,'semantic_trust',v_trust);
end
$function$;

update public.lf_operation_step_contracts
set resolver_ref='BOUND_SEMANTIC_JUDGE_V1',
    required_evidence_keys=jsonb_build_array(
      'semantic_judge_result','unsupported_claims','semantic_result_validation',
      'reviewer_execution_id','reviewer_runtime_provider','producer_execution_id',
      'judge_source_ref','validator_source_ref','scope_packet_server_fingerprint',
      'evidence_manifest_server_fingerprint'
    ),
    pass_condition=jsonb_build_object(
      'required_evidence_keys',jsonb_build_array(
        'semantic_judge_result','unsupported_claims','semantic_result_validation',
        'reviewer_execution_id','reviewer_runtime_provider','producer_execution_id',
        'judge_source_ref','validator_source_ref','scope_packet_server_fingerprint',
        'evidence_manifest_server_fingerprint'
      ),
      'server_trust_function','public.lf_profile_semantic_judge_trust_v1',
      'dedicated_recorder','public.lf_record_profile_semantic_judge_step_v1',
      'independence_required',true,
      'must_not_be_generic',true
    ),
    notes='Bound semantic judge V1: independent reviewer execution, isolated context, exact profile revision, server readback and dedicated receipt.',
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-RUNTIME-BOUND-SEMANTIC-JUDGE-20260922-001'
where operation_code='EJECUCION_PERFIL_LF' and step_id='semantic_judge';

revoke all on function public.lf_profile_semantic_judge_trust_v1(text,jsonb) from public;
revoke all on function public.lf_record_profile_semantic_judge_step_v1(text,text,jsonb,text) from public;
grant execute on function public.lf_profile_semantic_judge_trust_v1(text,jsonb) to service_role;
grant execute on function public.lf_record_profile_semantic_judge_step_v1(text,text,jsonb,text) to service_role;

commit;
