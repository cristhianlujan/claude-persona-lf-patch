-- Owner decision D3: governed current-pointer activation for migration Write-Ahead + Saga.
-- No production deploy. No migration DDL beyond governance/currentness metadata and evidence.
-- Entry path: ORCHESTRATION -> dispatch receipt -> guard -> canonical promote -> guarded bind.

do $activate$
declare
  v_orch_id constant text := 'EXEC-MIGRATION-CAPABILITY-ACTIVATION-ORCH-20261005-V1';
  v_wa_id constant text := 'EXEC-MIGRATION-WRITE-AHEAD-ACTIVATE-20261005-V1';
  v_saga_id constant text := 'EXEC-MIGRATION-SAGA-ACTIVATE-20261005-V1';

  v_wa_cap constant text := 'MIGRATION_WRITE_AHEAD_V1';
  v_saga_cap constant text := 'MIGRATION_ORCHESTRATED_SAGA_V1';
  v_wa_manifest constant text := 'cf6cc96283539f3e2d70322d698c82a3ce15209887c89136008c1364af6babb9';
  v_saga_manifest constant text := 'a785ed956d88d2276e4d5094269ed694f761e00ab96966960afdefbdaf1cf462';

  v_wa_plan text := encode(extensions.digest(convert_to(
    'D3|MIGRATION_WRITE_AHEAD_V1|1.0.0|CURRENT_POINTER_AND_GUARDED_BINDING','UTF8'
  ),'sha256'),'hex');
  v_saga_plan text := encode(extensions.digest(convert_to(
    'D3|MIGRATION_ORCHESTRATED_SAGA_V1|1.0.0|CURRENT_POINTER_AND_GUARDED_BINDING','UTF8'
  ),'sha256'),'hex');
  v_orch_request text := encode(extensions.digest(convert_to(v_orch_id,'UTF8'),'sha256'),'hex');
  v_wa_request text := encode(extensions.digest(convert_to(v_wa_id,'UTF8'),'sha256'),'hex');
  v_saga_request text := encode(extensions.digest(convert_to(v_saga_id,'UTF8'),'sha256'),'hex');

  v_orch jsonb;
  v_cons jsonb;
  v_receipt jsonb;
  v_receipt_id uuid;
  v_guard jsonb;
  v_promote jsonb;
  v_bind jsonb;
