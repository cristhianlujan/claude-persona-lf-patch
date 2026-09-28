-- LF Input Governance direct Router execution v1
-- Target: LF_SUPABASE_SANDBOX.
-- Canonical Router asset: EDGE_FN_INPUT_GOVERNANCE_AGENT_V1 (CAPABILITY).
-- Governed subject: lf_ops.pantallas code supplied in the request (e.g. B2B-AUTH-001).
-- This migration does not promote production/runtime authority.

begin;

-- Bootstrap provenance. Safe to replay when the bootstrap execution already exists.
insert into public.lf_operation_execution (
  execution_id, operation_code, target_type, target_code, status, manifest,
  created_by_execution_id
)
values (
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF',
  'OPERATION_PROTOCOL_REPAIR',
  'EJECUCION_INPUT_GOVERNANCE_LF',
  'IN_PROGRESS',
  jsonb_build_object(
    'mode','INPUT_GOVERNANCE_OPERATION_BOOTSTRAP',
    'governance_bootstrap',true,
    'bootstrap_operation_code','EJECUCION_INPUT_GOVERNANCE_LF',
    'bootstrap_status_ceiling','SANDBOX_ACTIVE',
    'production_allowed',false,
    'runtime_activation',false,
    'automatic_promotion',false,
    'subject_type','LF_OPS_PANTALLA',
    'canonical_runtime','SUPABASE_EDGE_FUNCTION:input-governance-agent-v1'
  ),
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
)
on conflict (execution_id) do nothing;

-- Make only the canonical Input Governance orchestrator discoverable from natural language.
with aliases as (
  select coalesce(jsonb_agg(x order by x),'[]'::jsonb) value
  from (
    select distinct x
    from (
      select jsonb_array_elements_text(coalesce(a.metadata->'aliases','[]'::jsonb)) x
      from public.lf_activos a
      where a.codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1' and a.archived_at is null
      union all select 'input governance'
      union all select 'input-governance'
      union all select 'input gobernance'
      union all select 'gobernanza de entrada'
      union all select 'gobernanza de inputs'
    ) q
  ) d
), keywords as (
  select coalesce(jsonb_agg(x order by x),'[]'::jsonb) value
  from (
    select distinct x
    from (
      select jsonb_array_elements_text(coalesce(a.metadata->'keywords','[]'::jsonb)) x
      from public.lf_activos a
      where a.codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1' and a.archived_at is null
      union all select 'input governance'
      union all select 'input readiness governance'
      union all select 'governance agent'
    ) q
  ) d
)
update public.lf_activos a
set metadata=jsonb_set(
      jsonb_set(coalesce(a.metadata,'{}'::jsonb),'{aliases}',aliases.value,true),
      '{keywords}',keywords.value,true
    ),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
from aliases,keywords
where a.codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
  and a.archived_at is null;

-- Governed operation bridge.
insert into public.lf_operation_registry (
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  created_by_execution_id,updated_by_execution_id,lifecycle_state_code
)
values (
  'EJECUCION_INPUT_GOVERNANCE_LF','v0.1','SANDBOX_ACTIVE',
  'SUPABASE_STRUCTURED_OPERATION','cristhianlujan/claude-persona-lf-patch',
  jsonb_build_array(
    'public.lf_router_resolve_v1',
    'public.lf_router_action_registry',
    'programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)',
    'programacion.fn_input_governance_worker_spec(integer,text)',
    'programacion.fn_input_governance_execute(integer,text)',
    'programacion.contratos/INPUT_GOVERNANCE_EXECUTION_CONTRACT',
    'SUPABASE_EDGE_FUNCTION:input-governance-agent-v1'
  ),
  'Direct sandbox execution route for the existing Input Governance capability. ACT-0001 resolves EDGE_FN_INPUT_GOVERNANCE_AGENT_V1; a canonical lf_ops.pantallas code is downstream subject input. MANUAL is the direct operator consumer. No production promotion or generic CAPABILITY execution is authorized.',
  'INPUT_GOVERNANCE_OPERATIONS','INPUT_GOVERNANCE_EXECUTION',
  'INPUT_GOVERNANCE_EXECUTION','CAPABILITY',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001',
  'OP_CANDIDATE'
)
on conflict (operation_code) do update set
  version=excluded.version,status=excluded.status,source_model=excluded.source_model,
  source_repo=excluded.source_repo,source_paths=excluded.source_paths,notes=excluded.notes,
  operation_family=excluded.operation_family,operation_domain=excluded.operation_domain,
  operation_type=excluded.operation_type,applies_to_asset_type=excluded.applies_to_asset_type,
  lifecycle_state_code=excluded.lifecycle_state_code,
  updated_by_execution_id=excluded.updated_by_execution_id,updated_at=clock_timestamp();

