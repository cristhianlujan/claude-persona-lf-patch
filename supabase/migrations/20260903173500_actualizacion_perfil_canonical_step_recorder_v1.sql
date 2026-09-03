-- Source-first candidate only. Do not apply live from this PR until exact-head tests pass.
create or replace function public.lf_record_actualizacion_perfil_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
set search_path to 'public'
as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_step public.lf_operation_steps%rowtype;
  v_contract public.lf_operation_step_contracts%rowtype;
  v_binding public.lf_operation_step_judge_bindings%rowtype;
  v_judge public.lf_operation_judges%rowtype;
  v_existing public.lf_operation_execution_steps%rowtype;
  v_key text;
  v_missing_keys text[] := array[]::text[];
  v_prior_missing integer := 0;
  v_prior_bad integer := 0;
  v_blocking_codes jsonb := '[]'::jsonb;
  v_payload jsonb;
  v_remaining_before_report integer := 0;
  v_expected_judge_sha constant text := 'bef12f5dd3c08db63b92faf64f77703acf9172288dc0547e0de56241d1521557';
  v_bound_revision jsonb;
  v_current_revision jsonb;
  v_shell_receipt jsonb;
  v_mode text;
  v_artifact_type text;
begin
  if p_execution_id is null or btrim(p_execution_id) = '' or p_step_id is null or btrim(p_step_id) = '' then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_IDENTITY_MISSING');
  end if;
  if p_step_id = 'init_execution' then
    return jsonb_build_object('outcome','BLOCKED','code','INIT_STEP_IMMUTABLE');
  end if;
  if p_actor_execution_id is distinct from p_execution_id then
    return jsonb_build_object('outcome','BLOCKED','code','ACTOR_EXECUTION_MUST_MATCH_TARGET_EXECUTION');
  end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) <> 'object' then
    return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID');
  end if;

  select * into v_execution
  from public.lf_operation_execution
  where execution_id = p_execution_id
  for update;

  if not found or v_execution.operation_code <> 'ACTUALIZACION_PERFIL_LF' or v_execution.target_type <> 'PERFIL' then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID');
  end if;
  if v_execution.status <> 'IN_PROGRESS' then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_NOT_IN_PROGRESS','status',v_execution.status);
  end if;

  select * into v_step
  from public.lf_operation_steps
  where operation_code='ACTUALIZACION_PERFIL_LF' and step_id=p_step_id and active is true;
  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE');
  end if;

  select * into v_contract
  from public.lf_operation_step_contracts
  where operation_code='ACTUALIZACION_PERFIL_LF' and step_id=p_step_id and status='ACTIVE_ENFORCEMENT';
  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_CONTRACT_MISSING_OR_NOT_ENFORCED');
  end if;

  select * into v_binding
  from public.lf_operation_step_judge_bindings
  where operation_code='ACTUALIZACION_PERFIL_LF' and step_id=p_step_id and status='ACTIVE_ENFORCEMENT';
  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_JUDGE_BINDING_MISSING');
  end if;

  select * into v_judge
  from public.lf_operation_judges
  where operation_code='ACTUALIZACION_PERFIL_LF'
    and judge_code=v_binding.judge_code
    and status='ACTIVE_ENFORCEMENT';
  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','SOURCE_BOUND_JUDGE_MISSING');
  end if;
  if v_judge.judge_sha is null or v_judge.judge_sha <> v_expected_judge_sha
     or jsonb_typeof(v_judge.pass_if) <> 'array' or jsonb_array_length(v_judge.pass_if)=0
     or jsonb_typeof(v_judge.fail_if) <> 'array' or jsonb_array_length(v_judge.fail_if)=0 then
    return jsonb_build_object('outcome','BLOCKED','code','SOURCE_BOUND_JUDGE_NOT_READY','judge_sha',v_judge.judge_sha);
  end if;

  select * into v_existing
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id=p_step_id;
  if found then
    if v_existing.status=v_binding.clean_result_value
       and v_existing.evidence_ref=p_evidence_ref
       and v_existing.evidence_payload @> p_evidence_payload then
      return jsonb_build_object('outcome','STEP_RECORDED','replay',true,'step_id',p_step_id,'status',v_existing.status);
    end if;
    return jsonb_build_object('outcome','BLOCKED','code','STEP_ALREADY_RECORDED_DIFFERENT_EVIDENCE','status',v_existing.status);
  end if;

  select count(*) into v_prior_missing
  from public.lf_operation_steps s
  where s.operation_code='ACTUALIZACION_PERFIL_LF' and s.required is true and s.active is true
    and coalesce(s.execution_order,0)<coalesce(v_step.execution_order,0)
    and not exists(
      select 1 from public.lf_operation_execution_steps es
      where es.execution_id=p_execution_id and es.step_id=s.step_id
    );

  select count(*) into v_prior_bad
  from public.lf_operation_steps s
  join public.lf_operation_execution_steps es
    on es.execution_id=p_execution_id and es.step_id=s.step_id
  left join public.lf_operation_step_judge_bindings pb
    on pb.operation_code=s.operation_code and pb.step_id=s.step_id and pb.status='ACTIVE_ENFORCEMENT'
  where s.operation_code='ACTUALIZACION_PERFIL_LF' and s.required is true and s.active is true
    and coalesce(s.execution_order,0)<coalesce(v_step.execution_order,0)
    and ((s.step_id='init_execution' and es.status not in ('STEP_CLEAN_PASS','STEP_PASS_WITH_EVIDENCE'))
      or (s.step_id<>'init_execution' and (pb.clean_result_value is null or es.status<>pb.clean_result_value)));

  if v_prior_missing>0 or v_prior_bad>0 then
    return jsonb_build_object('outcome','BLOCKED','code','PRIOR_REQUIRED_STEP_NOT_CLEAN','prior_missing',v_prior_missing,'prior_bad',v_prior_bad);
  end if;

  for v_key in select jsonb_array_elements_text(coalesce(v_binding.required_evidence_keys,v_contract.required_evidence_keys,'[]'::jsonb)) loop
    if not (p_evidence_payload ? v_key)
       or p_evidence_payload->v_key is null
       or p_evidence_payload->v_key='null'::jsonb
       or (jsonb_typeof(p_evidence_payload->v_key)='string' and btrim(p_evidence_payload->>v_key)='') then
      v_missing_keys:=array_append(v_missing_keys,v_key);
    end if;
  end loop;
  if cardinality(v_missing_keys)>0 then
    return jsonb_build_object('outcome','BLOCKED','code','REQUIRED_EVIDENCE_MISSING','missing_keys',to_jsonb(v_missing_keys));
  end if;

  if p_evidence_payload ? 'blocking_codes' then
    if jsonb_typeof(p_evidence_payload->'blocking_codes')<>'array' then
      return jsonb_build_object('outcome','BLOCKED','code','BLOCKING_CODES_INVALID');
    end if;
    v_blocking_codes:=p_evidence_payload->'blocking_codes';
    if jsonb_array_length(v_blocking_codes)>0 then
      return jsonb_build_object('outcome','BLOCKED','code',coalesce(v_contract.blocking_code,'STEP_BLOCKED'),'blocking_codes',v_blocking_codes);
    end if;
  end if;

  if p_step_id='pre_write_execution_binding_gate' then
    if p_evidence_payload->>'execution_id' <> p_execution_id
       or p_evidence_payload->>'target_code' <> v_execution.target_code
       or p_evidence_payload->>'target_path' <> v_execution.target_path then
      return jsonb_build_object('outcome','BLOCKED','code','TARGET_IDENTITY_MISMATCH');
    end if;
    if coalesce((p_evidence_payload->>'pre_write_gate_passed')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'execution_bound_to_target_before_change')::boolean,false) is not true then
      return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_NOT_BOUND_TO_TARGET');
    end if;

    v_bound_revision:=p_evidence_payload->'bound_revision';
    v_current_revision:=p_evidence_payload->'current_resolved_revision';
    if jsonb_typeof(v_bound_revision)<>'object' then
      return jsonb_build_object('outcome','BLOCKED','code','BOUND_REVISION_NOT_STRUCTURED');
    end if;
    if jsonb_typeof(v_current_revision)<>'object' then
      return jsonb_build_object('outcome','BLOCKED','code','CURRENT_RESOLVED_REVISION_NOT_STRUCTURED');
    end if;
    if v_bound_revision <> v_current_revision then
      return jsonb_build_object('outcome','BLOCKED','code','REVISION_MISMATCH');
    end if;

    if coalesce((p_evidence_payload->>'revision_was_stale')::boolean,false) is true then
      if coalesce((p_evidence_payload->>'reread_performed')::boolean,false) is not true then
        return jsonb_build_object('outcome','BLOCKED','code','STALE_REVISION_WITHOUT_REREAD');
      end if;
      if coalesce((p_evidence_payload->>'explicit_rebind')::boolean,false) is not true then
        return jsonb_build_object('outcome','BLOCKED','code','STALE_REVISION_WITHOUT_REBIND');
      end if;
    end if;

    v_artifact_type:=upper(coalesce(p_evidence_payload->>'artifact_type','PROFILE'));
    if v_artifact_type='RASTER' then
      if coalesce(p_evidence_payload->>'artifact_id','')=''
         or coalesce(p_evidence_payload->>'source_ref','')=''
         or coalesce(p_evidence_payload->>'sha256','')=''
         or p_evidence_payload->'dimensions' is null then
        return jsonb_build_object('outcome','BLOCKED','code','RASTER_EXACT_IDENTITY_MISSING');
      end if;
    end if;

    if coalesce((p_evidence_payload->>'shell_applies')::boolean,false) is true then
      v_shell_receipt:=p_evidence_payload->'shell_adapter_receipt';
      if jsonb_typeof(v_shell_receipt)<>'object' then
        return jsonb_build_object('outcome','BLOCKED','code','SHELL_RECEIPT_MISSING_WHEN_APPLICABLE');
      end if;
      if v_shell_receipt->'bound_revision' is distinct from v_bound_revision then
        return jsonb_build_object('outcome','BLOCKED','code','SHELL_RECEIPT_BOUND_REVISION_MISMATCH');
      end if;
    end if;

    v_mode:=upper(coalesce(p_evidence_payload->>'mode',''));
    if v_mode='REMEDIATE_EXISTING' then
      if p_evidence_payload->'authorized_delta' is null
         or jsonb_typeof(p_evidence_payload->'editable_zones')<>'array'
         or jsonb_typeof(p_evidence_payload->'shell_locked_zones')<>'array' then
        return jsonb_build_object('outcome','BLOCKED','code','MISSING_AUTHORIZED_DELTA_FOR_REMEDIATE_EXISTING');
      end if;
    end if;
    if coalesce((p_evidence_payload->>'outside_authorized_delta_changes')::integer,0)<>0 then
      return jsonb_build_object('outcome','BLOCKED','code','OUTSIDE_DELTA_MUTATION');
    end if;
    if coalesce((p_evidence_payload->>'shell_locked_mutations')::integer,0)<>0 then
      return jsonb_build_object('outcome','BLOCKED','code','SHELL_LOCKED_MUTATION');
    end if;
  elsif p_step_id='github_write' then
    if coalesce(p_evidence_payload->>'commit_sha','')=''
       or jsonb_typeof(p_evidence_payload->'written_files')<>'array'
       or jsonb_array_length(p_evidence_payload->'written_files')=0
       or coalesce((p_evidence_payload->>'identity_preserved')::boolean,false) is not true then
      return jsonb_build_object('outcome','BLOCKED','code','BLOCKED_GITHUB_WRITE_NOT_CLEAN');
    end if;
  elsif p_step_id='github_readback' then
    if coalesce(p_evidence_payload->>'exact_head','')=''
       or jsonb_typeof(p_evidence_payload->'readback_files')<>'array'
       or jsonb_array_length(p_evidence_payload->'readback_files')=0
       or coalesce((p_evidence_payload->>'sha_match')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'identity_preserved')::boolean,false) is not true then
      return jsonb_build_object('outcome','BLOCKED','code','BLOCKED_GITHUB_READBACK_NOT_CLEAN');
    end if;
  elsif p_step_id='deterministic_validation' then
    if p_evidence_payload->>'validator_result' not in ('PASS','STEP_PASS_WITH_EVIDENCE')
       or p_evidence_payload->>'malformed_input_result' not in ('PASS','REJECTED_AS_EXPECTED') then
      return jsonb_build_object('outcome','BLOCKED','code','DETERMINISTIC_VALIDATION_NOT_CLEAN');
    end if;
  elsif p_step_id='semantic_judge' then
    if p_evidence_payload->>'semantic_judge_result' not in ('PASS','STEP_PASS_WITH_EVIDENCE') then
      return jsonb_build_object('outcome','BLOCKED','code','SEMANTIC_JUDGE_NOT_CLEAN');
    end if;
  elsif p_step_id='close' then
    if coalesce((p_evidence_payload->>'all_required_steps_clean')::boolean,false) is not true
       or jsonb_typeof(p_evidence_payload->'open_blockers')<>'array'
       or jsonb_array_length(p_evidence_payload->'open_blockers')<>0
       or coalesce((p_evidence_payload->>'runtime_unchanged')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'no_auto_promotion')::boolean,false) is not true then
      return jsonb_build_object('outcome','BLOCKED','code','UPDATE_CLOSE_NOT_CLEAN');
    end if;
  end if;

  v_payload:=p_evidence_payload || jsonb_build_object(
    'step_result',v_binding.clean_result_value,
    'blocking_codes','[]'::jsonb,
    'mini_judge_code',v_binding.judge_code,
    'mini_judge_result',v_binding.clean_result_value,
    'judge_sha',v_judge.judge_sha,
    'recorded_by_rpc','lf_record_actualizacion_perfil_step_v1'
  );

  insert into public.lf_operation_execution_steps(
    execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id
  ) values (
    p_execution_id,v_step.step_order,p_step_id,v_binding.clean_result_value,p_evidence_ref,v_payload,
    'Recorded transactionally by governed Profile Update canonical recorder.',p_actor_execution_id
  );

  if p_step_id='close' then
    update public.lf_operation_execution
    set manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object(
      'closure_ready',true,
      'closure_step_status',v_binding.clean_result_value,
      'next_gate','report_output'
    ), updated_by_execution_id=p_actor_execution_id, updated_at=now()
    where execution_id=p_execution_id;
  elsif p_step_id='report_output' then
    select count(*) into v_remaining_before_report
    from public.lf_operation_steps s
    where s.operation_code='ACTUALIZACION_PERFIL_LF' and s.required is true and s.active is true
      and s.step_id<>'report_output'
      and not exists(
        select 1 from public.lf_operation_execution_steps es
        join public.lf_operation_step_judge_bindings b
          on b.operation_code='ACTUALIZACION_PERFIL_LF'
         and b.step_id=es.step_id
         and b.status='ACTIVE_ENFORCEMENT'
        where es.execution_id=p_execution_id and es.step_id=s.step_id
          and (es.step_id='init_execution' or es.status=b.clean_result_value)
      );
    if v_remaining_before_report<>0 then
      raise exception 'UPDATE_REPORT_OUTPUT_CLOSE_GATE_FAILED:remaining=%',v_remaining_before_report;
    end if;
    update public.lf_operation_execution
    set status='COMPLETED',
        manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object(
          'closure_ready',true,
          'report_output_recorded',true,
          'next_gate',coalesce(p_evidence_payload->>'next_gate','NONE')
        ),
        updated_by_execution_id=p_actor_execution_id,
        updated_at=now()
    where execution_id=p_execution_id;
  end if;

  return jsonb_build_object(
    'outcome','STEP_RECORDED',
    'replay',false,
    'execution_id',p_execution_id,
    'step_id',p_step_id,
    'step_order',v_step.step_order,
    'execution_order',v_step.execution_order,
    'status',v_binding.clean_result_value,
    'judge_code',v_binding.judge_code,
    'judge_sha',v_judge.judge_sha,
    'next_gate',v_contract.next_if_pass
  );
end;
$function$;

comment on function public.lf_record_actualizacion_perfil_step_v1(text,text,text,jsonb,text)
is 'Source-first canonical recorder candidate for ACTUALIZACION_PERFIL_LF. Requires source-bound judge, exact current step, prior clean steps, exact target/revision binding and transactional evidence. Runtime activation remains separately gated.';
