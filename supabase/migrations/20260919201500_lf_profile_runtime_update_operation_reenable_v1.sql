do $pre$
declare c int;
begin
  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and lifecycle_state_code='OP_CANDIDATE'
      and status='CANDIDATO_READ_ONLY'
  ) then raise exception 'RUNTIME_UPDATE_PRE_REGISTRY_STATE_DRIFT'; end if;

  select count(*) into c from public.lf_operation_steps
   where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF';
  if c<>14 then raise exception 'RUNTIME_UPDATE_PRE_STEP_COUNT:%',c; end if;

  select count(*) into c from public.lf_operation_steps
   where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and active;
  if c<>0 then raise exception 'RUNTIME_UPDATE_PRE_ACTIVE_STEPS:%',c; end if;

  select count(*) into c from public.lf_operation_step_contracts
   where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';
  if c<>14 then raise exception 'RUNTIME_UPDATE_PRE_ACTIVE_CONTRACTS:%',c; end if;

  select count(*) into c from public.lf_operation_step_judge_bindings
   where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';
  if c<>0 then raise exception 'RUNTIME_UPDATE_PRE_BINDINGS:%',c; end if;

  select count(*) into c from public.lf_operation_execution
   where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
     and status='IN_PROGRESS'
     and execution_id<>'EXEC-RUNTIME-UPDATE-REENABLE-20260919-001';
  if c<>0 then raise exception 'RUNTIME_UPDATE_OPEN_EXECUTIONS:%',c; end if;

  if not exists (
    select 1 from public.lf_router_action_registry
    where asset_type='OPERATION_CODE' and action_code='RUNTIME_UPDATE'
      and operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and status='ACTIVE' and write_allowed=true
  ) then raise exception 'RUNTIME_UPDATE_ROUTE_BINDING_MISSING'; end if;
end $pre$;

-- Candidate operations must not remain Router-active before exact-revision
-- qualification. Preserve the canonical binding but make it non-routable
-- until governed promotion completes.
update public.lf_router_action_registry
set status='CANDIDATO_READ_ONLY',
    updated_at=now(),
    updated_by_execution_id='EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'
where asset_type='OPERATION_CODE'
  and action_code='RUNTIME_UPDATE'
  and operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
  and status='ACTIVE';

update public.lf_operation_step_contracts
set resolver_ref = case
      when step_id='router' then resolver_ref
      else 'NATIVE_MODEL_RUNTIME_WITH_SUPABASE_CONTEXT'
    end,
    required_evidence_keys = case
      when step_id='pre_write_execution_binding_gate'
      then (
        select jsonb_agg(distinct x order by x)
        from jsonb_array_elements_text(
          required_evidence_keys || '["bound_revision","execution_bound_to_target_before_change"]'::jsonb
        ) x
      )
      else required_evidence_keys
    end,
    updated_at=now(),
    updated_by_execution_id='EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'
where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
  and status='ACTIVE_ENFORCEMENT';

