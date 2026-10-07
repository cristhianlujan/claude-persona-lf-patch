-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / N-18 / PAULO-183
-- Checkpoint: MINIMAL_DATA_CONTRACT
-- Consumer-only minimal data contract. PRIVACY_MINIMALITY_GUARD remains unchanged.

do $n18_minimal$
declare
  v_execution constant text := 'IG-N18-PRIVACY-CONSUMER-20261007-V1';
  v_capability constant text := 'PRIVACY_MINIMALITY_GUARD';
  v_manifest_before text;
  v_manifest_after text;
begin
  select manifest_sha256
    into v_manifest_before
  from public.lf_capability_current
  where capability_code=v_capability;

  if v_manifest_before is null then
    raise exception 'BLOCK_N18_MINIMAL_PRIVACY_GUARD_NOT_CURRENT';
  end if;

  update public.lf_operation_execution
     set checkpoint_payload=jsonb_set(
           checkpoint_payload,
           '{minimal_data_contract}',
           jsonb_build_object(
             'schema_version','IG_N18_MINIMAL_DATA_CONTRACT_V1',
             'default_state','NOT_REQUIRED',
             'default_requested_items','[]'::jsonb,
             'activation_requires',jsonb_build_array(
               'MATERIAL_SIGNAL',
               'DECLARED_PURPOSE',
               'DECLARED_CONSUMER',
               'DECLARED_DATA_NEED',
               'GOVERNED_AUTHORITY'
             ),
             'milestone_policy','ONLY_DECLARED_MILESTONES_WHEN_MATERIAL',
             'field_policy','REQUESTED_ITEMS_MUST_BE_SUBSET_OF_NECESSARY_ITEMS',
             'identifier_policy','OPAQUE_SCOPED_ONLY',
             'retention_policy','NO_RETENTION_WITHOUT_GOVERNED_AUTHORITY_AND_DECLARED_NEED',
             'prohibited_by_default',jsonb_build_array(
               'DEVICE_FINGERPRINT',
               'PRECISE_GEOLOCATION',
               'SESSION_DURATION'
             ),
             'guard_capability',v_capability,
             'guard_input_fields',jsonb_build_array(
               'consumer_ref',
               'operation',
               'need',
               'authority',
               'requested_items',
               'necessary_items'
             ),
             'parallel_authority_created',false,
             'runtime_activated',false
           ),
           true
         ),
         updated_by_execution_id='IG-N18-MINIMAL-DATA-20261007-V1',
         updated_at=clock_timestamp()
   where execution_id=v_execution
     and status='COMPLETED'
     and checkpoint_payload->>'capability_code'=v_capability
     and checkpoint_payload->>'outside_material_signal_state'='NOT_REQUIRED';

  if not found then
    raise exception 'BLOCK_N18_MINIMAL_CONSUMER_BINDING_NOT_FOUND';
  end if;

  select manifest_sha256
    into v_manifest_after
  from public.lf_capability_current
  where capability_code=v_capability;

  if v_manifest_after is distinct from v_manifest_before then
    raise exception 'BLOCK_N18_MINIMAL_CAPABILITY_MUTATED';
  end if;

  if not exists(
    select 1
    from public.lf_operation_execution e
    where e.execution_id=v_execution
      and e.checkpoint_payload#>>'{minimal_data_contract,default_state}'='NOT_REQUIRED'
      and e.checkpoint_payload#>'{minimal_data_contract,default_requested_items}'='[]'::jsonb
      and e.checkpoint_payload#>>'{minimal_data_contract,identifier_policy}'='OPAQUE_SCOPED_ONLY'
      and e.checkpoint_payload#>>'{minimal_data_contract,retention_policy}'='NO_RETENTION_WITHOUT_GOVERNED_AUTHORITY_AND_DECLARED_NEED'
      and coalesce((e.checkpoint_payload#>>'{minimal_data_contract,parallel_authority_created}')::boolean,true)=false
      and coalesce((e.checkpoint_payload#>>'{minimal_data_contract,runtime_activated}')::boolean,true)=false
  ) then
    raise exception 'BLOCK_N18_MINIMAL_READBACK';
  end if;
end
$n18_minimal$;
