-- PE10 Updater recorder candidate — NOT deployed, NOT an apply migration.
-- Source: live public.lf_record_profile_operation_step_v1 at 2026-10-14.
-- Scope: v0.2 conditional routing and output-parity proof, preserving legacy frozen steps.
-- Activate only atomically with qualified methods, actual governed evidence,
-- 2 steps/2 judges/new policy and full Train ROLLBACK + readback.
CREATE OR REPLACE FUNCTION public.lf_record_profile_operation_step_v1(p_execution_id text, p_step_id text, p_evidence_ref text, p_evidence_payload jsonb, p_actor_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
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
  v_required_not_clean integer := 0;
  v_blocking_codes jsonb := '[]'::jsonb;
  v_payload jsonb;
  v_attempt_history jsonb := '[]'::jsonb;
  v_existing_retryable boolean := false;
  v_block_code text;
  v_block_details jsonb := '{}'::jsonb;
  v_snapshot_steps jsonb;
  v_snapshot_applies boolean := false;
  v_trust jsonb;
  v_route_resolution jsonb;
  v_has_evolved_route boolean := false;
  v_output_parity jsonb;
  v_head_readback jsonb;
  v_candidate_head text;
  v_profile_slug text;
begin
  if p_execution_id is null or btrim(p_execution_id) = '' or p_step_id is null or btrim(p_step_id) = '' then return jsonb_build_object('outcome','BLOCKED','code','STEP_IDENTITY_MISSING','durable',false); end if;
  if p_step_id = 'init_execution' then return jsonb_build_object('outcome','BLOCKED','code','INIT_STEP_IMMUTABLE','durable',false); end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) <> 'object' then return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false); end if;
  select * into v_execution from public.lf_operation_execution where execution_id = p_execution_id for update;
  if not found or v_execution.target_type <> 'PERFIL' or v_execution.operation_code not in ('CREACION_PERFIL_LF','ACTUALIZACION_PERFIL_LF') then return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID','durable',false); end if;
  if v_execution.status <> 'IN_PROGRESS' then return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_NOT_IN_PROGRESS','status',v_execution.status,'durable',false); end if;

  -- Resolve immutable PASS_POLICY requirements from execution, not today's catalog.
  -- Absent snapshots retain the original current-catalog enforcement.
  v_snapshot_steps:=v_execution.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}';
  IF v_snapshot_steps IS NOT NULL THEN
    IF jsonb_typeof(v_snapshot_steps)<>'array'
       OR jsonb_array_length(v_snapshot_steps)=0
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_snapshot_steps) x WHERE jsonb_typeof(x.value)<>'string')
       OR (SELECT count(*) FROM jsonb_array_elements_text(v_snapshot_steps))
          <> (SELECT count(DISTINCT value) FROM jsonb_array_elements_text(v_snapshot_steps) t(value))
       OR EXISTS (
          SELECT 1 FROM jsonb_array_elements_text(v_snapshot_steps) t(value)
          WHERE nullif(btrim(t.value),'') IS NULL
             OR NOT EXISTS (
                SELECT 1 FROM public.lf_operation_steps st
                WHERE st.operation_code=v_execution.operation_code
                  AND st.step_id=t.value AND st.required AND st.active
             )
       ) THEN
      RETURN jsonb_build_object('outcome','BLOCKED','code','FROZEN_REQUIRED_STEPS_INVALID','durable',false);
    END IF;
    v_snapshot_applies:=true;
  END IF;

  -- New policy uses frozen conditional route, old v0.1 snapshots remain exact.
  v_has_evolved_route :=
      v_execution.operation_code='ACTUALIZACION_PERFIL_LF'
      and v_execution.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps_by_outcome}' IS NOT NULL;
  if v_has_evolved_route then
    v_route_resolution:=public.lf_profile_update_effective_route_v1(p_execution_id);
    if v_route_resolution->>'outcome' IN ('BLOCKED','LEGACY_NO_SNAPSHOT','LEGACY_FROZEN')
       or coalesce(jsonb_typeof(v_route_resolution->'effective_steps'),'') <> 'array'
       or jsonb_array_length(v_route_resolution->'effective_steps')=0 then
      return jsonb_build_object('outcome','BLOCKED','code','PROFILE_UPDATE_EVOLUTION_ROUTE_UNRESOLVED','route',v_route_resolution,'durable',false);
    end if;
    v_snapshot_steps:=v_route_resolution->'effective_steps';
    v_snapshot_applies:=true;
    if not v_snapshot_steps ? p_step_id then
      return jsonb_build_object('outcome','BLOCKED','code','PROFILE_UPDATE_STEP_NOT_ON_FROZEN_ROUTE','step_id',p_step_id,'durable',false);
    end if;
  end if;

  select * into v_step from public.lf_operation_steps where operation_code=v_execution.operation_code and step_id=p_step_id and active is true;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false); end if;
  select * into v_contract from public.lf_operation_step_contracts where operation_code=v_execution.operation_code and step_id=p_step_id and status=case when v_execution.operation_code='ACTUALIZACION_PERFIL_LF' then 'ACTIVE_ENFORCEMENT' else 'ACTIVE' end;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_CONTRACT_MISSING','durable',false); end if;
  select * into v_binding from public.lf_operation_step_judge_bindings where operation_code=v_execution.operation_code and step_id=p_step_id and status='ACTIVE_ENFORCEMENT';
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_JUDGE_BINDING_MISSING','durable',false); end if;
  select * into v_existing from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id=p_step_id;
  if found then
    if v_existing.status=v_binding.clean_result_value and v_existing.evidence_ref=p_evidence_ref and v_existing.evidence_payload @> p_evidence_payload then
      if v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then
        select count(*) into v_required_not_clean
        from public.lf_operation_steps s
        left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_id=s.step_id
        left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_id=s.step_id and b.status='ACTIVE_ENFORCEMENT'
        where s.operation_code=v_execution.operation_code and s.required is true and s.active is true and (not v_snapshot_applies or exists (select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id) where frozen.step_id=s.step_id))
          and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);
        if v_required_not_clean>0 then return jsonb_build_object('outcome','BLOCKED','code','PROFILE_UPDATE_COMPLETION_NOT_CLEAN','required_not_clean',v_required_not_clean,'durable',false); end if;
        update public.lf_operation_execution
        set status='COMPLETED',
            completed_at=coalesce(completed_at,now()),
            manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('operation_closed',true,'next_gate',coalesce(p_evidence_payload->'next_gate',manifest->'next_gate')),
            updated_by_execution_id=p_actor_execution_id,
            updated_at=now()
        where execution_id=p_execution_id and status='IN_PROGRESS';
      end if;
      return jsonb_build_object('outcome','STEP_RECORDED','replay',true,'step_id',p_step_id,'status',v_existing.status,'execution_status',case when v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then 'COMPLETED' else v_execution.status end);
    end if;
    if v_existing.status in (v_binding.blocked_result_value,v_binding.return_result_value) then v_existing_retryable:=true; if jsonb_typeof(v_existing.evidence_payload->'attempt_history')='array' then v_attempt_history:=v_existing.evidence_payload->'attempt_history'; end if; else return jsonb_build_object('outcome','BLOCKED','code','STEP_ALREADY_RECORDED_DIFFERENT_EVIDENCE','status',v_existing.status,'durable',true); end if;
  end if;
  select count(*) into v_prior_missing from public.lf_operation_steps s where s.operation_code=v_execution.operation_code and s.required is true and s.active is true and (not v_snapshot_applies or exists (select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id) where frozen.step_id=s.step_id)) and coalesce(s.execution_order,0)<coalesce(v_step.execution_order,0) and not exists(select 1 from public.lf_operation_execution_steps es where es.execution_id=p_execution_id and es.step_id=s.step_id);
  select count(*) into v_prior_bad from public.lf_operation_steps s join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_id=s.step_id left join public.lf_operation_step_judge_bindings pb on pb.operation_code=s.operation_code and pb.step_id=s.step_id and pb.status='ACTIVE_ENFORCEMENT' where s.operation_code=v_execution.operation_code and s.required is true and s.active is true and (not v_snapshot_applies or exists (select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id) where frozen.step_id=s.step_id)) and coalesce(s.execution_order,0)<coalesce(v_step.execution_order,0) and (pb.clean_result_value is null or es.status<>pb.clean_result_value);
  if v_prior_missing>0 or v_prior_bad>0 then v_block_code:='PRIOR_REQUIRED_STEP_NOT_CLEAN'; v_block_details:=jsonb_build_object('prior_missing',v_prior_missing,'prior_bad',v_prior_bad); end if;
  if v_block_code is null then for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop if not (p_evidence_payload ? v_key) or p_evidence_payload->v_key is null or p_evidence_payload->v_key='null'::jsonb or (jsonb_typeof(p_evidence_payload->v_key)='string' and btrim(p_evidence_payload->>v_key)='') then v_missing_keys:=array_append(v_missing_keys,v_key); end if; end loop; if cardinality(v_missing_keys)>0 then v_block_code:='REQUIRED_EVIDENCE_MISSING'; v_block_details:=jsonb_build_object('missing_keys',to_jsonb(v_missing_keys)); end if; end if;
  if v_block_code is null and p_evidence_payload ? 'blocking_codes' then if jsonb_typeof(p_evidence_payload->'blocking_codes')<>'array' then v_block_code:='BLOCKING_CODES_INVALID'; else v_blocking_codes:=p_evidence_payload->'blocking_codes'; if jsonb_array_length(v_blocking_codes)>0 then v_block_code:=coalesce(v_contract.blocking_code,'STEP_BLOCKED'); v_block_details:=jsonb_build_object('caller_blocking_codes',v_blocking_codes); end if; end if; end if;
  if v_block_code is null and v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='pre_write_execution_binding_gate' then
    v_trust:=p_evidence_payload->'server_trust_context';
    if coalesce(p_evidence_payload->'server_trust_context_valid','false'::jsonb) <> 'true'::jsonb or p_evidence_payload->>'server_trust_context_source'<>'run-creacion-perfil-lf' or jsonb_typeof(v_trust)<>'object' or v_trust->>'resolver'<>'GITHUB_PUBLIC_API_EXACT_REF_V1' or v_trust->>'repository'<>coalesce(v_execution.target_repo,'') or v_trust->>'ref'<>'main' or v_trust->>'target_path'<>coalesce(v_execution.target_path,'') or v_trust->>'bound_revision'<>p_evidence_payload->>'bound_revision' or v_trust->>'continuity_state' not in ('CURRENT_BOUND','STALE_REBOUND_CURRENT') or (v_trust->>'revision_sha') !~ '^[0-9a-f]{40}$' or (v_trust->>'target_blob_sha') !~ '^[0-9a-f]{40}$' or (v_trust->>'baseline_revision') !~ '^[0-9a-f]{40}$' then v_block_code:='PROFILE_UPDATE_SERVER_TRUST_CONTEXT_NOT_MATERIALIZED'; v_block_details:=jsonb_build_object('reason','Validated server-derived trust context required'); end if;
  end if;
  if v_block_code is null and v_has_evolved_route
     and p_step_id IN ('method_selection','evolution_decision') then
    v_block_code:=public.lf_profile_update_evolution_step_guard_v1(
        p_execution_id,p_step_id,p_evidence_payload);
    if v_block_code is not null then
      v_block_details:=jsonb_build_object(
        'reason','Evolution step requires verified evidence, not producer claims');
    end if;
  end if;
  if v_block_code is null and v_execution.operation_code='ACTUALIZACION_PERFIL_LF' then
    v_block_code:=public.lf_profile_update_substantive_block_v1(p_execution_id,p_step_id,p_evidence_payload,v_execution.manifest);
    if v_block_code is not null then v_block_details:=jsonb_build_object('reason','Substantive Profile update/graduation evidence did not satisfy fail-closed contract','graduation_contract',v_execution.manifest->>'graduation_contract'); end if;
  end if;
  -- Frozen v0.2 UPDATE only: NO_CHANGE creates no candidate output;
  -- legacy v0.1 executions and creation run their original contracts.
  -- The positive and negative source-bound receipts must be VERIFIED by
  -- the existing private-ledger reader; user-supplied PASS text cannot admit.
  if v_block_code is null and v_has_evolved_route
     and v_route_resolution->>'outcome'='UPDATE'
     and p_step_id='deterministic_validation' then
    v_output_parity:=p_evidence_payload->'candidate_output_contract_gate';
    select es.evidence_payload into v_head_readback
      from public.lf_operation_execution_steps es
     where es.execution_id=p_execution_id and es.step_id='github_readback'
       and es.status='STEP_PASS_WITH_EVIDENCE';
    v_profile_slug:=split_part(coalesce(v_execution.target_path,''),'/',2);
    v_candidate_head:=v_head_readback->>'exact_head';
    if jsonb_typeof(v_output_parity) is distinct from 'object'
       or nullif(v_profile_slug,'') is null
       or coalesce(v_candidate_head,'') !~ '^[0-9a-f]{40}  -- Preserve v0.1 frozen executions; require actual successful validation
  -- for both evolved outcomes before recording a clean judge step.
  if v_block_code is null and v_has_evolved_route
     and v_route_resolution->>'outcome' in ('NO_CHANGE','UPDATE') then
    if p_step_id='deterministic_validation' then
      if public.lf_profile_update_result_class_v1(p_evidence_payload->'validator_result') is distinct from 'PASS' then
        v_block_code:='PROFILE_EVOLUTION_VALIDATOR_PASS_UNPROVEN';
      elsif public.lf_profile_update_result_class_v1(p_evidence_payload->'malformed_input_result') is distinct from 'PASS' then
        v_block_code:='PROFILE_EVOLUTION_MALFORMED_GATE_PASS_UNPROVEN';
      end if;
    elsif p_step_id='semantic_judge'
      and public.lf_profile_update_result_class_v1(p_evidence_payload->'semantic_judge_result') is distinct from 'PASS' then
      v_block_code:='PROFILE_EVOLUTION_SEMANTIC_PASS_UNPROVEN';
    end if;
    if v_block_code is not null then
      v_block_details:=jsonb_build_object('reason','Evolved profile route requires substantive PASS from real validator, not UNPROVEN');
    end if;
  end if;
  if v_block_code is not null then
    v_payload:=p_evidence_payload; for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop if not (v_payload ? v_key) then v_payload:=v_payload||jsonb_build_object(v_key,null); end if; end loop;
    v_attempt_history:=v_attempt_history||jsonb_build_array(jsonb_build_object('at',clock_timestamp(),'outcome','BLOCKED','code',v_block_code,'evidence_ref',p_evidence_ref,'details',v_block_details));
    v_payload:=v_payload||jsonb_build_object('step_result',v_binding.blocked_result_value,'blocking_findings',jsonb_build_array(v_block_code),'blocking_codes',jsonb_build_array(v_block_code),'return_to_worker_reasons','[]'::jsonb,'assertions_checked',coalesce(v_payload->'assertions_checked','[]'::jsonb),'hard_fails_checked',coalesce(v_payload->'hard_fails_checked','[]'::jsonb),'blocked_by_recorder',true,'blocked_reason_code',v_block_code,'blocked_details',v_block_details,'attempt_history',v_attempt_history,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.blocked_result_value,'recorded_by_rpc','lf_record_profile_operation_step_v1');
    if v_existing_retryable then update public.lf_operation_execution_steps set status=v_binding.blocked_result_value,evidence_ref=p_evidence_ref,evidence_payload=v_payload,notes='Blocked attempt persisted transactionally; retry remains allowed on same row.' where execution_id=p_execution_id and step_id=p_step_id; else insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id) values(p_execution_id,v_step.step_order,p_step_id,v_binding.blocked_result_value,p_evidence_ref,v_payload,'Blocked attempt persisted transactionally by common governed Profile operation recorder.',p_actor_execution_id); end if;
    return jsonb_build_object('outcome','BLOCKED','code',v_block_code,'durable',true,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'status',v_binding.blocked_result_value,'retryable',true,'attempt_count',jsonb_array_length(v_attempt_history))||v_block_details;
  end if;
  v_payload:=p_evidence_payload||jsonb_build_object('step_result',v_binding.clean_result_value,'blocking_codes','[]'::jsonb,'blocking_findings','[]'::jsonb,'return_to_worker_reasons','[]'::jsonb,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.clean_result_value,'recorded_by_rpc','lf_record_profile_operation_step_v1','attempt_history',v_attempt_history);
  if v_existing_retryable then update public.lf_operation_execution_steps set status=v_binding.clean_result_value,evidence_ref=p_evidence_ref,evidence_payload=v_payload,notes='Clean retry accepted transactionally; prior blocked attempts preserved in attempt_history.' where execution_id=p_execution_id and step_id=p_step_id; else insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id) values(p_execution_id,v_step.step_order,p_step_id,v_binding.clean_result_value,p_evidence_ref,v_payload,'Recorded transactionally by common governed Profile operation recorder.',p_actor_execution_id); end if;
  if v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then
    select count(*) into v_required_not_clean
    from public.lf_operation_steps s
    left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_id=s.step_id
    left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_id=s.step_id and b.status='ACTIVE_ENFORCEMENT'
    where s.operation_code=v_execution.operation_code and s.required is true and s.active is true and (not v_snapshot_applies or exists (select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id) where frozen.step_id=s.step_id))
      and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);
    if v_required_not_clean>0 then raise exception 'PROFILE_UPDATE_COMPLETION_NOT_CLEAN execution=% required_not_clean=%',p_execution_id,v_required_not_clean; end if;
    update public.lf_operation_execution
    set status='COMPLETED',
        completed_at=coalesce(completed_at,now()),
        manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('operation_closed',true,'next_gate',coalesce(p_evidence_payload->'next_gate',manifest->'next_gate')),
        updated_by_execution_id=p_actor_execution_id,
        updated_at=now()
    where execution_id=p_execution_id and status='IN_PROGRESS';
  end if;
  return jsonb_build_object('outcome','STEP_RECORDED','replay',false,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'step_order',v_step.step_order,'execution_order',v_step.execution_order,'status',v_binding.clean_result_value,'execution_status',case when v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then 'COMPLETED' else v_execution.status end,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.clean_result_value,'next_gate',v_contract.next_if_pass,'resumed_from_blocked',v_existing_retryable,'prior_attempt_count',jsonb_array_length(v_attempt_history));
