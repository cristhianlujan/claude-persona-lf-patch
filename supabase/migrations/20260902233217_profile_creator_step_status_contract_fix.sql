create or replace function public.lf_record_creacion_perfil_step_v1(
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
  v_gate jsonb;
begin
  if p_execution_id is null or p_execution_id = '' or p_step_id is null or p_step_id = '' then return jsonb_build_object('outcome','BLOCKED','code','STEP_IDENTITY_MISSING'); end if;
  if p_step_id = 'init_execution' then return jsonb_build_object('outcome','BLOCKED','code','INIT_STEP_IMMUTABLE'); end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) <> 'object' then return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID'); end if;
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id for update;
  if not found or v_execution.operation_code <> 'CREACION_PERFIL_LF' or v_execution.target_type <> 'PERFIL' then return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID'); end if;
  if v_execution.status <> 'IN_PROGRESS' then return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_NOT_IN_PROGRESS','status',v_execution.status); end if;
  select * into v_step from public.lf_operation_steps where operation_code='CREACION_PERFIL_LF' and step_id=p_step_id and active is true;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE'); end if;
  select * into v_contract from public.lf_operation_step_contracts where operation_code='CREACION_PERFIL_LF' and step_id=p_step_id and status='ACTIVE';
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_CONTRACT_MISSING'); end if;
  select * into v_binding from public.lf_operation_step_judge_bindings where operation_code='CREACION_PERFIL_LF' and step_id=p_step_id and status='ACTIVE_ENFORCEMENT';
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_JUDGE_BINDING_MISSING'); end if;
  select * into v_existing from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id=p_step_id;
  if found then
    if v_existing.status=v_binding.clean_result_value and v_existing.evidence_ref=p_evidence_ref and v_existing.evidence_payload @> p_evidence_payload then return jsonb_build_object('outcome','STEP_RECORDED','replay',true,'step_id',p_step_id,'status',v_existing.status); end if;
    return jsonb_build_object('outcome','BLOCKED','code','STEP_ALREADY_RECORDED_DIFFERENT_EVIDENCE','status',v_existing.status);
  end if;
  select count(*) into v_prior_missing
  from public.lf_operation_steps s
  where s.operation_code='CREACION_PERFIL_LF' and s.required is true and s.active is true
    and coalesce(s.execution_order,0)<coalesce(v_step.execution_order,0)
    and not exists(select 1 from public.lf_operation_execution_steps es where es.execution_id=p_execution_id and es.step_id=s.step_id);
  select count(*) into v_prior_bad
  from public.lf_operation_steps s
  join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_id=s.step_id
  left join public.lf_operation_step_judge_bindings pb on pb.operation_code=s.operation_code and pb.step_id=s.step_id and pb.status='ACTIVE_ENFORCEMENT'
  where s.operation_code='CREACION_PERFIL_LF' and s.required is true and s.active is true
    and coalesce(s.execution_order,0)<coalesce(v_step.execution_order,0)
    and ((s.step_id='init_execution' and es.status<>'STEP_CLEAN_PASS')
      or (s.step_id<>'init_execution' and (pb.clean_result_value is null or es.status<>pb.clean_result_value)));
  if v_prior_missing>0 or v_prior_bad>0 then return jsonb_build_object('outcome','BLOCKED','code','PRIOR_REQUIRED_STEP_NOT_CLEAN','prior_missing',v_prior_missing,'prior_bad',v_prior_bad); end if;
  for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop
    if not (p_evidence_payload ? v_key) or p_evidence_payload->v_key is null or p_evidence_payload->v_key='null'::jsonb or (jsonb_typeof(p_evidence_payload->v_key)='string' and btrim(p_evidence_payload->>v_key)='') then v_missing_keys:=array_append(v_missing_keys,v_key); end if;
  end loop;
  if cardinality(v_missing_keys)>0 then return jsonb_build_object('outcome','BLOCKED','code','REQUIRED_EVIDENCE_MISSING','missing_keys',to_jsonb(v_missing_keys)); end if;
  if p_evidence_payload ? 'blocking_codes' then
    if jsonb_typeof(p_evidence_payload->'blocking_codes')<>'array' then return jsonb_build_object('outcome','BLOCKED','code','BLOCKING_CODES_INVALID'); end if;
    v_blocking_codes:=p_evidence_payload->'blocking_codes';
    if jsonb_array_length(v_blocking_codes)>0 then return jsonb_build_object('outcome','BLOCKED','code',coalesce(v_contract.blocking_code,'STEP_BLOCKED'),'blocking_codes',v_blocking_codes); end if;
  end if;
  if p_step_id='destination_validate' then
    if p_evidence_payload->>'repo'<>'cristhianlujan/claude-persona-lf-patch' or p_evidence_payload->>'base_folder' not in ('profiles','/profiles/') or coalesce(p_evidence_payload->>'package_root','') not like 'profiles/%' or p_evidence_payload->>'artifact_type'<>'PERFIL' or coalesce(p_evidence_payload->>'destination_source','') not ilike '%artifact_destination_registry%' then return jsonb_build_object('outcome','BLOCKED','code','BLOCKED_DESTINATION_VALIDATE_NOT_CLEAN'); end if;
  elsif p_step_id='pre_destination_resolution_gate' then
    if jsonb_typeof(p_evidence_payload->'missing_required_roles')<>'array' or jsonb_array_length(p_evidence_payload->'missing_required_roles')<>0 or jsonb_typeof(p_evidence_payload->'write_plan')<>'array' or jsonb_array_length(p_evidence_payload->'write_plan')=0 then return jsonb_build_object('outcome','BLOCKED','code','BLOCKED_DESTINATION_ROLE_NOT_CONFIGURED'); end if;
  elsif p_step_id='pre_write_execution_binding_gate' then
    if p_evidence_payload->>'estado_recibido'<>'CANDIDATO_NO_OFICIAL' or coalesce((p_evidence_payload->>'files_ready')::boolean,false) is not true or coalesce((p_evidence_payload->>'pre_write_gate_passed')::boolean,false) is not true or coalesce((p_evidence_payload->>'no_blockers')::boolean,false) is not true then return jsonb_build_object('outcome','BLOCKED','code','BLOCKED_PRE_WRITE_GATE_NOT_PASSED'); end if;
  elsif p_step_id='github_write' then
    if coalesce((p_evidence_payload->>'partial_write_detected')::boolean,true) is not false or coalesce(p_evidence_payload->>'commit_sha','')='' or jsonb_typeof(p_evidence_payload->'written_files')<>'array' or jsonb_array_length(p_evidence_payload->'written_files')=0 then return jsonb_build_object('outcome','BLOCKED','code','BLOCKED_GITHUB_WRITE_NOT_CLEAN'); end if;
  elsif p_step_id='github_readback' then
    if p_evidence_payload->>'sha_match_status'<>'PASS' or jsonb_typeof(p_evidence_payload->'readback_files')<>'array' or jsonb_array_length(p_evidence_payload->'readback_files')=0 then return jsonb_build_object('outcome','BLOCKED','code','BLOCKED_GITHUB_READBACK_NOT_CLEAN'); end if;
  elsif p_step_id='contract_judge' then
    if coalesce((p_evidence_payload->>'required_steps_clean_pass')::boolean,false) is not true or p_evidence_payload->>'judge_result'<>'PASS' or jsonb_array_length(coalesce(p_evidence_payload->'missing_contracts','[]'::jsonb))>0 or jsonb_array_length(coalesce(p_evidence_payload->'missing_judges','[]'::jsonb))>0 or jsonb_array_length(coalesce(p_evidence_payload->'generic_critical_contracts','[]'::jsonb))>0 then return jsonb_build_object('outcome','BLOCKED','code','BLOCKED_CONTRACT_JUDGE_NOT_CLEAN'); end if;
  end if;
  v_payload:=p_evidence_payload || jsonb_build_object('step_result',v_binding.clean_result_value,'blocking_codes','[]'::jsonb,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.clean_result_value,'recorded_by_rpc','lf_record_creacion_perfil_step_v1');
  if p_step_id='close' then update public.lf_operation_execution set manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('closure_allowed',true,'blocked_from_closure',false,'scope','GOVERNED_STEPS_1_39','next_gate','close'),updated_by_execution_id=p_actor_execution_id,updated_at=now() where execution_id=p_execution_id; end if;
  insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id) values(p_execution_id,v_step.step_order,p_step_id,v_binding.clean_result_value,p_evidence_ref,v_payload,'Recorded transactionally by governed Profile Creator continuation RPC.',p_actor_execution_id);
  if p_step_id='close' then
    v_gate:=public.lf_creacion_perfil_lf_no_close_gate(p_execution_id);
    if v_gate->>'verdict'<>'PASS_CLEAN' then raise exception 'PROFILE_CLOSE_GATE_FAILED:%',v_gate::text; end if;
    update public.lf_operation_execution set status='CONTROLLED_READ_ONLY_PASS',manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('no_close_gate',v_gate,'next_gate','report_output'),updated_by_execution_id=p_actor_execution_id,updated_at=now() where execution_id=p_execution_id;
  end if;
  return jsonb_build_object('outcome','STEP_RECORDED','replay',false,'execution_id',p_execution_id,'step_id',p_step_id,'step_order',v_step.step_order,'execution_order',v_step.execution_order,'status',v_binding.clean_result_value,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.clean_result_value,'next_gate',v_contract.next_if_pass);
