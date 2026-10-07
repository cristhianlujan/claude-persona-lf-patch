-- ENGINEERING bounded checkpoint test authoring v1
-- Converts verification/test contract debt into real executable checkpoint work:
-- author one exact test artifact -> run it -> record machine assertion -> transition.
-- Semantic authority is the canonical plan exit criterion plus declared source pack,
-- never title-only inference.

create or replace function programacion.fn_engineering_bounded_checkpoint_test_spec_v1(
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
  v_exit text;
  v_title text;
  v_test_code text;
  v_test_path text;
  v_family text := coalesce(v_spec->>'contract_family','');
  v_old_status text := coalesce(v_spec->>'status','');
  v_negative boolean := false;
  v_target jsonb := coalesce(v_spec->'target','{}'::jsonb);
  v_evidence jsonb := coalesce(v_target->'evidence_artifacts',v_target->'declared_artifacts','[]'::jsonb);
  v_mutation jsonb;
  v_pass_when jsonb;
begin
  select pu.exit_criterion,c.title
    into v_exit,v_title
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_checkpoints c
    on c.work_item_id=pu.work_item_id
   and c.checkpoint_code=p_checkpoint_code
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_exit is null then
    raise exception 'ENGINEERING_CHECKPOINT_TEST_EXIT_CRITERION_MISSING:%/%/%',
      p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  v_negative :=
    v_old_status in (
      'BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED',
      'BLOCK_MUTATION_TARGET_ASSERTION_REQUIRED'
    )
    or p_checkpoint_code ~* '(^NEG_|NEGATIVE|FALSE|DRIFT|TAMPER|MUTATION|OVER_LIMIT|INSUFFICIENT|MISMATCH|RESIDUE|UNRESOLVED|MISSING)'
    or coalesce(v_title,'') ~* 'negativ';

  v_test_code :=
    'ENG_'||
    upper(regexp_replace(p_unit_code,'[^A-Za-z0-9]+','_','g'))||'_'||
    upper(regexp_replace(p_checkpoint_code,'[^A-Za-z0-9]+','_','g'));

  v_test_path :=
    'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/'||
    lower(regexp_replace(p_unit_code,'[^A-Za-z0-9]+','_','g'))||'/'||
    lower(regexp_replace(p_checkpoint_code,'[^A-Za-z0-9]+','_','g'))||'.py';

  v_mutation:=jsonb_build_array(jsonb_build_object(
    'path',v_test_path,
    'role','MUTATION_TARGET',
    'target_kind','EXACT_NEW_OR_UPDATE_FILE',
    'purpose','CHECKPOINT_TEST_ARTIFACT'
  ));

  v_target:=v_target||jsonb_build_object(
    'evidence_artifacts',v_evidence,
    'mutation_artifacts',v_mutation,
    'declared_artifacts',v_mutation
  );

  v_pass_when:=jsonb_build_object(
    'test_passed',true,
    'test_exit_code',0,
    'semantic_authority_bound',true
  );
  if v_negative then
    v_pass_when:=v_pass_when||jsonb_build_object('adversarial_case_executed',true);
  end if;

  return (
    v_spec
    || jsonb_build_object(
      'status','READY',
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
      'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING',
      'recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
      'requires_material_execution',true,
      'mutation_policy','TEST_ARTIFACT_ONLY',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'contract_family','BOUNDED_CHECKPOINT_TEST',
      'target',v_target,
      'assertion_contract',jsonb_build_object(
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',v_pass_when
      ),
      'test_execution_contract',jsonb_build_object(
        'mode',case when v_negative then 'AUTHORED_NEGATIVE' else 'EXPLICIT_VERIFICATION_QUERY' end,
        'test_code',v_test_code,
        'test_path',v_test_path,
        'authoring_required',true,
        'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION',
        'canonical_exit_criterion',v_exit,
        'checkpoint_title_context',v_title,
        'declared_queries',coalesce(v_spec->'verification_queries','[]'::jsonb),
        'declared_objects',coalesce(v_target->'declared_objects','[]'::jsonb),
        'negative_required',v_negative,
        'fallback_case_discovery','FORBIDDEN',
        'synthetic_pass','FORBIDDEN'
      ),
      'expected','Author and execute the exact checkpoint test against the canonical exit criterion and declared source pack. PASS requires real test evidence and machine assertion receipt.'
    )
  ) - 'required_contract';
end;
$function$;

comment on function programacion.fn_engineering_bounded_checkpoint_test_spec_v1(text,text,text,jsonb)
is 'Compiles verification/test debt to one exact checkpoint-owned test artifact whose semantics are bound to the canonical plan exit criterion and declared source pack.';

create or replace function programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1(
  p_packet jsonb,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_contract jsonb := coalesce(p_action_spec->'test_execution_contract','{}'::jsonb);
  v_test_code text := nullif(v_contract->>'test_code','');
  v_test_path text := nullif(v_contract->>'test_path','');
  v_plan jsonb;
begin
  if coalesce(p_action_spec->>'status','')<>'READY'
     or coalesce(p_action_spec->>'contract_family','')<>'BOUNDED_CHECKPOINT_TEST' then
    return p_packet;
  end if;

  if v_test_code is null or v_test_path is null
     or nullif(v_contract->>'canonical_exit_criterion','') is null then
    return p_packet||jsonb_build_object(
      'status','BLOCK_BOUNDED_CHECKPOINT_TEST_CONTRACT_INCOMPLETE',
      'execution_allowed',false
    );
  end if;

  v_plan:=programacion.fn_engineering_plan_add_transition_args_v1(
    jsonb_build_array(
      jsonb_build_object(
        'seq',1,
        'provider','GITHUB',
        'operation','WRITE_GIT',
        'capability','WRITE_GIT',
        'mode','AUTHOR_CHECKPOINT_TEST',
        'targets',jsonb_build_array(jsonb_build_object(
          'path',v_test_path,
          'test_code',v_test_code
        )),
        'authoring_contract',jsonb_build_object(
          'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION',
          'canonical_exit_criterion',v_contract->>'canonical_exit_criterion',
          'checkpoint_title_context',v_contract->>'checkpoint_title_context',
          'declared_queries',coalesce(v_contract->'declared_queries','[]'::jsonb),
          'declared_objects',coalesce(v_contract->'declared_objects','[]'::jsonb),
          'negative_required',coalesce((v_contract->>'negative_required')::boolean,false),
          'synthetic_pass','FORBIDDEN',
          'fallback_case_discovery','FORBIDDEN',
          'scope','CURRENT_CHECKPOINT_ONLY'
        ),
        'executor_contract',jsonb_build_object(
          'branch_required',true,
          'pull_request_required',true,
          'governed_merge_required',true,
          'direct_main_write','FORBIDDEN',
          'exact_test_path_required',true
        )
      ),
      jsonb_build_object(
        'seq',2,
        'provider','GITHUB',
        'operation','RUN_TEST',
        'capability','RUN_TEST',
        'mode','AUTHORED_CHECKPOINT_TEST',
        'targets',jsonb_build_array(jsonb_build_object(
          'path',v_test_path,
          'test_code',v_test_code
        )),
        'test_execution_contract',v_contract,
        'result_contract',jsonb_build_object(
          'status','PASS',
          'test_code',v_test_code,
          'observed_required',true,
          'evidence_ref_required',true
        )
      ),
      jsonb_build_object(
        'seq',3,
        'provider','SUPABASE',
        'operation','CHECKPOINT_ASSERTION_RECORD',
        'capability','WRITE_DB',
        'entrypoint','programacion.fn_engineering_checkpoint_assertion_record_v1',
        'result_source','PREVIOUS_RUN_TEST_RESULT',
        'result_mapping',jsonb_build_object(
          'status','PASS',
          'evidence_ref','RUN_TEST_EVIDENCE_REF',
          'observed','RUN_TEST_OBSERVED'
        )
      ),
      jsonb_build_object(
        'seq',4,
        'provider','SUPABASE',
        'operation','CHECKPOINT_TRANSITION'
      )
    ),
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  return p_packet||jsonb_build_object(
    'status','READY',
    'execution_allowed',true,
    'execution_capability','RUN_TEST',
    'capability_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
    'requires_material_execution',true,
    'effective_action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING',
    'verification_mode','AUTHORED_TEST_BOUND_TO_CANONICAL_EXIT_CRITERION',
    'explicit_test_case_set',jsonb_build_array(v_test_code),
    'block_reasons','[]'::jsonb,
    'connector_plan',v_plan,
    'mutation_policy','TEST_ARTIFACT_ONLY'
  );
end;
$function$;

comment on function programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1(jsonb,text,text,text,jsonb)
is 'Packet overlay for bounded checkpoint tests: governed Git authoring, exact test execution, assertion receipt, then checkpoint transition.';

-- Tests are test artifacts, even when their title mentions a migration under test.
-- Do not require the checkpoint-test action itself to author a database migration.
create or replace function programacion.fn_engineering_action_spec_apply_git_migration_guard_v1(
  p_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_spec jsonb := coalesce(p_spec,'{}'::jsonb);
  v_title text := lower(coalesce(v_spec->>'checkpoint_title',''));
  v_material boolean := coalesce((v_spec->>'requires_material_execution')::boolean,false);
  v_expects_migration boolean := false;
  v_has_migration boolean := false;
  v_mutation_artifacts jsonb;
begin
  if coalesce(v_spec->>'status','')<>'READY' then
    return v_spec;
  end if;

  if coalesce(v_spec->>'contract_family','')='BOUNDED_CHECKPOINT_TEST'
     or coalesce(v_spec->>'recipe_mode','')='AUTHOR_AND_RUN_CHECKPOINT_TEST' then
    return v_spec;
  end if;

  v_expects_migration :=
    v_material
    and (
      coalesce(v_spec->>'recipe_mode','') in ('GIT_FIRST_MIGRATION','GIT_FIRST_OR_VERSIONED_CONTRACT')
      or (
        v_title ~ '(migraci|git-first)'
        and v_title !~ '(fuera de|sin|excepto|salvo) (las |los )?migraci'
      )
    );

  if not v_expects_migration then
    return v_spec;
  end if;

  v_mutation_artifacts :=
    programacion.fn_engineering_action_spec_artifact_roles_v1(v_spec)
    #>'{target,mutation_artifacts}';

  select exists(
    select 1
    from jsonb_array_elements(coalesce(v_mutation_artifacts,'[]'::jsonb)) a(item)
    where coalesce(a.item->>'path','') like '%:supabase/migrations/%'
       or coalesce(a.item->>'path','') like '%/supabase/migrations/%'
  ) into v_has_migration;

  if v_has_migration then
    return v_spec;
  end if;

  return v_spec || jsonb_build_object(
    'status','BLOCK_GIT_MIGRATION_ARTIFACT_NOT_AUTHORED',
    'precision','EXPLICIT_GIT_FIRST_MIGRATION_OUTPUT_REQUIRED',
    'migration_guard',jsonb_build_object(
      'expected_output','supabase/migrations/<version>_<name>.sql',
      'declared_migration_artifact_present',false,
      'mutation_artifact_required',true,
      'evidence_artifacts_do_not_satisfy_output',true,
      'docs_or_auxiliary_artifacts_do_not_satisfy_output',true
    ),
    'forbidden',
      coalesce(v_spec->'forbidden','[]'::jsonb)
      || jsonb_build_array(
        'ACTION_SPEC_READY_WITHOUT_REQUIRED_MIGRATION_OUTPUT',
        'TREAT_DOC_AS_MIGRATION_OUTPUT',
        'TREAT_EVIDENCE_ARTIFACT_AS_MUTATION_TARGET'
      )
  );
end;
$function$;

-- Preserve the current execution compiler and add the bounded-test overlay
-- before the generic RUN_TEST guard.
create or replace function programacion.fn_engineering_execution_packet_from_spec_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb,
  p_execution_input jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_packet jsonb;
  v_budget int;
  v_spec jsonb := programacion.fn_engineering_action_spec_artifact_roles_v1(
    coalesce(p_action_spec,'{}'::jsonb)
  );
  v_material boolean := coalesce((p_action_spec->>'requires_material_execution')::boolean,false);
  v_kind text := coalesce(p_action_spec->>'action_kind','');
  v_title text := coalesce(p_action_spec->>'checkpoint_title','');
begin
  if v_material
     and v_kind not in ('READBACK_ONCE','OBSERVE_ONCE','DECISION_GATE','TERMINAL_RECONCILE') then
    v_spec := jsonb_set(
      v_spec,
      '{checkpoint_title}',
      to_jsonb('execute material: ' || v_title),
      true
    );
  end if;

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_spec,p_execution_input
  );

  v_packet:=programacion.fn_engineering_execution_packet_apply_transversal_adapter_v1(
    v_packet,p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec
  );

  v_packet:=programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1(
    v_packet,p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec
  );

  v_packet:=programacion.fn_engineering_packet_apply_test_contract_guard_v1(
    v_packet,p_action_spec
  );

  v_packet:=programacion.fn_engineering_packet_apply_assertion_guard_v1(
    v_packet,p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec
  );

  v_budget:=nullif(p_action_spec#>>'{read_budget,checkpoint_queries_max}','')::int;

  if v_budget is null then
    select nullif(
      coalesce(
        pu.unit_metadata#>>'{source_fast_path_v2,read_budget,checkpoint_queries_max}',
        pu.unit_metadata#>>'{source_fast_path_v1,preferred_queries_max}'
      ),''
    )::int
    into v_budget
    from programacion.engineering_plan_units pu
    where pu.plan_code=p_plan_code
      and pu.unit_code=p_unit_code;
  end if;

  v_packet:=programacion.fn_engineering_packet_apply_read_budget_v1(
    v_packet,v_budget
  );

  v_packet:=programacion.fn_engineering_packet_apply_governed_merge_v1(v_packet);

  return v_packet || jsonb_build_object(
    'artifact_role_contract',v_spec->'artifact_role_contract',
    'evidence_artifacts',v_spec#>'{target,evidence_artifacts}',
    'mutation_artifacts',v_spec#>'{target,mutation_artifacts}',
    'readonly_policy',jsonb_build_object(
      'scope','EXPLICIT_READ_ACTIONS_ONLY',
      'materiality_authority','ACTION_SPEC_REQUIRES_MATERIAL_EXECUTION',
      'title_based_materiality_downgrade','FORBIDDEN',
      'material_actions_allowed',jsonb_build_array('WRITE_DB','WRITE_GIT','RUN_TEST')
    )
  );
end;
$function$;

do $bind$
declare
  r record;
  v_spec jsonb;
  v_new jsonb;
  v_count int := 0;
begin
  for r in
    select pu.unit_code,c.checkpoint_code
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c
      on c.work_item_id=pu.work_item_id
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.disposition='ASSIGNED'
      and c.required
      and c.status not in ('DONE','NOT_APPLICABLE')
      and programacion.fn_engineering_checkpoint_action_spec_v3(
        'IG_CURATOR_VALIDATOR_REFACTOR_V2',pu.unit_code,c.checkpoint_code
      )->>'status' in (
        'BLOCK_VERIFICATION_ASSERTION_REQUIRED',
        'BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED',
        'BLOCK_TEST_EXECUTION_CONTRACT_MISSING',
        'BLOCK_MUTATION_TARGET_ASSERTION_REQUIRED'
      )
    order by pu.unit_code,c.sequence_no
  loop
    select pu.unit_metadata#>array['action_specs_v1',r.checkpoint_code]
      into v_spec
    from programacion.engineering_plan_units pu
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.unit_code=r.unit_code
      and pu.disposition='ASSIGNED';

    if v_spec is null then
      raise exception 'ENGINEERING_BOUNDED_TEST_SPEC_MISSING:%/%',r.unit_code,r.checkpoint_code;
    end if;

    v_new:=programacion.fn_engineering_bounded_checkpoint_test_spec_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',
      r.unit_code,
      r.checkpoint_code,
      v_spec
    );

    update programacion.engineering_plan_units pu
    set unit_metadata=jsonb_set(
      pu.unit_metadata,
      '{action_specs_v1}',
      coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
        ||jsonb_build_object(r.checkpoint_code,v_new),
      true
    )
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.unit_code=r.unit_code
      and pu.disposition='ASSIGNED';

    v_count:=v_count+1;
  end loop;

  if v_count<>71 then
    raise exception 'ENGINEERING_BOUNDED_TEST_BIND_COUNT expected=71 actual=%',v_count;
  end if;
end;
$bind$;

do $selftest$
declare
  v_generic int;
  v_bound int;
  v_sample jsonb;
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
  select
    count(*) filter(where s->>'status' in (
      'BLOCK_VERIFICATION_ASSERTION_REQUIRED',
      'BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED',
      'BLOCK_TEST_EXECUTION_CONTRACT_MISSING',
      'BLOCK_MUTATION_TARGET_ASSERTION_REQUIRED'
    )),
    count(*) filter(where s->>'contract_family'='BOUNDED_CHECKPOINT_TEST' and s->>'status'='READY')
  into v_generic,v_bound
  from x;

  if v_generic<>0 then
    raise exception 'ENGINEERING_BOUNDED_TEST_GENERIC_BLOCKS_REMAIN:%',v_generic;
  end if;

  if v_bound<>71 then
    raise exception 'ENGINEERING_BOUNDED_TEST_READY_COUNT expected=71 actual=%',v_bound;
  end if;

  v_sample:=programacion.fn_engineering_unit_bootstrap_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','N-17'
  );
  -- N-17 may not currently be on the bounded checkpoint due sequence, so compile
  -- its exact negative checkpoint directly to validate packet semantics.
  v_sample:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'N-17',
    'NEG_HEURISTIC_CAUSALITY',
    programacion.fn_engineering_checkpoint_action_spec_v3(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','N-17','NEG_HEURISTIC_CAUSALITY'
    ),
    '{}'::jsonb
  );

  if v_sample->>'status'<>'READY'
     or v_sample->>'execution_capability'<>'RUN_TEST'
     or v_sample->>'capability_mode'<>'AUTHOR_AND_RUN_CHECKPOINT_TEST'
     or jsonb_array_length(coalesce(v_sample->'connector_plan','[]'::jsonb))<4 then
    raise exception 'ENGINEERING_BOUNDED_TEST_PACKET_SELFTEST_FAIL:%',v_sample;
  end if;
end;
$selftest$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-BOUNDED-CHECKPOINT-TEST-AUTHORING-001',
  'ENGINEERING_ORCHESTRATION',
  'Verification and negative-test debt must compile to executable checkpoint-owned tests',
  'Verification/assertion/test sanitation left checkpoints non-claimable until a test/assertion artifact already existed, recreating the same future-output circular dependency as materialization.',
  'Test artifact existence and test execution authority were collapsed into one precondition.',
  'FUTURE_TEST_ARTIFACT_REQUIRED_BEFORE_TEST_WORKER_CAN_RUN',
  'Compile each verification/test checkpoint to AUTHOR_AND_RUN_CHECKPOINT_TEST with one deterministic checkpoint-owned test path. Bind semantics to canonical plan exit criterion plus exact source-pack queries/objects, author through governed Git, execute the test, record machine assertion evidence, then transition. No fallback test discovery or synthetic PASS.',
  'PASS when the four generic verification/test blocker families are zero, 71 open checkpoints compile READY as BOUNDED_CHECKPOINT_TEST, and packet selftest produces WRITE_GIT + RUN_TEST + assertion record + transition.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_bounded_checkpoint_test_spec_v1; supabase://programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','ENGINEERING_EXECUTOR','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Plan-wide verification/test contract reduction',
  'supabase://programacion.fn_engineering_bounded_checkpoint_test_spec_v1'
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
