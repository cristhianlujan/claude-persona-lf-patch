-- LF PE10_C6. Governed recorder integration plus reversible transactional
-- trial of actual step 35/37 recorder and immutable outcome-specific routes.
-- NO policy cutover; 35/37 remain inactive after commit. NO C6/C7 close.
-- Route: PASE + ACTUALIZACION_DB_LF / LF Migration Merge Train only.
BEGIN;
DO $preflight$
BEGIN
  IF md5(pg_get_functiondef('public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text)'::regprocedure))
      <> 'd6f64fcd160843d9f9644cd388ebf4c5'
  THEN RAISE EXCEPTION 'PE10_C6_RECORDER_LIVE_SOURCE_DRIFT'; END IF;
  IF EXISTS (SELECT 1 FROM public.lf_eventos
             WHERE entidad_codigo='PE10_C6.RECORDER_ROUTE_GUARD_ROLLBACK_PROBE.V1')
     OR (SELECT version FROM public.lf_operation_registry
         WHERE operation_code='ACTUALIZACION_PERFIL_LF') <> 'v0.1'
     OR (SELECT count(*) FROM public.lf_operation_execution
         WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS') <> 0
     OR (SELECT count(*) FROM public.lf_operation_steps
         WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND active) <> 15
     OR (SELECT status FROM programacion.engineering_work_checkpoints c
          JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
          WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
            AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C6') <> 'PENDING'
  THEN RAISE EXCEPTION 'PE10_C6_RECORDER_PRESTATE_CHANGED'; END IF;
END $preflight$;

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

  -- PE10_C6: no effect on historical v0.1 executions. Route authority is
  -- the immutable policy snapshot attached to THIS execution.
  v_has_evolved_route := v_execution.operation_code='ACTUALIZACION_PERFIL_LF'
    and v_execution.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps_by_outcome}' IS NOT NULL;
  IF v_has_evolved_route THEN
    v_route_resolution := public.lf_profile_update_effective_route_v1(p_execution_id);
    IF v_route_resolution->>'outcome' NOT IN ('AWAITING_EVOLUTION_DECISION','UPDATE','NO_CHANGE')
      OR coalesce(jsonb_typeof(v_route_resolution->'effective_steps'),'')<>'array'
      OR jsonb_array_length(v_route_resolution->'effective_steps')=0
    THEN RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_UPDATE_EVOLUTION_ROUTE_UNRESOLVED','durable',false,'route',v_route_resolution); END IF;
    v_snapshot_steps := v_route_resolution->'effective_steps';
    v_snapshot_applies := true;
    IF NOT (v_snapshot_steps ? p_step_id) THEN
      RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_UPDATE_STEP_NOT_ON_FROZEN_ROUTE','durable',false,'step_id',p_step_id);
    END IF;
  END IF;

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
  IF v_block_code IS NULL AND v_has_evolved_route
    AND p_step_id IN ('method_selection','evolution_decision') THEN
    v_block_code := public.lf_profile_update_evolution_step_guard_v1(
      p_execution_id,p_step_id,p_evidence_payload);
    IF v_block_code IS NOT NULL THEN
      v_block_details:=jsonb_build_object('reason','Verified evolution step evidence required; caller assertions alone do not grant authority');
    END IF;
  END IF;
  if v_block_code is null and v_execution.operation_code='ACTUALIZACION_PERFIL_LF' then
    v_block_code:=public.lf_profile_update_substantive_block_v1(p_execution_id,p_step_id,p_evidence_payload,v_execution.manifest);
    if v_block_code is not null then v_block_details:=jsonb_build_object('reason','Substantive Profile update/graduation evidence did not satisfy fail-closed contract','graduation_contract',v_execution.manifest->>'graduation_contract'); end if;
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
$function$


DO $pe10_c6_recorder$
DECLARE
  v_operation constant text := 'ACTUALIZACION_PERFIL_LF';
  v_actor constant text := 'EXEC-PE10-C6-RECORDER-TX-NONAUTHORITY-V1';
  v_event_code constant text := 'PE10_C6.RECORDER_ROUTE_GUARD_ROLLBACK_PROBE.V1';
  v_slug constant text := 'systemic_root_cause_repair_lf';
  v_receipt constant text := '9f758577-c9f6-4744-852b-a03827b466f6';
  v_subject_sha constant text := '692618756e551011b52487bc7091ed5f14f166c66f99f9ecea95619c0f5634fc';
  v_head constant text := '8dabb3a1bfd68dc90b78b09233000bce92d35ee9';
  v_selector text;
  v_policy jsonb;
  v_exec text;
  v_mode text;
  v_payload jsonb;
  v_decision jsonb;
  v_result jsonb;
  v_route jsonb;
  v_audit jsonb;
  v_count integer;
  v_event_id bigint;
BEGIN
  IF position('lf_profile_update_evolution_step_guard_v1' in
      pg_get_functiondef('public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text)'::regprocedure))=0
    OR position('lf_profile_update_effective_route_v1' in
      pg_get_functiondef('public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text)'::regprocedure))=0
  THEN RAISE EXCEPTION 'PE10_C6_RECORDER_INTEGRATION_NOT_MATERIAL'; END IF;

  SELECT policy_payload INTO v_policy FROM public.lf_policy_versions
    WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate'
      AND status='CANDIDATE';
  SELECT version INTO v_selector FROM public.lf_capability_current
    WHERE capability_code='CAPABILITY_SELECTOR';
  IF v_policy IS NULL OR v_selector<>'1.0.0'
     OR jsonb_array_length(v_policy->'required_steps')<>17
     OR jsonb_array_length(v_policy#>'{required_steps_by_outcome,NO_CHANGE}')<>10
     OR NOT public.lf_profile_update_verified_receipt_v1('PROFILE_ASSESSMENT',v_slug,v_receipt,v_subject_sha,v_head)
  THEN RAISE EXCEPTION 'PE10_C6_RECORDER_POLICY_OR_RECEIPT_STALE'; END IF;

  -- All changes to authority, executions and mini-judge attempt rows below are
  -- one PostgreSQL EXCEPTION SUBTRANSACTION and must fully roll back.
  BEGIN
    UPDATE public.lf_policy_versions SET status='CANDIDATE'
     WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1' AND status='ACTIVE';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>1 THEN RAISE EXCEPTION 'PE10_C6_ACTIVE_POLICY_NOT_UNIQUE'; END IF;
    UPDATE public.lf_policy_versions SET status='ACTIVE'
     WHERE policy_code='POL-PROFILE-UPDATE-PASS'
       AND policy_version='v1.4-evolved-routing-candidate' AND status='CANDIDATE';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>1 THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_POLICY_NOT_UNIQUE'; END IF;
    UPDATE public.lf_operation_steps SET active=true
     WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
       AND required AND NOT active;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>2 THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_STEPS_NOT_EXACT'; END IF;
    UPDATE public.lf_operation_step_contracts SET status='ACTIVE_ENFORCEMENT'
     WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
       AND status='CANDIDATE';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>2 THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_CONTRACTS_NOT_EXACT'; END IF;
    UPDATE public.lf_operation_step_judge_bindings SET status='ACTIVE_ENFORCEMENT'
     WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
       AND status='CANDIDATE';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>2 THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_BINDINGS_NOT_EXACT'; END IF;

    FOREACH v_mode IN ARRAY ARRAY['UPDATE','NO_CHANGE'] LOOP
      v_exec := 'EXEC-PE10-C6-RECORDER-SUBTX-'||v_mode||'-20261022-V1';
      SELECT public.lf_profile_update_begin_v1(
         v_exec,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
         'cristhianlujan/claude-persona-lf-patch',
         'profiles/systemic_root_cause_repair_lf',
         repeat('e',64),'pe10-c6-recorder-route-'||lower(v_mode)||'-20261022-v1',
         v_actor,
         jsonb_build_object('transactional_probe_only',true,
           'production_authorized',false,'initial_main_revision',v_head)
      ) INTO v_result;
      IF v_result->>'init_step' IS DISTINCT FROM 'RECORDED' THEN
        RAISE EXCEPTION 'PE10_C6_BEGIN_NOT_RECORDED:%',v_result; END IF;

      -- Fixture ONLY: prior three prefix steps are structurally clean within
      -- the rollback scope. This is NOT a real Router/provider pass receipt.
      INSERT INTO public.lf_operation_execution_steps(
        execution_id,step_order,step_id,status,evidence_ref,evidence_payload,
        notes,created_by_execution_id
      )
      SELECT v_exec,s.step_order,s.step_id,b.clean_result_value,
        'pe10-c6://rollback-only-prefix-fixture',
        CASE s.step_id
         WHEN 'router' THEN
           jsonb_build_object('router_read',true,'action','PROFILE_UPDATE')
         WHEN 'profile_resolve' THEN
           jsonb_build_object('codigo_activo','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
             'profile_slug',v_slug,'repo_path','profiles/'||v_slug,'exact_profile_resolved',true)
         WHEN 'baseline_read' THEN
           jsonb_build_object('baseline_revision',v_head,
             'baseline_files',jsonb_build_array('profiles/'||v_slug),
             'before_evidence',jsonb_build_object('fixture_only',true))
        END || jsonb_build_object(
          'assertions_checked','[]'::jsonb,'hard_fails_checked','[]'::jsonb,
          'blocking_findings','[]'::jsonb,'return_to_worker_reasons','[]'::jsonb,
          'mini_judge_result',b.clean_result_value,'recorded_by_rpc','PE10_C6_ROLLBACK_ONLY_FIXTURE',
          'fixture_not_provider_attestation',true),
        'Rollback-only synthetic prefix; no operational certification',v_actor
      FROM public.lf_operation_steps s
      JOIN public.lf_operation_step_judge_bindings b ON b.operation_code=s.operation_code
        AND b.step_id=s.step_id AND b.status='ACTIVE_ENFORCEMENT'
      WHERE s.operation_code=v_operation AND s.step_id IN ('router','profile_resolve','baseline_read');
      GET DIAGNOSTICS v_count=ROW_COUNT;
      IF v_count<>3 THEN RAISE EXCEPTION 'PE10_C6_PREFIX_FIXTURE_NOT_EXACT'; END IF;

      v_payload := jsonb_build_object(
        'profile_slug',v_slug,'source_head_sha',v_head,
        'profile_assessment_receipt_id',v_receipt,
        'profile_assessment_sha256',v_subject_sha,
        'selector_version',v_selector,'selected_methods','[]'::jsonb,
        'no_additional_method_needed',true,
        'empty_selection_reason','STRUCTURAL_BINDING_NO_METHOD_EXECUTION',
        'method_execution_permitted',false,
        'assertions_checked',jsonb_build_array(
          'verified_assessment','qualified_method_receipts_or_reasoned_empty',
          'current_selector','method_execution_permitted_false'),
        'hard_fails_checked','[]'::jsonb);

      SELECT public.lf_record_profile_operation_step_v1(
         v_exec,'method_selection','pe10-c6://rollback-only-negative',
         v_payload-'empty_selection_reason',v_actor) INTO v_result;
      IF v_result->>'outcome' <> 'BLOCKED'
        OR v_result->>'code' <> 'EVOLUTION_EMPTY_METHOD_UNJUSTIFIED'
        OR v_result->>'retryable' <> 'true'
      THEN RAISE EXCEPTION 'PE10_C6_RECORDER_MISSING_REASON_ACCEPTED:%',v_result; END IF;

      SELECT public.lf_record_profile_operation_step_v1(
         v_exec,'method_selection','supabase://private/lf_evidence_ledger_v1/'||v_receipt,
         v_payload,v_actor) INTO v_result;
      IF v_result->>'outcome' <> 'STEP_RECORDED'
         OR v_result->>'status' <> 'STEP_PASS_WITH_EVIDENCE'
         OR v_result->>'resumed_from_blocked' <> 'true'
      THEN RAISE EXCEPTION 'PE10_C6_RECORDER_SELECTION_NOT_CLEAN:%',v_result; END IF;

      IF NOT EXISTS (
        SELECT 1 FROM public.lf_operation_execution_steps
        WHERE execution_id=v_exec AND step_id='method_selection'
          AND status='STEP_PASS_WITH_EVIDENCE'
          AND evidence_payload->>'recorded_by_rpc'='lf_record_profile_operation_step_v1'
          AND jsonb_array_length(evidence_payload->'attempt_history')=1
      ) THEN RAISE EXCEPTION 'PE10_C6_SELECTION_READBACK_FAILED'; END IF;

      v_decision := jsonb_build_object(
         'profile_slug',v_slug,'source_head_sha',v_head,
         'profile_assessment_receipt_id',v_receipt,
         'profile_assessment_sha256',v_subject_sha,
         'decision',v_mode,
         'evolution_mode',CASE WHEN v_mode='UPDATE' THEN 'PATCH' ELSE 'NO_CHANGE' END,
         'decision_evidence_ref','pe10-c6://rollback-only-decision-fixture',
         'github_write_permitted',false,
         'assertions_checked',jsonb_build_array('verified_assessment',
            'clean_method_selection','typed_decision_mode','frozen_route_consistency'),
         'hard_fails_checked','[]'::jsonb
      );
      SELECT public.lf_record_profile_operation_step_v1(
        v_exec,'evolution_decision','pe10-c6://rollback-only-negative',
        v_decision||jsonb_build_object(
          'evolution_mode',CASE WHEN v_mode='UPDATE' THEN 'NO_CHANGE' ELSE 'PATCH' END),
        v_actor
      ) INTO v_result;
      IF v_result->>'outcome' <> 'BLOCKED'
         OR v_result->>'code' <> CASE WHEN v_mode='UPDATE'
             THEN 'EVOLUTION_UPDATE_MODE_INVALID' ELSE 'EVOLUTION_NO_CHANGE_MODE_INVALID' END
      THEN RAISE EXCEPTION 'PE10_C6_RECORDER_DECISION_MISMATCH_ACCEPTED:%',v_result; END IF;

      SELECT public.lf_record_profile_operation_step_v1(
        v_exec,'evolution_decision','pe10-c6://rollback-only-decision-fixture',
        v_decision,v_actor) INTO v_result;
      IF v_result->>'outcome' <> 'STEP_RECORDED'
         OR v_result->>'status' <> 'STEP_PASS_WITH_EVIDENCE'
         OR v_result->>'resumed_from_blocked'<>'true'
      THEN RAISE EXCEPTION 'PE10_C6_RECORDER_DECISION_NOT_CLEAN:%',v_result; END IF;

      SELECT public.lf_profile_update_effective_route_v1(v_exec) INTO v_route;
      IF v_route->>'outcome' <> v_mode
         OR jsonb_array_length(v_route->'effective_steps') <>
            CASE WHEN v_mode='UPDATE' THEN 17 ELSE 10 END
      THEN RAISE EXCEPTION 'PE10_C6_EFFECTIVE_ROUTE_NOT_FROZEN:%',v_route; END IF;

      IF v_mode='NO_CHANGE' THEN
        SELECT public.lf_record_profile_operation_step_v1(
          v_exec,'github_write','pe10-c6://forbidden-route-fixture',
          '{}'::jsonb,v_actor) INTO v_result;
        IF v_result->>'code'<>'PROFILE_UPDATE_STEP_NOT_ON_FROZEN_ROUTE'
           OR v_result->>'durable'<>'false'
        THEN RAISE EXCEPTION 'PE10_C6_NO_CHANGE_WRITE_ADMITTED:%',v_result; END IF;
      ELSE
        SELECT public.lf_record_profile_operation_step_v1(
          v_exec,'github_write','pe10-c6://premature-write-fixture',
          '{}'::jsonb,v_actor) INTO v_result;
        IF v_result->>'code'<>'PRIOR_REQUIRED_STEP_NOT_CLEAN'
        THEN RAISE EXCEPTION 'PE10_C6_UPDATE_WRITE_PREMATURELY_ADMITTED:%',v_result; END IF;
      END IF;
    END LOOP;
    RAISE EXCEPTION 'PE10_C6_EXPECTED_RECORDER_ROLLBACK';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'PE10_C6_EXPECTED_RECORDER_ROLLBACK' THEN RAISE; END IF;
  END;

  IF EXISTS (SELECT 1 FROM public.lf_operation_execution
       WHERE execution_id LIKE 'EXEC-PE10-C6-RECORDER-SUBTX-%-20261022-V1')
     OR (SELECT count(*) FROM public.lf_operation_steps
         WHERE operation_code=v_operation AND active)<>15
     OR (SELECT count(*) FROM public.lf_operation_steps
         WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
           AND NOT active)<>2
     OR (SELECT count(*) FROM public.lf_operation_step_contracts
         WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
           AND status='CANDIDATE')<>2
     OR (SELECT count(*) FROM public.lf_operation_step_judge_bindings
         WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
           AND status='CANDIDATE')<>2
     OR (SELECT count(*) FROM public.lf_policy_versions
         WHERE policy_code='POL-PROFILE-UPDATE-PASS'
           AND policy_version='v1.1' AND status='ACTIVE')<>1
     OR (SELECT count(*) FROM public.lf_policy_versions
         WHERE policy_code='POL-PROFILE-UPDATE-PASS'
           AND policy_version='v1.4-evolved-routing-candidate' AND status='CANDIDATE')<>1
  THEN RAISE EXCEPTION 'PE10_C6_RECORDER_TRANSACTION_RESIDUE'; END IF;

  v_audit := jsonb_build_object(
     'evidence_schema_version','operational-event/v2',
     'producer','LF_MIGRATION_TRAIN_PE10_C6_RECORDER_PROBE',
     'purpose','Verify recorder routes with a real receipt in rollback-only test fixtures',
     'execution_id',v_actor,'occurred_at',clock_timestamp(),
     'checkpoint_code','PE10_C6',
     'profile_slug',v_slug,
     'profile_assessment_receipt_id',v_receipt,
     'recorder_guard_integrated',true,
     'recorder_transactional_fixture_pass',true,
     'recorder_fixture_synthetic_prefix',true,
     'decision_paths_tested',jsonb_build_array('UPDATE','NO_CHANGE'),
     'negative_cases_tested',jsonb_build_array('MISSING_EMPTY_REASON',
        'DECISION_MODE_MISMATCH','NO_CHANGE_FORBIDS_GITHUB_WRITE',
        'UPDATE_PREMATURE_WRITE_BLOCKED'),
     'transactional_rollback_verified',true,
     'legacy_v01_kept_active',true,
     'checkpoint_pass',false,'production_activation',false,
     'positive_provider_end_to_end_verified',false,
     'acceptance_declared',false
  );
  IF private.fn_lf_event_acceptance_signal_v2(
       'ARTIFACT_RECONCILED',v_event_code,
       'PE10_C6 recorder rollback-only validation, checkpoint remains pending',
       v_audit) IS NOT NULL
  THEN RAISE EXCEPTION 'PE10_C6_EVENT_FALSE_ACCEPTANCE'; END IF;
  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,
    severidad,origen,created_by_execution_id,payload)
  VALUES('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_event_code,
    'PE10 C6 recorder tested in transaction; provider E2E and activation still pending',
    'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_audit)
  RETURNING id INTO v_event_id;
  IF NOT EXISTS (SELECT 1 FROM public.lf_eventos
      WHERE id=v_event_id AND payload->>'checkpoint_pass'='false'
        AND payload->>'transactional_rollback_verified'='true')
      OR (SELECT status FROM programacion.engineering_work_checkpoints c
          JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
          WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
          AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C6') <> 'PENDING'
      OR (SELECT version FROM public.lf_operation_registry
          WHERE operation_code=v_operation) <> 'v0.1'
  THEN RAISE EXCEPTION 'PE10_C6_RECORDER_POSTCOMMIT_EVIDENCE_UNVERIFIED'; END IF;
END $pe10_c6_recorder$;
COMMIT;
