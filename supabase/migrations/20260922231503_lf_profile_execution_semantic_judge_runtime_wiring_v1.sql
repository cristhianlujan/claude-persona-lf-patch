
begin;
-- LF_PROFILE_SEMANTIC_JUDGE_RUNTIME_WIRING_V1
-- Governed by EXEC-RUNTIME-SEMANTIC-JUDGE-WIRING-20260922-001.
-- Sandbox apply only. No automatic promotion. V2 composes the existing V1 trust boundary.

do $pre$
begin
  if not exists (
    select 1
    from public.lf_operation_execution e
    join public.lf_operation_execution_steps s
      on s.execution_id=e.execution_id
     and s.step_id='pre_write_execution_binding_gate'
     and s.status='STEP_PASS_WITH_EVIDENCE'
    where e.execution_id='EXEC-RUNTIME-SEMANTIC-JUDGE-WIRING-20260922-001'
      and e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and e.target_type='OPERATION_CODE'
      and e.target_code='EJECUCION_PERFIL_LF'
      and e.status='IN_PROGRESS'
      and e.manifest->>'source_baseline_sha'='cd8546d3f6beca16bc1160e92b67b29f929ec12e'
      and coalesce((e.manifest->>'sandbox_apply_authorized')::boolean,false)=true
      and coalesce((e.manifest->>'production_apply_authorized')::boolean,true)=false
  ) then
    raise exception 'SEMANTIC_JUDGE_WIRING_PREWRITE_AUTHORITY_MISSING';
  end if;
end
$pre$;

