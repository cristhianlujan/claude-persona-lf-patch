
do $$
declare
  v_body text;
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='programacion'
      and p.proname='fn_engineering_checkpoint_action_spec_v3_legacy'
  ) then
    select routine_definition into v_body
    from information_schema.routines
    where routine_schema='programacion'
      and routine_name='fn_engineering_checkpoint_action_spec_v3';

    if v_body is null then
      raise exception 'ACTION_SPEC_V3_SOURCE_NOT_FOUND';
    end if;

    execute
      'create function programacion.fn_engineering_checkpoint_action_spec_v3_legacy(' ||
      'p_plan_code text, p_unit_code text, p_checkpoint_code text default null::text) ' ||
      'returns jsonb language sql stable as ' || quote_literal(v_body);
  end if;
end
$$;

update programacion.engineering_plan_units
set unit_metadata =
  unit_metadata ||
  jsonb_build_object(
    'transversal_execution_v1',
    coalesce(unit_metadata->'transversal_execution_v1','{}'::jsonb) ||
    jsonb_build_object(
      'SHADOW_RUN',
      jsonb_build_object(
        'mode','EXPLICIT',
        'capabilities',jsonb_build_array('CONTROL_EQUIVALENCE_JUDGE'),
        'dependency_resolution','MANIFEST_GRAPH',
        'execution_order','TOPOLOGICAL',
        'admission_required',false
      )
    )
  )
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M3.9';

