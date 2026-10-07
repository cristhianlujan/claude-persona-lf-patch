-- ENGINEERING material assertion binding v1
-- Persist machine-verifiable assertion receipts on the canonical checkpoint row
-- and enforce them at the storage boundary for every future material DONE.

alter table programacion.engineering_work_checkpoints
  add column if not exists assertion_contract_sha256 text,
  add column if not exists assertion_receipt jsonb,
  add column if not exists assertion_receipt_sha256 text,
  add column if not exists assertion_recorded_at timestamptz,
  add column if not exists assertion_recorded_by text;

do $ddl$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid='programacion.engineering_work_checkpoints'::regclass
      and conname='engineering_work_checkpoints_assertion_contract_sha_ck'
  ) then
    alter table programacion.engineering_work_checkpoints
      add constraint engineering_work_checkpoints_assertion_contract_sha_ck
      check (
        assertion_contract_sha256 is null
        or assertion_contract_sha256 ~ '^[0-9a-f]{64}$'
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid='programacion.engineering_work_checkpoints'::regclass
      and conname='engineering_work_checkpoints_assertion_receipt_sha_ck'
  ) then
    alter table programacion.engineering_work_checkpoints
      add constraint engineering_work_checkpoints_assertion_receipt_sha_ck
      check (
        assertion_receipt_sha256 is null
        or assertion_receipt_sha256 ~ '^[0-9a-f]{64}$'
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid='programacion.engineering_work_checkpoints'::regclass
      and conname='engineering_work_checkpoints_assertion_receipt_object_ck'
  ) then
    alter table programacion.engineering_work_checkpoints
      add constraint engineering_work_checkpoints_assertion_receipt_object_ck
      check (
        assertion_receipt is null
        or jsonb_typeof(assertion_receipt)='object'
      );
  end if;
end;
$ddl$;

create or replace function programacion.fn_engineering_action_spec_assertion_contract_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_spec jsonb := coalesce(p_spec,'{}'::jsonb);
  v_material boolean := coalesce((v_spec->>'requires_material_execution')::boolean,false);
  v_kind text := coalesce(v_spec->>'action_kind','');
  v_explicit jsonb := v_spec->'assertion_contract';
  v_result_contract jsonb;
  v_exec jsonb;
  v_code text;
  v_current_version text;
  v_current_manifest_sha text;
  v_validator_ref text;
  v_output_schema text;
  v_pass_when jsonb;
