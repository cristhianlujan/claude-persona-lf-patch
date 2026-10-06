
-- 1) Plan-level inherited contract: every unit knows how transversal execution is represented.
update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  unit_metadata,
  '{plan_inherited_execution_policies_v1}',
  coalesce(unit_metadata->'plan_inherited_execution_policies_v1','{}'::jsonb)
  || jsonb_build_object(
    'TRANSVERSAL_EXECUTION_DECLARATION_V1',
    jsonb_build_object(
      'authority','PLAN_UNIT_METADATA',
      'inheritance','PLAN_LEVEL',
      'storage_path','unit_metadata.transversal_execution_v1[checkpoint_code]',
      'modes',jsonb_build_array('EXPLICIT','SELECT'),
      'explicit_shape','ORDERED_CAPABILITIES_ARRAY',
      'sequence_mode','ONE_BY_ONE_REBOOTSTRAP',
      'engine_surface','READ|WRITE_DB|WRITE_GIT|RUN_TEST',
      'title_heuristic_when_declared','FORBIDDEN',
      'unsupported_handler_policy','DECLARED_ONLY_NO_ROUTING_CHANGE',
      'last_item_transition','NORMAL_CHECKPOINT_TRANSITION',
      'nonfinal_item_transition','programacion.fn_engineering_transversal_step_transition_v1',
      'state_function','programacion.fn_engineering_transversal_sequence_state_v1'
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2';

-- 2) action_spec: DECLARED_ONLY is plan information, not an execution blocker.
create or replace function programacion.fn_engineering_checkpoint_action_spec_v3(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text default null
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_base jsonb;
  v_tx jsonb;
  v_cp text;
  v_state jsonb;
  v_item jsonb;
  v_spec jsonb;
begin
  v_base:=programacion.fn_engineering_checkpoint_action_spec_v3_legacy(
    p_plan_code,p_unit_code,p_checkpoint_code
  );
  if v_base is null then return null; end if;

  v_cp:=coalesce(p_checkpoint_code,v_base->>'checkpoint_code');

  select pu.unit_metadata#>array['transversal_execution_v1',v_cp]
    into v_tx
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code;

  if v_tx is null then return v_base; end if;

  if coalesce(v_tx->>'activation','ACTIVE')='DECLARED_ONLY' then
    return v_base || jsonb_build_object(
      'transversal_execution',v_tx,
      'transversal_gate','DECLARED_NOT_ACTIVATED',
      'transversal_routing_changed',false
    );
  end if;

  if coalesce(v_tx->>'mode','')='SELECT' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_SELECTOR_RUNTIME_REQUIRED',
      'precision','STRUCTURAL_TRANSVERSAL_SELECT',
      'transversal_execution',v_tx,
      'transversal_gate','SELECTOR_REQUIRED'
    );
  end if;

  if coalesce(v_tx->>'mode','')<>'EXPLICIT' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_MODE_INVALID',
      'transversal_execution',v_tx
    );
  end if;

  v_state:=programacion.fn_engineering_transversal_sequence_state_v1(
    p_plan_code,p_unit_code,v_cp
  );

  if coalesce((v_state->>'total')::int,0)=0 then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_CAPABILITIES_MISSING',
      'transversal_execution',v_tx
    );
  end if;

  if coalesce((v_state->>'all_done')::boolean,false) then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_SEQUENCE_ALREADY_COMPLETE_REQUIRES_CHECKPOINT_TRANSITION',
      'transversal_execution',v_tx,
      'transversal_sequence',v_state
    );
  end if;

  v_item:=v_state->'current_item';
  v_spec:=programacion.fn_engineering_transversal_capability_action_spec_v1(
    p_plan_code,p_unit_code,v_cp,v_item
  );

  return v_spec || jsonb_build_object(
    'transversal_execution',v_tx,
    'transversal_sequence',v_state,
    'transversal_gate',
      case when v_spec->>'status'='READY' then 'PASS_CURRENT_ITEM' else 'BLOCK_CURRENT_ITEM' end,
    'forbidden',
      coalesce(v_spec->'forbidden','[]'::jsonb)
      || jsonb_build_array('FALLBACK_TO_TITLE_HEURISTIC_WHEN_EXPLICIT_DECLARED')
  );
end;
$$;