-- Reuse the live Input Governance authority contract.
insert into public.lf_operation_contracts (
  operation_code,contract_code,contract_path,contract_sha,
  required_before_write,allowed,blocked,required_after_write,status,
  created_by_execution_id,updated_by_execution_id
)
select
  'EJECUCION_INPUT_GOVERNANCE_LF',
  'CONTRACT-EJECUCION-INPUT-GOVERNANCE-LF-v0.1',
  'programacion.contratos/INPUT_GOVERNANCE_EXECUTION_CONTRACT',
  programacion.fn_v09_sha256_jsonb(c.especificacion),
  jsonb_build_array('exact_screen_resolved','consumer_authorized','worker_spec_resolved'),
  jsonb_build_object(
    'sandbox_only',true,
    'asset_code','EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'asset_type','CAPABILITY',
    'subject_type','LF_OPS_PANTALLA',
    'direct_request_consumer','MANUAL',
    'canonical_execution_contract','INPUT_GOVERNANCE_EXECUTION_CONTRACT',
    'entrypoint','programacion.fn_input_governance_execute(integer,text)',
    'worker_spec','programacion.fn_input_governance_worker_spec(integer,text)',
    'runtime_orchestrator','SUPABASE_EDGE_FUNCTION:input-governance-agent-v1',
    'production_authorized',false,
    'generic_capability_execution',false
  ),
  jsonb_build_array(
    'screen_not_found','screen_inactive','screen_ambiguous','consumer_not_allowed',
    'production_promotion','generic_capability_execution','subject_asset_role_inversion'
  ),
  jsonb_build_array('governance_status','output_sha256','screen_code','consumer'),
  'ACTIVE_ENFORCEMENT',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
from programacion.contratos c
where c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
  and c.estado='defined'
order by c.id desc
limit 1
on conflict (operation_code,contract_code) do update set
  contract_path=excluded.contract_path,contract_sha=excluded.contract_sha,
  required_before_write=excluded.required_before_write,allowed=excluded.allowed,
  blocked=excluded.blocked,required_after_write=excluded.required_after_write,
  status=excluded.status,updated_by_execution_id=excluded.updated_by_execution_id,
  updated_at=clock_timestamp();

-- Canonical two-step operation shape.
insert into public.lf_operation_steps (
  operation_code,step_order,execution_order,step_id,required,evidence_required,
  source_path,source_sha,active,created_by_execution_id,updated_by_execution_id
)
values
(
  'EJECUCION_INPUT_GOVERNANCE_LF',10,10,'resolve_screen',true,
  'pantalla_id; screen_code; consumer; worker_spec_sha256',
  'public.lf_operation_step_contracts/EJECUCION_INPUT_GOVERNANCE_LF/resolve_screen',
  null,true,
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
),
(
  'EJECUCION_INPUT_GOVERNANCE_LF',20,20,'execute_input_governance',true,
  'status; pantalla_id; screen_code; consumer; output_sha256',
  'public.lf_operation_step_contracts/EJECUCION_INPUT_GOVERNANCE_LF/execute_input_governance',
  null,true,
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
)
on conflict (operation_code,step_id) do update set
  step_order=excluded.step_order,execution_order=excluded.execution_order,
  required=excluded.required,evidence_required=excluded.evidence_required,
  source_path=excluded.source_path,active=excluded.active,
  updated_by_execution_id=excluded.updated_by_execution_id,updated_at=clock_timestamp();

