-- ENGINEERING_ACTION_SPEC_V1
-- Compiles every current engineering checkpoint into a closed executable action contract.
-- Builds on bootstrap V2 + checkpoint recipe; preserves V1/V2 as compatibility history.

create or replace function programacion.fn_engineering_checkpoint_action_spec_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text default null
) returns jsonb
language sql
stable
set search_path = programacion, public, pg_catalog
as $function$
with u as (
  select pu.plan_code, pu.unit_code, pu.work_item_id, pu.exit_criterion, pu.unit_metadata
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code
), cp as (
  select c.checkpoint_code,c.title,c.sequence_no,c.status
  from programacion.engineering_work_checkpoints c
  join u on u.work_item_id=c.work_item_id
  where c.checkpoint_code=coalesce(
    p_checkpoint_code,
    (
      select c2.checkpoint_code
      from programacion.engineering_work_checkpoints c2
      where c2.work_item_id=u.work_item_id
        and c2.status not in ('DONE','NOT_APPLICABLE')
      order by c2.sequence_no
      limit 1
    )
  )
  limit 1
), inp as (
  select case
    when cp.checkpoint_code is null then null
    when u.unit_metadata#>array['source_pack_v2','checkpoint_inputs',cp.checkpoint_code] is not null
      then u.unit_metadata#>array['source_pack_v2','checkpoint_inputs',cp.checkpoint_code]
    when u.unit_metadata#>array['source_pack_v1','checkpoint_inputs',cp.checkpoint_code] is not null
      then u.unit_metadata#>array['source_pack_v1','checkpoint_inputs',cp.checkpoint_code]
    when u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}' is not null
      and u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}' <> 'null'::jsonb
      then u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}'
    else null
  end execution_input
  from u cross join cp
), base as (
  select
    u.*,
    cp.*,
    inp.execution_input,
    programacion.fn_engineering_checkpoint_recipe_v1(p_plan_code,p_unit_code,cp.checkpoint_code) recipe,
    u.unit_metadata#>array['action_specs_v1',cp.checkpoint_code] explicit_spec
  from u cross join cp cross join inp
), classified as (
  select *,
    (lower(title) ~ '(ejecut|invoc|inyect|mutaci|rollback|revert|2 corridas|2 ejecuciones|concurren|simulad|drill|fresh|fresca|reproducir|reproducci)') as material_action_hint,
    case
      when explicit_spec is not null then 'EXPLICIT_OVERRIDE'
      when recipe->>'recipe_mode'='OBSERVE_AND_PERSIST' then 'OBSERVE_ONCE'
      when recipe->>'recipe_mode'='READBACK_EXACT' then 'READBACK_ONCE'
      when recipe->>'recipe_mode'='TERMINAL_RECONCILE' then 'TERMINAL_RECONCILE'
      when recipe->>'recipe_mode'='DECISION_OR_GATE' then 'DECISION_GATE'
      when recipe->>'recipe_mode'='VERIFY_EXPECTED' and lower(title) ~ '(concurren)' then 'CONCURRENCY_EXECUTION'
      when recipe->>'recipe_mode'='VERIFY_EXPECTED' and lower(title) ~ '(rollback|revert|drill)' then 'ROLLBACK_DRILL'
      when recipe->>'recipe_mode'='VERIFY_EXPECTED' and lower(title) ~ '(timeout)' then 'FAULT_INJECTION_TIMEOUT'
      when recipe->>'recipe_mode'='VERIFY_EXPECTED' and lower(title) ~ '(inyect|regresi)' then 'FAULT_INJECTION'
      when recipe->>'recipe_mode'='VERIFY_EXPECTED' and lower(title) ~ '(mutaci)' then 'MUTATION_EXECUTION'
      when recipe->>'recipe_mode'='VERIFY_EXPECTED' and lower(title) ~ '(2 corridas|2 ejecuciones|reproducir|reproducci|reproducibilidad)' then 'REPRODUCIBILITY_EXECUTION'
      when recipe->>'recipe_mode'='VERIFY_EXPECTED' and lower(title) ~ '(simulad|ejecutables|ejecutar|invoc)' then 'DECLARED_TEST_EXECUTION'
      when recipe->>'recipe_mode'='VERIFY_EXPECTED' then 'VERIFY_QUERY_ONCE'
      else 'MATERIALIZE_DECLARED_DELIVERABLE'
    end action_kind
  from base
), compiled as (
  select *,
    case action_kind
      when 'OBSERVE_ONCE' then jsonb_build_array(
        'EXECUTE_CURRENT_INPUT_ONCE',
        'ASSERT_LIVE_OBSERVATION_MATCHES_CHECKPOINT_TITLE',
        'PERSIST_DONE',
        'USE_RETURNED_BOOTSTRAP'
      )
      when 'READBACK_ONCE' then jsonb_build_array(
        'READ_DECLARED_AUTHORITY_ONCE',
        'ASSERT_EXACT_STATE',
        'PERSIST_DONE',
        'USE_RETURNED_BOOTSTRAP'
      )
      when 'TERMINAL_RECONCILE' then jsonb_build_array(
        'ASSERT_ALL_REQUIRED_PRIOR_CHECKPOINTS_TERMINAL',
        'ASSERT_CLOSURE_EVIDENCE_PRESENT',
        'RECONCILE_LEDGER_ONLY',
        'PERSIST_DONE',
        'USE_RETURNED_BOOTSTRAP'
      )
      when 'DECISION_GATE' then jsonb_build_array(
        'EXECUTE_DECLARED_AUTHORITY_INPUT_ONCE',
        'APPLY_ONLY_CURRENT_GATE_RULE',
        'PERSIST_DECISION_AND_EVIDENCE',
        'USE_RETURNED_BOOTSTRAP'
      )
      when 'VERIFY_QUERY_ONCE' then jsonb_build_array(
        'EXECUTE_CURRENT_INPUT_ONCE',
        'COMPARE_RESULT_TO_CHECKPOINT_EXPECTATION',
        'PERSIST_DONE_ON_PASS',
        'USE_RETURNED_BOOTSTRAP'
      )
      when 'REPRODUCIBILITY_EXECUTION' then jsonb_build_array(
        'FREEZE_ONE_DECLARED_TEST_INPUT',
        'EXECUTE_DECLARED_OPERATION_TWICE_WITH_IDENTICAL_INPUT',
        'CAPTURE_CANONICAL_OUTPUT_OR_SHA_BOTH_TIMES',
        'ASSERT_OUTPUTS_IDENTICAL',
        'EXECUTE_DECLARED_NEGATIVE_IF_PRESENT',
        'ASSERT_DECLARED_NEGATIVE_OUTCOME',
        'PERSIST_DONE_ON_PASS',
        'USE_RETURNED_BOOTSTRAP'
      )
      when 'CONCURRENCY_EXECUTION' then jsonb_build_array(
        'OPEN_ROLLBACK_OR_SANDBOX_TEST_CONTEXT',
        'EXECUTE_DECLARED_OPERATION_CONCURRENTLY_AS_STATED',
        'ASSERT_SINGLE_EFFECT_OR_DECLARED_WAIT_REJECT_OUTCOME',
        'ROLLBACK_TEST_SIDE_EFFECTS',
        'PERSIST_DONE_ON_PASS',
        'USE_RETURNED_BOOTSTRAP'
      )
      when 'ROLLBACK_DRILL' then jsonb_build_array(
        'CAPTURE_PRE_STATE',
        'EXECUTE_DECLARED_REVERSIBLE_CHANGE_IN_SAFE_CONTEXT',
        'EXECUTE_DECLARED_ROLLBACK',
        'ASSERT_PRE_STATE_RESTORED_AND_NO_RESIDUE',
        'PERSIST_DONE_ON_PASS',
        'USE_RETURNED_BOOTSTRAP'
      )
      when 'MUTATION_EXECUTION' then jsonb_build_array(
        'LOAD_ONLY_DECLARED_MUTATION_CASES',
        'EXECUTE_MUTATIONS_ON_DECLARED_TARGET',
        'ASSERT_EACH_EXPECTED_FAIL',
        'BLOCK_ON_ANY_FALSE_PASS',
        'PERSIST_DONE_ON_PASS',
        'USE_RETURNED_BOOTSTRAP'
      )
      when 'FAULT_INJECTION_TIMEOUT' then jsonb_build_array(
        'SANDBOX_OR_ROLLBACK_CONTEXT_ONLY',
        'INJECT_DECLARED_TIMEOUT_FAULT',
        'ASSERT_DECLARED_ROLLBACK_OR_BLOCK_OUTCOME',
        'RESTORE_TEST_CONTEXT',
        'PERSIST_DONE_ON_PASS',
        'USE_RETURNED_BOOTSTRAP'
      )
      when 'FAULT_INJECTION' then jsonb_build_array(
        'SANDBOX_OR_ROLLBACK_CONTEXT_ONLY',
        'INJECT_ONLY_DECLARED_FAULT',
        'ASSERT_DECLARED_FAIL_OR_BLOCK_OUTCOME',
        'RESTORE_TEST_CONTEXT',
        'PERSIST_DONE_ON_PASS',
        'USE_RETURNED_BOOTSTRAP'
      )
      when 'DECLARED_TEST_EXECUTION' then jsonb_build_array(
        'EXECUTE_ONLY_TEST_CASES_NAMED_BY_CURRENT_CHECKPOINT',
        'ASSERT_DECLARED_EXPECTED_OUTCOME',
        'PERSIST_DONE_ON_PASS',
        'USE_RETURNED_BOOTSTRAP'
      )
      else jsonb_build_array(
        'MATERIALIZE_ONLY_CURRENT_CHECKPOINT_DELIVERABLE',
        'VERIFY_DECLARED_DELIVERABLE_EXACTLY',
        'PERSIST_DONE_ON_PASS',
        'USE_RETURNED_BOOTSTRAP'
      )
    end compiled_steps
  from classified
)
select case
  when explicit_spec is not null then
    explicit_spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V1',
      'status',coalesce(explicit_spec->>'status','READY'),
      'precision',coalesce(explicit_spec->>'precision','EXPLICIT'),
      'checkpoint_code',checkpoint_code,
      'checkpoint_title',title,
      'checkpoint_sequence_no',sequence_no,
      'recipe_mode',recipe->>'recipe_mode',
      'persist',jsonb_build_object(
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'on_pass','DONE',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      )
    )
  else jsonb_build_object(
    'schema_version','ENGINEERING_ACTION_SPEC_V1',
    'status',case when execution_input is null then 'INCOMPLETE_MISSING_EXECUTION_INPUT' else 'READY' end,
    'precision',case when material_action_hint then 'COMPILED_TYPED_HANDLER' else 'COMPILED_CLOSED' end,
    'checkpoint_code',checkpoint_code,
    'checkpoint_title',title,
    'checkpoint_sequence_no',sequence_no,
    'recipe_mode',recipe->>'recipe_mode',
    'action_kind',action_kind,
    'requires_material_execution',material_action_hint,
    'target',jsonb_build_object(
      'checkpoint',checkpoint_code,
      'declared_objects',coalesce(execution_input#>'{inputs,db_objects}','[]'::jsonb),
      'declared_assets',coalesce(execution_input#>'{inputs,assets}','[]'::jsonb),
      'declared_artifacts',coalesce(execution_input#>'{inputs,artifacts}','[]'::jsonb),
      'declared_events',coalesce(execution_input#>'{inputs,events}','[]'::jsonb)
    ),
    'action_steps',compiled_steps,
    'expected',title,
    'verification_queries',coalesce(execution_input#>'{inputs,queries}','[]'::jsonb),
    'persist',jsonb_build_object(
      'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
      'on_pass','DONE',
      'next_state','RETURNED_BOOTSTRAP_ONLY'
    ),
    'fallback_only_on',jsonb_build_array(
      'MISSING_CANONICAL_OBJECT','CONTRADICTION','STALE_CURRENTNESS','DEMONSTRATED_DRIFT','MATERIAL_FINGERPRINT_CHANGE'
    ),
    'forbidden',jsonb_build_array(
      'FREEFORM_CROSS_CHECKPOINT_DESIGN','REPEATED_SOLUTION_REDESIGN','UNTRIGGERED_DISCOVERY','NARRATIVE_PROGRESS_PERCENT'
    )
  )
end
from compiled;
$function$;

-- Explicit action override for M2.8 current reproducibility checkpoint.
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1,REPRODUCIBILITY_NEGATIVE}',
  jsonb_build_object(
    'status','READY',
    'precision','EXPLICIT',
    'action_kind','DETERMINISTIC_REPRODUCIBILITY_AND_SEMANTIC_NEGATIVE',
    'target',jsonb_build_object(
      'function','programacion.fn_input_deterministic_assess(jsonb,text,jsonb,jsonb)',
      'fresh_screen_sample_size',3,
      'families_per_screen',47,
      'fresh_executions_per_input',2,
      'historical_baseline','13x47_REUSE_ONLY'
    ),
    'sample_selection',jsonb_build_object(
      'mode','FRESHEST_ELIGIBLE_COMPLETED_SCREEN_SAMPLE',
      'size',3,
      'tie_break','pantalla_id ASC',
      'selector_query','select pantalla_id from (select pantalla_id,max(created_at) last_at from programacion.input_readiness_runs where status=''COMPLETED'' group by pantalla_id) s order by last_at desc nulls last,pantalla_id asc limit 3'
    ),
    'action_steps',jsonb_build_array(
      'RUN_SAMPLE_SELECTOR_ONCE_AND_FREEZE_3_SCREEN_IDS',
      'REUSE_CURRENT_SUBJECT_GRAPH_CONTRACT_INPUTS_FOR_47_FAMILIES_PER_SELECTED_SCREEN',
      'CALL_FN_INPUT_DETERMINISTIC_ASSESS_TWICE_PER_IDENTICAL_INPUT',
      'CAPTURE_CANONICAL_JSON_BYTES_AND_SHA256_FOR_RUN1_AND_RUN2',
      'ASSERT_BYTE_IDENTICAL_AND_SHA_EQUAL_FOR_ALL_3x47',
      'RUN_ONE_DECLARED_SEMANTIC_SOURCE_INPUT_NEGATIVE',
      'ASSERT_DETERMINISTIC_FACADE_REJECTS_OR_REFUSES_SEMANTIC_SOURCE',
      'USE_13x47_HISTORY_ONLY_FOR_PARITY_READBACK_NOT_FRESH_EXECUTION',
      'PERSIST_DONE_ON_PASS',
      'USE_RETURNED_BOOTSTRAP'
    ),
    'expected',jsonb_build_object(
      'fresh_scope','3x47',
      'reproducibility','BYTE_IDENTICAL_AND_SAME_SHA',
      'semantic_source_negative','REJECTED',
      'fresh_13x47','FORBIDDEN_UNLESS_FALLBACK_TRIGGER'
    ),
    'execution_input_override',jsonb_build_object(
      'inputs',jsonb_build_object(
        'queries',jsonb_build_array(
          'select pantalla_id from (select pantalla_id,max(created_at) last_at from programacion.input_readiness_runs where status=''COMPLETED'' group by pantalla_id) s order by last_at desc nulls last,pantalla_id asc limit 3'
        ),
        'db_objects',jsonb_build_array(
          'programacion.fn_input_deterministic_assess(jsonb,text,jsonb,jsonb)',
          'programacion.input_readiness_runs',
          'programacion.input_family_assessments'
        ),
        'assets','[]'::jsonb,
        'events','[]'::jsonb,
        'artifacts','[]'::jsonb
      ),
      'missing','[]'::jsonb,
      'missing_typed','[]'::jsonb,
      'action_handler','DETERMINISTIC_REPRODUCIBILITY_AND_SEMANTIC_NEGATIVE'
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M2.8';

create or replace function programacion.fn_engineering_unit_bootstrap_v3(
  p_plan_code text,
  p_unit_code text
) returns jsonb
language sql
stable
set search_path = programacion, public, pg_catalog
as $function$
with b as (
  select programacion.fn_engineering_unit_bootstrap_v2(p_plan_code,p_unit_code) payload
), a as (
  select case
    when b.payload->'current_checkpoint' is null then null
    else programacion.fn_engineering_checkpoint_action_spec_v1(
      p_plan_code,p_unit_code,b.payload#>>'{current_checkpoint,checkpoint_code}'
    )
  end action_spec,
  b.payload
  from b
)
select payload
  || jsonb_build_object(
      'schema_version','ENGINEERING_UNIT_BOOTSTRAP_V3',
      'action_spec',action_spec,
      'action_spec_gate',case
        when payload->'current_checkpoint' is null then 'NOT_APPLICABLE'
        when action_spec->>'status'='READY' then 'PASS'
        else 'BLOCK'
      end,
      'terminal_action',case
        when payload->'current_checkpoint' is not null and coalesce(action_spec->>'status','')<>'READY'
          then 'STOP_ACTION_SPEC_INCOMPLETE'
        else payload->>'terminal_action'
      end,
      'execution_input',coalesce(action_spec->'execution_input_override',payload->'execution_input'),
      'execution_contract',jsonb_build_object(
        'sequence',jsonb_build_array(
          'BOOTSTRAP_V3','OBEY_ACTION_SPEC','EXECUTE_CURRENT_ACTION_ONLY','VERIFY_CURRENT_CHECKPOINT','PERSIST_ATOMIC_TRANSITION','USE_RETURNED_BOOTSTRAP'
        ),
        'freeform_design_before_action_spec','FORBIDDEN',
        'progress','LEDGER_DERIVED_ONLY'
      )
    )
from a;
$function$;

-- Make V3 the single entrypoint for the whole IG plan; preserve V2 as compatibility history.
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  jsonb_set(
    coalesce(unit_metadata,'{}'::jsonb),
    '{canonical_bootstrap_v3}',
    jsonb_build_object(
      'contract','ENGINEERING_UNIT_BOOTSTRAP_V3',
      'entrypoint','programacion.fn_engineering_unit_bootstrap_v3',
      'identity',jsonb_build_array('plan_code','unit_code'),
      'action_spec','programacion.fn_engineering_checkpoint_action_spec_v1',
      'transition_entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
      'action_spec_gate','REQUIRED_FOR_PENDING_CHECKPOINT',
      'progress_rule','LEDGER_DERIVED_ONLY',
      'effective_at',now()
    ),true
  ),
  '{canonical_bootstrap_v2,status}','"COMPATIBILITY_ONLY"'::jsonb,true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2';

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{source_pack_v1,lookup_strategy_v2,preferred_input}',
  jsonb_build_object(
    'mode','CANONICAL_ENGINEERING_UNIT_BOOTSTRAP',
    'entrypoint','programacion.fn_engineering_unit_bootstrap_v3',
    'args',jsonb_build_object('plan_code',plan_code,'unit_code',unit_code),
    'rule','CALL_DIRECTLY_BEFORE_SOURCE_PACK_OR_WORK_CODE_LOOKUP'
  ),true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_metadata ? 'source_pack_v1';

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{source_pack_v2,preferred_input}',
  jsonb_build_object(
    'mode','CANONICAL_ENGINEERING_UNIT_BOOTSTRAP',
    'entrypoint','programacion.fn_engineering_unit_bootstrap_v3',
    'args',jsonb_build_object('plan_code',plan_code,'unit_code',unit_code),
    'rule','CALL_DIRECTLY_BEFORE_SOURCE_PACK_OR_WORK_CODE_LOOKUP'
  ),true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_metadata ? 'source_pack_v2';

update public.lf_error_knowledge
set estado='SUPERSEDED',
    prevencion='SUPERSEDED by ENGINEERING-ACTION-SPEC-CONTRACT-001. Use bootstrap V3 with mandatory ACTION_SPEC_V1.',
    updated_at=now()
where codigo='ENGINEERING-CHECKPOINT-EXECUTION-CONTRACT-001';

update public.lf_error_knowledge
set prevencion='Invoke programacion.fn_engineering_unit_bootstrap_v3(plan_code,unit_code) as the first and only plan entrypoint. work_code is derived. Do not discover SOURCE_PACK, schemas, projects or dependencies before bootstrap.',
    validacion='PASS when all IG units expose canonical_bootstrap_v3 and pending checkpoints receive action_spec_gate=PASS before execution.',
    source_ref='supabase://programacion.fn_engineering_unit_bootstrap_v3',
    updated_at=now()
where codigo='ENGINEERING-PLAN-CANONICAL-BOOTSTRAP-001';

insert into public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,created_at,updated_at,lifecycle_phase,consumer_role,
  root_cause_family,detectability,source_context,source_ref
)
select gen_random_uuid(),
  'ENGINEERING-ACTION-SPEC-CONTRACT-001',
  'ENGINEERING_GOVERNANCE',
  'A checkpoint must declare an executable action, not only evidence to inspect',
  'Bootstrap and checkpoint recipes can still stall when execution_input shows evidence but does not state the exact action needed to close the checkpoint.',
  'The evidence contract was more precise than discovery but less precise than execution.',
  'diagnosis -> free-form deliberation -> delayed material action',
  'Use ENGINEERING_UNIT_BOOTSTRAP_V3. Every pending checkpoint must return ACTION_SPEC_V1 with status READY. Closed/readback checkpoints compile automatically; material tests use typed handlers; explicit overrides replace stale execution inputs when needed. STOP_ACTION_SPEC_INCOMPLETE is fail-closed.',
  'PASS when all pending IG checkpoints return action_spec.status=READY, action_spec_gate=PASS, no pending checkpoint lacks execution_input, and M2.8 REPRODUCIBILITY_NEGATIVE uses fresh 3x47 execution while 13x47 remains history-only.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2',null,'ACTIVO',
  'supabase://programacion.fn_engineering_unit_bootstrap_v3',now(),now(),'EXECUTION',
  '{IG,ENGINEERING_AGENT}'::text[],'R5_EROSION_PROCESO','PROCESS_DEPENDENT',
  'IG checkpoint diagnosis-to-action latency','supabase://programacion.fn_engineering_checkpoint_action_spec_v1'
where not exists (select 1 from public.lf_error_knowledge where codigo='ENGINEERING-ACTION-SPEC-CONTRACT-001');
