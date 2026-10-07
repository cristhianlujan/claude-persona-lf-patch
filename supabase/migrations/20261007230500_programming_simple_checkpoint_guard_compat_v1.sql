-- PROGRAMMING_SIMPLE_EXECUTOR_V1 checkpoint guard compatibility.
-- Explicit simple-executor bindings use their own current-run validation contract.
-- All other checkpoints keep the existing Engineering material assertion guard unchanged.

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
  v_binding programacion.programming_checkpoint_bindings%rowtype;
  v_admission jsonb;
  v_receipt_run_id bigint;
  v_simple_receipt_sha text;
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

  select *
    into v_binding
  from programacion.programming_checkpoint_bindings b
  where b.plan_code=v_plan_code
    and b.unit_code=v_unit_code
    and b.checkpoint_code=new.checkpoint_code
    and b.enabled;

  if found then
    v_admission:=programacion.fn_programming_rule_admission_v1(
      v_binding.validation_code,
      v_binding.failure_code
    );

    if not coalesce((v_admission->>'admitted')::boolean,false) then
      raise exception 'PROGRAMMING_SIMPLE_CHECKPOINT_RULE_NOT_ADMITTED:%/%/%',
        v_plan_code,v_unit_code,new.checkpoint_code;
    end if;

    if coalesce(jsonb_typeof(new.assertion_receipt),'')<>'object'
       or coalesce(new.assertion_receipt->>'schema_version','')<>'PROGRAMMING_VALIDATION_RECEIPT_V1'
       or coalesce(new.assertion_receipt->>'result','')<>'PASS'
       or coalesce(new.assertion_receipt->>'plan_code','')<>v_plan_code
       or coalesce(new.assertion_receipt->>'unit_code','')<>v_unit_code
       or coalesce(new.assertion_receipt->>'checkpoint_code','')<>new.checkpoint_code
       or coalesce(new.assertion_receipt->>'validation_code','')<>v_binding.validation_code
       or coalesce(jsonb_typeof(new.assertion_receipt->'run_id'),'')<>'number'
       or new.assertion_receipt_sha256 is null
       or new.assertion_recorded_at is null then
      raise exception 'PROGRAMMING_SIMPLE_CURRENT_VALIDATION_RECEIPT_REQUIRED:%/%/%',
        v_plan_code,v_unit_code,new.checkpoint_code;
    end if;

    v_receipt_run_id:=(new.assertion_receipt->>'run_id')::bigint;
    v_simple_receipt_sha:=encode(
      extensions.digest(convert_to(new.assertion_receipt::text,'UTF8'),'sha256'),
      'hex'
    );

    if new.assertion_receipt_sha256 is distinct from v_simple_receipt_sha then
      raise exception 'PROGRAMMING_SIMPLE_VALIDATION_RECEIPT_HASH_MISMATCH:%/%/%',
        v_plan_code,v_unit_code,new.checkpoint_code;
    end if;

    if not exists (
      select 1
      from programacion.programming_simple_runs r
      join programacion.programming_simple_run_units ru
        on ru.run_id=r.id
      where r.id=v_receipt_run_id
        and r.plan_code=v_plan_code
        and r.status='RUNNING'
        and ru.plan_code=v_plan_code
        and ru.unit_code=v_unit_code
        and ru.status='RUNNING'
    ) then
      raise exception 'PROGRAMMING_SIMPLE_ACTIVE_RUN_RECEIPT_REQUIRED:%/%/%',
        v_plan_code,v_unit_code,new.checkpoint_code;
    end if;

    return new;
  end if;

  -- Existing Engineering/IG path remains unchanged for non-simple checkpoints.
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

comment on function programacion.fn_guard_engineering_material_checkpoint_done_v1() is
'Checkpoint DONE guard with two explicit contracts: PROGRAMMING_SIMPLE checkpoints require current-run simple validation receipts; all other Engineering checkpoints retain the original material assertion contract. No title inference or blanket bypass.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values (
  'PROGRAMMING-SIMPLE-FOREIGN-GUARD-COMPAT-001',
  'PROGRAMMING_GOVERNANCE',
  'Simple Programming checkpoints must not inherit unrelated IG material-assertion controls',
  'The canonical engineering_work_checkpoints table had a global DONE trigger that compiled the IG/Engineering action-spec assertion contract for every assigned plan unit. Simple Programming plans therefore inherited a control outside their nature and could not close despite a valid current simple validation receipt.',
  'Shared storage had a single closure guard contract instead of explicit contract selection by plan binding.',
  'EXPLICIT SIMPLE BINDING -> simple current-run receipt guard; no simple binding -> existing Engineering material assertion guard unchanged.',
  'Do not disable the global guard. Extend it with an explicit alternate closure contract selected only by programming_checkpoint_bindings. Preserve the existing Engineering/IG path byte-for-byte for all other checkpoints.',
  'Synthetic E2E must close a simple checkpoint with its current-run validation receipt while a non-simple checkpoint continues through the original material assertion branch.',
  'HIGH',
  'ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261007230500_programming_simple_checkpoint_guard_compat_v1.sql',
  now()
)
on conflict (codigo) do update
set titulo=excluded.titulo,
    descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,
    patron=excluded.patron,
    prevencion=excluded.prevencion,
    validacion=excluded.validacion,
    severidad=excluded.severidad,
    estado=excluded.estado,
    source_ref=excluded.source_ref,
    updated_at=excluded.updated_at;
