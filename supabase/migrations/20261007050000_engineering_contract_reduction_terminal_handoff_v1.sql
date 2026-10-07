-- ENGINEERING contract reduction: terminal/readback/handoff v1
-- Converts repeated temporary contract-family blockers into exact reusable contracts.
-- Does NOT transition checkpoints or record closure events during migration.

create or replace function programacion.fn_engineering_terminal_acceptance_assert_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
  v_seq int;
  v_prior_open int := 0;
  v_prior_done_without_evidence int := 0;
  v_unmet_dependencies int := 0;
  v_open_blockers int := 0;
begin
  select pu.work_item_id,c.sequence_no
    into v_work_item_id,v_seq
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_checkpoints c
    on c.work_item_id=pu.work_item_id
   and c.checkpoint_code=p_checkpoint_code
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    raise exception 'ENGINEERING_TERMINAL_ASSERT_TARGET_NOT_FOUND:%/%/%',
      p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  select
    count(*) filter(where c.status not in ('DONE','NOT_APPLICABLE')),
    count(*) filter(where c.status='DONE' and nullif(btrim(coalesce(c.evidence_ref,'')),'') is null)
  into v_prior_open,v_prior_done_without_evidence
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.required
    and c.sequence_no<v_seq;

  select count(*)
    into v_unmet_dependencies
  from programacion.fn_engineering_effective_dependencies_v1(v_work_item_id) d
  where d.is_unmet;

  v_open_blockers:=programacion.fn_engineering_effective_open_blocker_count_v1(v_work_item_id);

  if v_prior_open<>0
     or v_prior_done_without_evidence<>0
     or v_unmet_dependencies<>0
     or v_open_blockers<>0 then
    raise exception
      'ENGINEERING_TERMINAL_ACCEPTANCE_NOT_READY:%/%/% prior_open=% prior_done_without_evidence=% unmet_dependencies=% open_blockers=%',
      p_plan_code,p_unit_code,p_checkpoint_code,
      v_prior_open,v_prior_done_without_evidence,v_unmet_dependencies,v_open_blockers;
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_TERMINAL_ACCEPTANCE_ASSERT_V1',
    'status','PASS',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'prior_required_open',v_prior_open,
    'prior_done_without_evidence',v_prior_done_without_evidence,
    'unmet_dependencies',v_unmet_dependencies,
    'open_blockers',v_open_blockers
  );
end;
$function$;

comment on function programacion.fn_engineering_terminal_acceptance_assert_v1(text,text,text)
is 'Read-only fail-closed terminal gate: all prior required checkpoints terminal with evidence, effective dependencies met, and no effective blockers. Raises on any failure.';