begin
  if coalesce(v_spec->>'status','')<>'READY' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
      'status','BLOCK_ACTION_SPEC_NOT_READY',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code
    );
  end if;

  if not v_material then
    return jsonb_build_object(
      'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
      'status','NOT_REQUIRED',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'reason','NON_MATERIAL_CHECKPOINT'
    );
  end if;

  if jsonb_typeof(v_explicit)='object' then
    v_pass_when:=v_explicit->'pass_when';
    if jsonb_typeof(v_pass_when)<>'object' then
      return jsonb_build_object(
        'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
        'status','BLOCK_ASSERTION_CONTRACT_INCOMPLETE',
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'reason','PASS_WHEN_OBJECT_REQUIRED',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',p_checkpoint_code
      );
    end if;

    return jsonb_build_object(
      'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
      'status','READY',
      'mode',coalesce(nullif(v_explicit->>'mode',''),'EXPLICIT_PASS_WHEN_SUBSET'),
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'expected_status','PASS',
      'pass_when',v_pass_when
    );
  end if;

  if v_kind='DECLARED_CAPABILITY_TEST_EXECUTION' then
    v_result_contract:=v_spec#>'{capability_execution,result_contract}';
    v_pass_when:=v_result_contract->'pass_when';

    if jsonb_typeof(v_result_contract)<>'object'
       or nullif(btrim(coalesce(v_result_contract->>'test_code','')),'') is null
       or jsonb_typeof(v_pass_when)<>'object' then
      return jsonb_build_object(
        'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
        'status','BLOCK_ASSERTION_CONTRACT_INCOMPLETE',
        'mode','CAPABILITY_TEST_RESULT_CONTRACT',
        'reason','EXACT_TEST_CODE_AND_PASS_WHEN_REQUIRED',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',p_checkpoint_code
      );
    end if;

    return jsonb_strip_nulls(jsonb_build_object(
      'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
      'status','READY',
      'mode','CAPABILITY_TEST_RESULT_CONTRACT',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'expected_status','PASS',
      'test_code',v_result_contract->>'test_code',
      'suite_code',nullif(v_result_contract->>'suite_code',''),
      'pass_when',v_pass_when
    ));
  end if;

  if v_kind='TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION' then
    v_exec:=coalesce(v_spec->'capability_execution','{}'::jsonb);
    v_code:=nullif(btrim(coalesce(v_exec->>'capability_code','')),'');

    select c.version,c.manifest_sha256,v.validator_ref,v.manifest#>>'{contract,output}'
      into v_current_version,v_current_manifest_sha,v_validator_ref,v_output_schema
    from public.lf_capability_current c
    join public.lf_capability_version_registry v
      on v.capability_code=c.capability_code
     and v.version=c.version
     and v.release_state='RELEASED'
    where c.capability_code=v_code;

    if v_code is null
       or v_current_version is null
       or v_current_manifest_sha is null
       or nullif(btrim(coalesce(v_validator_ref,'')),'') is null
       or nullif(btrim(coalesce(v_output_schema,'')),'') is null
       or coalesce((v_exec->>'result_evidence_required')::boolean,false)=false then
      return jsonb_build_object(
        'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
        'status','BLOCK_ASSERTION_CONTRACT_INCOMPLETE',
        'mode','REPOSITORY_CAPABILITY_VALIDATED_OUTPUT',
        'reason','CURRENT_RELEASE_OUTPUT_VALIDATOR_AND_RESULT_EVIDENCE_REQUIRED',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',p_checkpoint_code,
        'capability_code',v_code
      );
    end if;

    if v_exec->>'current_version' is distinct from v_current_version
       or v_exec->>'manifest_sha256' is distinct from v_current_manifest_sha then
      return jsonb_build_object(
        'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
        'status','BLOCK_ASSERTION_CONTRACT_STALE_CAPABILITY',
        'mode','REPOSITORY_CAPABILITY_VALIDATED_OUTPUT',
        'reason','ACTION_SPEC_CAPABILITY_CURRENTNESS_MISMATCH',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',p_checkpoint_code,
        'capability_code',v_code,
        'expected_version',v_current_version,
        'expected_manifest_sha256',v_current_manifest_sha
      );
    end if;

    return jsonb_build_object(
      'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
      'status','READY',
      'mode','REPOSITORY_CAPABILITY_VALIDATED_OUTPUT',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'expected_status','PASS',
      'expected_validator_status','PASS',
      'capability_code',v_code,
      'version',v_current_version,
      'manifest_sha256',v_current_manifest_sha,
      'result_schema',v_output_schema,
      'validator_ref',v_validator_ref
    );
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
    'status','BLOCK_ASSERTION_CONTRACT_REQUIRED',
    'mode','UNBOUND_MATERIAL_RESULT',
    'reason','MATERIAL_DONE_REQUIRES_MACHINE_VERIFIABLE_ASSERTION_BINDING',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'action_kind',v_kind
  );
end;
$function$;

comment on function programacion.fn_engineering_action_spec_assertion_contract_v1(text,text,text,jsonb)
is 'Derives a machine-verifiable material-result contract from explicit pass_when, capability test result_contract, or current released repository capability output+validator authority.';

create or replace function programacion.fn_engineering_checkpoint_assertion_record_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_result jsonb,
  p_actor text
)
returns jsonb
language plpgsql
security definer
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
  v_checkpoint_id bigint;
  v_current_code text;
  v_spec jsonb;
  v_contract jsonb;
  v_contract_sha text;
  v_mode text;
  v_pass boolean := false;
  v_pass_when jsonb;
  v_result_sha text;
  v_evidence_ref text;
  v_recorded_at timestamptz := clock_timestamp();
  v_receipt jsonb;
  v_receipt_sha text;