-- Operation-specific mini judge.
insert into public.lf_operation_judges (
  operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
  created_by_execution_id,updated_by_execution_id
)
values (
  'EJECUCION_INPUT_GOVERNANCE_LF',
  'JUDGE-EJECUCION-INPUT-GOVERNANCE-LF-v0.1',
  'supabase://public/lf_operation_step_contracts/EJECUCION_INPUT_GOVERNANCE_LF',
  null,
  jsonb_build_object('required_evidence_keys_present',true,'canonical_subject_bound',true),
  jsonb_build_object('required_evidence_missing',true,'subject_unresolved_or_ambiguous',true,'consumer_not_allowed',true),
  jsonb_build_object(
    'pass','STEP_PASS_WITH_EVIDENCE',
    'blocked','BLOCKED_STEP_NOT_CLEAN',
    'return','RETURN_TO_ROUTER'
  ),
  'ACTIVE_ENFORCEMENT',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
)
on conflict (operation_code,judge_code) do update set
  judge_path=excluded.judge_path,judge_sha=excluded.judge_sha,
  pass_if=excluded.pass_if,fail_if=excluded.fail_if,result_values=excluded.result_values,
  status=excluded.status,updated_by_execution_id=excluded.updated_by_execution_id,
  updated_at=clock_timestamp();

insert into public.lf_operation_step_contracts (
  operation_code,step_id,step_order,execution_order,contract_code,purpose,
  input_required,resolver_ref,output_payload,pass_condition,block_condition,
  blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,
  status,notes,execution_sql,created_by_execution_id,updated_by_execution_id
)
values
(
  'EJECUCION_INPUT_GOVERNANCE_LF','resolve_screen',10,10,
  'CONTRACT-EJECUCION-INPUT-GOVERNANCE-LF-v0.1',
  'Resolve exactly one active lf_ops.pantallas subject and materialize the current Input Governance worker specification.',
  jsonb_build_array('screen_code','consumer'),
  'lf_ops.pantallas + programacion.fn_input_governance_worker_spec(integer,text)',
  jsonb_build_array('pantalla_id','screen_code','consumer','worker_spec','worker_spec_sha256'),
  jsonb_build_object('exact_screen_resolved',true,'consumer_authorized',true),
  jsonb_build_object('screen_not_found',true,'screen_inactive',true,'screen_ambiguous',true,'consumer_not_allowed',true),
  'BLOCKED_EJECUCION_INPUT_GOVERNANCE_LF_SCREEN_RESOLVE_NOT_CLEAN',
  'JUDGE-EJECUCION-INPUT-GOVERNANCE-LF-v0.1',
  jsonb_build_array('pantalla_id','screen_code','consumer','worker_spec_sha256'),
  'execute_input_governance',null,'ACTIVE_ENFORCEMENT',
  'The screen is the governed subject/input; it is not the ACT-0001 target asset.',
  'programacion.fn_input_governance_worker_spec(integer,text)',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
),
(
  'EJECUCION_INPUT_GOVERNANCE_LF','execute_input_governance',20,20,
  'CONTRACT-EJECUCION-INPUT-GOVERNANCE-LF-v0.1',
  'Execute the existing Input Governance authority for the resolved screen using an authorized consumer.',
  jsonb_build_array('pantalla_id','consumer'),
  'programacion.fn_input_governance_execute(integer,text)',
  jsonb_build_array('status','pantalla_id','screen_code','consumer','output_sha256'),
  jsonb_build_object('canonical_execution_contract_resolved',true),
  jsonb_build_object('contract_unresolvable',true,'screen_invalid',true,'consumer_not_allowed',true,'freshness_gate_failed',true),
  'BLOCKED_EJECUCION_INPUT_GOVERNANCE_LF_EXECUTION_NOT_CLEAN',
  'JUDGE-EJECUCION-INPUT-GOVERNANCE-LF-v0.1',
  jsonb_build_array('status','pantalla_id','screen_code','consumer','output_sha256'),
  null,null,'ACTIVE_ENFORCEMENT',
  'Direct operator requests use MANUAL; the existing Input Governance contract remains the execution authority.',
  'programacion.fn_input_governance_execute(integer,text)',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
)
on conflict (operation_code,step_id) do update set
  step_order=excluded.step_order,execution_order=excluded.execution_order,
  contract_code=excluded.contract_code,purpose=excluded.purpose,
  input_required=excluded.input_required,resolver_ref=excluded.resolver_ref,
  output_payload=excluded.output_payload,pass_condition=excluded.pass_condition,
  block_condition=excluded.block_condition,blocking_code=excluded.blocking_code,
  mini_judge_code=excluded.mini_judge_code,
  required_evidence_keys=excluded.required_evidence_keys,
  next_if_pass=excluded.next_if_pass,next_if_blocked=excluded.next_if_blocked,
  status=excluded.status,notes=excluded.notes,execution_sql=excluded.execution_sql,
  updated_by_execution_id=excluded.updated_by_execution_id,updated_at=clock_timestamp();

