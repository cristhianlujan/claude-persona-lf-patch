-- PROGRAMMING_SIMPLE_EXECUTOR_V1
-- Per-checkpoint validation_input prevents validator proliferation.
-- The same proven deterministic validator can be reused with explicit checkpoint inputs.

alter table programacion.programming_checkpoint_bindings
  add column if not exists validation_input jsonb not null default '{}'::jsonb;

alter table programacion.programming_checkpoint_bindings
  drop constraint if exists programming_checkpoint_bindings_validation_input_object_ck;

alter table programacion.programming_checkpoint_bindings
  add constraint programming_checkpoint_bindings_validation_input_object_ck
  check (jsonb_typeof(validation_input)='object');

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
        'validation_input',b.validation_input,
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
          'validation_input',b.validation_input,
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
        'validation_input',b.validation_input,
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
        'validation_input',b.validation_input,
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
    'validation_input',b.validation_input,
    'failure_code',b.failure_code,
    'validator_handler',a->>'validator_handler',
    'rule_mode',a->>'rule_mode',
    'reuse_policy','REUSE_PROCEDURE_NOT_PASS'
  );
end;
$function$;

comment on column programacion.programming_checkpoint_bindings.validation_input is
'Explicit per-checkpoint input consumed by a reusable proven validator. Prevents one validator definition per atomic checkpoint.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values (
  'PROGRAMMING-SIMPLE-BINDING-INPUT-001',
  'PROGRAMMING_GOVERNANCE',
  'Reusable validators need explicit per-checkpoint inputs to avoid atomic-plan explosion',
  'Atomic plans become unmanageable if every checkpoint requires a new validator definition only because file paths, expected literals or refs differ. The validator procedure should be reusable while the binding carries explicit deterministic inputs.',
  'The initial simple binding stored validation_code and failure_code but no checkpoint-specific input payload.',
  'PROVEN VALIDATOR + EXPLICIT validation_input PER CHECKPOINT -> current validation receipt.',
  'Put variable parameters in programming_checkpoint_bindings.validation_input. Do not duplicate validators for data-only differences and do not infer parameters from titles.',
  'Bootstrap must return the exact validation_input for VALIDATE/REVALIDATE/RESOLVE/HUMAN_DECISION paths; JSON object constraint prevents malformed payloads.',
  'HIGH',
  'ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261007232000_programming_simple_binding_input_v1.sql',
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
