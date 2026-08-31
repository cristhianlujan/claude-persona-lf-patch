-- GOV-JUDGE-SHAPE-001
create or replace function public.lf_prod_enforcement_step_gate_v01()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_operation_code text;
  v_manifest jsonb;
  v_canonical_exists boolean;
  v_max_step integer;
  v_missing_required integer;
  v_restricted_steps integer;
  v_binding public.lf_operation_step_judge_bindings%rowtype;
  v_has_binding boolean := false;
  v_judge_result_values jsonb;
  v_pass_if jsonb;
  v_fail_if jsonb;
  v_result_values_norm jsonb := '[]'::jsonb;
  v_pass_if_norm jsonb := '[]'::jsonb;
  v_fail_if_norm jsonb := '[]'::jsonb;
  v_required_key text;
  v_missing_keys text[] := array[]::text[];
  v_assertions jsonb;
  v_hard_fails jsonb;
  v_blocking_findings jsonb;
  v_return_reasons jsonb;
  v_pass_item text;
  v_fail_item text;
  v_missing_pass_items text[] := array[]::text[];
  v_triggered_fail_items text[] := array[]::text[];
  v_derived_result text;
begin
  select e.operation_code, e.manifest into v_operation_code, v_manifest
  from public.lf_operation_execution e where e.execution_id = new.execution_id;
  if v_operation_code is null then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: execution_id % does not exist for step gate', new.execution_id using errcode = 'P0001'; end if;
  select max(s.step_order) into v_max_step from public.lf_operation_steps s where s.operation_code = v_operation_code and s.active is true;
  if v_max_step is null then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: operation_code % has no active canonical steps', v_operation_code using errcode = 'P0001'; end if;
  if new.step_order > v_max_step then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: step_order % exceeds canonical max % for operation %', new.step_order, v_max_step, v_operation_code using errcode = 'P0001'; end if;
  select exists (select 1 from public.lf_operation_steps s where s.operation_code=v_operation_code and s.step_order=new.step_order and s.step_id=new.step_id and s.active is true) into v_canonical_exists;
  if not v_canonical_exists then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: non-canonical step %.% for operation %', new.step_order,new.step_id,v_operation_code using errcode='P0001'; end if;
  if upper(coalesce(new.status,'')) in ('PASS','OK','DONE','VALIDATED','PASS_WITH_RESTRICTIONS') then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: symbolic step status % is not allowed',new.status using errcode='P0001'; end if;
  select * into v_binding from public.lf_operation_step_judge_bindings b where b.operation_code=v_operation_code and b.step_order=new.step_order and b.step_id=new.step_id and b.status='ACTIVE_ENFORCEMENT';
  v_has_binding := found;
  if v_has_binding then
    select j.result_values,j.pass_if,j.fail_if into v_judge_result_values,v_pass_if,v_fail_if from public.lf_operation_judges j where j.operation_code=v_binding.operation_code and j.judge_code=v_binding.judge_code and j.status='ACTIVE_ENFORCEMENT';
    if v_judge_result_values is null then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: active judge % missing for operation %',v_binding.judge_code,v_operation_code using errcode='P0001'; end if;
    if jsonb_typeof(v_judge_result_values)='array' then v_result_values_norm:=v_judge_result_values;
    elsif jsonb_typeof(v_judge_result_values)='object' then select coalesce(jsonb_agg(value order by key),'[]'::jsonb) into v_result_values_norm from jsonb_each_text(v_judge_result_values) where value is not null and btrim(value)<>'';
    else raise exception 'LF_PROD_ENFORCEMENT_BLOCK: unsupported result_values JSONB shape % for judge %',jsonb_typeof(v_judge_result_values),v_binding.judge_code using errcode='P0001'; end if;
    if jsonb_typeof(v_pass_if)='array' then v_pass_if_norm:=v_pass_if;
    elsif jsonb_typeof(v_pass_if)='object' and jsonb_typeof(v_pass_if->'pass_if')='array' then v_pass_if_norm:=v_pass_if->'pass_if';
    elsif jsonb_typeof(v_pass_if)='object' then select coalesce(jsonb_agg(key order by key),'[]'::jsonb) into v_pass_if_norm from jsonb_each(v_pass_if) where value='true'::jsonb;
    else raise exception 'LF_PROD_ENFORCEMENT_BLOCK: unsupported pass_if JSONB shape % for judge %',jsonb_typeof(v_pass_if),v_binding.judge_code using errcode='P0001'; end if;
    if jsonb_typeof(v_fail_if)='array' then v_fail_if_norm:=v_fail_if;
    elsif jsonb_typeof(v_fail_if)='object' and jsonb_typeof(v_fail_if->'fail_if')='array' then v_fail_if_norm:=v_fail_if->'fail_if';
    elsif jsonb_typeof(v_fail_if)='object' then select coalesce(jsonb_agg(key order by key),'[]'::jsonb) into v_fail_if_norm from jsonb_each(v_fail_if) where value='true'::jsonb;
    else raise exception 'LF_PROD_ENFORCEMENT_BLOCK: unsupported fail_if JSONB shape % for judge %',jsonb_typeof(v_fail_if),v_binding.judge_code using errcode='P0001'; end if;
    if not exists (select 1 from jsonb_array_elements_text(v_result_values_norm) rv where rv=new.status) then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: step status % is not in judge result_values for %.%',new.status,v_operation_code,new.step_id using errcode='P0001'; end if;
    if new.evidence_payload is null or jsonb_typeof(new.evidence_payload)<>'object' then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: bound step requires evidence_payload object for judge-derived result' using errcode='P0001'; end if;
    for v_required_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop if not (new.evidence_payload ? v_required_key) then v_missing_keys:=array_append(v_missing_keys,v_required_key); end if; end loop;
    if array_length(v_missing_keys,1) is not null then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: evidence_payload missing required judge keys % for %.%',array_to_string(v_missing_keys,','),v_operation_code,new.step_id using errcode='P0001'; end if;
    v_assertions:=coalesce(new.evidence_payload->'assertions_checked','[]'::jsonb); v_hard_fails:=coalesce(new.evidence_payload->'hard_fails_checked','[]'::jsonb); v_blocking_findings:=coalesce(new.evidence_payload->'blocking_findings','[]'::jsonb); v_return_reasons:=coalesce(new.evidence_payload->'return_to_worker_reasons','[]'::jsonb);
    if jsonb_typeof(v_assertions)<>'array' or jsonb_typeof(v_hard_fails)<>'array' or jsonb_typeof(v_blocking_findings)<>'array' or jsonb_typeof(v_return_reasons)<>'array' then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: judge evidence arrays invalid' using errcode='P0001'; end if;
    if jsonb_array_length(v_return_reasons)>0 then v_derived_result:=v_binding.return_result_value;
    elsif jsonb_array_length(v_blocking_findings)>0 then v_derived_result:=v_binding.blocked_result_value;
    else
      for v_fail_item in select jsonb_array_elements_text(v_fail_if_norm) loop if exists(select 1 from jsonb_array_elements_text(v_hard_fails) hf where hf=v_fail_item) then v_triggered_fail_items:=array_append(v_triggered_fail_items,v_fail_item); end if; end loop;
      if array_length(v_triggered_fail_items,1) is not null then v_derived_result:=v_binding.blocked_result_value;
      else for v_pass_item in select jsonb_array_elements_text(v_pass_if_norm) loop if not exists(select 1 from jsonb_array_elements_text(v_assertions) pa where pa=v_pass_item) then v_missing_pass_items:=array_append(v_missing_pass_items,v_pass_item); end if; end loop;
        if array_length(v_missing_pass_items,1) is not null then v_derived_result:=v_binding.return_result_value; else v_derived_result:=v_binding.clean_result_value; end if;
      end if;
    end if;
    if new.status<>v_derived_result then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: manual status % does not match judge-derived result % for %.%',new.status,v_derived_result,v_operation_code,new.step_id using errcode='P0001'; end if;
    new.evidence_payload:=new.evidence_payload||jsonb_build_object('derived_result',v_derived_result,'derived_by_judge',v_binding.judge_code,'manual_status_accepted_only_if_matches_derived',true,'missing_pass_items',coalesce(to_jsonb(v_missing_pass_items),'[]'::jsonb),'triggered_fail_items',coalesce(to_jsonb(v_triggered_fail_items),'[]'::jsonb),'judge_jsonb_shape_compatibility','ARRAY_OR_OBJECT_V1');
  end if;
  if v_has_binding and new.step_id in ('contract_judge','close','report_output','audit_trail') and upper(coalesce(new.status,'')) in ('READBACK_PASS','CLOSED_WITH_VERIFIED_EVIDENCE','QA_PASS','VERIFIED') then
    if coalesce(v_manifest->>'mini_judge_verdict','')='PASS_WITH_RESTRICTIONS' then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: % cannot pass when manifest mini_judge_verdict=PASS_WITH_RESTRICTIONS',new.step_id using errcode='P0001'; end if;
    if coalesce((v_manifest->>'closure_allowed')::boolean,true) is false then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: % cannot pass when manifest closure_allowed=false',new.step_id using errcode='P0001'; end if;
    if coalesce((v_manifest->>'blocked_from_closure')::boolean,false) is true then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: % cannot pass when manifest blocked_from_closure=true',new.step_id using errcode='P0001'; end if;
    select count(*) into v_missing_required from public.lf_operation_steps s left join public.lf_operation_execution_steps es on es.execution_id=new.execution_id and es.step_order=s.step_order and es.step_id=s.step_id where s.operation_code=v_operation_code and s.active is true and s.required is true and s.step_order<new.step_order and (es.execution_id is null or coalesce(es.status,'MISSING')='MISSING');
    if v_missing_required>0 then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: % cannot pass with % prior required steps missing',new.step_id,v_missing_required using errcode='P0001'; end if;
    select count(*) into v_restricted_steps from public.lf_operation_execution_steps es where es.execution_id=new.execution_id and es.step_order<new.step_order and upper(coalesce(es.status,'')) like '%PASS_WITH_RESTRICTIONS%';
    if v_restricted_steps>0 then raise exception 'LF_PROD_ENFORCEMENT_BLOCK: % cannot pass with % prior PASS_WITH_RESTRICTIONS steps',new.step_id,v_restricted_steps using errcode='P0001'; end if;
  end if;
  return new;
end;
$function$;
comment on function public.lf_prod_enforcement_step_gate_v01() is 'Operation step enforcement. ARRAY_OR_OBJECT_V1 judge JSONB shape compatibility; preserves judge-derived status and fail-closed behavior.';