end;
$function$;

       or v_head_readback->>'recorded_by_rpc' is distinct from 'lf_record_profile_operation_step_v1'
       or v_head_readback->>'sha_match' is distinct from 'true'
       or v_output_parity->>'candidate_head_sha' is distinct from v_candidate_head
       or coalesce(v_output_parity->>'positive_output_sha256','') !~ '^[0-9a-f]{64}  -- Preserve v0.1 frozen executions; require actual successful validation
  -- for both evolved outcomes before recording a clean judge step.
  if v_block_code is null and v_has_evolved_route
     and v_route_resolution->>'outcome' in ('NO_CHANGE','UPDATE') then
    if p_step_id='deterministic_validation' then
      if public.lf_profile_update_result_class_v1(p_evidence_payload->'validator_result') is distinct from 'PASS' then
        v_block_code:='PROFILE_EVOLUTION_VALIDATOR_PASS_UNPROVEN';
      elsif public.lf_profile_update_result_class_v1(p_evidence_payload->'malformed_input_result') is distinct from 'PASS' then
        v_block_code:='PROFILE_EVOLUTION_MALFORMED_GATE_PASS_UNPROVEN';
      end if;
    elsif p_step_id='semantic_judge'
      and public.lf_profile_update_result_class_v1(p_evidence_payload->'semantic_judge_result') is distinct from 'PASS' then
      v_block_code:='PROFILE_EVOLUTION_SEMANTIC_PASS_UNPROVEN';
    end if;
    if v_block_code is not null then
      v_block_details:=jsonb_build_object('reason','Evolved profile route requires substantive PASS from real validator, not UNPROVEN');
    end if;
  end if;
  if v_block_code is not null then
    v_payload:=p_evidence_payload; for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop if not (v_payload ? v_key) then v_payload:=v_payload||jsonb_build_object(v_key,null); end if; end loop;
    v_attempt_history:=v_attempt_history||jsonb_build_array(jsonb_build_object('at',clock_timestamp(),'outcome','BLOCKED','code',v_block_code,'evidence_ref',p_evidence_ref,'details',v_block_details));
    v_payload:=v_payload||jsonb_build_object('step_result',v_binding.blocked_result_value,'blocking_findings',jsonb_build_array(v_block_code),'blocking_codes',jsonb_build_array(v_block_code),'return_to_worker_reasons','[]'::jsonb,'assertions_checked',coalesce(v_payload->'assertions_checked','[]'::jsonb),'hard_fails_checked',coalesce(v_payload->'hard_fails_checked','[]'::jsonb),'blocked_by_recorder',true,'blocked_reason_code',v_block_code,'blocked_details',v_block_details,'attempt_history',v_attempt_history,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.blocked_result_value,'recorded_by_rpc','lf_record_profile_operation_step_v1');
    if v_existing_retryable then update public.lf_operation_execution_steps set status=v_binding.blocked_result_value,evidence_ref=p_evidence_ref,evidence_payload=v_payload,notes='Blocked attempt persisted transactionally; retry remains allowed on same row.' where execution_id=p_execution_id and step_id=p_step_id; else insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id) values(p_execution_id,v_step.step_order,p_step_id,v_binding.blocked_result_value,p_evidence_ref,v_payload,'Blocked attempt persisted transactionally by common governed Profile operation recorder.',p_actor_execution_id); end if;
    return jsonb_build_object('outcome','BLOCKED','code',v_block_code,'durable',true,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'status',v_binding.blocked_result_value,'retryable',true,'attempt_count',jsonb_array_length(v_attempt_history))||v_block_details;
  end if;
  v_payload:=p_evidence_payload||jsonb_build_object('step_result',v_binding.clean_result_value,'blocking_codes','[]'::jsonb,'blocking_findings','[]'::jsonb,'return_to_worker_reasons','[]'::jsonb,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.clean_result_value,'recorded_by_rpc','lf_record_profile_operation_step_v1','attempt_history',v_attempt_history);
  if v_existing_retryable then update public.lf_operation_execution_steps set status=v_binding.clean_result_value,evidence_ref=p_evidence_ref,evidence_payload=v_payload,notes='Clean retry accepted transactionally; prior blocked attempts preserved in attempt_history.' where execution_id=p_execution_id and step_id=p_step_id; else insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id) values(p_execution_id,v_step.step_order,p_step_id,v_binding.clean_result_value,p_evidence_ref,v_payload,'Recorded transactionally by common governed Profile operation recorder.',p_actor_execution_id); end if;
  if v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then
    select count(*) into v_required_not_clean
    from public.lf_operation_steps s
    left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_id=s.step_id
    left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_id=s.step_id and b.status='ACTIVE_ENFORCEMENT'
    where s.operation_code=v_execution.operation_code and s.required is true and s.active is true and (not v_snapshot_applies or exists (select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id) where frozen.step_id=s.step_id))
      and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);
    if v_required_not_clean>0 then raise exception 'PROFILE_UPDATE_COMPLETION_NOT_CLEAN execution=% required_not_clean=%',p_execution_id,v_required_not_clean; end if;
    update public.lf_operation_execution
    set status='COMPLETED',
        completed_at=coalesce(completed_at,now()),
        manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('operation_closed',true,'next_gate',coalesce(p_evidence_payload->'next_gate',manifest->'next_gate')),
        updated_by_execution_id=p_actor_execution_id,
        updated_at=now()
    where execution_id=p_execution_id and status='IN_PROGRESS';
  end if;
  return jsonb_build_object('outcome','STEP_RECORDED','replay',false,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'step_order',v_step.step_order,'execution_order',v_step.execution_order,'status',v_binding.clean_result_value,'execution_status',case when v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then 'COMPLETED' else v_execution.status end,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.clean_result_value,'next_gate',v_contract.next_if_pass,'resumed_from_blocked',v_existing_retryable,'prior_attempt_count',jsonb_array_length(v_attempt_history));
