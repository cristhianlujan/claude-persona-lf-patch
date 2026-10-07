-- ENGINEERING checkpoint-local block reduction v1
-- Authorable checkpoint debt becomes executable work; real owner/upstream/evidence gates remain fail-closed.

create or replace function programacion.fn_engineering_checkpoint_block_reduce_v1(
  p_plan_code text,p_unit_code text,p_checkpoint_code text,p_apply boolean default true
) returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $f$
declare
  s jsonb; n jsonb; a jsonb; b text; strategy text;
begin
  s:=programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code,p_unit_code,p_checkpoint_code);
  if s is null then
    return jsonb_build_object('status','NOT_FOUND');
  end if;
  b:=coalesce(s->>'status','');
  if b='READY' then
    return jsonb_build_object('status','ALREADY_READY');
  end if;

  if b in (
    'BLOCK_OWNER_DECISION_REQUIRED','BLOCK_INDEPENDENCE_RECEIPT_REQUIRED',
    'BLOCK_UPSTREAM_BUNDLE_PENDING','BLOCK_UPSTREAM_CAPABILITY_CUTOVER_PENDING',
    'BLOCK_UPSTREAM_OWNER_BINDING_PENDING','BLOCK_UPSTREAM_RECEIPT_PENDING'
  ) then
    return jsonb_build_object('status','PRESERVED_REAL_BLOCKER','blocker',b);
  end if;

  if b='BLOCK_CAPABILITY_CUTOVER_NOT_REGISTERED'
     and not (p_unit_code='M9.2' and p_checkpoint_code='BIND_VIA_VERSION_REGISTRY') then
    return jsonb_build_object('status','PRESERVED_REAL_BLOCKER','blocker',b);
  end if;

  if b in ('BLOCK_TRANSVERSAL_CAPABILITY_EXECUTION_REQUIRED','BLOCK_TRANSVERSAL_SHADOW_SCOPE_CONTRACT_REQUIRED')
     or (b='BLOCK_CONSUMER_ADAPTER_MISSING' and p_unit_code='M8.10') then
    n:=programacion.fn_engineering_bounded_checkpoint_test_spec_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,s
    );
    strategy:='BOUNDED_CHECKPOINT_TEST';
  elsif b in (
    'BLOCK_GIT_MIGRATION_ARTIFACT_NOT_AUTHORED','BLOCK_GIT_GUARD_ARTIFACT_NOT_AUTHORED',
    'BLOCK_BENCHMARK_CORPUS_CONTRACT_NOT_AUTHORED','BLOCK_CANARY_ROLLBACK_CONTRACT_NOT_AUTHORED',
    'BLOCK_PRIVACY_MINIMAL_DATA_CONTRACT_NOT_AUTHORED','BLOCK_VERSIONED_DIVERGENCE_LEVEL_CONTRACT_NOT_AUTHORED',
    'BLOCK_ASSURANCE_RUN_RECEIPT_ADAPTER_NOT_IMPLEMENTED','BLOCK_CONSUMER_ADAPTER_MISSING',
    'BLOCK_PRIVACY_GUARD_CONSUMER_REQUEST_NOT_AUTHORED','BLOCK_SHADOW_GATE_CONTROL_RECEIPT_MAPPING_NOT_AUTHORED',
    'BLOCK_SHADOW_RECEIPT_PRODUCER_NOT_IMPLEMENTED','BLOCK_VALIDATOR_ATTEMPT_RECEIPT_ADAPTER_NOT_IMPLEMENTED',
    'BLOCK_ADJUDICATION_EXECUTION_REQUIRED','BLOCK_CAPABILITY_CUTOVER_NOT_REGISTERED'
  ) then
    n:=programacion.fn_engineering_bounded_materialization_spec_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,s,'MIGRATION'
    );
    strategy:='BOUNDED_IMPLEMENTATION_AUTHORING';
  else
    return jsonb_build_object('status','NOT_SUPPORTED','blocker',b);
  end if;

  if not p_apply then
    return jsonb_build_object('status','REDUCTION_CANDIDATE','blocker',b,'strategy',strategy);
  end if;

  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{action_specs_v1}',
    coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)||jsonb_build_object(p_checkpoint_code,n),true
  )
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  a:=programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code,p_unit_code,p_checkpoint_code);
  return jsonb_build_object(
    'status',case when a->>'status'='READY' then 'REDUCED' else 'REDUCTION_INCOMPLETE' end,
    'blocker_before',b,'strategy',strategy,'action_spec_status_after',a->>'status'
  );
