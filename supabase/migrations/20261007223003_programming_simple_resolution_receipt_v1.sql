-- PROGRAMMING_SIMPLE_EXECUTOR_V1 resolution receipt hardening.
-- A resolver is reusable, but its execution cannot be bypassed after a current FAIL.

create table if not exists programacion.programming_resolution_receipts (
  id bigserial primary key,
  run_id bigint not null
    references programacion.programming_simple_runs(id) on delete cascade,
  plan_code text not null,
  unit_code text not null,
  checkpoint_code text not null,
  validation_code text not null
    references programacion.programming_validation_registry(validation_code),
  resolver_code text not null
    references programacion.programming_resolver_registry(resolver_code),
  failure_receipt_sha256 text not null
    check (failure_receipt_sha256 ~ '^[0-9a-f]{64}$'),
  evidence_ref text not null
    check (nullif(btrim(evidence_ref),'') is not null),
  detail jsonb not null default '{}'::jsonb,
  observed_at timestamptz not null default now(),
  actor text not null default 'PROGRAMMING_SIMPLE_EXECUTOR_V1',
  unique (run_id,unit_code,checkpoint_code)
);

create or replace function programacion.fn_programming_resolution_record_v1(
  p_run_id bigint,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_resolver_code text,
  p_evidence_ref text,
  p_actor text default 'PROGRAMMING_SIMPLE_EXECUTOR_V1',
  p_detail jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
  v_current text;
  b programacion.programming_checkpoint_bindings%rowtype;
  a jsonb;
  r jsonb;
  v_sha text;
begin
  if nullif(btrim(coalesce(p_evidence_ref,'')),'') is null then
    raise exception 'PROGRAMMING_RESOLUTION_EVIDENCE_REQUIRED';
  end if;

  if not exists (
    select 1
    from programacion.programming_simple_run_units ru
    where ru.run_id=p_run_id
      and ru.plan_code=p_plan_code
      and ru.unit_code=p_unit_code
      and ru.status='RUNNING'
  ) then
    raise exception 'PROGRAMMING_RESOLUTION_ACTIVE_RUN_UNIT_REQUIRED';
  end if;

  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  select c.checkpoint_code into v_current
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.required
    and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no
  limit 1;

  if v_current is distinct from p_checkpoint_code then
    raise exception 'PROGRAMMING_RESOLUTION_NOT_CURRENT:% current=%',
      p_checkpoint_code,coalesce(v_current,'(none)');
  end if;

  select * into b
  from programacion.programming_checkpoint_bindings
  where plan_code=p_plan_code
    and unit_code=p_unit_code
    and checkpoint_code=p_checkpoint_code
    and enabled;

  if not found then
    raise exception 'PROGRAMMING_RESOLUTION_BINDING_MISSING';
  end if;

  a:=programacion.fn_programming_rule_admission_v1(
    b.validation_code,b.failure_code
  );

  if not coalesce((a->>'admitted')::boolean,false)
     or a->>'rule_mode'<>'BLOCKING_AUTOMATIC' then
    raise exception 'PROGRAMMING_RESOLUTION_AUTOMATIC_RULE_REQUIRED';
  end if;

  if a#>>'{resolver,resolver_code}' is distinct from p_resolver_code then
    raise exception 'PROGRAMMING_RESOLUTION_RESOLVER_MISMATCH';
  end if;

  select assertion_receipt,assertion_receipt_sha256
    into r,v_sha
  from programacion.engineering_work_checkpoints
  where work_item_id=v_work_item_id
    and checkpoint_code=p_checkpoint_code
  for update;

  if coalesce(jsonb_typeof(r),'')<>'object'
     or coalesce(r->>'schema_version','')<>'PROGRAMMING_VALIDATION_RECEIPT_V1'
     or coalesce(r->>'result','')<>'FAIL'
     or coalesce(r->>'validation_code','')<>b.validation_code
     or coalesce(r->>'checkpoint_code','')<>p_checkpoint_code
     or coalesce(r->>'unit_code','')<>p_unit_code
     or coalesce(r->>'plan_code','')<>p_plan_code
     or coalesce(jsonb_typeof(r->'run_id'),'')<>'number'
     or (r->>'run_id')::bigint is distinct from p_run_id
     or v_sha is null then
    raise exception 'PROGRAMMING_RESOLUTION_CURRENT_FAIL_REQUIRED';
  end if;

  insert into programacion.programming_resolution_receipts(
    run_id,plan_code,unit_code,checkpoint_code,validation_code,resolver_code,
    failure_receipt_sha256,evidence_ref,detail,actor
  ) values (
    p_run_id,p_plan_code,p_unit_code,p_checkpoint_code,b.validation_code,p_resolver_code,
    v_sha,p_evidence_ref,coalesce(p_detail,'{}'::jsonb),
    coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
  )
  on conflict (run_id,unit_code,checkpoint_code) do update
  set resolver_code=excluded.resolver_code,
      validation_code=excluded.validation_code,
      failure_receipt_sha256=excluded.failure_receipt_sha256,
      evidence_ref=excluded.evidence_ref,
      detail=excluded.detail,
      observed_at=now(),
      actor=excluded.actor;

  return programacion.fn_programming_simple_unit_bootstrap_v1(
    p_run_id,p_plan_code,p_unit_code
  ) || jsonb_build_object(
    'resolution_recorded',true,
    'resolver_code',p_resolver_code,
    'failure_receipt_sha256',v_sha
  );
end;
$function$;

create or replace function programacion.fn_programming_simple_unit_bootstrap_v1(
  p_run_id bigint,
  p_plan_code text,
  p_unit_code text
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
  v_work_status text;
  c record;
  b programacion.programming_checkpoint_bindings%rowtype;
  a jsonb;
  r jsonb;
  v_resolution boolean:=false;
begin
  select pu.work_item_id,w.status
    into v_work_item_id,v_work_status
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
      'terminal_action','STOP_UNIT_NOT_FOUND'
    );
  end if;

  if v_work_status='DONE' then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'terminal_action','UNIT_DONE'
    );
  end if;

  select *
    into c
  from programacion.engineering_work_checkpoints
  where work_item_id=v_work_item_id
    and required
    and status not in ('DONE','NOT_APPLICABLE')
  order by sequence_no
  limit 1;

  if not found then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'terminal_action','UNIT_CLOSE_REQUIRED',
      'reason','NO_OPEN_REQUIRED_CHECKPOINTS'
    );
  end if;

  select *
    into b
  from programacion.programming_checkpoint_bindings
  where plan_code=p_plan_code
    and unit_code=p_unit_code
    and checkpoint_code=c.checkpoint_code
    and enabled;

  if not found then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
      'terminal_action','STOP_RULE_NOT_ADMISSIBLE',
      'reason','CHECKPOINT_BINDING_MISSING',
      'checkpoint_code',c.checkpoint_code
    );
  end if;

  a:=programacion.fn_programming_rule_admission_v1(
    b.validation_code,b.failure_code
  );

  if not coalesce((a->>'admitted')::boolean,false) then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
      'terminal_action','STOP_RULE_NOT_ADMISSIBLE',
      'checkpoint_code',c.checkpoint_code,
      'rule_admission',a
    );
  end if;

  r:=c.assertion_receipt;

  if jsonb_typeof(r)='object'
     and r->>'schema_version'='PROGRAMMING_VALIDATION_RECEIPT_V1'
     and r->>'validation_code'=b.validation_code
     and r->>'checkpoint_code'=c.checkpoint_code
     and r->>'unit_code'=p_unit_code
     and r->>'plan_code'=p_plan_code
     and jsonb_typeof(r->'run_id')='number'
     and (r->>'run_id')::bigint=p_run_id then

    if r->>'result'='PASS' then
      return jsonb_build_object(
        'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',c.checkpoint_code,
        'terminal_action','TRANSITION_CURRENT_CHECKPOINT',
        'validation_code',b.validation_code,
        'validation_receipt',r,
        'reuse_policy','REUSE_PROCEDURE_NOT_PASS'
      );
    end if;

    if r->>'result'='FAIL'
       and a->>'rule_mode'='BLOCKING_AUTOMATIC' then
      select exists (
        select 1
        from programacion.programming_resolution_receipts rr
        where rr.run_id=p_run_id
          and rr.plan_code=p_plan_code
          and rr.unit_code=p_unit_code
          and rr.checkpoint_code=c.checkpoint_code
          and rr.validation_code=b.validation_code
          and rr.resolver_code=a#>>'{resolver,resolver_code}'
          and rr.failure_receipt_sha256=c.assertion_receipt_sha256
      ) into v_resolution;

      if v_resolution then
        return jsonb_build_object(
          'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
          'plan_code',p_plan_code,
          'unit_code',p_unit_code,
          'checkpoint_code',c.checkpoint_code,
          'terminal_action','REVALIDATE_CURRENT_CHECKPOINT',
          'validation_code',b.validation_code,
          'validator_handler',a->>'validator_handler',
          'resolver',a->'resolver',
          'validation_receipt',r,
          'resolution_receipt_present',true,
          'post_condition','CURRENT_VALIDATOR_MUST_PASS'
        );
      end if;

      return jsonb_build_object(
        'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',c.checkpoint_code,
        'terminal_action','RESOLVE_CURRENT_CHECKPOINT',
        'validation_code',b.validation_code,
        'resolver',a->'resolver',
        'validation_receipt',r,
        'resolution_receipt_required',true,
        'post_condition','RECORD_RESOLUTION_RECEIPT_THEN_RERUN_VALIDATOR'
      );
    end if;

    if r->>'result'='FAIL'
       and a->>'rule_mode'='HUMAN_DECISION' then
      return jsonb_build_object(
        'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',c.checkpoint_code,
        'terminal_action','HUMAN_DECISION_REQUIRED',
        'validation_code',b.validation_code,
        'validation_receipt',r
      );
    end if;
  end if;

  return jsonb_build_object(
    'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',c.checkpoint_code,
    'checkpoint_title',c.title,
    'terminal_action','VALIDATE_CURRENT_CHECKPOINT',
    'validation_code',b.validation_code,
    'failure_code',b.failure_code,
    'validator_handler',a->>'validator_handler',
    'rule_mode',a->>'rule_mode',
    'reuse_policy','REUSE_PROCEDURE_NOT_PASS'
  );