create or replace function public.lf_runtime_update_trust_validation_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_payload jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  f text;
  hard jsonb := '[]'::jsonb;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_step_id,'')),'') is null
     or p_evidence_payload is null
     or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object('valid',false,'code','RUNTIME_UPDATE_TRUST_INPUT_INVALID',
      'details','{}'::jsonb,'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  select * into e from public.lf_operation_execution
   where execution_id=p_execution_id;

  if not found
     or e.operation_code<>'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
     or e.target_type<>'OPERATION_CODE'
     or e.target_code<>'EJECUCION_PERFIL_LF'
     or e.status<>'IN_PROGRESS' then
    return jsonb_build_object('valid',false,'code','RUNTIME_UPDATE_EXECUTION_BINDING_INVALID',
      'details',jsonb_build_object('execution_id',p_execution_id),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  if p_step_id='runtime_resolve' and (
       p_evidence_payload->>'operation_code' is distinct from 'EJECUCION_PERFIL_LF'
       or coalesce((p_evidence_payload->>'exact_runtime_target_resolved')::boolean,false) is not true
       or nullif(btrim(coalesce(p_evidence_payload->>'runtime_path','')),'') is null
     ) then hard:=hard||jsonb_build_array('runtime_target_not_exact');
  elsif p_step_id='baseline_read' and coalesce(p_evidence_payload->>'baseline_revision','') !~ '^[0-9a-f]{40}$'
     then hard:=hard||jsonb_build_array('baseline_revision_invalid');
  elsif p_step_id='pre_write_execution_binding_gate' and (
       p_evidence_payload->>'execution_id' is distinct from p_execution_id
       or p_evidence_payload->>'target_code' is distinct from 'EJECUCION_PERFIL_LF'
       or p_evidence_payload->>'target_path' is distinct from coalesce(e.target_path,'')
       or coalesce((p_evidence_payload->>'pre_write_gate_passed')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'execution_bound_to_target_before_change')::boolean,false) is not true
       or coalesce(p_evidence_payload->>'bound_revision','') !~ '^[0-9a-f]{40}$'
     ) then hard:=hard||jsonb_build_array('prewrite_binding_invalid');
  elsif p_step_id='github_write' then
    if coalesce((p_evidence_payload->>'identity_preserved')::boolean,false) is not true
       or coalesce(p_evidence_payload->>'commit_sha','') !~ '^[0-9a-f]{40}$'
       or jsonb_typeof(p_evidence_payload->'written_files')<>'array'
       or jsonb_array_length(p_evidence_payload->'written_files')=0
       or nullif(btrim(coalesce(p_evidence_payload->>'branch','')),'') is null
    then hard:=hard||jsonb_build_array('github_write_evidence_invalid');
    else
      for f in select jsonb_array_elements_text(p_evidence_payload->'written_files') loop
        if f like 'profiles/%' or f like 'adapters/%' then
          hard:=hard||jsonb_build_array('forbidden_authority_file_change');
        end if;
      end loop;
    end if;
  elsif p_step_id='github_readback' and (
       coalesce(p_evidence_payload->>'exact_head','') !~ '^[0-9a-f]{40}$'
       or coalesce((p_evidence_payload->>'sha_match')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'identity_preserved')::boolean,false) is not true
     ) then hard:=hard||jsonb_build_array('github_readback_not_exact');
  elsif p_step_id='close' and (
       coalesce((p_evidence_payload->>'all_required_steps_clean')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'runtime_unchanged')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'no_auto_promotion')::boolean,false) is not true
       or jsonb_typeof(p_evidence_payload->'open_blockers')<>'array'
       or jsonb_array_length(p_evidence_payload->'open_blockers')<>0
     ) then hard:=hard||jsonb_build_array('close_contract_not_clean');
  elsif p_step_id='report_output' and (
       coalesce(p_evidence_payload->>'exact_head','') !~ '^[0-9a-f]{40}$'
       or jsonb_typeof(p_evidence_payload->'evidence_refs')<>'array'
       or jsonb_array_length(p_evidence_payload->'evidence_refs')=0
       or jsonb_typeof(p_evidence_payload->'open_blockers')<>'array'
       or jsonb_array_length(p_evidence_payload->'open_blockers')<>0
       or nullif(btrim(coalesce(p_evidence_payload->>'next_gate','')),'') is null
     ) then hard:=hard||jsonb_build_array('report_output_not_clean');
  end if;

  if jsonb_array_length(hard)>0 then
    return jsonb_build_object('valid',false,'code','RUNTIME_UPDATE_SERVER_VALIDATION_FAILED',
      'details',jsonb_build_object('step_id',p_step_id,'hard_fails',hard),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  return jsonb_build_object('valid',true,'code','RUNTIME_UPDATE_SERVER_VALIDATED',
    'details',jsonb_build_object('step_id',p_step_id,'execution_id',p_execution_id),
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb);
end
$fn$;

create or replace function public.lf_record_runtime_update_operation_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $fn$
declare v_trust jsonb;
begin
  v_trust:=public.lf_runtime_update_trust_validation_v1(
    p_execution_id,p_step_id,p_evidence_payload
  );
  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF','OPERATION_CODE',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    v_trust,true,'lf_record_runtime_update_operation_step_v1'
  );
end
$fn$;

create or replace function public.lf_runtime_update_begin_v1(
  p_execution_id text,
  p_idempotency_key text,
  p_request_sha256 text,
  p_actor_execution_id text,
  p_target_repo text,
  p_target_path text,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $fn$
declare
  r jsonb;
  b public.lf_operation_step_judge_bindings%rowtype;
begin
  if nullif(btrim(coalesce(p_target_repo,'')),'') is null
     or nullif(btrim(coalesce(p_target_path,'')),'') is null then
    raise exception 'RUNTIME_UPDATE_TARGET_REQUIRED';
  end if;
  r:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF',
    'OPERATION_CODE','EJECUCION_PERFIL_LF',
    p_idempotency_key,p_request_sha256,p_actor_execution_id,
    p_target_repo,p_target_path,
    coalesce(p_manifest,'{}'::jsonb)||jsonb_build_object(
      'runtime_update_governed',true,
      'target_operation','EJECUCION_PERFIL_LF',
      'automatic_promotion',false
    )
  );
  select * into b from public.lf_operation_step_judge_bindings
   where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
     and step_id='init_execution' and status='ACTIVE_ENFORCEMENT';

  if r->>'result'='RESERVED_NEW_EXECUTION' then
    insert into public.lf_operation_execution_steps(
      execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id
    ) values(
      r->>'execution_id',0,'init_execution',b.clean_result_value,
      'supabase://public.lf_operation_execution/'||(r->>'execution_id'),
      jsonb_build_object(
        'execution_id_created',true,
        'target_code','EJECUCION_PERFIL_LF',
        'target_path',p_target_path,
        'step_result',b.clean_result_value,
        'blocking_codes','[]'::jsonb,
        'mini_judge_code',b.judge_code,
        'mini_judge_result',b.clean_result_value,
        'recorded_by_rpc','lf_runtime_update_begin_v1'
      ),
      'Runtime update init materialized after canonical idempotent reserve.',
      p_actor_execution_id
    );
  end if;
  return r||jsonb_build_object('init_materialized',true);
