begin;

-- S30 context transversal activation v1.
-- Closes the operationalization gap left after context-admission v1:
--   * POLICY_CONSUMPTION was active but undocumented in the transversal index;
--   * CONTEXT_BUDGET_GOVERNANCE was wired but still READ_ONLY / low-adoption.
-- Reuses public.lf_activos + existing README contract. No new engine/table.

do $pre$
declare
  v_policy_status text;
  v_budget_state text;
  v_budget_inventory text;
begin
  select metadata #>> '{transversal_inventory,inventory_status}'
    into v_policy_status
  from public.lf_activos
  where codigo_activo='POL-LF-POLICY-CONSUMPTION'
    and archived_at is null
    and estado_operativo='ACTIVO';

  if v_policy_status is distinct from 'ACTIVE_TRANSVERSAL_POLICY' then
    raise exception 'BLOCK_POLICY_CONSUMPTION_TRANSVERSAL_PRESTATE:%',v_policy_status;
  end if;

  select estado_operativo,
         metadata #>> '{transversal_inventory,inventory_status}'
    into v_budget_state,v_budget_inventory
  from public.lf_activos
  where codigo_activo='CONTEXT_BUDGET_GOVERNANCE'
    and archived_at is null;

  if v_budget_state is distinct from 'READ_ONLY'
     or v_budget_inventory is distinct from 'EXISTING_PARTIAL_LOW_ADOPTION' then
    raise exception 'BLOCK_CONTEXT_BUDGET_PRESTATE state=% inventory=%',
      v_budget_state,v_budget_inventory;
  end if;
end
$pre$;

update public.lf_activos
set metadata=jsonb_set(
      metadata,
      '{transversal_inventory}',
      coalesce(metadata->'transversal_inventory','{}'::jsonb)
      || jsonb_build_object(
        'inventory_status','ACTIVE_TRANSVERSAL_POLICY',
        'gap','CLOSED_BY_CONTEXT_ADMISSION_V1',
        'usage_evidence','Resolved once by Router context admission; model receives compact policy refs/version/SHA and JIT handles.',
        'documentation',jsonb_build_object(
          'status','SOURCE_FIRST_BOUND',
          'repo','cristhianlujan/claude-persona-lf-patch',
          'readme_ref','sandbox/lf_contract_gate_test/transversal_assets/pol_lf_policy_consumption/README.md',
          'contract_version','lf-transversal-readme-contract/v3'
        ),
        'physical_assets',jsonb_build_array(
          'POL-LF-POLICY-CONSUMPTION:v1.2-context-admission',
          'public.v_lf_operation_policy_snapshot',
          'public.fn_lf_router_preflight_v1(text)',
          'sandbox/lf_contract_gate_test/transversal_assets/pol_lf_policy_consumption/README.md'
        )
      ),
      true
    ),
    updated_by_execution_id='EXEC-S30-CONTEXT-TRANSVERSAL-ACTIVATION-20260918-001',
    updated_at=clock_timestamp()
where codigo_activo='POL-LF-POLICY-CONSUMPTION'
  and archived_at is null;

update public.lf_activos
set estado_operativo='ACTIVO',
    version='v1.0-context-admission',
    metadata=jsonb_set(
      metadata,
      '{transversal_inventory}',
      coalesce(metadata->'transversal_inventory','{}'::jsonb)
      || jsonb_build_object(
        'inventory_status','ACTIVE_SHARED_ENFORCEMENT',
        'gap','CLOSED_BY_CONTEXT_ADMISSION_V1',
        'usage_evidence','Router preflight emits context budget events for every compiled receipt; GREEN/YELLOW/RED enforcement is active.',
        'consumers_known',jsonb_build_array(
          'ROUTER_CONTEXT_ADMISSION_V1',
          'POL-LF-POLICY-CONSUMPTION'
        ),
        'documentation',jsonb_build_object(
          'status','SOURCE_FIRST_BOUND',
          'repo','cristhianlujan/claude-persona-lf-patch',
          'readme_ref','sandbox/lf_contract_gate_test/transversal_assets/context_budget_governance/README.md',
          'contract_version','lf-transversal-readme-contract/v3'
        ),
        'physical_assets',jsonb_build_array(
          'private.lf_context_budget_events_v2',
          'public.v_lf_context_budget_latest_v2',
          'public.fn_lf_router_preflight_v1(text)',
          'POL-LF-POLICY-CONSUMPTION:v1.2-context-admission',
          'sandbox/lf_contract_gate_test/transversal_assets/context_budget_governance/README.md'
        )
      ),
      true
    ),
    updated_by_execution_id='EXEC-S30-CONTEXT-TRANSVERSAL-ACTIVATION-20260918-001',
    updated_at=clock_timestamp()
where codigo_activo='CONTEXT_BUDGET_GOVERNANCE'
  and archived_at is null;

do $post$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.lf_activos
  where codigo_activo='POL-LF-POLICY-CONSUMPTION'
    and archived_at is null
    and estado_operativo='ACTIVO'
    and metadata #>> '{transversal_inventory,inventory_status}'='ACTIVE_TRANSVERSAL_POLICY'
    and metadata #>> '{transversal_inventory,documentation,readme_ref}'=
      'sandbox/lf_contract_gate_test/transversal_assets/pol_lf_policy_consumption/README.md';

  if v_count<>1 then
    raise exception 'BLOCK_POLICY_CONSUMPTION_README_ACTIVATION_READBACK:%',v_count;
  end if;

  select count(*) into v_count
  from public.lf_activos
  where codigo_activo='CONTEXT_BUDGET_GOVERNANCE'
    and archived_at is null
    and estado_operativo='ACTIVO'
    and version='v1.0-context-admission'
    and metadata #>> '{transversal_inventory,inventory_status}'='ACTIVE_SHARED_ENFORCEMENT'
    and metadata #>> '{transversal_inventory,documentation,readme_ref}'=
      'sandbox/lf_contract_gate_test/transversal_assets/context_budget_governance/README.md';

  if v_count<>1 then
    raise exception 'BLOCK_CONTEXT_BUDGET_ACTIVATION_READBACK:%',v_count;
  end if;

  if not exists (
    select 1
    from public.lf_policy_versions
    where policy_code='POL-LF-POLICY-CONSUMPTION'
      and policy_version='v1.2-context-admission'
      and status='ACTIVE'
      and policy_sha='9cbea9e36403439303312cd2e1d207c4506356624d224374cbe87220329fcbd5'
  ) then
    raise exception 'BLOCK_POLICY_CONSUMPTION_V12_CURRENTNESS';
  end if;
end
$post$;

commit;