end;
$function$;

create or replace function programacion.fn_programming_validation_record_v1(
  p_run_id bigint,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_validation_code text,
  p_result text,
  p_evidence_ref text,
  p_actor text default 'PROGRAMMING_SIMPLE_EXECUTOR_V1',
  p_detail jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','extensions','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
  v_current text;
  b programacion.programming_checkpoint_bindings%rowtype;
  a jsonb;
  v_receipt jsonb;
  v_sha text;
  v_previous_receipt jsonb;
  v_previous_sha text;
  v_resolution_ok boolean:=false;
begin
  if p_result not in ('PASS','FAIL') then
    raise exception 'PROGRAMMING_VALIDATION_RESULT_UNSUPPORTED:%',p_result;
  end if;

  if nullif(btrim(coalesce(p_evidence_ref,'')),'') is null then
    raise exception 'PROGRAMMING_VALIDATION_EVIDENCE_REQUIRED';
  end if;

  if not exists (
    select 1
    from programacion.programming_simple_run_units ru
    where ru.run_id=p_run_id
      and ru.plan_code=p_plan_code
      and ru.unit_code=p_unit_code
      and ru.status='RUNNING'
  ) then
    raise exception 'PROGRAMMING_VALIDATION_ACTIVE_RUN_UNIT_REQUIRED';
  end if;

  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  select c.checkpoint_code into v_current
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.required
    and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no
  limit 1;

  if v_current is distinct from p_checkpoint_code then
    raise exception 'PROGRAMMING_VALIDATION_NOT_CURRENT:% current=%',
      p_checkpoint_code,coalesce(v_current,'(none)');
  end if;

  select * into b
  from programacion.programming_checkpoint_bindings
  where plan_code=p_plan_code
    and unit_code=p_unit_code
    and checkpoint_code=p_checkpoint_code
    and enabled;

  if not found then
    raise exception 'PROGRAMMING_VALIDATION_BINDING_MISSING';
  end if;

  if b.validation_code<>p_validation_code then
    raise exception 'PROGRAMMING_VALIDATION_BINDING_MISMATCH';
  end if;

  a:=programacion.fn_programming_rule_admission_v1(
    b.validation_code,b.failure_code
  );

  if not coalesce((a->>'admitted')::boolean,false) then
    raise exception 'PROGRAMMING_RULE_NOT_ADMITTED:%',a::text;
  end if;

  select assertion_receipt,assertion_receipt_sha256
    into v_previous_receipt,v_previous_sha
  from programacion.engineering_work_checkpoints
  where work_item_id=v_work_item_id
    and checkpoint_code=p_checkpoint_code
  for update;

  if p_result='PASS'
     and coalesce(v_previous_receipt->>'schema_version','')='PROGRAMMING_VALIDATION_RECEIPT_V1'
     and coalesce(v_previous_receipt->>'result','')='FAIL'
     and coalesce(v_previous_receipt->>'validation_code','')=b.validation_code
     and coalesce(v_previous_receipt->>'checkpoint_code','')=p_checkpoint_code
     and coalesce(v_previous_receipt->>'unit_code','')=p_unit_code
     and coalesce(v_previous_receipt->>'plan_code','')=p_plan_code
     and coalesce(jsonb_typeof(v_previous_receipt->'run_id'),'')='number'
     and (v_previous_receipt->>'run_id')::bigint=p_run_id
     and a->>'rule_mode'='BLOCKING_AUTOMATIC' then

    select exists (
      select 1
      from programacion.programming_resolution_receipts rr
      where rr.run_id=p_run_id
        and rr.plan_code=p_plan_code
        and rr.unit_code=p_unit_code
        and rr.checkpoint_code=p_checkpoint_code
        and rr.validation_code=b.validation_code
        and rr.resolver_code=a#>>'{resolver,resolver_code}'
        and rr.failure_receipt_sha256=v_previous_sha
    ) into v_resolution_ok;

    if not v_resolution_ok then
      raise exception 'PROGRAMMING_POST_VALIDATION_RESOLUTION_RECEIPT_REQUIRED';
    end if;
  end if;

  v_receipt:=jsonb_build_object(
    'schema_version','PROGRAMMING_VALIDATION_RECEIPT_V1',
    'run_id',p_run_id,
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'validation_code',p_validation_code,
    'result',p_result,
    'evidence_ref',p_evidence_ref,
    'detail',coalesce(p_detail,'{}'::jsonb),
    'observed_at',now(),
    'actor',coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1'),
    'prior_runtime_pass_reused',false
  );

  v_sha:=encode(
    extensions.digest(convert_to(v_receipt::text,'UTF8'),'sha256'),
    'hex'
  );

  update programacion.engineering_work_checkpoints
     set status='IN_PROGRESS',
         assertion_receipt=v_receipt,
         assertion_receipt_sha256=v_sha,
         assertion_recorded_at=now(),
         assertion_recorded_by=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1'),
         updated_at=now(),
         updated_by_execution_id=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
   where work_item_id=v_work_item_id
     and checkpoint_code=p_checkpoint_code;

  update programacion.engineering_work_items
     set status='IN_PROGRESS',
         started_at=coalesce(started_at,now()),
         updated_at=now(),
         updated_by_execution_id=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
   where id=v_work_item_id
     and status not in ('DONE','CANCELLED');

  return programacion.fn_programming_simple_unit_bootstrap_v1(
    p_run_id,p_plan_code,p_unit_code
  ) || jsonb_build_object(
    'validation_recorded',true,
    'validation_result',p_result,
    'receipt_sha256',v_sha
  );
end;
$function$;

comment on table programacion.programming_resolution_receipts is
'Current-run resolver execution receipts for PROGRAMMING_SIMPLE_EXECUTOR_V1. A PASS after a BLOCKING_AUTOMATIC FAIL requires a matching receipt bound to the exact FAIL receipt hash.';

comment on function programacion.fn_programming_resolution_record_v1(bigint,text,text,text,text,text,text,jsonb) is
'Records deterministic resolver execution for the current FAIL. Does not grant PASS; bootstrap moves to REVALIDATE_CURRENT_CHECKPOINT.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values (
  'PROGRAMMING-SIMPLE-RESOLVER-NO-BYPASS-001',
  'PROGRAMMING_GOVERNANCE',
  'Automatic resolver execution requires a current failure-bound receipt before revalidation can PASS',
  'Reusing a resolver procedure never means assuming that it executed for the current failure. After a current BLOCKING_AUTOMATIC FAIL, the executor requires a resolver receipt bound to the exact failure receipt hash, then reruns the validator.',
  'Without a current resolution receipt, a caller could overwrite a FAIL with PASS and bypass the declared resolver path.',
  'CURRENT FAIL -> resolver receipt bound to FAIL hash -> REVALIDATE -> current PASS -> DONE.',
  'Record resolver execution with fn_programming_resolution_record_v1. Reject PASS-after-FAIL unless the receipt exists for the same run/unit/checkpoint/validator/resolver/failure hash.',
  'Negative test: PASS immediately after FAIL is rejected. Positive test: FAIL -> resolution receipt -> bootstrap REVALIDATE_CURRENT_CHECKPOINT -> PASS -> transition DONE.',
  'HIGH',
  'ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261007225000_programming_simple_resolution_receipt_v1.sql',
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
