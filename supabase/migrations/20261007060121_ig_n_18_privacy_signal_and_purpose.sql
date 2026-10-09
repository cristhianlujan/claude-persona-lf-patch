-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / N-18 / PAULO-183
-- Checkpoint: PRIVACY_SIGNAL_AND_PURPOSE
-- IG is a consumer of PRIVACY_MINIMALITY_GUARD. No parallel privacy authority is created.

do $n18$
declare
  v_capability constant text := 'PRIVACY_MINIMALITY_GUARD';
  v_consumer_execution constant text := 'IG-N18-PRIVACY-CONSUMER-20261007-V1';
  v_orchestrator_execution constant text := 'IG-N18-PRIVACY-ORCH-20261007-V1';
  v_version text;
  v_manifest_sha text;
  v_plan_digest text;
  v_request_sha text;
  v_orch jsonb;
  v_consumer jsonb;
  v_receipt jsonb;
  v_receipt_id uuid;
  v_bind jsonb;
begin
  select c.version,c.manifest_sha256
    into v_version,v_manifest_sha
  from public.lf_capability_current c
  join public.lf_capability_registry r using(capability_code)
  join public.lf_capability_version_registry v
    on v.capability_code=c.capability_code
   and v.version=c.version
   and v.manifest_sha256=c.manifest_sha256
  where c.capability_code=v_capability
    and r.status='ACTIVE'
    and v.release_state='RELEASED';

  if v_version is null or v_manifest_sha is null then
    raise exception 'BLOCK_N18_PRIVACY_MINIMALITY_GUARD_NOT_CURRENT';
  end if;

  v_plan_digest:=encode(
    extensions.digest(
      convert_to(
        'IG_CURATOR_VALIDATOR_REFACTOR_V2:N-18|PRIVACY_MINIMALITY_GUARD|PRIVACY_SIGNAL_POLICY_V1',
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
  v_request_sha:=encode(
    extensions.digest(convert_to(v_consumer_execution,'UTF8'),'sha256'),
    'hex'
  );

  v_orch:=public.fn_lf_operation_reserve_execution_v1(
    v_orchestrator_execution,
    'ORQUESTACION_PIPELINE_LF',
    'ENGINEERING_PLAN_UNIT_BINDING',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2:N-18',
    'ig-n18-privacy-orch-20261007-v1',
    v_request_sha,
    v_orchestrator_execution,
    null,
    null,
    jsonb_build_object(
      'purpose','N18_PRIVACY_CAPABILITY_BINDING',
      'consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'consumer_unit','N-18',
      'capability_code',v_capability,
      'effects_executed',false
    )
  );

  if coalesce(v_orch->>'result','') not in ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') then
    raise exception 'BLOCK_N18_ORCHESTRATOR_RESERVE:%',v_orch::text;
  end if;

  v_consumer:=public.fn_lf_operation_reserve_execution_v1(
    v_consumer_execution,
    'GITHUB_CONTRACT_GATE_LF',
    'ENGINEERING_PLAN_UNIT_BINDING',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2:N-18',
    'ig-n18-privacy-consumer-20261007-v1',
    v_request_sha,
    v_orchestrator_execution,
    null,
    null,
    jsonb_build_object(
      'orchestrator_execution_id',v_orchestrator_execution,
      'plan_digest',v_plan_digest,
      'capability_code',v_capability,
      'consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'consumer_unit','N-18',
      'effects_executed',false
    )
  );

  if coalesce(v_consumer->>'result','') not in ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') then
    raise exception 'BLOCK_N18_CONSUMER_RESERVE:%',v_consumer::text;
  end if;

  v_receipt:=public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orchestrator_execution,
    v_consumer_execution,
    v_capability,
    v_plan_digest,
    jsonb_build_object(
      'consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'consumer_unit','N-18',
      'purpose','PRIVACY_SIGNAL_AND_PURPOSE',
      'effects_executed',false
    ),
    v_orchestrator_execution
  );

  if coalesce((v_receipt->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_N18_DISPATCH:%',v_receipt::text;
  end if;

  v_receipt_id:=(v_receipt->>'receipt_id')::uuid;

  v_bind:=public.fn_lf_capability_bind_from_orchestrator_v1(
    v_consumer_execution,
    v_capability,
    v_manifest_sha,
    v_plan_digest,
    v_receipt_id,
    v_consumer_execution
  );

  if coalesce((v_bind->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_N18_PRIVACY_BIND:%',v_bind::text;
  end if;

  update public.lf_operation_execution
     set status='COMPLETED',
         completed_at=coalesce(completed_at,clock_timestamp()),
         checkpoint_payload=jsonb_build_object(
           'schema_version','IG_N18_PRIVACY_SIGNAL_POLICY_V1',
           'consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2',
           'consumer_unit','N-18',
           'consumer_ref','INPUT_GOVERNANCE',
           'capability_code',v_capability,
           'bound_version',v_version,
           'bound_manifest_sha256',v_manifest_sha,
           'activation_signals',jsonb_build_array(
             'ANALYTICS',
             'TRACKING',
             'STABLE_IDENTITY',
             'RETENTION'
           ),
           'outside_material_signal_state','NOT_REQUIRED',
           'required_declarations',jsonb_build_array(
             'PURPOSE',
             'CONSUMER',
             'DATA_NEED'
           ),
           'authority_resolution','UNKNOWN_REQUIRES_DECISION',
           'authority_ref',null,
           'invasive_signals_without_need_and_authority','FORBIDDEN',
           'forbidden_examples',jsonb_build_array(
             'DEVICE_FINGERPRINT',
             'GEOLOCATION',
             'SESSION_DURATION'
           ),
           'parallel_privacy_policy_created',false,
           'runtime_activated',false,
           'effects_executed',false,
           'dispatch_receipt_id',v_receipt_id
         ),
         updated_by_execution_id=v_consumer_execution,
         updated_at=clock_timestamp()
   where execution_id=v_consumer_execution;

  update public.lf_operation_execution
     set status='COMPLETED',
         completed_at=coalesce(completed_at,clock_timestamp()),
         checkpoint_payload=jsonb_build_object(
           'schema_version','IG_N18_PRIVACY_ORCHESTRATION_PROOF_V1',
           'consumer_execution_id',v_consumer_execution,
           'capability_code',v_capability,
           'dispatch_receipt_id',v_receipt_id,
           'effects_executed',false
         ),
         updated_by_execution_id=v_orchestrator_execution,
         updated_at=clock_timestamp()
   where execution_id=v_orchestrator_execution;

  if not exists(
    select 1
    from public.lf_capability_binding b
    join public.lf_capability_current c using(capability_code)
    where b.execution_id=v_consumer_execution
      and b.capability_code=v_capability
      and b.binding_state='BOUND'
      and b.bound_version=c.version
      and b.bound_manifest_sha256=c.manifest_sha256
  ) then
    raise exception 'BLOCK_N18_PRIVACY_BIND_READBACK';
  end if;

  if not exists(
    select 1
    from public.lf_operation_execution e
    where e.execution_id=v_consumer_execution
      and e.status='COMPLETED'
      and e.checkpoint_payload->>'authority_resolution'='UNKNOWN_REQUIRES_DECISION'
      and e.checkpoint_payload->>'outside_material_signal_state'='NOT_REQUIRED'
      and coalesce((e.checkpoint_payload->>'parallel_privacy_policy_created')::boolean,true)=false
      and coalesce((e.checkpoint_payload->>'runtime_activated')::boolean,true)=false
  ) then
    raise exception 'BLOCK_N18_POLICY_READBACK';
  end if;
end
$n18$;