create or replace function programacion.fn_engineering_closure_event_guarded_v2(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_event_kind text
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_gate jsonb;
  v_event jsonb;
  v_event_id bigint;
  v_all_dependencies_done boolean;
begin
  v_gate:=programacion.fn_engineering_terminal_acceptance_assert_v1(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  v_event:=programacion.fn_engineering_closure_event_v1(
    p_plan_code,p_unit_code,p_event_kind
  );

  v_event_id:=nullif(v_event->>'event_id','')::bigint;
  if v_event_id is null then
    raise exception 'ENGINEERING_CLOSURE_EVENT_ID_MISSING:%/%/%/%',
      p_plan_code,p_unit_code,p_checkpoint_code,p_event_kind;
  end if;

  select coalesce((e.payload->>'all_dependencies_done')::boolean,false)
    into v_all_dependencies_done
  from public.lf_eventos e
  where e.id=v_event_id;

  if coalesce(v_all_dependencies_done,false)=false then
    raise exception 'ENGINEERING_CLOSURE_EVENT_DEPENDENCIES_NOT_DONE:event_id=%',v_event_id;
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_CLOSURE_EVENT_GUARDED_V2',
    'status','PASS',
    'event_kind',upper(p_event_kind),
    'event_id',v_event_id,
    'event_ref','event://'||v_event_id,
    'event_status',v_event->>'status',
    'terminal_gate',v_gate
  );
end;
$function$;

comment on function programacion.fn_engineering_closure_event_guarded_v2(text,text,text,text)
is 'Guarded canonical closure writer. Terminal acceptance must PASS before HANDOFF/INDEPENDENT_READBACK event creation/reuse, and persisted event must prove all dependencies done.';

do $repair$
declare
  r record;
  v_spec jsonb;
  v_queries jsonb;
  v_assert_query text;
  v_new jsonb;
  v_total int := 0;
begin
  -- Pure terminal/readback checkpoints: existing exact source queries are retained,
  -- plus one generic fail-closed terminal acceptance assertion.
  for r in
    select * from (values
      ('M5.2','TERMINAL'),
      ('M5.3','TERMINAL'),
      ('M5.4','TERMINAL'),
      ('M5.5','TERMINAL'),
      ('M5.6','TERMINAL'),
      ('M5.8','TERMINAL'),
      ('M5.9','HANDOFF_ASIS'),
      ('M5.9','TERMINAL'),
      ('M6.10','TERMINAL'),
      ('M6.12','TERMINAL'),
      ('M6.2','TERMINAL'),
      ('M6.7','TERMINAL'),
      ('M7.10','TERMINAL'),
      ('M7.9','TERMINAL'),
      ('M8.2','TERMINAL'),
      ('M8.5','TERMINAL'),
      ('M8.6','TERMINAL'),
      ('N-6','TERMINAL'),
      ('M7.14','M7_ALL_DONE_GATE'),
      ('M8.12','M8_ALL_DONE_GATE'),
      ('M9.13','M9_ALL_DONE_GATE')
    ) as x(unit_code,checkpoint_code)
  loop
    select pu.unit_metadata#>array['action_specs_v1',r.checkpoint_code]
      into v_spec
    from programacion.engineering_plan_units pu
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.unit_code=r.unit_code
      and pu.disposition='ASSIGNED';

    if v_spec is null then
      raise exception 'ENGINEERING_TERMINAL_REPAIR_SPEC_MISSING:%/%',r.unit_code,r.checkpoint_code;
    end if;

    v_queries:=coalesce(v_spec->'verification_queries','[]'::jsonb);
    v_assert_query:=format(
      'select programacion.fn_engineering_terminal_acceptance_assert_v1(%L,%L,%L) as result',
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',r.unit_code,r.checkpoint_code
    );

    v_new:=(
      v_spec || jsonb_build_object(
        'status','READY',
        'precision','EXPLICIT_TERMINAL_ACCEPTANCE_BOUND_V1',
        'action_kind','READBACK_ONCE',
        'recipe_mode','TERMINAL_ACCEPTANCE_ASSERT_V1',
        'requires_material_execution',false,
        'mutation_policy','NO_DOMAIN_MUTATION',
        'contract_source','EXPLICIT_ACTION_SPEC',
        'contract_family','TERMINAL_ACCEPTANCE_BOUND',
        'verification_queries',v_queries||jsonb_build_array(v_assert_query),
        'terminal_acceptance_contract',jsonb_build_object(
          'entrypoint','programacion.fn_engineering_terminal_acceptance_assert_v1',
          'prior_required_terminal',true,
          'prior_done_evidence_required',true,
          'effective_dependencies_met',true,
          'effective_open_blockers_zero',true,
          'failure_semantics','RAISE_EXCEPTION_FAIL_CLOSED'
        ),
        'expected','Retain declared readbacks and pass only after the reusable terminal acceptance assertion succeeds.',
        'action_steps',jsonb_build_array(
          'EXECUTE_DECLARED_READBACKS',
          'ASSERT_TERMINAL_ACCEPTANCE',
          'PERSIST_CHECKPOINT_ONLY',
          'USE_RETURNED_BOOTSTRAP'
        )
      )
    ) - 'required_contract' - 'assertion_contract';

    update programacion.engineering_plan_units pu
       set unit_metadata=jsonb_set(
         pu.unit_metadata,
         '{action_specs_v1}',
         coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
           || jsonb_build_object(r.checkpoint_code,v_new),
         true
       )
     where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
       and pu.unit_code=r.unit_code
       and pu.disposition='ASSIGNED';

    v_total:=v_total+1;
  end loop;

  -- Canonical HANDOFF and independent-readback event checkpoints.
  for r in
    select * from (values
      ('M1.9','M1_HANDOFF_TERMINAL','HANDOFF'),
      ('M10.13','FINAL_HANDOFF','HANDOFF'),
      ('M3.11','HANDOFF_EVENT','HANDOFF'),
      ('M5.10','HANDOFF_EVENT','HANDOFF'),
      ('M6.13','HANDOFF_EVENT','HANDOFF'),
      ('M7.14','M7_HANDOFF_EVENT','HANDOFF'),
      ('M8.12','M8_HANDOFF_EVENT','HANDOFF'),
      ('M9.13','M9_HANDOFF_EVENT','HANDOFF'),
      ('M1.9','M1_INDEPENDENT_READBACK','INDEPENDENT_READBACK'),
      ('M3.11','INDEPENDENT_READBACK_TERMINAL','INDEPENDENT_READBACK'),
      ('M7.14','M7_INDEPENDENT_READBACK','INDEPENDENT_READBACK'),
      ('M8.12','M8_INDEPENDENT_READBACK','INDEPENDENT_READBACK'),
      ('M9.13','M9_INDEPENDENT_READBACK','INDEPENDENT_READBACK')
    ) as x(unit_code,checkpoint_code,event_kind)
  loop
    select pu.unit_metadata#>array['action_specs_v1',r.checkpoint_code]
      into v_spec
    from programacion.engineering_plan_units pu
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.unit_code=r.unit_code
      and pu.disposition='ASSIGNED';

    if v_spec is null then
      raise exception 'ENGINEERING_CLOSURE_REPAIR_SPEC_MISSING:%/%',r.unit_code,r.checkpoint_code;
    end if;

    v_assert_query:=format(
      'select programacion.fn_engineering_closure_event_guarded_v2(%L,%L,%L,%L) as result',
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',r.unit_code,r.checkpoint_code,r.event_kind
    );

    v_new:=(
      v_spec || jsonb_build_object(
        'status','READY',
        'precision','EXPLICIT_GUARDED_CLOSURE_EVENT_V2',
        'action_kind','MUTATION_EXECUTION',
        'recipe_mode','EXECUTE_CANONICAL_CLOSURE_EVENT',
        'requires_material_execution',true,
        'mutation_policy','ONLY_DECLARED_TARGETS',
        'contract_source','EXPLICIT_ACTION_SPEC',
        'contract_family','GUARDED_CLOSURE_EVENT_BOUND',
        'target',jsonb_build_object(
          'checkpoint',r.checkpoint_code,
          'declared_assets','[]'::jsonb,
          'declared_events','[]'::jsonb,
          'declared_objects',jsonb_build_array('public.lf_eventos'),
          'declared_artifacts','[]'::jsonb,
          'mutation_artifacts','[]'::jsonb
        ),
        'verification_queries',jsonb_build_array(v_assert_query),
        'assertion_contract',jsonb_build_object(
          'mode','EXPLICIT_PASS_WHEN_SUBSET',
          'pass_when',jsonb_build_object('status','PASS')
        ),
        'closure_event_contract',jsonb_build_object(
          'entrypoint','programacion.fn_engineering_closure_event_guarded_v2',
          'event_kind',r.event_kind,
          'terminal_acceptance_required',true,
          'all_dependencies_done_required',true,
          'idempotent_reuse_allowed',true
        ),
        'expected','Create or reuse the canonical closure event only after terminal acceptance passes; persisted event must prove all dependencies done.',
        'action_steps',jsonb_build_array(
          'ASSERT_TERMINAL_ACCEPTANCE',
          'EMIT_OR_REUSE_CANONICAL_CLOSURE_EVENT',
          'VERIFY_PERSISTED_EVENT',
          'RECORD_ASSERTION_RECEIPT',
          'PERSIST_CHECKPOINT_ONLY',
          'USE_RETURNED_BOOTSTRAP'
        )
      )
    ) - 'required_contract';

    update programacion.engineering_plan_units pu
       set unit_metadata=jsonb_set(
         pu.unit_metadata,
         '{action_specs_v1}',
         coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
           || jsonb_build_object(r.checkpoint_code,v_new),
         true
       )
     where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
       and pu.unit_code=r.unit_code
       and pu.disposition='ASSIGNED';

    v_total:=v_total+1;
  end loop;

  if v_total<>34 then
    raise exception 'ENGINEERING_TERMINAL_REPAIR_COUNT_MISMATCH expected=34 actual=%',v_total;
  end if;
end;
$repair$;

-- Structural self-readback: exact repaired checkpoints must compile READY and route
-- to READ for terminal assertions or WRITE_DB for guarded closure events.
do $selftest$
declare
  v_bad int;
  v_assertion jsonb;
begin
  with mapped(unit_code,checkpoint_code,capability) as (
    values
      ('M5.2','TERMINAL','READ'),
      ('M5.3','TERMINAL','READ'),
      ('M5.4','TERMINAL','READ'),
      ('M5.5','TERMINAL','READ'),
      ('M5.6','TERMINAL','READ'),
      ('M5.8','TERMINAL','READ'),
      ('M5.9','HANDOFF_ASIS','READ'),
      ('M5.9','TERMINAL','READ'),
      ('M6.10','TERMINAL','READ'),
      ('M6.12','TERMINAL','READ'),
      ('M6.2','TERMINAL','READ'),
      ('M6.7','TERMINAL','READ'),
      ('M7.10','TERMINAL','READ'),
      ('M7.9','TERMINAL','READ'),
      ('M8.2','TERMINAL','READ'),
      ('M8.5','TERMINAL','READ'),
      ('M8.6','TERMINAL','READ'),
      ('N-6','TERMINAL','READ'),
      ('M7.14','M7_ALL_DONE_GATE','READ'),
      ('M8.12','M8_ALL_DONE_GATE','READ'),
      ('M9.13','M9_ALL_DONE_GATE','READ'),
      ('M1.9','M1_HANDOFF_TERMINAL','WRITE_DB'),
      ('M10.13','FINAL_HANDOFF','WRITE_DB'),
      ('M3.11','HANDOFF_EVENT','WRITE_DB'),
      ('M5.10','HANDOFF_EVENT','WRITE_DB'),
      ('M6.13','HANDOFF_EVENT','WRITE_DB'),
      ('M7.14','M7_HANDOFF_EVENT','WRITE_DB'),
      ('M8.12','M8_HANDOFF_EVENT','WRITE_DB'),
      ('M9.13','M9_HANDOFF_EVENT','WRITE_DB'),
      ('M1.9','M1_INDEPENDENT_READBACK','WRITE_DB'),
      ('M3.11','INDEPENDENT_READBACK_TERMINAL','WRITE_DB'),
      ('M7.14','M7_INDEPENDENT_READBACK','WRITE_DB'),
      ('M8.12','M8_INDEPENDENT_READBACK','WRITE_DB'),
      ('M9.13','M9_INDEPENDENT_READBACK','WRITE_DB')
  ), x as (
    select m.*,
      programacion.fn_engineering_checkpoint_action_spec_v3(
        'IG_CURATOR_VALIDATOR_REFACTOR_V2',m.unit_code,m.checkpoint_code
      ) spec
    from mapped m
  ), p as (
    select x.*,
      programacion.fn_engineering_execution_packet_from_spec_v1(
        'IG_CURATOR_VALIDATOR_REFACTOR_V2',unit_code,checkpoint_code,spec,'{}'::jsonb
      ) packet
    from x
  )
  select count(*) into v_bad
  from p
  where spec->>'status'<>'READY'
     or packet->>'status'<>'READY'
     or packet->>'execution_capability'<>capability;

  if v_bad<>0 then
    raise exception 'ENGINEERING_TERMINAL_REPAIR_SELFTEST_FAIL bad=%',v_bad;
  end if;

  v_assertion:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M3.11',
    'HANDOFF_EVENT',
    programacion.fn_engineering_checkpoint_action_spec_v3(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.11','HANDOFF_EVENT'
    )
  );

  if v_assertion->>'status'<>'READY' then
    raise exception 'ENGINEERING_CLOSURE_ASSERTION_CONTRACT_NOT_READY:%',v_assertion;
  end if;