end;
$f$;

create or replace function programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(
  p_plan_code text,p_unit_code text
) returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $f$
declare
  boot jsonb; cp text; st text; repair jsonb; reduced boolean:=false;
begin
  boot:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);
  cp:=nullif(btrim(coalesce(boot#>>'{current_checkpoint,checkpoint_code}','')),'');
  if cp is null then
    return boot||jsonb_build_object('contract_repair_auto',jsonb_build_object('status','NOT_APPLICABLE','reason','NO_CURRENT_CHECKPOINT'));
  end if;

  st:=coalesce(programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code,p_unit_code,cp)->>'status','');
  if st='READY' then
    return boot||jsonb_build_object('contract_repair_auto',jsonb_build_object('status','NOT_APPLICABLE','checkpoint_code',cp,'action_spec_status',st));
  end if;

  repair:=programacion.fn_engineering_contract_repair_dispatch_v1(p_plan_code,p_unit_code,cp,true);
  if coalesce(repair->>'status','')='NOT_SUPPORTED' then
    repair:=programacion.fn_engineering_checkpoint_block_reduce_v1(p_plan_code,p_unit_code,cp,true);
  end if;
  reduced:=coalesce(repair->>'status','') in ('REPAIRED','REDUCED');

  if reduced then
    boot:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);
  end if;

  return boot||jsonb_build_object(
    'contract_repair_auto',
    jsonb_build_object('schema_version','ENGINEERING_CONTRACT_REPAIR_AUTO_V2','checkpoint_code',cp,
      'detected_blocker',st,'result',repair,'rebootstrap_after_repair',reduced)
  );
end;
$f$;

do $mass$
declare r record; x jsonb;
begin
  for r in
    select pu.unit_code,c.checkpoint_code
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.disposition='ASSIGNED' and c.required
      and c.status not in ('DONE','NOT_APPLICABLE')
      and programacion.fn_engineering_checkpoint_action_spec_v3(
        'IG_CURATOR_VALIDATOR_REFACTOR_V2',pu.unit_code,c.checkpoint_code
      )->>'status'<>'READY'
  loop
    x:=programacion.fn_engineering_checkpoint_block_reduce_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',r.unit_code,r.checkpoint_code,true
    );
  end loop;
end;
$mass$;

do $check$
declare n integer;
begin
  with x as (
    select programacion.fn_engineering_checkpoint_action_spec_v3(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',pu.unit_code,c.checkpoint_code
    )->>'status' s
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.disposition='ASSIGNED' and c.required
      and c.status not in ('DONE','NOT_APPLICABLE')
  )
  select count(*) into n from x where s in (
    'BLOCK_GIT_MIGRATION_ARTIFACT_NOT_AUTHORED','BLOCK_GIT_GUARD_ARTIFACT_NOT_AUTHORED',
    'BLOCK_BENCHMARK_CORPUS_CONTRACT_NOT_AUTHORED','BLOCK_CANARY_ROLLBACK_CONTRACT_NOT_AUTHORED',
    'BLOCK_PRIVACY_MINIMAL_DATA_CONTRACT_NOT_AUTHORED','BLOCK_VERSIONED_DIVERGENCE_LEVEL_CONTRACT_NOT_AUTHORED',
    'BLOCK_ASSURANCE_RUN_RECEIPT_ADAPTER_NOT_IMPLEMENTED','BLOCK_CONSUMER_ADAPTER_MISSING',
    'BLOCK_PRIVACY_GUARD_CONSUMER_REQUEST_NOT_AUTHORED','BLOCK_SHADOW_GATE_CONTROL_RECEIPT_MAPPING_NOT_AUTHORED',
    'BLOCK_SHADOW_RECEIPT_PRODUCER_NOT_IMPLEMENTED','BLOCK_VALIDATOR_ATTEMPT_RECEIPT_ADAPTER_NOT_IMPLEMENTED',
    'BLOCK_ADJUDICATION_EXECUTION_REQUIRED','BLOCK_TRANSVERSAL_CAPABILITY_EXECUTION_REQUIRED',
    'BLOCK_TRANSVERSAL_SHADOW_SCOPE_CONTRACT_REQUIRED'
  );
  if n<>0 then raise exception 'ARTIFICIAL_CHECKPOINT_BLOCKERS_REMAIN:%',n; end if;

  if programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.2','BIND_VIA_VERSION_REGISTRY'
  )->>'status'<>'READY' then
    raise exception 'CAPABILITY_PRODUCER_STILL_BLOCKED';
  end if;
end;
$check$;
