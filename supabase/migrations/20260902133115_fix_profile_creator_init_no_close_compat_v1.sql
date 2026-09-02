create or replace function public.lf_creacion_perfil_lf_no_close_gate(p_execution_id text)
returns jsonb
language plpgsql
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
  where execution_id = p_execution_id
    and operation_code = 'CREACION_PERFIL_LF';
  if v_manifest is null then
    return jsonb_build_object('verdict','BLOCKED_BY_ENFORCEMENT','reason','execution_missing_or_wrong_operation');
  end if;
  select count(*) into v_missing_count
  from public.lf_operation_steps s
  where s.operation_code='CREACION_PERFIL_LF' and s.required is true and s.active is true
    and not exists (select 1 from public.lf_operation_execution_steps es where es.execution_id=p_execution_id and es.step_id=s.step_id);
  select count(*) into v_not_clean_count
  from public.lf_operation_steps s
  left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_id=s.step_id
  where s.operation_code='CREACION_PERFIL_LF' and s.required is true and s.active is true
    and (((s.step_id='init_execution') and coalesce(es.status,'MISSING') <> 'STEP_CLEAN_PASS')
      or ((s.step_id<>'init_execution') and coalesce(es.status,'MISSING') <> 'STEP_PASS_WITH_EVIDENCE'));
  select count(*) into v_restricted_count from public.lf_operation_execution_steps where execution_id=p_execution_id and status in ('PASS_WITH_RESTRICTIONS','STEP_PASS_WITH_RESTRICTIONS');
  select count(*) into v_blocked_count from public.lf_operation_execution_steps where execution_id=p_execution_id and status in ('BLOCKED','STEP_BLOCKED','MISSING');
  select count(*) into v_return_count from public.lf_operation_execution_steps where execution_id=p_execution_id and status in ('RETURN_TO_WORKER','STEP_RETURN_TO_WORKER');
  select count(*) into v_final_bad_pass_count
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id in ('contract_judge','close','report_output')
    and status in ('PASS','OK','DONE','VALIDATED','STEP_PASS_WITH_EVIDENCE')
    and (v_missing_count>0 or v_not_clean_count>0 or v_restricted_count>0 or v_blocked_count>0 or v_return_count>0
      or coalesce(v_manifest->>'closure_allowed','')='false' or coalesce(v_manifest->>'blocked_from_closure','')='true'
      or coalesce(v_manifest->>'security_hold_continues','')='true' or coalesce(v_manifest->>'mini_judge_verdict','')='PASS_WITH_RESTRICTIONS');
  v_closure_allowed_false := coalesce(v_manifest->>'closure_allowed','')='false';
  v_blocked_from_closure_true := coalesce(v_manifest->>'blocked_from_closure','')='true';
  v_security_hold_true := coalesce(v_manifest->>'security_hold_continues','')='true';
  v_block := v_missing_count>0 or v_not_clean_count>0 or v_restricted_count>0 or v_blocked_count>0 or v_return_count>0
    or v_closure_allowed_false or v_blocked_from_closure_true or v_security_hold_true
    or coalesce(v_manifest->>'mini_judge_verdict','')='PASS_WITH_RESTRICTIONS';
  return jsonb_build_object(
    'verdict',case when v_block then 'BLOCKED_BY_ENFORCEMENT' else 'PASS_CLEAN' end,
    'missing_required_steps',v_missing_count,
    'required_steps_not_clean_pass',v_not_clean_count,
    'pass_with_restrictions_count',v_restricted_count,
    'blocked_count',v_blocked_count,
    'return_to_worker_count',v_return_count,
    'closure_allowed_false',v_closure_allowed_false,
    'blocked_from_closure_true',v_blocked_from_closure_true,
    'security_hold_active',v_security_hold_true,
    'final_steps_invalid_pass_count',v_final_bad_pass_count,
    'final_steps_block_required',v_block,
    'init_status_contract','STEP_CLEAN_PASS',
    'post_init_status_contract','STEP_PASS_WITH_EVIDENCE');
end;
$function$;