insert into public.lf_operation_step_judge_bindings (
  operation_code,step_order,step_id,judge_code,
  clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
)
values
(
  'EJECUCION_INPUT_GOVERNANCE_LF',10,'resolve_screen',
  'JUDGE-EJECUCION-INPUT-GOVERNANCE-LF-v0.1',
  'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',
  jsonb_build_array('pantalla_id','screen_code','consumer','worker_spec_sha256'),
  'ACTIVE_ENFORCEMENT',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
),
(
  'EJECUCION_INPUT_GOVERNANCE_LF',20,'execute_input_governance',
  'JUDGE-EJECUCION-INPUT-GOVERNANCE-LF-v0.1',
  'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',
  jsonb_build_array('status','pantalla_id','screen_code','consumer','output_sha256'),
  'ACTIVE_ENFORCEMENT',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
)
on conflict (operation_code,step_id,judge_code) do update set
  step_order=excluded.step_order,clean_result_value=excluded.clean_result_value,
  blocked_result_value=excluded.blocked_result_value,
  return_result_value=excluded.return_result_value,
  required_evidence_keys=excluded.required_evidence_keys,status=excluded.status,
  updated_by_execution_id=excluded.updated_by_execution_id,updated_at=clock_timestamp();

-- Narrow Router mapping: only the explicit Input Governance action.
insert into public.lf_router_action_registry (
  asset_type,action_code,operation_code,operation_resolution,
  requires_existing_target,requires_missing_target,write_allowed,status,notes,
  created_by_execution_id,updated_by_execution_id
)
values (
  'CAPABILITY','INPUT_GOVERNANCE_EXECUTION','EJECUCION_INPUT_GOVERNANCE_LF','STATIC',
  true,false,false,'ACTIVE',
  'Direct execution of EDGE_FN_INPUT_GOVERNANCE_AGENT_V1 only. The screen is downstream governed subject input. This does not authorize generic CAPABILITY execution or production promotion.',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001',
  'EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
)
on conflict (asset_type,action_code) do update set
  operation_code=excluded.operation_code,operation_resolution=excluded.operation_resolution,
  requires_existing_target=excluded.requires_existing_target,
  requires_missing_target=excluded.requires_missing_target,
  write_allowed=excluded.write_allowed,status=excluded.status,notes=excluded.notes,
  updated_by_execution_id=excluded.updated_by_execution_id,updated_at=clock_timestamp();

