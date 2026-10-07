-- ENGINEERING contract reduction: terminal residual normalization v1
-- Eliminates residual generic terminal-family blockers by binding them to
-- reusable terminal/readback/closure semantics or reclassifying to the exact
-- remaining execution family.

do $repair$
declare
  v_spec jsonb;
  v_queries jsonb;
  v_new jsonb;
begin
  -- Pure capability-current readback: M9.8 AS-IS.
  select unit_metadata#>'{action_specs_v1,CLOSURE_GATE_ASIS}'
    into v_spec
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.8';

  v_queries:=coalesce(v_spec->'verification_queries','[]'::jsonb)
    || jsonb_build_array(
      'select programacion.fn_engineering_current_capability_set_assert_v1(array[''CLOSURE_GATE'',''FINAL_EVIDENCE'']::text[]) as result'
    );

  v_new:=(
    v_spec||jsonb_build_object(
      'status','READY',
      'precision','EXPLICIT_CAPABILITY_READBACK_BOUND_V1',
      'action_kind','READBACK_ONCE',
      'recipe_mode','CURRENT_CAPABILITY_SET_ASSERT_V1',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'contract_family','CURRENT_CAPABILITY_READBACK_BOUND',
      'verification_queries',v_queries,
      'expected','CLOSURE_GATE and FINAL_EVIDENCE must be ACTIVE/CURRENT/RELEASED and declared readbacks must remain consistent.'
    )
  )-'required_contract';

  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(
    unit_metadata,'{action_specs_v1}',
    coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)||jsonb_build_object('CLOSURE_GATE_ASIS',v_new),true
  )
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.8';

  -- M10.13 reuses current closure authority plus terminal acceptance.
  select unit_metadata#>'{action_specs_v1,CLOSURE_GATE_REUSE}'
    into v_spec
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M10.13';

  v_queries:=coalesce(v_spec->'verification_queries','[]'::jsonb)
    || jsonb_build_array(
      'select programacion.fn_engineering_current_capability_set_assert_v1(array[''CLOSURE_GATE'',''FINAL_EVIDENCE'']::text[]) as result',
      'select programacion.fn_engineering_terminal_acceptance_assert_v1(''IG_CURATOR_VALIDATOR_REFACTOR_V2'',''M10.13'',''CLOSURE_GATE_REUSE'') as result'
    );

  v_new:=(
    v_spec||jsonb_build_object(
      'status','READY',
      'precision','EXPLICIT_CLOSURE_AUTHORITY_REUSE_BOUND_V1',
      'action_kind','READBACK_ONCE',
      'recipe_mode','CLOSURE_AUTHORITY_AND_TERMINAL_ASSERT_V1',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'contract_family','CLOSURE_AUTHORITY_REUSE_BOUND',
      'verification_queries',v_queries,
      'expected','Reuse current CLOSURE_GATE/FINAL_EVIDENCE authority and require terminal acceptance; no IG-owned closure gate is created.'
    )
  )-'required_contract';

  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(
    unit_metadata,'{action_specs_v1}',
    coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)||jsonb_build_object('CLOSURE_GATE_REUSE',v_new),true
  )
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M10.13';

  -- M4.12 combines canonical HANDOFF and independent readback in one exact
  -- terminal checkpoint; both guarded calls must succeed.
  select unit_metadata#>'{action_specs_v1,M4_HANDOFF_READBACK}'
    into v_spec
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M4.12';

  v_new:=(
    v_spec||jsonb_build_object(
      'status','READY',
      'precision','EXPLICIT_GUARDED_CLOSURE_PAIR_V2',
      'action_kind','MUTATION_EXECUTION',
      'recipe_mode','EXECUTE_CANONICAL_CLOSURE_EVENT',
      'requires_material_execution',true,
      'mutation_policy','ONLY_DECLARED_TARGETS',
      'contract_family','GUARDED_CLOSURE_EVENT_BOUND',
      'target',jsonb_build_object(
        'checkpoint','M4_HANDOFF_READBACK',
        'declared_assets','[]'::jsonb,
        'declared_events','[]'::jsonb,
        'declared_objects',jsonb_build_array('public.lf_eventos'),
        'declared_artifacts','[]'::jsonb,
        'mutation_artifacts','[]'::jsonb
      ),
      'verification_queries',jsonb_build_array(
        'select programacion.fn_engineering_closure_event_guarded_v2(''IG_CURATOR_VALIDATOR_REFACTOR_V2'',''M4.12'',''M4_HANDOFF_READBACK'',''HANDOFF'') as result',
        'select programacion.fn_engineering_closure_event_guarded_v2(''IG_CURATOR_VALIDATOR_REFACTOR_V2'',''M4.12'',''M4_HANDOFF_READBACK'',''INDEPENDENT_READBACK'') as result'
      ),
      'assertion_contract',jsonb_build_object(
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',jsonb_build_object('status','PASS')
      ),
      'expected','Both canonical HANDOFF and independent readback must be persisted through the guarded closure writer.'
    )
  )-'required_contract';

  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(
    unit_metadata,'{action_specs_v1}',
    coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)||jsonb_build_object('M4_HANDOFF_READBACK',v_new),true
  )
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M4.12';

  -- M5/M6 independent readbacks consume the canonical handoff produced by the
  -- immediately preceding HANDOFF_EVENT checkpoint.
  for v_new in
    select jsonb_build_object('unit_code',u,'checkpoint_code',c)
    from (values
      ('M5.10','INDEPENDENT_READBACK'),
      ('M6.13','INDEPENDENT_READBACK')
    ) x(u,c)
  loop
    select unit_metadata#>array['action_specs_v1',v_new->>'checkpoint_code']
      into v_spec
    from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and unit_code=v_new->>'unit_code';

    v_spec:=(
      v_spec||jsonb_build_object(
        'status','READY',
        'precision','EXPLICIT_GUARDED_INDEPENDENT_READBACK_V2',
        'action_kind','MUTATION_EXECUTION',
        'recipe_mode','EXECUTE_CANONICAL_CLOSURE_EVENT',
        'requires_material_execution',true,
        'mutation_policy','ONLY_DECLARED_TARGETS',
        'contract_family','GUARDED_CLOSURE_EVENT_BOUND',
        'target',jsonb_build_object(
          'checkpoint',v_new->>'checkpoint_code',
          'declared_assets','[]'::jsonb,
          'declared_events','[]'::jsonb,
          'declared_objects',jsonb_build_array('public.lf_eventos'),
          'declared_artifacts','[]'::jsonb,
          'mutation_artifacts','[]'::jsonb
        ),
        'verification_queries',jsonb_build_array(format(
          'select programacion.fn_engineering_closure_event_guarded_v2(%L,%L,%L,%L) as result',
          'IG_CURATOR_VALIDATOR_REFACTOR_V2',
          v_new->>'unit_code',
          v_new->>'checkpoint_code',
          'INDEPENDENT_READBACK'
        )),
        'assertion_contract',jsonb_build_object(
          'mode','EXPLICIT_PASS_WHEN_SUBSET',
          'pass_when',jsonb_build_object('status','PASS')
        ),
        'expected','Persist independent canonical closure readback only after the predecessor HANDOFF exists and terminal acceptance passes.'
      )
    )-'required_contract';

    update programacion.engineering_plan_units pu
    set unit_metadata=jsonb_set(
      pu.unit_metadata,'{action_specs_v1}',
      coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
        ||jsonb_build_object(v_new->>'checkpoint_code',v_spec),true
    )
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.unit_code=v_new->>'unit_code';
  end loop;

  -- Negative false-closure is a test obligation, not terminal acceptance.
  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{action_specs_v1}',
    coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
      || jsonb_build_object(
        'NEG_FALSE_CLOSURE',
        (pu.unit_metadata#>'{action_specs_v1,NEG_FALSE_CLOSURE}')
          || jsonb_build_object(
            'status','BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED',
            'precision','RECLASSIFIED_NEGATIVE_TEST_CONTRACT_V1',
            'action_kind','DECLARED_TEST_EXECUTION',
            'contract_family','AUTHORED_TEST_DRILL_REQUIRED',
            'expected','Exact negative closure test must prove that an open unit or stale receipt is rejected; fallback test discovery is forbidden.'
          )
      ),true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M10.13';

  -- M9.12 is material capability execution, not terminal readback. Bind exact
  -- reusable authorities and leave only the capability input/execution receipt.
  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{action_specs_v1}',
    coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
      || jsonb_build_object(
        'CLOSURE_GATE_CONSUME',
        (pu.unit_metadata#>'{action_specs_v1,CLOSURE_GATE_CONSUME}')
          || jsonb_build_object(
            'status','BLOCK_TRANSVERSAL_CAPABILITY_EXECUTION_REQUIRED',
            'precision','EXPLICIT_FINAL_EVIDENCE_CLOSURE_GATE_EXECUTION_V1',
            'action_kind','TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION',
            'requires_material_execution',true,
            'contract_family','TRANSVERSAL_CAPABILITY_EXECUTION_PENDING',
            'capability_execution_contract',jsonb_build_object(
              'sequence',jsonb_build_array('FINAL_EVIDENCE','CLOSURE_GATE'),
              'authority_owner','SUPER_ADMIN',
              'input_source','CURRENT_M9_PREREQUISITE_RECEIPTS_AND_M9_0_BUNDLE',
              'result','CUTOVER_READY',
              'ig_local_gate','FORBIDDEN'
            ),
            'expected','Execute FINAL_EVIDENCE then CLOSURE_GATE using current released capabilities and exact M9 prerequisite receipts; emit CUTOVER_READY only from that result.'
          )
      ),true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M9.12';
end;
$repair$;

do $selftest$
declare
  v_terminal_generic int;
  v_ready int;
begin
  with x as (
    select pu.unit_code,c.checkpoint_code,
      programacion.fn_engineering_checkpoint_action_spec_v3(
        'IG_CURATOR_VALIDATOR_REFACTOR_V2',pu.unit_code,c.checkpoint_code
      ) s
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.disposition='ASSIGNED'
      and c.required and c.status not in ('DONE','NOT_APPLICABLE')
  )
  select count(*) filter(where s->>'status'='BLOCK_TERMINAL_ACCEPTANCE_CONTRACT_REQUIRED'),
         count(*) filter(where (unit_code,checkpoint_code) in (
           ('M9.8','CLOSURE_GATE_ASIS'),
           ('M10.13','CLOSURE_GATE_REUSE'),
           ('M4.12','M4_HANDOFF_READBACK'),
           ('M5.10','INDEPENDENT_READBACK'),
           ('M6.13','INDEPENDENT_READBACK')
         ) and s->>'status'='READY')
    into v_terminal_generic,v_ready
  from x;

  if v_terminal_generic<>0 then
    raise exception 'ENGINEERING_TERMINAL_RESIDUAL_GENERIC_BLOCKS_REMAIN:%',v_terminal_generic;
  end if;
  if v_ready<>5 then
    raise exception 'ENGINEERING_TERMINAL_RESIDUAL_READY_MISMATCH:%',v_ready;
  end if;
end;
$selftest$;

update public.lf_error_knowledge
set validacion='PASS when terminal/readback/handoff generic family blockers are zero. Pure readbacks reuse current authority; canonical closure writes use guarded closure events; negative closure is a test obligation; M9.12 remains fail-closed as exact FINAL_EVIDENCE+CLOSURE_GATE execution.',
    ultima_vez=now(),updated_at=now()
where codigo='ENGINEERING-CONTRACT-REDUCTION-TERMINAL-HANDOFF-001';
