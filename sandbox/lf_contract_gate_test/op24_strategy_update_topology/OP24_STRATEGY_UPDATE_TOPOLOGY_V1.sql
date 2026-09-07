-- OP24 Strategy Update Topology V1 — candidate-only materializer.
-- Source-first, rollback-tested only. No Router activation. No production authorization.
-- Requires a scope-matched VULNERABILITY_COVERAGE_REPAIR_LF bootstrap execution
-- supplied through current_setting('op24.bootstrap_execution_id').

do $preflight$
declare
  v_exec text := nullif(current_setting('op24.bootstrap_execution_id', true), '');
  v_steps integer;
  v_status text;
begin
  if v_exec is null then
    raise exception 'OP24_STRATEGY_UPDATE_BOOTSTRAP_EXECUTION_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.lf_operation_execution e
    where e.execution_id = v_exec
      and e.operation_code = 'VULNERABILITY_COVERAGE_REPAIR_LF'
      and e.status = 'IN_PROGRESS'
      and coalesce((e.manifest->>'governance_bootstrap')::boolean, false) = true
      and e.manifest->>'bootstrap_operation_code' = 'ACTUALIZACION_ESTRATEGIA_LF'
      and e.manifest->>'bootstrap_status_ceiling' = 'SANDBOX_ACTIVE'
  ) then
    raise exception 'OP24_STRATEGY_UPDATE_BOOTSTRAP_SCOPE_MISMATCH:%', v_exec;
  end if;

  select status into v_status
  from public.lf_operation_registry
  where operation_code = 'ACTUALIZACION_ESTRATEGIA_LF';
  if v_status is distinct from 'CANDIDATO_READ_ONLY' then
    raise exception 'OP24_STRATEGY_UPDATE_OPERATION_STATE_DRIFT:%', coalesce(v_status,'<missing>');
  end if;

  select count(*) into v_steps
  from public.lf_operation_steps
  where operation_code = 'ACTUALIZACION_ESTRATEGIA_LF'
    and active = true
    and required = true;
  if v_steps <> 14 then
    raise exception 'OP24_STRATEGY_UPDATE_REQUIRED_STEP_COUNT_DRIFT:%', v_steps;
  end if;

  if exists(select 1 from public.lf_operation_step_contracts where operation_code='ACTUALIZACION_ESTRATEGIA_LF')
     or exists(select 1 from public.lf_operation_judges where operation_code='ACTUALIZACION_ESTRATEGIA_LF')
     or exists(select 1 from public.lf_operation_step_judge_bindings where operation_code='ACTUALIZACION_ESTRATEGIA_LF') then
    raise exception 'OP24_STRATEGY_UPDATE_TOPOLOGY_ALREADY_MATERIALIZED';
  end if;
end
$preflight$;

with steps as (
  select
    s.*,
    regexp_replace(upper(s.step_id),'[^A-Z0-9]+','_','g') as step_token,
    to_jsonb(regexp_split_to_array(s.evidence_required, '\s*;\s*|\s*,\s*')) as evidence_keys
  from public.lf_operation_steps s
  where s.operation_code='ACTUALIZACION_ESTRATEGIA_LF'
    and s.active=true
    and s.required=true
)
insert into public.lf_operation_judges(
  operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,created_by_execution_id
)
select
  operation_code,
  'JUDGE_STRATEGY_UPDATE_'||step_token||'_V1',
  'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/op24_strategy_update_topology/OP24_STRATEGY_UPDATE_TOPOLOGY_V1.sql#judge/'||step_id,
  'OP24_STRATEGY_UPDATE_'||step_token||'_V1_CANDIDATE',
  jsonb_build_object(
    'step_contract_present',true,
    'required_evidence_keys_present',true,
    'operation_scope','ACTUALIZACION_ESTRATEGIA_LF',
    'target_scope_match',true
  ),
  jsonb_build_object(
    'step_contract_missing',true,
    'required_evidence_missing',true,
    'wrong_operation_or_target',true
  ),
  jsonb_build_object(
    'pass','STEP_CLEAN_PASS',
    'return','RETURN_TO_WORKER_FOR_SELF_REPAIR',
    'blocked','BLOCK_STRATEGY_UPDATE_'||step_token||'_EVIDENCE_MISSING'
  ),
  'ACTIVE_ENFORCEMENT',
  current_setting('op24.bootstrap_execution_id', true)
from steps;

with steps as (
  select
    s.*,
    regexp_replace(upper(s.step_id),'[^A-Z0-9]+','_','g') as step_token,
    to_jsonb(regexp_split_to_array(s.evidence_required, '\s*;\s*|\s*,\s*')) as evidence_keys,
    lead(s.step_id) over(order by coalesce(s.execution_order,s.step_order),s.step_order) as next_step
  from public.lf_operation_steps s
  where s.operation_code='ACTUALIZACION_ESTRATEGIA_LF'
    and s.active=true
    and s.required=true
)
insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,
  output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,
  next_if_pass,next_if_blocked,status,notes,created_by_execution_id
)
select
  operation_code,
  step_id,
  step_order,
  coalesce(execution_order,step_order),
  'CONTRACT-ACTUALIZACION-ESTRATEGIA-LF-STEP-v0.1',
  'Governed Strategy Update step '||step_id||': require exact declared evidence before transition.',
  case when step_id='init_execution' then '[]'::jsonb else jsonb_build_array('prior_step_readback') end,
  'GPT_RUNTIME_WITH_SUPABASE_CONTEXT',
  evidence_keys,
  jsonb_build_object(
    'all_required_evidence_keys_present',true,
    'operation_code','ACTUALIZACION_ESTRATEGIA_LF',
    'step_id',step_id
  ),
  jsonb_build_object(
    'missing_required_evidence',true,
    'wrong_operation_or_target',true
  ),
  'BLOCK_STRATEGY_UPDATE_'||step_token||'_EVIDENCE_MISSING',
  'JUDGE_STRATEGY_UPDATE_'||step_token||'_V1',
  evidence_keys,
  next_step,
  case when step_id='report_output' then null else 'report_output' end,
  'ACTIVE_ENFORCEMENT',
  'OP24 P4 candidate topology. Structural enforcement only; no runtime/production activation.',
  current_setting('op24.bootstrap_execution_id', true)
from steps;

with steps as (
  select
    s.*,
    regexp_replace(upper(s.step_id),'[^A-Z0-9]+','_','g') as step_token,
    to_jsonb(regexp_split_to_array(s.evidence_required, '\s*;\s*|\s*,\s*')) as evidence_keys
  from public.lf_operation_steps s
  where s.operation_code='ACTUALIZACION_ESTRATEGIA_LF'
    and s.active=true
    and s.required=true
)
insert into public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id
)
select
  operation_code,
  step_order,
  step_id,
  'JUDGE_STRATEGY_UPDATE_'||step_token||'_V1',
  'STEP_CLEAN_PASS',
  'BLOCK_STRATEGY_UPDATE_'||step_token||'_EVIDENCE_MISSING',
  'RETURN_TO_WORKER_FOR_SELF_REPAIR',
  evidence_keys,
  'ACTIVE_ENFORCEMENT',
  current_setting('op24.bootstrap_execution_id', true)
from steps;