end
$fn$;

revoke all on function public.lf_runtime_update_trust_validation_v1(text,text,jsonb) from public,anon,authenticated;
revoke all on function public.lf_record_runtime_update_operation_step_v1(text,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.lf_runtime_update_begin_v1(text,text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.lf_runtime_update_trust_validation_v1(text,text,jsonb) to service_role;
grant execute on function public.lf_record_runtime_update_operation_step_v1(text,text,text,jsonb,text) to service_role;
grant execute on function public.lf_runtime_update_begin_v1(text,text,text,text,text,text,jsonb) to service_role;

do $judges$
declare s record; jc text;
begin
  for s in
    select st.step_order,st.step_id,c.required_evidence_keys
    from public.lf_operation_steps st
    join public.lf_operation_step_contracts c
      on c.operation_code=st.operation_code and c.step_id=st.step_id
     and c.step_order=st.step_order and c.status='ACTIVE_ENFORCEMENT'
    where st.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    order by st.step_order
  loop
    jc:='MINI_JUDGE_RUNTIME_UPDATE_'||
       upper(regexp_replace(s.step_id,'[^a-zA-Z0-9]+','_','g'))||'_V1';

    insert into public.lf_operation_judges(
      operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
      created_by_execution_id,updated_by_execution_id
    ) values(
      'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF',jc,
      'supabase://public/lf_operation_judges/ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF/'||jc,
      null,'["server_validated"]'::jsonb,'["server_validation_failed"]'::jsonb,
      jsonb_build_array('STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER'),
      'ACTIVE_ENFORCEMENT','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'
    );

    insert into public.lf_operation_step_judge_bindings(
      operation_code,step_order,step_id,judge_code,
      clean_result_value,blocked_result_value,return_result_value,
      required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
    ) values(
      'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF',s.step_order,s.step_id,jc,
      'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',
      s.required_evidence_keys,'ACTIVE_ENFORCEMENT',
      'EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'
    );

    update public.lf_operation_step_contracts
       set mini_judge_code=jc,updated_at=now(),
           updated_by_execution_id='EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'
     where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
       and step_order=s.step_order and step_id=s.step_id
       and status='ACTIVE_ENFORCEMENT';
  end loop;
end $judges$;

update public.lf_operation_steps
set active=true,updated_at=now(),
    updated_by_execution_id='EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'
where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF';

insert into public.lf_test_suites(
  suite_code,module_code,name,version,status,execution_policy,metadata,
  created_by_execution_id,updated_by_execution_id
) values(
  'TS-RUNTIME-OP-UPDATE-V1','PROFILE_RUNTIME_GOVERNANCE',
  'Profile Runtime Update Operation Qualification Matrix','v1','CANDIDATO',
  '{"exact_revision":true,"deterministic_first":true,"false_pass_tolerance":0}'::jsonb,
  '{"matrix_family":"OPERATION_QUALIFICATION","operation_code":"ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF","prepromotion":true}'::jsonb,
  'EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'
);

insert into public.lf_test_requirement_bindings(
  binding_code,subject_type,subject_code,suite_code,required,min_pass_rate,false_pass_tolerance,
  independent_review_required,rollback_required,currentness_mode,activation_condition,effective_from,status,
  created_by_execution_id,updated_by_execution_id
) values(
  'BIND-OP-RUNTIME-UPDATE-V1','OPERATION','ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF',
  'TS-RUNTIME-OP-UPDATE-V1',true,1.0,0,false,true,'EXACT_REVISION',
  '{"type":"ALWAYS","phase":"PREPROMOTION","router_not_required_pre_promotion":true}'::jsonb,
  now(),'ACTIVE','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'
);

insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,
  created_by_execution_id,updated_by_execution_id
) values
('TS-RUNTIME-OP-UPDATE-V1','RU01',10,'Operation lifecycle state is catalog-valid','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"OP_REGISTRY_STATE_VALID"}','{"passed":true}','{}','CANDIDATO','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'),
('TS-RUNTIME-OP-UPDATE-V1','RU02',20,'Active enforcement contract exists','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"ACTIVE_CONTRACT_PRESENT"}','{"passed":true}','{}','CANDIDATO','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'),
('TS-RUNTIME-OP-UPDATE-V1','RU03',30,'Active step contracts exist','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"ACTIVE_STEPS_PRESENT"}','{"passed":true}','{}','CANDIDATO','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'),
('TS-RUNTIME-OP-UPDATE-V1','RU04',40,'All active steps have active judges','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"ALL_ACTIVE_STEPS_JUDGED"}','{"passed":true}','{}','CANDIDATO','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'),
('TS-RUNTIME-OP-UPDATE-V1','RU05',50,'Pre-write execution binding step exists','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"STEP_PRESENT","step_id":"pre_write_execution_binding_gate"}','{"passed":true}','{}','CANDIDATO','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'),
('TS-RUNTIME-OP-UPDATE-V1','RU06',60,'GitHub write step exists','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"STEP_PRESENT","step_id":"github_write"}','{"passed":true}','{}','CANDIDATO','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'),
('TS-RUNTIME-OP-UPDATE-V1','RU07',70,'GitHub readback step exists','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"STEP_PRESENT","step_id":"github_readback"}','{"passed":true}','{}','CANDIDATO','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'),
('TS-RUNTIME-OP-UPDATE-V1','RU08',80,'Qualification binding is registered','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"QUALIFICATION_BINDING_PRESENT"}','{"passed":true}','{}','CANDIDATO','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'),
('TS-RUNTIME-OP-UPDATE-V1','RU09',90,'Automatic production promotion remains forbidden','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"production_promotion","expected":false}','{"passed":true}','{}','CANDIDATO','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'),
('TS-RUNTIME-OP-UPDATE-V1','RU10',100,'Profile files remain outside runtime update scope','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"profile_files_unchanged","expected":true}','{"passed":true}','{}','CANDIDATO','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'),
('TS-RUNTIME-OP-UPDATE-V1','RU11',110,'Runtime adapter composition stays in one model call','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"same_llm_call","expected":true}','{"passed":true}','{}','CANDIDATO','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001','EXEC-RUNTIME-UPDATE-REENABLE-20260919-001');

update public.lf_operation_registry
set notes=regexp_replace(coalesce(notes,''),' \| 2026-09-03 Q4 safety neutralization:.*$','')||
  ' | 2026-09-19 repair: dedicated 14/14 per-step judges, server-bound runtime-update recorder, exact prewrite revision binding, qualification suite materialized; remains OP_CANDIDATE until qualification + governed promotion.',
    updated_at=now(),
    updated_by_execution_id='EXEC-RUNTIME-UPDATE-REENABLE-20260919-001'
where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF';

do $post$
declare c int;
begin
  select count(*) into c from public.lf_operation_steps
   where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and active;
  if c<>14 then raise exception 'RUNTIME_UPDATE_POST_ACTIVE_STEPS:%',c; end if;

  select count(*) into c from public.lf_operation_step_judge_bindings
   where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';
  if c<>14 then raise exception 'RUNTIME_UPDATE_POST_BINDINGS:%',c; end if;

  select count(distinct judge_code) into c from public.lf_operation_step_judge_bindings
   where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';
  if c<>14 then raise exception 'RUNTIME_UPDATE_POST_DISTINCT_JUDGES:%',c; end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and step_id='pre_write_execution_binding_gate'
      and required_evidence_keys @> '["bound_revision","execution_bound_to_target_before_change"]'::jsonb
  ) then raise exception 'RUNTIME_UPDATE_POST_PREWRITE_KEYS_MISSING'; end if;

  if to_regprocedure('public.lf_runtime_update_begin_v1(text,text,text,text,text,text,jsonb)') is null
     or to_regprocedure('public.lf_record_runtime_update_operation_step_v1(text,text,text,jsonb,text)') is null
     or to_regprocedure('public.lf_runtime_update_trust_validation_v1(text,text,jsonb)') is null
  then raise exception 'RUNTIME_UPDATE_POST_FUNCTIONS_MISSING'; end if;

  if not exists (
    select 1 from public.lf_test_requirement_bindings
    where binding_code='BIND-OP-RUNTIME-UPDATE-V1'
      and subject_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and status='ACTIVE' and required
  ) then raise exception 'RUNTIME_UPDATE_POST_QUALIFICATION_BINDING_MISSING'; end if;
end $post$;