-- ACT-0001 source patch. Fail closed on source drift.
do $router_patch$
declare
  v_def text;
  v_old text := $old$elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(ejecuta|ejecutar|corre|correr|continua|continuar|retoma|retomar)( |$)' then v_action:='STRATEGY_EXECUTION';$old$;
  v_new text := $new$elsif v_type_hint='CAPABILITY'
      and v_asset_found
      and v_asset.codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and v_req ~ '(^| )(ejecuta|ejecutar|corre|correr|realiza|realizar)( |$)'
      then v_action:='INPUT_GOVERNANCE_EXECUTION';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(ejecuta|ejecutar|corre|correr|continua|continuar|retoma|retomar)( |$)' then v_action:='STRATEGY_EXECUTION';$new$;
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)
    into v_def;

  if position(v_new in v_def)>0 then
    return;
  end if;
  if position(v_old in v_def)=0 then
    raise exception 'LF_INPUT_GOVERNANCE_ROUTER_ACTION_SOURCE_DRIFT';
  end if;

  v_def:=replace(v_def,v_old,v_new);
  execute v_def;

  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)
    into v_def;
  if position(v_new in v_def)=0 then
    raise exception 'LF_INPUT_GOVERNANCE_ROUTER_ACTION_PATCH_FAILED';
  end if;
end;
$router_patch$;

-- Postconditions: exact natural-language request must resolve the Input Governance asset/operation.
do $verify$
declare
  v jsonb;
begin
  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and archived_at is null
      and metadata->'aliases' ? 'input governance'
  ) then
    raise exception 'LF_INPUT_GOVERNANCE_ALIAS_NOT_MATERIALIZED';
  end if;

  if not exists (
    select 1 from public.lf_router_action_registry
    where asset_type='CAPABILITY'
      and action_code='INPUT_GOVERNANCE_EXECUTION'
      and operation_code='EJECUCION_INPUT_GOVERNANCE_LF'
      and status='ACTIVE'
  ) then
    raise exception 'LF_INPUT_GOVERNANCE_ROUTER_BINDING_NOT_ACTIVE';
  end if;

  v:=public.lf_router_resolve_v1(
    'ejecuta input governance para inicio de sesion del b2b B2B-AUTH-001',
    null,null,null,'ROUTER'
  );

  if v->>'asset_type' is distinct from 'CAPABILITY'
     or v->>'action_code' is distinct from 'INPUT_GOVERNANCE_EXECUTION'
     or v->>'operation_code' is distinct from 'EJECUCION_INPUT_GOVERNANCE_LF'
     or v#>>'{asset,codigo_activo}' is distinct from 'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
     or v->>'status' not in ('READY_TO_EXECUTE','INPUT_GOVERNANCE_REQUIRED','BLOCKED') then
    raise exception 'LF_INPUT_GOVERNANCE_ROUTER_POSTCONDITION_FAILED:%',v;
  end if;
end;
$verify$;

update public.lf_operation_execution
set status='COMPLETED',
    completed_at=clock_timestamp(),
    updated_at=clock_timestamp(),
    checkpoint_payload=jsonb_build_object(
      'result','INPUT_GOVERNANCE_ROUTER_EXECUTION_ROUTE_MATERIALIZED',
      'operation_code','EJECUCION_INPUT_GOVERNANCE_LF',
      'asset_code','EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
      'action_code','INPUT_GOVERNANCE_EXECUTION',
      'production_allowed',false
    ),
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
where execution_id='EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001'
  and status='IN_PROGRESS';

comment on function public.lf_router_resolve_v1(text,text,text,text,text) is
  'ACT-0001 canonical Router. Explicit execution of EDGE_FN_INPUT_GOVERNANCE_AGENT_V1 routes through INPUT_GOVERNANCE_EXECUTION -> EJECUCION_INPUT_GOVERNANCE_LF. The lf_ops.pantallas code remains downstream Input Governance subject, not Router target asset.';

commit;