create or replace function programacion.fn_engineering_checkpoint_action_spec_v3(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text default null::text
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_base jsonb;
  v_tx jsonb;
  v_cp text;
  v_caps jsonb;
  v_plan_digest text;
begin
  v_base := programacion.fn_engineering_checkpoint_action_spec_v3_legacy(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  if v_base is null then
    return null;
  end if;

  v_cp := coalesce(p_checkpoint_code,v_base->>'checkpoint_code');

  select pu.unit_metadata#>array['transversal_execution_v1',v_cp]
    into v_tx
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code;

  if v_tx is null then
    return v_base;
  end if;

  if coalesce(v_tx->>'mode','')='SELECT' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_SELECTOR_RUNTIME_REQUIRED',
      'precision','STRUCTURAL_TRANSVERSAL_SELECT',
      'transversal_execution',v_tx,
      'transversal_gate','SELECTOR_REQUIRED',
      'forbidden',coalesce(v_base->'forbidden','[]'::jsonb)
        || jsonb_build_array('FALLBACK_TO_TITLE_HEURISTIC_WHEN_SELECT_DECLARED')
    );
  end if;

  if coalesce(v_tx->>'mode','')<>'EXPLICIT' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_MODE_INVALID',
      'transversal_execution',v_tx
    );
  end if;

  v_caps := coalesce(v_tx->'capabilities','[]'::jsonb);

  if jsonb_typeof(v_caps)<>'array' or jsonb_array_length(v_caps)=0 then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_CAPABILITIES_MISSING',
      'transversal_execution',v_tx
    );
  end if;

  if jsonb_array_length(v_caps)=1
     and v_caps @> jsonb_build_array('CONTROL_EQUIVALENCE_JUDGE') then

    v_plan_digest := encode(
      extensions.digest(
        convert_to(
          p_plan_code||':'||p_unit_code||'|CONTROL_EQUIVALENCE_JUDGE|EXACT_ONLY',
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    );

    return v_base || jsonb_build_object(
      'status','READY',
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','STRUCTURAL_TRANSVERSAL_EXPLICIT',
      'action_kind','DECLARED_CAPABILITY_TEST_EXECUTION',
      'recipe_mode','EXECUTE_DECLARED_CAPABILITY_TEST',
      'requires_material_execution',true,
      'mutation_policy','TEST_EVIDENCE_ONLY',
      'transversal_execution',v_tx,
      'transversal_gate','PASS_EXPLICIT',
      'target',
        coalesce(v_base->'target','{}'::jsonb)
        || jsonb_build_object(
          'declared_objects',
          coalesce(v_base#>'{target,declared_objects}','[]'::jsonb)
          || jsonb_build_array(
            'programacion.fn_input_governance_shadow_evaluate_v2',
            'programacion.fn_input_governance_shadow_sweep_v2',
            'public.lf_capability_current',
            'public.lf_capability_binding',
            'public.lf_operation_execution',
            'public.lf_test_suite_cases',
            'public.lf_test_suite_runs',
            'public.lf_test_runs',
            'public.lf_test_assertion_results'
          )
        ),
      'capability_execution',jsonb_build_object(
        'contract','DECLARED_CAPABILITY_SHADOW_V1',
        'capability_code','CONTROL_EQUIVALENCE_JUDGE',
        'version_policy','CURRENT_EXACT_MANIFEST',
        'policy_mode','EXACT_ONLY_ALL_DIVERGENCE_BLOCKS',
        'currentness_source','public.lf_capability_current',
        'orchestrator_operation_code','ORQUESTACION_PIPELINE_LF',
        'consumer_operation_code','GITHUB_CONTRACT_GATE_LF',
        'target_type','ENGINEERING_PLAN_UNIT_BINDING_PROOF',
        'target_code',p_plan_code||':'||p_unit_code,
        'plan_digest',v_plan_digest,
        'binding_recipe_entrypoint','programacion.fn_engineering_capability_bind_receipt_v1',
        'run_test_persistence_entrypoint','programacion.fn_engineering_run_test_persist_v1',
        'result_contract',jsonb_build_object(
          'suite_code','INPUT_GOVERNANCE_REGRESSION',
          'test_code','M3_9_SHADOW_T_EQUIV_CORPUS',
          'pass_when',jsonb_build_object(
            'shadow_contract','M3_9_T_EQUIV_CORPUS_V1',
            'screen_count',3,
            'fresh_t_equiv_binding_receipt',true,
            'domain_mutation',false,
            'diff_adjudication','NEXT_CHECKPOINT'
          )
        ),
        'orchestrator_reserve_entrypoint','public.fn_lf_operation_reserve_execution_v1',
        'consumer_reserve_entrypoint','public.fn_lf_operation_reserve_execution_v1',
        'dispatch_entrypoint','public.fn_lf_orchestrator_dispatch_receipt_v1',
        'binding_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
        'binding_readback_source','public.lf_capability_binding',
        'execution_readback_source','public.lf_operation_execution',
        'shadow_entrypoint','programacion.fn_input_governance_shadow_evaluate_v2',
        'fresh_receipt_required',true,
        'execution_id_prefix','T-EQUIV-IG-M3-9-',
        'orchestrator_execution_id_prefix','T-EQUIV-ORCH-IG-M3-9-',
        'plan_digest_seed',p_plan_code||':'||p_unit_code||'|CONTROL_EQUIVALENCE_JUDGE|EXACT_ONLY',
        'corpus_screen_ids',jsonb_build_array(1,43,58),
        'domain_mutation','FORBIDDEN',
        'comparison_only',true
      ),
      'verification_queries',jsonb_build_array(
        $q$with v as (
          select public.fn_lf_version_compatibility_current_version_id_v1(
            'PROGRAMACION_CONTRACT',
            'INPUT_READINESS_CONTRACT',
            'INPUT_GOVERNANCE_AGENT'
          ) as version_id
        ), s(id) as (
          values (1),(43),(58)
        )
        select jsonb_build_object(
          'shadow_contract','M3_9_T_EQUIV_CORPUS_V1',
          'version_id',max(v.version_id),
          'screen_count',count(*),
          'screens',jsonb_agg(
            jsonb_build_object(
              'pantalla_id',s.id,
              'shadow',programacion.fn_input_governance_shadow_evaluate_v2(s.id,v.version_id)
            ) order by s.id
          )
        )
        from s cross join v$q$
      ),
      'material_contract',jsonb_build_object(
        'scope','CURRENT_CHECKPOINT_ONLY',
        'heartbeat_required',true,
        'verification_mode','CAPABILITY_OWNED',
        'design_boundary','BIND_SELECTED_TRANSVERSAL_THEN_EXECUTE_DECLARED_SCOPE_ONLY',
        'persist_on_pass','programacion.fn_engineering_checkpoint_transition_v1',
        'execution_semantics','REAL_SHADOW_AND_FRESH_RECEIPT_REQUIRED'
      ),
      'action_steps',jsonb_build_array(
        'BIND_CURRENT_SELECTED_TRANSVERSAL_AND_PERSIST_FRESH_RECEIPT',
        'EXECUTE_EXISTING_SHADOW_ON_DECLARED_CORPUS',
        'PERSIST_REAL_TEST_EVIDENCE',
        'VERIFY_BINDING_AND_SHADOW_RECEIPTS',
        'PERSIST_DONE_ONLY_AFTER_REAL_EXECUTION',
        'USE_RETURNED_BOOTSTRAP'
      ),
      'forbidden',
        coalesce(v_base->'forbidden','[]'::jsonb)
        || jsonb_build_array(
          'FALLBACK_TO_TITLE_HEURISTIC_WHEN_EXPLICIT_DECLARED',
          'CREATE_PARALLEL_SHADOW_ENGINE',
          'SYNTHETIC_PASS_WITHOUT_SHADOW_EXECUTION',
          'REUSE_OLD_BINDING_AS_THIS_RUN_RECEIPT',
          'MUTATE_DOMAIN_DATA'
        )
    );
  end if;

  return v_base || jsonb_build_object(
    'status','BLOCK_TRANSVERSAL_CAPABILITY_HANDLER_MISSING',
    'precision','STRUCTURAL_TRANSVERSAL_EXPLICIT',
    'transversal_execution',v_tx,
    'transversal_gate','NO_COMPILED_HANDLER'
  );
end;
$$;
