-- Block 3 closeout: deactivate dependency edges touching repo objects
-- classified MISSING by external-currentness snapshot #11.
-- Historical dependency rows are retained; only active is changed.

begin;

with missing as (
  select object_id
  from inventory.objects
  where object_ref like 'repo://%'
    and currentness='MISSING'
    and not active
),
targets as (
  select d.dependency_id,
         d.source_object_id in (select object_id from missing) as source_missing,
         d.target_object_id in (select object_id from missing) as target_missing
  from inventory.dependencies d
  where d.active
    and (
      d.source_object_id in (select object_id from missing)
      or d.target_object_id in (select object_id from missing)
    )
)
update inventory.dependencies d
set active=false,
    last_verified_at=now(),
    metadata=jsonb_set(
      coalesce(d.metadata,'{}'::jsonb),
      '{external_currentness_deactivation}',
      jsonb_build_object(
        'snapshot_id',11,
        'snapshot_code','LF_EXTERNAL_CURRENTNESS_20261001171547971',
        'observed_main_sha','1f18636503cdaeda79a8df6cced0d0f2e5353c14',
        'reason','TOUCHES_MISSING_REPO_OBJECT',
        'source_missing',t.source_missing,
        'target_missing',t.target_missing,
        'deactivated_at',clock_timestamp()
      ),
      true
    )
from targets t
where d.dependency_id=t.dependency_id;

do $$
declare
  v_remaining bigint;
begin
  select count(*) into v_remaining
  from inventory.dependencies d
  join inventory.objects s on s.object_id=d.source_object_id
  left join inventory.objects t on t.object_id=d.target_object_id
  where d.active
    and (
      (s.object_ref like 'repo://%' and s.currentness='MISSING' and not s.active)
      or (t.object_ref like 'repo://%' and t.currentness='MISSING' and not t.active)
    );
  if v_remaining <> 0 then
    raise exception 'BLOCK_ACTIVE_DEPENDENCIES_STILL_TOUCH_MISSING:%',v_remaining;
  end if;
end
$$;


update inventory.snapshots
set metadata=jsonb_set(
  jsonb_set(
    coalesce(metadata,'{}'::jsonb),
    '{evidence_bundle}',
    jsonb_build_object(
      'repository','cristhianlujan/claude-persona-lf-patch',
      'observed_main_sha','1f18636503cdaeda79a8df6cced0d0f2e5353c14',
      'path','sandbox/lf_contract_gate_test/transversal_assets/global_technical_inventory/evidence/LF_EXTERNAL_CURRENTNESS_20261001171547971',
      'inputs_persisted',true,
      'operational_sql_persisted',true
    ),
    true
  ),
  '{dependency_cleanup}',
  jsonb_build_object(
    'active_inbound_before',104,
    'active_outbound_before',142,
    'unique_active_before',230,
    'unresolved_target_ref_only_before',0,
    'action','DEACTIVATE_PRESERVE_HISTORY'
  ),
  true
)
where snapshot_id=11
  and snapshot_code='LF_EXTERNAL_CURRENTNESS_20261001171547971';

commit;