begin
  if jsonb_typeof(p_result)<>'object' then
    raise exception 'ENGINEERING_ASSERTION_RESULT_OBJECT_REQUIRED:%/%/%',
      p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  select pu.work_item_id
    into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    raise exception 'ENGINEERING_ASSERTION_UNIT_NOT_FOUND:%/%',p_plan_code,p_unit_code;
  end if;

  select c.id
    into v_checkpoint_id
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.checkpoint_code=p_checkpoint_code
  for update;

  if v_checkpoint_id is null then
    raise exception 'ENGINEERING_ASSERTION_CHECKPOINT_NOT_FOUND:%/%/%',
      p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  select c.checkpoint_code
    into v_current_code
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no
  limit 1;

  if v_current_code is distinct from p_checkpoint_code then
    raise exception 'ENGINEERING_ASSERTION_CHECKPOINT_NOT_CURRENT:% current=%',
      p_checkpoint_code,coalesce(v_current_code,'<terminal>');
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code
  );
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_spec
  );

  if coalesce(v_contract->>'status','')<>'READY' then
    raise exception 'ENGINEERING_ASSERTION_CONTRACT_NOT_READY:%',
      coalesce(v_contract::text,'{}');
  end if;

  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract);
  v_mode:=v_contract->>'mode';

  if v_mode='CAPABILITY_TEST_RESULT_CONTRACT' then
    v_pass_when:=v_contract->'pass_when';
    v_evidence_ref:=nullif(btrim(coalesce(p_result->>'evidence_ref','')),'');
    v_pass :=
      p_result->>'status'='PASS'
      and p_result->>'test_code'=v_contract->>'test_code'
      and (
        v_contract->>'suite_code' is null
        or p_result->>'suite_code'=v_contract->>'suite_code'
      )
      and jsonb_typeof(p_result->'observed')='object'
      and (p_result->'observed') @> v_pass_when
      and v_evidence_ref is not null;

  elsif v_mode='REPOSITORY_CAPABILITY_VALIDATED_OUTPUT' then
    v_evidence_ref:=nullif(btrim(coalesce(p_result->>'validator_evidence_ref','')),'');
    v_pass :=
      p_result->>'status'='PASS'
      and p_result->>'validator_status'='PASS'
      and p_result->>'capability_code'=v_contract->>'capability_code'
      and p_result->>'version'=v_contract->>'version'
      and p_result->>'manifest_sha256'=v_contract->>'manifest_sha256'
      and p_result->>'result_schema'=v_contract->>'result_schema'
      and p_result->>'validator_ref'=v_contract->>'validator_ref'
      and v_evidence_ref is not null;

  elsif v_mode='EXPLICIT_PASS_WHEN_SUBSET' then
    v_pass_when:=v_contract->'pass_when';
    v_evidence_ref:=nullif(btrim(coalesce(p_result->>'evidence_ref','')),'');
    v_pass :=
      p_result->>'status'='PASS'
      and jsonb_typeof(p_result->'observed')='object'
      and (p_result->'observed') @> v_pass_when
      and v_evidence_ref is not null;
  else
    raise exception 'ENGINEERING_ASSERTION_MODE_UNSUPPORTED:%',v_mode;
  end if;

  if not v_pass then
    raise exception 'ENGINEERING_ASSERTION_RESULT_FAILED:%/%/% mode=%',
      p_plan_code,p_unit_code,p_checkpoint_code,v_mode;
  end if;

  v_result_sha:=programacion.fn_v09_sha256_jsonb(p_result);

  v_receipt:=jsonb_build_object(
    'schema_version','ENGINEERING_CHECKPOINT_ASSERTION_RECEIPT_V1',
    'passed',true,
    'mode',v_mode,
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'contract_sha256',v_contract_sha,
    'result_sha256',v_result_sha,
    'evidence_ref',v_evidence_ref,
    'recorded_at',v_recorded_at,
    'recorded_by',coalesce(nullif(btrim(p_actor),''),'ENGINEERING_ASSERTION_RECORDER')
  );
  v_receipt_sha:=programacion.fn_v09_sha256_jsonb(v_receipt);

  update programacion.engineering_work_checkpoints
     set assertion_contract_sha256=v_contract_sha,
         assertion_receipt=v_receipt,
         assertion_receipt_sha256=v_receipt_sha,
         assertion_recorded_at=v_recorded_at,
         assertion_recorded_by=coalesce(nullif(btrim(p_actor),''),'ENGINEERING_ASSERTION_RECORDER'),
         updated_at=now(),
         updated_by_execution_id=coalesce(nullif(btrim(p_actor),''),'ENGINEERING_ASSERTION_RECORDER')
   where id=v_checkpoint_id;

  return v_receipt || jsonb_build_object(
    'assertion_receipt_sha256',v_receipt_sha
  );
