begin;

-- S30 transversal policy README alias binding v1.
-- One README per logical policy family; canonical policy code and inventory alias
-- share the same documentation instead of duplicating policy content.

do $pre$
declare
  v_missing integer;
begin
  select count(*) into v_missing
  from (values
    ('OPERATION_LIFECYCLE_POLICY'),
    ('POL-LF-OPERATION-LIFECYCLE'),
    ('POLICY_CONSUMPTION'),
    ('POL-LF-SOURCE-RESOLUTION'),
    ('SOURCE_RESOLUTION_POLICY'),
    ('POL-LF-STATE-MODEL'),
    ('STATE_MODEL_POLICY')
  ) x(code)
  where not exists (
    select 1 from public.lf_activos a
    where a.codigo_activo=x.code
      and a.archived_at is null
      and a.estado_operativo='ACTIVO'
      and a.metadata #>> '{transversal_inventory,inventory_status}'='ACTIVE_TRANSVERSAL_POLICY'
  );

  if v_missing<>0 then
    raise exception 'BLOCK_TRANSVERSAL_POLICY_ALIAS_PRESTATE missing=%',v_missing;
  end if;
end
$pre$;

with mapping(code,readme_ref,current_version,current_physical) as (
  values
    (
      'OPERATION_LIFECYCLE_POLICY',
      'sandbox/lf_contract_gate_test/transversal_assets/pol_lf_operation_lifecycle/README.md',
      'v1.1-operational-closure',
      jsonb_build_array('POL-LF-OPERATION-LIFECYCLE:v1.1-operational-closure','public.v_lf_operation_policy_snapshot')
    ),
    (
      'POL-LF-OPERATION-LIFECYCLE',
      'sandbox/lf_contract_gate_test/transversal_assets/pol_lf_operation_lifecycle/README.md',
      'v1.1-operational-closure',
      null::jsonb
    ),
    (
      'POLICY_CONSUMPTION',
      'sandbox/lf_contract_gate_test/transversal_assets/pol_lf_policy_consumption/README.md',
      'v1.2-context-admission',
      jsonb_build_array('POL-LF-POLICY-CONSUMPTION:v1.2-context-admission','public.v_lf_operation_policy_snapshot','public.fn_lf_router_preflight_v1(text)')
    ),
    (
      'POL-LF-SOURCE-RESOLUTION',
      'sandbox/lf_contract_gate_test/transversal_assets/pol_lf_source_resolution/README.md',
      'v1.4-transversal-supabase-authority-visual-support',
      null::jsonb
    ),
    (
      'SOURCE_RESOLUTION_POLICY',
      'sandbox/lf_contract_gate_test/transversal_assets/pol_lf_source_resolution/README.md',
      'v1.4-transversal-supabase-authority-visual-support',
      null::jsonb
    ),
    (
      'POL-LF-STATE-MODEL',
      'sandbox/lf_contract_gate_test/transversal_assets/pol_lf_state_model/README.md',
      'v2.0-canonical-lifecycle',
      null::jsonb
    ),
    (
      'STATE_MODEL_POLICY',
      'sandbox/lf_contract_gate_test/transversal_assets/pol_lf_state_model/README.md',
      'v2.0-canonical-lifecycle',
      null::jsonb
    )
)
update public.lf_activos a
set version=m.current_version,
    metadata=jsonb_set(
      jsonb_set(
        a.metadata,
        '{transversal_inventory,documentation}',
        jsonb_build_object(
          'status','SOURCE_FIRST_BOUND',
          'repo','cristhianlujan/claude-persona-lf-patch',
          'readme_ref',m.readme_ref,
          'contract_version','lf-transversal-readme-contract/v3'
        ),
        true
      ),
      '{transversal_inventory,physical_assets}',
      coalesce(m.current_physical,a.metadata #> '{transversal_inventory,physical_assets}','[]'::jsonb)
      || jsonb_build_array(m.readme_ref),
      true
    ),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-S30-TRANSVERSAL-POLICY-README-ALIASES-20260918-001'
from mapping m
where a.codigo_activo=m.code
  and a.archived_at is null;

do $post$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from (values
    ('OPERATION_LIFECYCLE_POLICY','sandbox/lf_contract_gate_test/transversal_assets/pol_lf_operation_lifecycle/README.md'),
    ('POL-LF-OPERATION-LIFECYCLE','sandbox/lf_contract_gate_test/transversal_assets/pol_lf_operation_lifecycle/README.md'),
    ('POLICY_CONSUMPTION','sandbox/lf_contract_gate_test/transversal_assets/pol_lf_policy_consumption/README.md'),
    ('POL-LF-SOURCE-RESOLUTION','sandbox/lf_contract_gate_test/transversal_assets/pol_lf_source_resolution/README.md'),
    ('SOURCE_RESOLUTION_POLICY','sandbox/lf_contract_gate_test/transversal_assets/pol_lf_source_resolution/README.md'),
    ('POL-LF-STATE-MODEL','sandbox/lf_contract_gate_test/transversal_assets/pol_lf_state_model/README.md'),
    ('STATE_MODEL_POLICY','sandbox/lf_contract_gate_test/transversal_assets/pol_lf_state_model/README.md')
  ) x(code,readme_ref)
  join public.lf_activos a on a.codigo_activo=x.code
  where a.archived_at is not null
     or a.estado_operativo<>'ACTIVO'
     or a.metadata #>> '{transversal_inventory,inventory_status}'<>'ACTIVE_TRANSVERSAL_POLICY'
     or a.metadata #>> '{transversal_inventory,documentation,readme_ref}' is distinct from x.readme_ref;

  if v_bad<>0 then
    raise exception 'BLOCK_TRANSVERSAL_POLICY_ALIAS_READBACK bad=%',v_bad;
  end if;

  if (select version from public.lf_activos where codigo_activo='OPERATION_LIFECYCLE_POLICY')
     is distinct from 'v1.1-operational-closure' then
    raise exception 'BLOCK_OPERATION_LIFECYCLE_ALIAS_CURRENTNESS';
  end if;

  if (select version from public.lf_activos where codigo_activo='POLICY_CONSUMPTION')
     is distinct from 'v1.2-context-admission' then
    raise exception 'BLOCK_POLICY_CONSUMPTION_ALIAS_CURRENTNESS';
  end if;
end
$post$;

commit;