begin
  -- Exact immutable registry preflight.
  if not exists (
    select 1 from public.lf_capability_registry
    where capability_code=v_wa_cap
      and status='ACTIVE'
      and entry_guard_required is true
      and entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) then raise exception 'BLOCK_D3_WRITE_AHEAD_REGISTRY_GUARD_DRIFT'; end if;

  if not exists (
    select 1 from public.lf_capability_registry
    where capability_code=v_saga_cap
      and status='ACTIVE'
      and entry_guard_required is true
      and entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) then raise exception 'BLOCK_D3_SAGA_REGISTRY_GUARD_DRIFT'; end if;

  if not exists (
    select 1 from public.lf_capability_version_registry
    where capability_code=v_wa_cap and version='1.0.0'
      and release_state='RELEASED' and manifest_sha256=v_wa_manifest
  ) then raise exception 'BLOCK_D3_WRITE_AHEAD_VERSION_DRIFT'; end if;

  if not exists (
    select 1 from public.lf_capability_version_registry
    where capability_code=v_saga_cap and version='1.0.0'
      and release_state='RELEASED' and manifest_sha256=v_saga_manifest
  ) then raise exception 'BLOCK_D3_SAGA_VERSION_DRIFT'; end if;

  if not exists (
    select 1 from public.lf_capability_current
    where capability_code='DB_WRITE_TRANSPORT' and version='1.0.0'
  ) then raise exception 'BLOCK_D3_DB_WRITE_TRANSPORT_NOT_CURRENT'; end if;

  if not exists (
    select 1 from public.lf_capability_current
    where capability_code='MIGRATION_SOURCE_PARITY' and version='1.0.0'
  ) then raise exception 'BLOCK_D3_MIGRATION_SOURCE_PARITY_NOT_CURRENT'; end if;

  -- Idempotent replay is allowed only if an existing pointer is exactly the intended one.
  if exists (
    select 1 from public.lf_capability_current
    where capability_code=v_wa_cap
      and (version<>'1.0.0' or manifest_sha256<>v_wa_manifest)
  ) then raise exception 'BLOCK_D3_WRITE_AHEAD_CURRENT_DRIFT'; end if;

  if exists (
    select 1 from public.lf_capability_current
    where capability_code=v_saga_cap
      and (version<>'1.0.0' or manifest_sha256<>v_saga_manifest)
  ) then raise exception 'BLOCK_D3_SAGA_CURRENT_DRIFT'; end if;

  v_orch:=public.fn_lf_operation_reserve_execution_v1(
    v_orch_id,'ORQUESTACION_PIPELINE_LF',
    'CAPABILITY_GOVERNED_ACTIVATION','MIGRATION_APPLICATOR:D3',
    'migration-capability-activation-orch-20261005-v1',v_orch_request,v_orch_id,
    null,null,
    jsonb_build_object(
      'purpose','MIGRATION_CAPABILITY_GOVERNED_ACTIVATION',
      'owner_decision','D3',
      'capabilities',jsonb_build_array(v_wa_cap,v_saga_cap),
      'runtime_deploy_effect',false,
      'production_activation',false
    )
  );
  if coalesce(v_orch->>'result','') not in ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') then
    raise exception 'BLOCK_D3_ORCH_RESERVE:%',v_orch::text;
  end if;

  -- Write-Ahead: consumer -> dispatch -> guard accepted -> promote -> guarded bind.
  v_cons:=public.fn_lf_operation_reserve_execution_v1(
    v_wa_id,'GITHUB_CONTRACT_GATE_LF',
    'CAPABILITY_GOVERNED_ACTIVATION','MIGRATION_APPLICATOR:D3:WRITE_AHEAD',
    'migration-write-ahead-activate-20261005-v1',v_wa_request,v_orch_id,
    null,null,
    jsonb_build_object(
      'orchestrator_execution_id',v_orch_id,
      'plan_digest',v_wa_plan,
      'capability_code',v_wa_cap,
      'owner_decision','D3',
      'mode','CURRENT_POINTER_AND_GUARDED_BINDING_ONLY',
      'production_activation',false
    )
  );
  if coalesce(v_cons->>'result','') not in ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') then
    raise exception 'BLOCK_D3_WRITE_AHEAD_CONSUMER_RESERVE:%',v_cons::text;
  end if;

  v_receipt:=public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orch_id,v_wa_id,v_wa_cap,v_wa_plan,
    jsonb_build_object(
      'purpose','D3_CURRENT_POINTER_ACTIVATION',
      'capability_code',v_wa_cap,
      'owner_decision','D3',
      'production_activation',false
    ),
    v_orch_id
  );
  if coalesce((v_receipt->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_D3_WRITE_AHEAD_DISPATCH:%',v_receipt::text;
  end if;
  v_receipt_id:=(v_receipt->>'receipt_id')::uuid;

  v_guard:=public.fn_lf_capability_orchestrator_entry_guard_v1(
    v_wa_id,v_wa_cap,v_wa_plan,v_receipt_id
  );
  if coalesce((v_guard->>'ready')::boolean,false) is not true
     or v_guard->>'decision'<>'ORCHESTRATOR_ENTRY_ACCEPTED' then
    raise exception 'BLOCK_D3_WRITE_AHEAD_GUARD:%',v_guard::text;
  end if;

  v_promote:=public.fn_lf_capability_promote_v1(
    v_wa_cap,'1.0.0',v_wa_manifest,v_wa_id,
    'Owner D3 approved guarded current-pointer activation for the single migration applicator; no production deploy.'
  );
  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_D3_WRITE_AHEAD_PROMOTE:%',v_promote::text;
  end if;

  v_bind:=public.fn_lf_capability_bind_from_orchestrator_v1(
    v_wa_id,v_wa_cap,v_wa_manifest,v_wa_plan,v_receipt_id,v_wa_id
  );
  if coalesce((v_bind->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_D3_WRITE_AHEAD_BIND:%',v_bind::text;
  end if;

  if not exists (
    select 1
    from public.lf_capability_binding b
    join public.lf_capability_current c using(capability_code)
    where b.execution_id=v_wa_id and b.capability_code=v_wa_cap
      and b.binding_state='BOUND'
      and b.bound_version='1.0.0'
      and b.bound_manifest_sha256=v_wa_manifest
      and c.version='1.0.0'
      and c.manifest_sha256=v_wa_manifest
  ) then raise exception 'BLOCK_D3_WRITE_AHEAD_BIND_READBACK'; end if;

  update public.lf_activos
  set metadata=jsonb_set(
        coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
          'registry_cutover_state','CURRENT_GUARDED',
          'activation_state','OWNER_D3_CURRENT_POINTER_ACTIVE',
          'activation_execution_id',v_wa_id,
          'activation_owner','Paulo',
          'runtime_deploy_effect',false,
          'production_activation',false
        ),
        '{entry_contract}',
        coalesce(metadata->'entry_contract','{}'::jsonb) || jsonb_build_object(
          'enforcement_state','ENFORCED_CURRENT',
          'updated_by_execution_id',v_wa_id
        ),
        true
      ),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_wa_id
  where codigo_activo=v_wa_cap and archived_at is null;
  if not found then raise exception 'BLOCK_D3_WRITE_AHEAD_ASSET_MISSING'; end if;

  -- Saga depends on Write-Ahead being current before its own promotion.
  if not exists (
    select 1 from public.lf_capability_current
    where capability_code=v_wa_cap and version='1.0.0' and manifest_sha256=v_wa_manifest
  ) then raise exception 'BLOCK_D3_SAGA_WRITE_AHEAD_DEPENDENCY_NOT_CURRENT'; end if;

  v_cons:=public.fn_lf_operation_reserve_execution_v1(
    v_saga_id,'GITHUB_CONTRACT_GATE_LF',
    'CAPABILITY_GOVERNED_ACTIVATION','MIGRATION_APPLICATOR:D3:SAGA',
    'migration-saga-activate-20261005-v1',v_saga_request,v_orch_id,
    null,null,
    jsonb_build_object(
      'orchestrator_execution_id',v_orch_id,
      'plan_digest',v_saga_plan,
      'capability_code',v_saga_cap,
      'owner_decision','D3',
      'mode','CURRENT_POINTER_AND_GUARDED_BINDING_ONLY',
      'production_activation',false
    )
  );
  if coalesce(v_cons->>'result','') not in ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') then
    raise exception 'BLOCK_D3_SAGA_CONSUMER_RESERVE:%',v_cons::text;
  end if;

  v_receipt:=public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orch_id,v_saga_id,v_saga_cap,v_saga_plan,
    jsonb_build_object(
      'purpose','D3_CURRENT_POINTER_ACTIVATION',
      'capability_code',v_saga_cap,
      'owner_decision','D3',
      'production_activation',false
    ),
    v_orch_id
  );
  if coalesce((v_receipt->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_D3_SAGA_DISPATCH:%',v_receipt::text;
  end if;
  v_receipt_id:=(v_receipt->>'receipt_id')::uuid;

  v_guard:=public.fn_lf_capability_orchestrator_entry_guard_v1(
    v_saga_id,v_saga_cap,v_saga_plan,v_receipt_id
  );
  if coalesce((v_guard->>'ready')::boolean,false) is not true
     or v_guard->>'decision'<>'ORCHESTRATOR_ENTRY_ACCEPTED' then
    raise exception 'BLOCK_D3_SAGA_GUARD:%',v_guard::text;
  end if;

  v_promote:=public.fn_lf_capability_promote_v1(
    v_saga_cap,'1.0.0',v_saga_manifest,v_saga_id,
    'Owner D3 approved guarded current-pointer activation for the single migration applicator; no production deploy.'
  );
  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_D3_SAGA_PROMOTE:%',v_promote::text;
  end if;

  v_bind:=public.fn_lf_capability_bind_from_orchestrator_v1(
    v_saga_id,v_saga_cap,v_saga_manifest,v_saga_plan,v_receipt_id,v_saga_id
  );
  if coalesce((v_bind->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_D3_SAGA_BIND:%',v_bind::text;
  end if;

  if not exists (
    select 1
    from public.lf_capability_binding b
    join public.lf_capability_current c using(capability_code)
    where b.execution_id=v_saga_id and b.capability_code=v_saga_cap
      and b.binding_state='BOUND'
      and b.bound_version='1.0.0'
      and b.bound_manifest_sha256=v_saga_manifest
      and c.version='1.0.0'
      and c.manifest_sha256=v_saga_manifest
  ) then raise exception 'BLOCK_D3_SAGA_BIND_READBACK'; end if;

  update public.lf_activos
  set metadata=jsonb_set(
        coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
          'registry_cutover_state','CURRENT_GUARDED',
          'activation_state','OWNER_D3_CURRENT_POINTER_ACTIVE',
          'activation_execution_id',v_saga_id,
          'activation_owner','Paulo',
          'runtime_deploy_effect',false,
          'production_activation',false
        ),
        '{entry_contract}',
        coalesce(metadata->'entry_contract','{}'::jsonb) || jsonb_build_object(
          'enforcement_state','ENFORCED_CURRENT',
          'updated_by_execution_id',v_saga_id
        ),
        true
      ),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_saga_id
  where codigo_activo=v_saga_cap and archived_at is null;
  if not found then raise exception 'BLOCK_D3_SAGA_ASSET_MISSING'; end if;

  update public.lf_operation_execution
  set status='COMPLETED',
      completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object(
        'schema_version','LF_MIGRATION_CAPABILITY_ACTIVATION_RECEIPT_V1',
        'capability_code',v_wa_cap,
        'current_version','1.0.0',
        'current_manifest_sha256',v_wa_manifest,
        'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
        'owner_decision','D3',
        'production_activation',false
      ),
      updated_by_execution_id=v_wa_id,
      updated_at=clock_timestamp()
  where execution_id=v_wa_id;

  update public.lf_operation_execution
  set status='COMPLETED',
      completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object(
        'schema_version','LF_MIGRATION_CAPABILITY_ACTIVATION_RECEIPT_V1',
        'capability_code',v_saga_cap,
        'current_version','1.0.0',
        'current_manifest_sha256',v_saga_manifest,
        'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
        'owner_decision','D3',
        'production_activation',false
      ),
      updated_by_execution_id=v_saga_id,
      updated_at=clock_timestamp()
  where execution_id=v_saga_id;

  update public.lf_operation_execution
  set status='COMPLETED',
      completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object(
        'schema_version','LF_MIGRATION_CAPABILITY_ORCHESTRATION_RECEIPT_V1',
        'owner_decision','D3',
        'capabilities',jsonb_build_array(v_wa_cap,v_saga_cap),
        'current_pointer_activation',true,
        'guarded_binding_evidence',true,
        'production_activation',false
      ),
      updated_by_execution_id=v_orch_id,
      updated_at=clock_timestamp()
  where execution_id=v_orch_id;

  if not exists (
    select 1 from public.lf_capability_current
    where capability_code=v_wa_cap and version='1.0.0' and manifest_sha256=v_wa_manifest
  ) then raise exception 'BLOCK_D3_WRITE_AHEAD_FINAL_CURRENT_READBACK'; end if;

  if not exists (
    select 1 from public.lf_capability_current
    where capability_code=v_saga_cap and version='1.0.0' and manifest_sha256=v_saga_manifest
  ) then raise exception 'BLOCK_D3_SAGA_FINAL_CURRENT_READBACK'; end if;
end
$activate$;