end;
$function$;

       or coalesce(v_output_parity->>'negative_output_sha256','') !~ '^[0-9a-f]{64}  -- Preserve v0.1 frozen executions; require actual successful validation
  -- for both evolved outcomes before recording a clean judge step.
  if v_block_code is null and v_has_evolved_route
     and v_route_resolution->>'outcome' in ('NO_CHANGE','UPDATE') then
    if p_step_id='deterministic_validation' then
      if public.lf_profile_update_result_class_v1(p_evidence_payload->'validator_result') is distinct from 'PASS' then
        v_block_code:='PROFILE_EVOLUTION_VALIDATOR_PASS_UNPROVEN';
      elsif public.lf_profile_update_result_class_v1(p_evidence_payload->'malformed_input_result') is distinct from 'PASS' then
        v_block_code:='PROFILE_EVOLUTION_MALFORMED_GATE_PASS_UNPROVEN';
      end if;
    elsif p_step_id='semantic_judge'
      and public.lf_profile_update_result_class_v1(p_evidence_payload->'semantic_judge_result') is distinct from 'PASS' then
      v_block_code:='PROFILE_EVOLUTION_SEMANTIC_PASS_UNPROVEN';
    end if;
    if v_block_code is not null then
      v_block_details:=jsonb_build_object('reason','Evolved profile route requires substantive PASS from real validator, not UNPROVEN');
    end if;
  end if;
  if v_block_code is not null then
    v_payload:=p_evidence_payload; for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop if not (v_payload ? v_key) then v_payload:=v_payload||jsonb_build_object(v_key,null); end if; end loop;
    v_attempt_history:=v_attempt_history||jsonb_build_array(jsonb_build_object('at',clock_timestamp(),'outcome','BLOCKED','code',v_block_code,'evidence_ref',p_evidence_ref,'details',v_block_details));
    v_payload:=v_payload||jsonb_build_object('step_result',v_binding.blocked_result_value,'blocking_findings',jsonb_build_array(v_block_code),'blocking_codes',jsonb_build_array(v_block_code),'return_to_worker_reasons','[]'::jsonb,'assertions_checked',coalesce(v_payload->'assertions_checked','[]'::jsonb),'hard_fails_checked',coalesce(v_payload->'hard_fails_checked','[]'::jsonb),'blocked_by_recorder',true,'blocked_reason_code',v_block_code,'blocked_details',v_block_details,'attempt_history',v_attempt_history,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.blocked_result_value,'recorded_by_rpc','lf_record_profile_operation_step_v1');
    if v_existing_retryable then update public.lf_operation_execution_steps set status=v_binding.blocked_result_value,evidence_ref=p_evidence_ref,evidence_payload=v_payload,notes='Blocked attempt persisted transactionally; retry remains allowed on same row.' where execution_id=p_execution_id and step_id=p_step_id; else insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id) values(p_execution_id,v_step.step_order,p_step_id,v_binding.blocked_result_value,p_evidence_ref,v_payload,'Blocked attempt persisted transactionally by common governed Profile operation recorder.',p_actor_execution_id); end if;
    return jsonb_build_object('outcome','BLOCKED','code',v_block_code,'durable',true,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'status',v_binding.blocked_result_value,'retryable',true,'attempt_count',jsonb_array_length(v_attempt_history))||v_block_details;
  end if;
  v_payload:=p_evidence_payload||jsonb_build_object('step_result',v_binding.clean_result_value,'blocking_codes','[]'::jsonb,'blocking_findings','[]'::jsonb,'return_to_worker_reasons','[]'::jsonb,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.clean_result_value,'recorded_by_rpc','lf_record_profile_operation_step_v1','attempt_history',v_attempt_history);
  if v_existing_retryable then update public.lf_operation_execution_steps set status=v_binding.clean_result_value,evidence_ref=p_evidence_ref,evidence_payload=v_payload,notes='Clean retry accepted transactionally; prior blocked attempts preserved in attempt_history.' where execution_id=p_execution_id and step_id=p_step_id; else insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id) values(p_execution_id,v_step.step_order,p_step_id,v_binding.clean_result_value,p_evidence_ref,v_payload,'Recorded transactionally by common governed Profile operation recorder.',p_actor_execution_id); end if;
  if v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then
    select count(*) into v_required_not_clean
    from public.lf_operation_steps s
    left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_id=s.step_id
    left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_id=s.step_id and b.status='ACTIVE_ENFORCEMENT'
    where s.operation_code=v_execution.operation_code and s.required is true and s.active is true and (not v_snapshot_applies or exists (select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id) where frozen.step_id=s.step_id))
      and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);
    if v_required_not_clean>0 then raise exception 'PROFILE_UPDATE_COMPLETION_NOT_CLEAN execution=% required_not_clean=%',p_execution_id,v_required_not_clean; end if;
    update public.lf_operation_execution
    set status='COMPLETED',
        completed_at=coalesce(completed_at,now()),
        manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('operation_closed',true,'next_gate',coalesce(p_evidence_payload->'next_gate',manifest->'next_gate')),
        updated_by_execution_id=p_actor_execution_id,
        updated_at=now()
    where execution_id=p_execution_id and status='IN_PROGRESS';
  end if;
  return jsonb_build_object('outcome','STEP_RECORDED','replay',false,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'step_order',v_step.step_order,'execution_order',v_step.execution_order,'status',v_binding.clean_result_value,'execution_status',case when v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then 'COMPLETED' else v_execution.status end,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.clean_result_value,'next_gate',v_contract.next_if_pass,'resumed_from_blocked',v_existing_retryable,'prior_attempt_count',jsonb_array_length(v_attempt_history));
