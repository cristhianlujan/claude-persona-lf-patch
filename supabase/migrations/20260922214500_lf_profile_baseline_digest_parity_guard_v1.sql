begin;

-- Generic parity guard for PROFILE_RESEARCH_BASELINE_FREEZE.
-- No execution/profile/case-specific identifiers are embedded.
do $pre$
begin
  if to_regprocedure('private.fn_payload_sha256_v7(jsonb)') is null then
    raise exception 'PROFILE_BASELINE_DIGEST_PRE_CANONICAL_HELPER_MISSING';
  end if;
  if to_regprocedure('public.lf_profile_execution_research_baseline_v1(text,jsonb,text)') is null then
    raise exception 'PROFILE_BASELINE_DIGEST_PRE_FREEZE_FUNCTION_MISSING';
  end if;
  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='EJECUCION_PERFIL_LF'
      and lifecycle_state_code='OP_OPERATIONAL'
  ) then
    raise exception 'PROFILE_BASELINE_DIGEST_PRE_OPERATION_NOT_OPERATIONAL';
  end if;
end
$pre$;

create or replace function public.lf_profile_execution_research_baseline_v1(
  p_execution_id text,
  p_baseline_envelope jsonb,
  p_actor_execution_id text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions'
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  prior public.lf_operation_execution_steps%rowtype;
  prior_binding public.lf_operation_step_judge_bindings%rowtype;
  existing public.lf_operation_execution_steps%rowtype;
  step_binding public.lf_operation_step_judge_bindings%rowtype;
  mode text;
  contract jsonb;
  expected_input text;
  expected_source text;
  server_snapshot_fingerprint text;
  canonical_baseline_digest text;
  receipt_ref text;
  binding jsonb;
  payload jsonb;
  trust jsonb;
  ref text;
  binding_source text;
  binding_path_json jsonb;
  binding_path text[];
  expected_bound_value jsonb;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null then
    raise exception 'PROFILE_RESEARCH_BASELINE_EXECUTION_ID_REQUIRED';
  end if;

  select * into e from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or e.operation_code<>'EJECUCION_PERFIL_LF' or e.target_type<>'PERFIL' or e.status<>'IN_PROGRESS' then
    raise exception 'PROFILE_RESEARCH_BASELINE_EXECUTION_BINDING_INVALID:%',p_execution_id;
  end if;

  mode:=coalesce(nullif(e.manifest->>'research_baseline_mode',''),'NOT_REQUIRED');
  contract:=e.manifest->'research_baseline_contract';
  if mode not in ('NOT_REQUIRED','PRE_RESEARCH_ALWAYS') then
    raise exception 'PROFILE_RESEARCH_BASELINE_MODE_INVALID:%',mode;
  end if;

  select * into step_binding
  from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF'
    and step_id='research_baseline_freeze'
    and status='ACTIVE_ENFORCEMENT';
  if not found then raise exception 'PROFILE_RESEARCH_BASELINE_BINDING_MISSING'; end if;

  select * into existing
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id='research_baseline_freeze';
  if found and existing.status=step_binding.clean_result_value then
    return existing.evidence_payload||jsonb_build_object('replay',true);
  end if;

  select * into prior_binding
  from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF'
    and step_id='context_admission'
    and status='ACTIVE_ENFORCEMENT';
  select * into prior
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id='context_admission';
  if not found or prior.status<>prior_binding.clean_result_value then
    raise exception 'PROFILE_RESEARCH_BASELINE_CONTEXT_NOT_CLEAN:%',p_execution_id;
  end if;

  receipt_ref:='supabase://public.lf_operation_execution_steps/'||p_execution_id||'/research_baseline_freeze';

  if mode='NOT_REQUIRED' then
    if p_baseline_envelope is not null then
      raise exception 'PROFILE_RESEARCH_BASELINE_UNEXPECTED_ENVELOPE';
    end if;
    binding:=jsonb_build_object(
      'applicability','NOT_APPLICABLE',
      'mode',mode,
      'contract_version','NOT_APPLICABLE',
      'capture_stage','NOT_APPLICABLE',
      'baseline_digest','NOT_APPLICABLE',
      'server_snapshot_fingerprint','NOT_APPLICABLE',
      'baseline_snapshot','{}'::jsonb,
      'input_digest','NOT_APPLICABLE',
      'profile_source_digest','NOT_APPLICABLE',
      'evidence_refs','[]'::jsonb
    );
  else
    if jsonb_typeof(contract)<>'object'
       or contract->>'contract_version'<>'PROFILE_RESEARCH_BASELINE_BINDING_V1'
       or contract->>'profile_validator_binding'<>'PROFILE_OUTPUT_VALIDATOR_BOUND_V1' then
      raise exception 'PROFILE_RESEARCH_BASELINE_CONTRACT_INVALID';
    end if;
    if p_baseline_envelope is null then
      return jsonb_build_object(
        'outcome','BASELINE_REQUIRED',
        'recorded',false,
        'execution_id',p_execution_id,
        'research_baseline_mode',mode,
        'research_baseline_contract',contract,
        'baseline_receipt_ref',receipt_ref,
        'next_action','INVOKE_SAME_PROFILE_MODEL_FOR_BASELINE_THEN_RETRY'
      );
    end if;
    if jsonb_typeof(p_baseline_envelope)<>'object'
       or jsonb_typeof(p_baseline_envelope->'snapshot')<>'object'
       or coalesce(p_baseline_envelope->>'baseline_digest','') !~ '^sha256:[0-9a-f]{64}$'
       or nullif(btrim(coalesce(p_baseline_envelope->>'capture_stage','')),'') is null
       or nullif(btrim(coalesce(p_baseline_envelope->>'input_digest','')),'') is null
       or nullif(btrim(coalesce(p_baseline_envelope->>'profile_source_digest','')),'') is null
       or jsonb_typeof(p_baseline_envelope->'evidence_refs')<>'array'
       or jsonb_array_length(p_baseline_envelope->'evidence_refs')=0
    then raise exception 'PROFILE_RESEARCH_BASELINE_ENVELOPE_INVALID'; end if;

    if p_baseline_envelope->>'capture_stage' is distinct from contract->>'capture_stage' then
      raise exception 'PROFILE_RESEARCH_BASELINE_CAPTURE_STAGE_MISMATCH';
    end if;

    expected_input:=e.manifest->>'input_sha256';
    if expected_input ~ '^[0-9a-f]{64}$' then expected_input:='sha256:'||expected_input; end if;
    expected_source:=e.manifest->>'profile_source_digest';
    if expected_source ~ '^[0-9a-f]{64}$' then expected_source:='sha256:'||expected_source; end if;

    if coalesce(expected_input,'') !~ '^sha256:[0-9a-f]{64}$'
       or p_baseline_envelope->>'input_digest' is distinct from expected_input then
      raise exception 'PROFILE_RESEARCH_BASELINE_INPUT_DIGEST_MISMATCH';
    end if;
    if coalesce(expected_source,'') !~ '^sha256:[0-9a-f]{64}$'
       or p_baseline_envelope->>'profile_source_digest' is distinct from expected_source then
      raise exception 'PROFILE_RESEARCH_BASELINE_SOURCE_DIGEST_MISMATCH';
    end if;

    for ref in select jsonb_array_elements_text(p_baseline_envelope->'evidence_refs') loop
      if btrim(ref) ~* '^(https?://|external://|web://)' then
        raise exception 'PROFILE_RESEARCH_BASELINE_EXTERNAL_REF_FORBIDDEN:%',ref;
      end if;
    end loop;

    for binding_source,binding_path_json in select key,value from jsonb_each(contract->'snapshot_binding_paths') loop
      select array_agg(value order by ord) into binding_path from jsonb_array_elements_text(binding_path_json) with ordinality x(value,ord);
      expected_bound_value:=case binding_source when 'input_digest' then to_jsonb(p_baseline_envelope->>'input_digest') when 'profile_source_digest' then to_jsonb(p_baseline_envelope->>'profile_source_digest') when 'evidence_refs' then p_baseline_envelope->'evidence_refs' when 'capture_stage' then to_jsonb(p_baseline_envelope->>'capture_stage') else null end;
      if (p_baseline_envelope->'snapshot')#>binding_path is distinct from expected_bound_value then raise exception 'PROFILE_RESEARCH_BASELINE_SNAPSHOT_BINDING_MISMATCH:%',binding_source; end if;
    end loop;

    canonical_baseline_digest:='sha256:'||private.fn_payload_sha256_v7(
      p_baseline_envelope->'snapshot'
    );
    if p_baseline_envelope->>'baseline_digest' is distinct from canonical_baseline_digest then
      raise exception 'PROFILE_RESEARCH_BASELINE_DIGEST_MISMATCH expected=% supplied=%',
        canonical_baseline_digest,p_baseline_envelope->>'baseline_digest';
    end if;

    server_snapshot_fingerprint:='sha256:'||encode(
      extensions.digest(convert_to((p_baseline_envelope->'snapshot')::text,'UTF8'),'sha256'),'hex'
    );
    binding:=jsonb_build_object(
      'applicability','REQUIRED',
      'mode',mode,
      'contract_version',contract->>'contract_version',
      'capture_stage',p_baseline_envelope->>'capture_stage',
      'baseline_digest',p_baseline_envelope->>'baseline_digest',
      'server_snapshot_fingerprint',server_snapshot_fingerprint,
      'baseline_snapshot',p_baseline_envelope->'snapshot',
      'input_digest',p_baseline_envelope->>'input_digest',
      'profile_source_digest',p_baseline_envelope->>'profile_source_digest',
      'evidence_refs',p_baseline_envelope->'evidence_refs',
      'profile_validator_binding',contract->>'profile_validator_binding'
    );
  end if;

  payload:=jsonb_build_object(
    'research_baseline_binding',binding,
    'baseline_receipt_ref',receipt_ref,
    'server_validated',true,
    'blocking_codes','[]'::jsonb
  );
  trust:=jsonb_build_object(
    'valid',true,
    'code','PROFILE_RESEARCH_BASELINE_SERVER_VALIDATED',
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );

  return public.lf_record_operation_step_core_v1(
    p_execution_id,'research_baseline_freeze',receipt_ref,payload,p_actor_execution_id,
    'EJECUCION_PERFIL_LF','PERFIL',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    trust,true,'lf_profile_execution_research_baseline_v1'
  );
end
$fn$;

comment on function public.lf_profile_execution_research_baseline_v1(text,jsonb,text)
is 'Fail-closed pre-research baseline freeze for EJECUCION_PERFIL_LF. The supplied baseline digest must match the shared LF canonical JSON digest before persistence; the independent jsonb-text server fingerprint remains readback evidence only.';

do $post$
declare
  v_def text;
  v_fixture jsonb := '{"z":[true,null,"ñ"],"a":{"n":7,"s":"á"}}'::jsonb;
begin
  select pg_get_functiondef(
    to_regprocedure('public.lf_profile_execution_research_baseline_v1(text,jsonb,text)')
  ) into v_def;

  if position('private.fn_payload_sha256_v7' in v_def)=0
     or position('PROFILE_RESEARCH_BASELINE_DIGEST_MISMATCH' in v_def)=0 then
    raise exception 'PROFILE_BASELINE_DIGEST_POST_GUARD_NOT_INSTALLED';
  end if;

  if private.fn_payload_sha256_v7(v_fixture)
     <> '29ed0b05def02fe73beceeaceafcd9d9ca025fa3c2ad405e3a365fdc1672e0d1' then
    raise exception 'PROFILE_BASELINE_DIGEST_POST_CANONICAL_FIXTURE_DRIFT';
  end if;
end
$post$;

commit;