end;
$function$;

comment on function programacion.fn_engineering_checkpoint_assertion_record_v1(text,text,text,jsonb,text)
is 'Records a PASS assertion receipt for the current material checkpoint only after exact machine-verifiable result binding succeeds.';

revoke all on function programacion.fn_engineering_checkpoint_assertion_record_v1(text,text,text,jsonb,text) from public;
revoke execute on function programacion.fn_engineering_checkpoint_assertion_record_v1(text,text,text,jsonb,text) from anon;
revoke execute on function programacion.fn_engineering_checkpoint_assertion_record_v1(text,text,text,jsonb,text) from authenticated;
grant execute on function programacion.fn_engineering_checkpoint_assertion_record_v1(text,text,text,jsonb,text) to service_role;
grant execute on function programacion.fn_engineering_checkpoint_assertion_record_v1(text,text,text,jsonb,text) to postgres;

create or replace function programacion.fn_guard_engineering_material_checkpoint_done_v1()
returns trigger
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_plan_code text;
  v_unit_code text;
  v_spec jsonb;
  v_contract jsonb;
  v_contract_sha text;
begin
  if new.status is distinct from 'DONE'
     or old.status='DONE' then
    return new;
  end if;

  select pu.plan_code,pu.unit_code
    into v_plan_code,v_unit_code
  from programacion.engineering_plan_units pu
  where pu.work_item_id=new.work_item_id
    and pu.disposition='ASSIGNED';

  if v_plan_code is null then
    raise exception 'ENGINEERING_CHECKPOINT_PLAN_UNIT_NOT_FOUND:work_item_id=%',new.work_item_id;
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    v_plan_code,v_unit_code,new.checkpoint_code
  );

  if not coalesce((v_spec->>'requires_material_execution')::boolean,false) then
    return new;
  end if;

  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    v_plan_code,v_unit_code,new.checkpoint_code,v_spec
  );

  if coalesce(v_contract->>'status','')<>'READY' then
    raise exception 'ENGINEERING_MATERIAL_ASSERTION_CONTRACT_REQUIRED:%',
      coalesce(v_contract::text,'{}');
  end if;

  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract);

  if new.assertion_receipt is null
     or new.assertion_contract_sha256 is distinct from v_contract_sha
     or new.assertion_receipt->>'contract_sha256' is distinct from v_contract_sha
     or coalesce((new.assertion_receipt->>'passed')::boolean,false)=false
     or new.assertion_receipt_sha256 is null
     or new.assertion_receipt_sha256 is distinct from
        programacion.fn_v09_sha256_jsonb(new.assertion_receipt)
     or new.assertion_recorded_at is null then
    raise exception 'ENGINEERING_MATERIAL_ASSERTION_RECEIPT_REQUIRED:%/%/%',
      v_plan_code,v_unit_code,new.checkpoint_code;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_engineering_material_checkpoint_done_guard_v1
  on programacion.engineering_work_checkpoints;

create trigger trg_engineering_material_checkpoint_done_guard_v1
before update of status on programacion.engineering_work_checkpoints
for each row
execute function programacion.fn_guard_engineering_material_checkpoint_done_v1();

comment on function programacion.fn_guard_engineering_material_checkpoint_done_v1()
is 'Storage-boundary fail-closed guard: future material checkpoint DONE requires a current machine-verifiable assertion receipt whose contract digest still matches the freshly compiled Action Spec.';