end;
$function$;

       or v_output_parity->>'positive_output_sha256' is not distinct from
          v_output_parity->>'negative_output_sha256' then
      v_block_code:='PROFILE_EVOLUTION_OUTPUT_PARITY_SOURCE_UNRESOLVED';
    elsif not public.lf_profile_update_verified_receipt_v1(
             'PROFILE_OUTPUT_VALIDATION_POSITIVE',v_profile_slug,
             v_output_parity->>'positive_receipt_id',
             v_output_parity->>'positive_output_sha256',v_candidate_head)
       or not public.lf_profile_update_verified_receipt_v1(
             'PROFILE_OUTPUT_VALIDATION_NEGATIVE',v_profile_slug,
             v_output_parity->>'negative_receipt_id',
             v_output_parity->>'negative_output_sha256',v_candidate_head)
    then
      v_block_code:='PROFILE_EVOLUTION_OUTPUT_PARITY_RECEIPT_NOT_VERIFIED';
    end if;
    if v_block_code is not null then
      v_block_details:=jsonb_build_object(
        'reason','Current profile output needs verified canonical positive and negative validator receipts, not claimed PASS',
        'candidate_head_sha',v_candidate_head,'profile_slug',v_profile_slug);
    end if;
  end if;
  -- v0.2 only: evidence marked UNPROVEN is not a substantive PASS.
  -- Preserve v0.1 frozen executions; require actual successful validation
  -- for both evolved outcomes before recording a clean judge step.
  if v_block_code is null and v_has_evolved_route
     and v_route_resolution->>'outcome' in ('NO_CHANGE','UPDATE') then
    if p_step_id='deterministic_validation' then
      if public.lf_profile_update_result_class_v1(p_evidence_payload->'validator_result') is distinct from 'PASS' then
        v_block_code:='PROFILE_EVOLUTION_VALIDATOR_PASS_UNPROVEN';
      elsif public.lf_profile_update_result_class_v1(p_evidence_payload->'malformed_input_result') is distinct from 'PASS' then
        v_block_code:='PROFILE_EVOLUTION_MALFORMED_GATE_PASS_UNPROVEN';
      end if;
    elsif p_step_id='semantic_judge'
      and public.lf_profile_update_result_class_v1(p_evidence_payload->'semantic_judge_result') is distinct from 'PASS' then
      v_block_code:='PROFILE_EVOLUTION_SEMANTIC_PASS_UNPROVEN';
    end if;
    if v_block_code is not null then
      v_block_details:=jsonb_build_object('reason','Evolved profile route requires substantive PASS from real validator, not UNPROVEN');
    end if;
  end if;
  if v_block_code is not null then
    v_payload:=p_evidence_payload; for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop if not (v_payload ? v_key) then v_payload:=v_payload||jsonb_build_object(v_key,null); end if; end loop;
    v_attempt_history:=v_attempt_history||jsonb_build_array(jsonb_build_object('at',clock_timestamp(),'outcome','BLOCKED','code',v_block_code,'evidence_ref',p_evidence_ref,'details',v_block_details));
    v_payload:=v_payload||jsonb_build_object('step_result',v_binding.blocked_result_value,'blocking_findings',jsonb_build_array(v_block_code),'blocking_codes',jsonb_build_array(v_block_code),'return_to_worker_reasons','[]'::jsonb,'assertions_checked',coalesce(v_payload->'assertions_checked','[]'::jsonb),'hard_fails_checked',coalesce(v_payload->'hard_fails_checked','[]'::jsonb),'blocked_by_recorder',true,'blocked_reason_code',v_block_code,'blocked_details',v_block_details,'attempt_history',v_attempt_history,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.blocked_result_value,'recorded_by_rpc','lf_record_profile_operation_step_v1');
    if v_existing_retryable then update public.lf_operation_execution_steps set status=v_binding.blocked_result_value,evidence_ref=p_evidence_ref,evidence_payload=v_payload,notes='Blocked attempt persisted transactionally; retry remains allowed on same row.' where execution_id=p_execution_id and step_id=p_step_id; else insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id) values(p_execution_id,v_step.step_order,p_step_id,v_binding.blocked_result_value,p_evidence_ref,v_payload,'Blocked attempt persisted transactionally by common governed Profile operation recorder.',p_actor_execution_id); end if;
    return jsonb_build_object('outcome','BLOCKED','code',v_block_code,'durable',true,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'status',v_binding.blocked_result_value,'retryable',true,'attempt_count',jsonb_array_length(v_attempt_history))||v_block_details;
  end if;
  v_payload:=p_evidence_payload||jsonb_build_object('step_result',v_binding.clean_result_value,'blocking_codes','[]'::jsonb,'blocking_findings','[]'::jsonb,'return_to_worker_reasons','[]'::jsonb,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.clean_result_value,'recorded_by_rpc','lf_record_profile_operation_step_v1','attempt_history',v_attempt_history);
  if v_existing_retryable then update public.lf_operation_execution_steps set status=v_binding.clean_result_value,evidence_ref=p_evidence_ref,evidence_payload=v_payload,notes='Clean retry accepted transactionally; prior blocked attempts preserved in attempt_history.' where execution_id=p_execution_id and step_id=p_step_id; else insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id) values(p_execution_id,v_step.step_order,p_step_id,v_binding.clean_result_value,p_evidence_ref,v_payload,'Recorded transactionally by common governed Profile operation recorder.',p_actor_execution_id); end if;
  if v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then
    select count(*) into v_required_not_clean
    from public.lf_operation_steps s
    left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_id=s.step_id
    left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_id=s.step_id and b.status='ACTIVE_ENFORCEMENT'
    where s.operation_code=v_execution.operation_code and s.required is true and s.active is true and (not v_snapshot_applies or exists (select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id) where frozen.step_id=s.step_id))
      and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);
    if v_required_not_clean>0 then raise exception 'PROFILE_UPDATE_COMPLETION_NOT_CLEAN execution=% required_not_clean=%',p_execution_id,v_required_not_clean; end if;
    update public.lf_operation_execution
    set status='COMPLETED',
        completed_at=coalesce(completed_at,now()),
        manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('operation_closed',true,'next_gate',coalesce(p_evidence_payload->'next_gate',manifest->'next_gate')),
        updated_by_execution_id=p_actor_execution_id,
        updated_at=now()
    where execution_id=p_execution_id and status='IN_PROGRESS';
  end if;
  return jsonb_build_object('outcome','STEP_RECORDED','replay',false,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'step_order',v_step.step_order,'execution_order',v_step.execution_order,'status',v_binding.clean_result_value,'execution_status',case when v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then 'COMPLETED' else v_execution.status end,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.clean_result_value,'next_gate',v_contract.next_if_pass,'resumed_from_blocked',v_existing_retryable,'prior_attempt_count',jsonb_array_length(v_attempt_history));
end;
$function$;