end;
$selftest$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-CONTRACT-REDUCTION-TERMINAL-HANDOFF-001',
  'ENGINEERING_ORCHESTRATION',
  'Terminal/readback/handoff contracts should be completed once by reusable acceptance guards',
  'Temporary family sanitation left repeated terminal, all-done and handoff checkpoints blocked even though their common mechanics are generic: prior required checkpoints, evidence, effective dependencies, blockers and canonical closure event persistence.',
  'The family sanitizer intentionally stopped at classification and did not bind reusable terminal acceptance or guarded closure-event semantics.',
  'REPEATED_TERMINAL_CONTRACT_AUTHORING_PER_UNIT',
  'Use fn_engineering_terminal_acceptance_assert_v1 for terminal/readback gates and fn_engineering_closure_event_guarded_v2 for canonical HANDOFF/INDEPENDENT_READBACK writes. Exact unit/checkpoint mappings remain explicit; title inference is forbidden.',
  'PASS when 34 mapped checkpoints compile READY; 21 route READ, 13 route WRITE_DB; closure-event assertion contract is READY; migration itself records no closure event and transitions no checkpoint.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_terminal_acceptance_assert_v1; supabase://programacion.fn_engineering_closure_event_guarded_v2; supabase://programacion.engineering_plan_units',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','ENGINEERING_EXECUTOR','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Plan-wide contract reduction for repeated terminal/handoff semantics',
  'supabase://programacion.fn_engineering_terminal_acceptance_assert_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();
