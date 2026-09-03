-- PROFILE_OPERATION_COMMON_RECORDER_V1
-- SOURCE_ONLY / NOT_DEPLOYED / NO_RUNTIME_ENABLEMENT
-- Generalizes the existing CREACION_PERFIL_LF recorder without creating a parallel UPDATE RPC.

create or replace function public.lf_record_profile_operation_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_step public.lf_operation_steps%rowtype;
  v_contract public.lf_operation_step_contracts%rowtype;
  v_binding public.lf_operation_step_judge_bindings%rowtype;
  v_existing public.lf_operation_execution_steps%rowtype;
  v_key text;
  v_missing_keys text[] := array[]::text[];
  v_prior_missing integer := 0;
  v_prior_bad integer := 0;
  v_blocking_codes jsonb := '[]'::jsonb;
  v_payload jsonb;
begin
  if p_execution_id is null or btrim(p_execution_id) = '' or p_step_id is null or btrim(p_step_id) = '' then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_IDENTITY_MISSING');
  end if;
  if p_step_id = 'init_execution' then
    return jsonb_build_object('outcome','BLOCKED','code','INIT_STEP_IMMUTABLE');
  end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) <> 'object' then
    return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID');
  end if;

  select * into v_execution
  from public.lf_operation_execution
  where execution_id = p_execution_id
  for update;

  if not found
     or v_execution.target_type <> 'PERFIL'
     or v_execution.operation_code not in ('CREACION_PERFIL_LF','ACTUALIZACION_PERFIL_LF') then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID');
  end if;
  if v_execution.status <> 'IN_PROGRESS' then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_NOT_IN_PROGRESS','status',v_execution.status);
  end if;

  select * into v_step
  from public.lf_operation_steps
  where operation_code = v_execution.operation_code
    and step_id = p_step_id
    and active is true;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE'); end if;

  select * into v_contract
  from public.lf_operation_step_contracts
  where operation_code = v_execution.operation_code
    and step_id = p_step_id
    and status = 'ACTIVE';
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_CONTRACT_MISSING'); end if;

  select * into v_binding
  from public.lf_operation_step_judge_bindings
  where operation_code = v_execution.operation_code
    and step_id = p_step_id
    and status = 'ACTIVE_ENFORCEMENT';
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_JUDGE_BINDING_MISSING'); end if;

  select * into v_existing
  from public.lf_operation_execution_steps
  where execution_id = p_execution_id and step_id = p_step_id;
  if found then
    if v_existing.status = v_binding.clean_result_value
       and v_existing.evidence_ref = p_evidence_ref
       and v_existing.evidence_payload @> p_evidence_payload then
      return jsonb_build_object('outcome','STEP_RECORDED','replay',true,'step_id',p_step_id,'status',v_existing.status);
    end if;
    return jsonb_build_object('outcome','BLOCKED','code','STEP_ALREADY_RECORDED_DIFFERENT_EVIDENCE','status',v_existing.status);
  end if;

  select count(*) into v_prior_missing
  from public.lf_operation_steps s
  where s.operation_code = v_execution.operation_code
    and s.required is true and s.active is true
    and coalesce(s.execution_order,0) < coalesce(v_step.execution_order,0)
    and not exists (
      select 1 from public.lf_operation_execution_steps es
      where es.execution_id = p_execution_id and es.step_id = s.step_id
    );

  select count(*) into v_prior_bad
  from public.lf_operation_steps s
  join public.lf_operation_execution_steps es
    on es.execution_id = p_execution_id and es.step_id = s.step_id
  left join public.lf_operation_step_judge_bindings pb
    on pb.operation_code = s.operation_code and pb.step_id = s.step_id and pb.status = 'ACTIVE_ENFORCEMENT'
  where s.operation_code = v_execution.operation_code
    and s.required is true and s.active is true
    and coalesce(s.execution_order,0) < coalesce(v_step.execution_order,0)
    and ((s.step_id='init_execution' and es.status <> 'STEP_CLEAN_PASS')
      or (s.step_id <> 'init_execution' and (pb.clean_result_value is null or es.status <> pb.clean_result_value)));
  if v_prior_missing > 0 or v_prior_bad > 0 then
    return jsonb_build_object('outcome','BLOCKED','code','PRIOR_REQUIRED_STEP_NOT_CLEAN','prior_missing',v_prior_missing,'prior_bad',v_prior_bad);
  end if;

  for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop
    if not (p_evidence_payload ? v_key)
       or p_evidence_payload->v_key is null
       or p_evidence_payload->v_key = 'null'::jsonb
       or (jsonb_typeof(p_evidence_payload->v_key)='string' and btrim(p_evidence_payload->>v_key)='') then
      v_missing_keys := array_append(v_missing_keys,v_key);
    end if;
  end loop;
  if cardinality(v_missing_keys) > 0 then
    return jsonb_build_object('outcome','BLOCKED','code','REQUIRED_EVIDENCE_MISSING','missing_keys',to_jsonb(v_missing_keys));
  end if;

  if p_evidence_payload ? 'blocking_codes' then
    if jsonb_typeof(p_evidence_payload->'blocking_codes') <> 'array' then
      return jsonb_build_object('outcome','BLOCKED','code','BLOCKING_CODES_INVALID');
    end if;
    v_blocking_codes := p_evidence_payload->'blocking_codes';
    if jsonb_array_length(v_blocking_codes) > 0 then
      return jsonb_build_object('outcome','BLOCKED','code',coalesce(v_contract.blocking_code,'STEP_BLOCKED'),'blocking_codes',v_blocking_codes);
    end if;
  end if;

  -- UPDATE pre-write continuity is deliberately NOT self-attested here.
  -- The governed caller resolves persisted baseline + trusted GitHub current + structured bound revision
  -- before this recorder can ever receive the step.
  if v_execution.operation_code = 'ACTUALIZACION_PERFIL_LF' and p_step_id = 'pre_write_execution_binding_gate' then
    if coalesce((p_evidence_payload->>'pre_write_gate_passed')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'execution_bound_to_target_before_change')::boolean,false) is not true
       or jsonb_typeof(p_evidence_payload->'bound_revision') <> 'object'
       or coalesce(p_evidence_payload->'trusted_current_revision'->>'resolver','') <> 'GITHUB_PUBLIC_API_EXACT_REF_V1'
       or coalesce((p_evidence_payload->>'current_revision_resolved_by_caller')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'declared_current_revision_ignored')::boolean,false) is not true then
      return jsonb_build_object('outcome','BLOCKED','code','PROFILE_UPDATE_PREWRITE_TRUST_CHAIN_REQUIRED');
    end if;
  end if;

  v_payload := p_evidence_payload || jsonb_build_object(
    'step_result',v_binding.clean_result_value,
    'blocking_codes','[]'::jsonb,
    'mini_judge_code',v_binding.judge_code,
    'mini_judge_result',v_binding.clean_result_value,
    'recorded_by_rpc','lf_record_profile_operation_step_v1'
  );

  insert into public.lf_operation_execution_steps(
    execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id
  ) values (
    p_execution_id,v_step.step_order,p_step_id,v_binding.clean_result_value,p_evidence_ref,v_payload,
    'Recorded transactionally by common governed Profile operation recorder.',p_actor_execution_id
  );

  return jsonb_build_object(
    'outcome','STEP_RECORDED','replay',false,'execution_id',p_execution_id,
    'operation_code',v_execution.operation_code,'step_id',p_step_id,
    'step_order',v_step.step_order,'execution_order',v_step.execution_order,
    'status',v_binding.clean_result_value,'mini_judge_code',v_binding.judge_code,
    'mini_judge_result',v_binding.clean_result_value,'next_gate',v_contract.next_if_pass
  );
end;
$function$;

-- Compatibility strategy when later materialized:
-- CREACION_PERFIL_LF keeps its existing public.lf_record_creacion_perfil_step_v1 entrypoint
-- until a separately tested thin wrapper can delegate to this common recorder.
-- ACTUALIZACION_PERFIL_LF runtime remains fail-closed until this source is deployed and live rollback-tested.