end;
$function$;

create or replace function public.lf_creacion_perfil_lf_no_close_gate(p_execution_id text)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_manifest jsonb;
  v_missing_count integer := 0;
  v_not_clean_count integer := 0;
  v_restricted_count integer := 0;
  v_blocked_count integer := 0;
  v_return_count integer := 0;
  v_final_bad_pass_count integer := 0;
  v_closure_allowed_false boolean := false;
  v_blocked_from_closure_true boolean := false;
  v_security_hold_true boolean := false;
  v_block boolean := false;
begin
  select coalesce(manifest,'{}'::jsonb) into v_manifest
  from public.lf_operation_execution
  where execution_id = p_execution_id and operation_code = 'CREACION_PERFIL_LF';
  if v_manifest is null then return jsonb_build_object('verdict','BLOCKED_BY_ENFORCEMENT','reason','execution_missing_or_wrong_operation'); end if;
  select count(*) into v_missing_count from public.lf_operation_steps s where s.operation_code='CREACION_PERFIL_LF' and s.required is true and s.active is true and not exists (select 1 from public.lf_operation_execution_steps es where es.execution_id=p_execution_id and es.step_id=s.step_id);
  select count(*) into v_not_clean_count
  from public.lf_operation_steps s
  left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_id=s.step_id
  left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_id=s.step_id and b.status='ACTIVE_ENFORCEMENT'
  where s.operation_code='CREACION_PERFIL_LF' and s.required is true and s.active is true
    and (((s.step_id='init_execution') and coalesce(es.status,'MISSING') <> 'STEP_CLEAN_PASS') or ((s.step_id<>'init_execution') and (b.clean_result_value is null or coalesce(es.status,'MISSING') <> b.clean_result_value)));
  select count(*) into v_restricted_count from public.lf_operation_execution_steps where execution_id=p_execution_id and upper(coalesce(status,'')) like '%PASS_WITH_RESTRICTIONS%';
  select count(*) into v_blocked_count from public.lf_operation_execution_steps where execution_id=p_execution_id and upper(coalesce(status,'')) like 'BLOCKED%';
  select count(*) into v_return_count from public.lf_operation_execution_steps where execution_id=p_execution_id and upper(coalesce(status,'')) like 'RETURN%';
  select count(*) into v_final_bad_pass_count
  from public.lf_operation_execution_steps es
  left join public.lf_operation_step_judge_bindings b on b.operation_code='CREACION_PERFIL_LF' and b.step_id=es.step_id and b.status='ACTIVE_ENFORCEMENT'
  where es.execution_id=p_execution_id and es.step_id in ('contract_judge','close','report_output')
    and es.status=coalesce(b.clean_result_value,'__NO_BINDING__')
    and (v_missing_count>0 or v_not_clean_count>0 or v_restricted_count>0 or v_blocked_count>0 or v_return_count>0 or coalesce(v_manifest->>'closure_allowed','')='false' or coalesce(v_manifest->>'blocked_from_closure','')='true' or coalesce(v_manifest->>'security_hold_continues','')='true' or coalesce(v_manifest->>'mini_judge_verdict','')='PASS_WITH_RESTRICTIONS');
  v_closure_allowed_false := coalesce(v_manifest->>'closure_allowed','')='false';
  v_blocked_from_closure_true := coalesce(v_manifest->>'blocked_from_closure','')='true';
  v_security_hold_true := coalesce(v_manifest->>'security_hold_continues','')='true';
  v_block := v_missing_count>0 or v_not_clean_count>0 or v_restricted_count>0 or v_blocked_count>0 or v_return_count>0 or v_closure_allowed_false or v_blocked_from_closure_true or v_security_hold_true or coalesce(v_manifest->>'mini_judge_verdict','')='PASS_WITH_RESTRICTIONS';
  return jsonb_build_object('verdict',case when v_block then 'BLOCKED_BY_ENFORCEMENT' else 'PASS_CLEAN' end,'missing_required_steps',v_missing_count,'required_steps_not_clean_pass',v_not_clean_count,'pass_with_restrictions_count',v_restricted_count,'blocked_count',v_blocked_count,'return_to_worker_count',v_return_count,'closure_allowed_false',v_closure_allowed_false,'blocked_from_closure_true',v_blocked_from_closure_true,'security_hold_active',v_security_hold_true,'final_steps_invalid_pass_count',v_final_bad_pass_count,'final_steps_block_required',v_block,'init_status_contract','STEP_CLEAN_PASS','post_init_status_contract','JUDGE_BINDING_CLEAN_RESULT_VALUE');
end;
$function$;