-- 3) Preserve the proven active M3.9 declaration.
update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  unit_metadata,
  '{transversal_execution_v1,SHADOW_RUN}',
  jsonb_build_object(
    'mode','EXPLICIT',
    'activation','ACTIVE',
    'capabilities',jsonb_build_array(
      jsonb_build_object(
        'capability_code','CONTROL_EQUIVALENCE_JUDGE',
        'handler','T_EQUIV_SHADOW'
      )
    ),
    'dependency_resolution','MANIFEST_GRAPH',
    'execution_order','PLAN_ORDER_ONE_BY_ONE',
    'admission_required',false
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M3.9';

-- 4) Materialize known direct transversal invocations as plan data.
-- They remain DECLARED_ONLY until their exact handler is separately qualified,
-- so this metadata cannot introduce a new execution stop.
with decl(unit_code,checkpoint_code,capabilities) as (
  values
    ('M4.4','INDEPENDENCE_FROM_TINDEP',
      '[{"capability_code":"INDEPENDENT_ASSURANCE","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M4.5','REGISTRY_SOURCE_RESOLUTION',
      '[{"capability_code":"SOURCE_RESOLUTION_POLICY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M4.7','REUSE_EVIDENCE_LEDGER',
      '[{"capability_code":"EVIDENCE_LEDGER","handler":"DECLARED_HANDLER_PENDING"},{"capability_code":"TYPED_EVIDENCE_REGISTRY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M4.10','SHADOW_BY_MODULE',
      '[{"capability_code":"CONTROL_EQUIVALENCE_JUDGE","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M8.8','BUDGET_FROM_TPERF',
      '[{"capability_code":"TIMEOUT_PHASE_BUDGET_POLICY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M8.10','BENCH_VIA_TPERF',
      '[{"capability_code":"PERFORMANCE_EXACT_SOURCE_BENCHMARK","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M8.10','PHASE_BUDGET',
      '[{"capability_code":"TIMEOUT_PHASE_BUDGET_POLICY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M8.11','RECEIPT_MODEL_REUSE',
      '[{"capability_code":"EVIDENCE_LEDGER","handler":"DECLARED_HANDLER_PENDING"},{"capability_code":"TYPED_EVIDENCE_REGISTRY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M9.3','TEQUIV_CONSUMPTION',
      '[{"capability_code":"CONTROL_EQUIVALENCE_JUDGE","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M9.5','TEQUIV_ENGINE_BINDING',
      '[{"capability_code":"CONTROL_EQUIVALENCE_JUDGE","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M9.7','TYPED_SCHEMA',
      '[{"capability_code":"TYPED_EVIDENCE_REGISTRY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M10.11','REUSE_RETIREMENT_GOV',
      '[{"capability_code":"ASSET_RETIREMENT_GOVERNANCE","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M10.13','GIT_RUNTIME_PARITY',
      '[{"capability_code":"MIGRATION_SOURCE_PARITY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('N-6','INDEPENDENT_JUDGE',
      '[{"capability_code":"INDEPENDENT_ASSURANCE","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb)
)
update programacion.engineering_plan_units pu
set unit_metadata=jsonb_set(
  pu.unit_metadata,
  array['transversal_execution_v1',d.checkpoint_code],
  jsonb_build_object(
    'mode','EXPLICIT',
    'activation','DECLARED_ONLY',
    'capabilities',d.capabilities,
    'dependency_resolution','MANIFEST_GRAPH',
    'execution_order','PLAN_ORDER_ONE_BY_ONE',
    'admission_required',false
  ),
  true
)
from decl d
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code=d.unit_code
  and not (
    pu.unit_code='M3.9' and d.checkpoint_code='SHADOW_RUN'
  );

-- 5) Remove two known stale "capability missing" claims that are false live.
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  jsonb_set(
    unit_metadata,
    '{source_pack_v1,checkpoint_inputs,SHADOW_BY_MODULE,missing}',
    coalesce((
      select jsonb_agg(x)
      from jsonb_array_elements(
        coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,SHADOW_BY_MODULE,missing}','[]'::jsonb)
      ) x
      where x #>> '{}' not ilike '%control equivalence judge%no existe en lf_capability_registry%'
    ),'[]'::jsonb),
    true
  ),
  '{source_pack_v1,checkpoint_inputs,SHADOW_BY_MODULE,missing_typed}',
  coalesce((
    select jsonb_agg(x)
    from jsonb_array_elements(
      coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,SHADOW_BY_MODULE,missing_typed}','[]'::jsonb)
    ) x
    where coalesce(x->>'text','') not ilike '%control equivalence judge%no existe en lf_capability_registry%'
  ),'[]'::jsonb),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.10';

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  jsonb_set(
    unit_metadata,
    '{source_pack_v1,checkpoint_inputs,BUDGET_FROM_TPERF,missing}',
    coalesce((
      select jsonb_agg(x)
      from jsonb_array_elements(
        coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,BUDGET_FROM_TPERF,missing}','[]'::jsonb)
      ) x
      where x #>> '{}' not ilike '%timeout_phase_budget_policy%no existe en lf_capability_registry%'
    ),'[]'::jsonb),
    true
  ),
  '{source_pack_v1,checkpoint_inputs,BUDGET_FROM_TPERF,missing_typed}',
  coalesce((
    select jsonb_agg(x)
    from jsonb_array_elements(
      coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,BUDGET_FROM_TPERF,missing_typed}','[]'::jsonb)
    ) x
    where coalesce(x->>'text','') not ilike '%timeout_phase_budget_policy%no existe en lf_capability_registry%'
  ),'[]'::jsonb),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M8.8';