create or replace function public.lf_profile_execution_scope_authority_packet_v1(
  p_execution_id text,
  p_input_literal text,
  p_input_source_ref text
) returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public','extensions'
as $scope$
declare
  e public.lf_operation_execution%rowtype;
  reqs jsonb := '[]'::jsonb;
  constraints_json jsonb := '[]'::jsonb;
  forbidden_json jsonb := '[]'::jsonb;
  packet_body jsonb;
  packet jsonb;
  digest_value text;
  execution_ref text;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_input_literal,'')),'') is null
     or nullif(btrim(coalesce(p_input_source_ref,'')),'') is null then
    return jsonb_build_object('status','BLOCKED','code','SCOPE_AUTHORITY_PACKET_INPUT_INVALID');
  end if;

  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found or e.operation_code<>'EJECUCION_PERFIL_LF' or e.target_type<>'PERFIL' then
    return jsonb_build_object('status','BLOCKED','code','SCOPE_AUTHORITY_EXECUTION_INVALID');
  end if;

  execution_ref:='supabase://public.lf_operation_execution/'||p_execution_id||'#manifest';
  reqs:=jsonb_build_array(jsonb_build_object(
    'id','REQ-INPUT-LITERAL',
    'statement',p_input_literal,
    'source_ref',p_input_source_ref,
    'materiality','MATERIAL'
  ));

  constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
    'id','CON-TARGET-EXACT',
    'statement','Execution target must remain exact: '||e.target_type||'/'||e.target_code||'.',
    'source_ref',execution_ref,
    'materiality','BLOCKING'
  ));

  if coalesce((e.manifest->>'read_only')::boolean,false) then
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-READ-ONLY','statement','Execution is read-only.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  end if;

  if coalesce((e.manifest->>'no_write')::boolean,false) then
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-NO-WRITE','statement','No operational write is authorized.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
    forbidden_json:=forbidden_json||jsonb_build_array(jsonb_build_object(
      'id','FORBID-WRITE','statement','Do not perform operational mutation.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  end if;

  if coalesce((e.manifest->>'no_promotion')::boolean,false) then
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-NO-PROMOTION','statement','No promotion is authorized.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
    forbidden_json:=forbidden_json||jsonb_build_array(jsonb_build_object(
      'id','FORBID-PROMOTION','statement','Do not promote or activate the target.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  end if;

  if coalesce((e.manifest->>'automatic_impact')::boolean,false)=false then
    forbidden_json:=forbidden_json||jsonb_build_array(jsonb_build_object(
      'id','FORBID-AUTOMATIC-IMPACT','statement','Do not introduce automatic impact.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  end if;

  if coalesce((e.manifest->>'prior_output_reuse_forbidden')::boolean,false) then
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-NO-PRIOR-OUTPUT-REUSE','statement','Prior candidate/output reuse is forbidden.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  end if;

  if coalesce((e.manifest->>'blind_holdout_required')::boolean,false) then
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-BLIND-HOLDOUT','statement','Blind holdout separation must be preserved.',
      'source_ref',execution_ref,'materiality','MATERIAL'
    ));
  end if;

  packet_body:=jsonb_build_object(
    'packet_version','LF_SCOPE_AUTHORITY_PACKET_V1',
    'execution_id',p_execution_id,
    'subject_ref',execution_ref,
    'authorized_requirements',reqs,
    'constraints',constraints_json,
    'forbidden_changes',forbidden_json,
    'authority_precedence',jsonb_build_array(
      jsonb_build_object(
        'rank',1,'source_ref',execution_ref,
        'reason','Exact execution manifest and literal request define authorized scope.'
      ),
      jsonb_build_object(
        'rank',2,
        'source_ref','supabase://public.v_lf_operation_policy_snapshot/EJECUCION_PERFIL_LF',
        'reason','Canonical operation policies constrain execution behavior.'
      )
    ),
    'related_context_refs','[]'::jsonb,
    'source_refs',jsonb_build_array(
      execution_ref,
      p_input_source_ref,
      'supabase://public.v_lf_operation_policy_snapshot/EJECUCION_PERFIL_LF'
    ),
    'compiled_at',to_jsonb(e.started_at),
    'canonicalization_rule','POSTGRES_JSONB_TEXT_UTF8_SHA256_V1'
  );

  digest_value:='sha256:'||
    encode(extensions.digest(convert_to(packet_body::text,'UTF8'),'sha256'),'hex');
  packet:=packet_body||jsonb_build_object('sha256',digest_value);

  return jsonb_build_object(
    'status','READY',
    'scope_authority_packet',packet,
    'scope_packet_sha256',digest_value,
    'canonicalization_rule','POSTGRES_JSONB_TEXT_UTF8_SHA256_V1'
  );
end
$scope$;

revoke all on function public.lf_profile_execution_scope_authority_packet_v1(text,text,text) from public;
revoke all on function public.lf_profile_execution_scope_authority_packet_v1(text,text,text) from anon;
revoke all on function public.lf_profile_execution_scope_authority_packet_v1(text,text,text) from authenticated;
grant execute on function public.lf_profile_execution_scope_authority_packet_v1(text,text,text) to service_role;

update public.lf_operation_step_contracts
set resolver_ref='public.lf_profile_execution_scope_authority_packet_v1 + BOUND_INPUT_VALIDATION',
    required_evidence_keys='["input_scope","activation_trigger_match","scope_authority_packet","scope_authority_packet_sha256"]'::jsonb,
    output_payload='["input_scope","activation_trigger_match","scope_authority_packet","scope_authority_packet_sha256"]'::jsonb,
    pass_condition=jsonb_set(
      coalesce(pass_condition,'{}'::jsonb),
      '{required_evidence_keys}',
      '["input_scope","activation_trigger_match","scope_authority_packet","scope_authority_packet_sha256"]'::jsonb,
      true
    ),
    notes='Supabase-only operational contract. Materializes producer-independent scope authority packet before profile execution; no Drive dereference.',
    updated_by_execution_id='EXEC-RUNTIME-SEMANTIC-JUDGE-WIRING-20260922-001',
    updated_at=clock_timestamp()
where operation_code='EJECUCION_PERFIL_LF'
  and step_id='input_validate'
  and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_step_judge_bindings
set required_evidence_keys='["input_scope","activation_trigger_match","scope_authority_packet","scope_authority_packet_sha256"]'::jsonb,
    updated_by_execution_id='EXEC-RUNTIME-SEMANTIC-JUDGE-WIRING-20260922-001',
    updated_at=clock_timestamp()
where operation_code='EJECUCION_PERFIL_LF'
  and step_id='input_validate'
  and status='ACTIVE_ENFORCEMENT';

create or replace function public.lf_profile_execution_trust_validation_v2(
  p_execution_id text,
  p_step_id text,
  p_evidence_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','extensions'
as $trust$
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

    if jsonb_typeof(semantic_result)<>'object'
       or semantic_result->>'status' is distinct from 'PASS'
       or semantic_result->>'verdict' is distinct from 'PASS_INDEPENDENT_SEMANTIC'
       or semantic_result->>'validator_status' is distinct from 'PASS'
       or coalesce((semantic_result->>'producer_independence_proven')::boolean,false) is not true
       or coalesce((semantic_result->>'model_call_count')::integer,0)<>1
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
$trust$;

create or replace function public.lf_record_profile_execution_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $rec$
declare
  v_trust jsonb;
begin
  v_trust:=public.lf_profile_execution_trust_validation_v2(
    p_execution_id,p_step_id,p_evidence_payload
  );

  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'EJECUCION_PERFIL_LF','PERFIL',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    v_trust,true,'lf_record_profile_execution_step_v1'
  );
end
$rec$;

comment on function public.lf_profile_execution_scope_authority_packet_v1(text,text,text) is
'LF_PROFILE_SEMANTIC_JUDGE_RUNTIME_WIRING_V1. Builds producer-independent exact execution scope before execute_profile. Digest authority is PostgreSQL jsonb::text UTF-8 SHA256 and is server-owned.';
comment on function public.lf_profile_execution_trust_validation_v2(text,text,jsonb) is
'LF_PROFILE_SEMANTIC_JUDGE_RUNTIME_WIRING_V1. Canonical V2 trust boundary composed over V1. Adds server-owned scope packet, exact candidate/scope binding, producer-independent semantic PASS, and report-output binding.';
comment on function public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text) is
'Canonical EJECUCION_PERFIL_LF recorder. Trust is derived by lf_profile_execution_trust_validation_v2 and step status by the operation-neutral recorder core.';

do $post$
declare
  v text;
begin
  select pg_get_functiondef(
    'public.lf_profile_execution_trust_validation_v2(text,text,jsonb)'::regprocedure
  ) into v;
  if position('scope_authority_packet_digest_mismatch' in v)=0
     or position('producer_independence_proven' in v)=0
     or position('report_output_semantic_binding_invalid' in v)=0 then
    raise exception 'SEMANTIC_JUDGE_WIRING_TRUST_POSTCHECK_FAILED';
  end if;

  select pg_get_functiondef(
    'public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)'::regprocedure
  ) into v;
  if position('lf_profile_execution_trust_validation_v2' in v)=0 then
    raise exception 'SEMANTIC_JUDGE_WIRING_RECORDER_POSTCHECK_FAILED';
  end if;

  if not exists (
    select 1
    from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='input_validate'
      and required_evidence_keys @>
          '["scope_authority_packet","scope_authority_packet_sha256"]'::jsonb
  ) then
    raise exception 'SEMANTIC_JUDGE_WIRING_INPUT_CONTRACT_POSTCHECK_FAILED';
  end if;
end
$post$;

commit;
