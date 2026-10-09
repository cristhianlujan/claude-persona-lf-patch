
do $reconcile$
declare
  v_meta jsonb;
  v_spec jsonb;
  v_binding jsonb;
  v_rows integer;
begin
  if not exists (
    select 1
    from public.lf_operation_execution e
    join public.lf_capability_binding b
      on b.execution_id=e.execution_id
     and b.capability_code='EVIDENCE_LEDGER'
     and b.binding_state='BOUND'
     and b.bound_version='1.1.0'
     and b.bound_manifest_sha256='b9c21eaa0cb4eceec3e6a0ae78272ed2da84e408e804c127ed6e43d1360f0982'
    where e.execution_id='EXEC-IG-M6-2-LEDGER-20261007-CGPT-V1'
      and e.status='IN_PROGRESS'
      and e.manifest->>'plan_code'='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and e.manifest->>'unit_code'='M6.2'
      and e.manifest->>'checkpoint_code'='GRAPH_SHA_RECEIPT'
      and e.manifest->>'orchestrator_execution_id'='EXEC-IG-M6-2-ORCH-20261007-CGPT-V1'
  ) then
    raise exception 'M6_2_EVIDENCE_LEDGER_BINDING_NOT_VERIFIED';
  end if;

  if not exists (
    select 1 from private.lf_orchestrator_dispatch_receipts_v1 d
    where d.receipt_id='29817c77-d345-4e64-8335-3ebf9637a83f'::uuid
      and d.orchestrator_execution_id='EXEC-IG-M6-2-ORCH-20261007-CGPT-V1'
      and d.consumer_execution_id='EXEC-IG-M6-2-LEDGER-20261007-CGPT-V1'
      and d.capability_code='EVIDENCE_LEDGER'
  ) then
    raise exception 'M6_2_DISPATCH_RECEIPT_NOT_VERIFIED';
  end if;

  select unit_metadata into v_meta
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and unit_code='M6.2'
    and disposition='ASSIGNED'
  for update;

  v_spec:=v_meta#>'{action_specs_v1,GRAPH_SHA_RECEIPT}';
  if v_spec->>'status'<>'BLOCK_MATERIALIZATION_CONTRACT_REQUIRED'
     or not (coalesce(v_spec->'blocking_codes','[]'::jsonb) ? 'EVIDENCE_LEDGER_EXECUTION_BINDING_MISSING') then
    raise exception 'M6_2_BINDING_RECONCILE_PREIMAGE_DRIFT:%',v_spec;
  end if;

  v_binding:=jsonb_build_object(
    'status','BOUND_CURRENT',
    'capability_code','EVIDENCE_LEDGER',
    'capability_version','1.1.0',
    'manifest_sha256','b9c21eaa0cb4eceec3e6a0ae78272ed2da84e408e804c127ed6e43d1360f0982',
    'orchestrator_execution_id','EXEC-IG-M6-2-ORCH-20261007-CGPT-V1',
    'consumer_execution_id','EXEC-IG-M6-2-LEDGER-20261007-CGPT-V1',
    'dispatch_receipt_id','29817c77-d345-4e64-8335-3ebf9637a83f',
    'dispatch_receipt_sha256','0e55593c4b6d99ac72ef9e609631780516a12a1d949ce8ff64c87cee473e015d',
    'authority','public.lf_operation_execution+public.lf_capability_binding+private.lf_orchestrator_dispatch_receipts_v1'
  );

  v_spec:=v_spec
    || jsonb_build_object(
      'status','READY',
      'precision','EXACT_EVIDENCE_LEDGER_EXECUTION_BOUND_V1',
      'blocking_codes','[]'::jsonb,
      'execution_binding',v_binding,
      'handler_requirement',
        coalesce(v_spec->'handler_requirement','{}'::jsonb)
        || jsonb_build_object(
          'status','RESOLVED',
          'resolved_by','CANONICAL_OPERATION_RESERVE_DISPATCH_BIND',
          'execution_binding',v_binding
        )
    );

  update programacion.engineering_plan_units
     set unit_metadata=jsonb_set(
       unit_metadata,
       '{action_specs_v1,GRAPH_SHA_RECEIPT}',
       v_spec,
       true
     )
   where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     and unit_code='M6.2'
     and disposition='ASSIGNED';

  get diagnostics v_rows=row_count;
  if v_rows<>1 then
    raise exception 'M6_2_BINDING_RECONCILE_CARDINALITY:%',v_rows;
  end if;

  if programacion.fn_engineering_checkpoint_action_spec_v3(
       'IG_CURATOR_VALIDATOR_REFACTOR_V2','M6.2','GRAPH_SHA_RECEIPT'
     )->>'status' <> 'READY' then
    raise exception 'M6_2_BINDING_RECONCILE_POSTCHECK_NOT_READY';
  end if;
end;
$reconcile$;
