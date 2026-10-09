
-- 1) Plan-wide inherited rule: family regression and dynamic selection are distinct gates.
update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  unit_metadata,
  '{plan_inherited_execution_policies_v1}',
  coalesce(unit_metadata->'plan_inherited_execution_policies_v1','{}'::jsonb)
  || jsonb_build_object(
    'DYNAMIC_SELECTION_VALIDATION_V1',
    jsonb_build_object(
      'authority','T-SELECT/CAPABILITY_SELECTOR@1.0.0 + event://20163 + event://20167 + event://20168 + event://20170',
      'architecture','CORE_PLUS_CAPABILITIES',
      'selection_model','MULTI_LABEL_CAPABILITY_ACTIVATION_NOT_SINGLE_METHOD_ROUTER',
      'default_fallback','FULL_SAFE_MIX_V1_CANDIDATE',
      'family_regression_gate','FAMILY_REGRESSION_PASS',
      'selection_benchmark_gate','DYNAMIC_SELECTION_BENCHMARK_PASS',
      'runtime_selection_gate','DYNAMIC_SELECTION_RUNTIME_PASS',
      'separation_rule','FAMILY_REGRESSION_PASS_NEVER_IMPLIES_DYNAMIC_SELECTION_PASS',
      'shadow_role','REGRESSION_ONLY_NON_DECISIONAL',
      'selector_role','CHOOSE_CAPABILITY_PACKS_FROM_SIGNALS_WITH_SAFE_FALLBACK',
      'runtime_claim_rule','RUNTIME_SELECTION_CLAIM_REQUIRES_RUNTIME_GATE_NOT_ONLY_BENCHMARK'
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2';

-- 2) M3.9 is explicitly only the 47-family regression layer.
update programacion.engineering_plan_units
set unit_metadata = unit_metadata || jsonb_build_object(
  'validation_layers_v1',
  jsonb_build_object(
    'FAMILY_REGRESSION',
    jsonb_build_object(
      'status','PROVEN',
      'producer','programacion.fn_input_governance_shadow_evaluate_v2',
      'scope','47_FAMILIES_PER_SCREEN',
      'decision_authority',false,
      'comparison_only',true,
      'checkpoint','SHADOW_RUN',
      'evidence_ref','supabase://programacion.fn_input_governance_shadow_evaluate_v2?sample=1,43,58',
      'cannot_satisfy',jsonb_build_array('DYNAMIC_SELECTION_BENCHMARK','DYNAMIC_SELECTION_RUNTIME')
    ),
    'DYNAMIC_SELECTION_BENCHMARK',
    jsonb_build_object(
      'status','PROVEN_EXISTING_WORK',
      'capability_code','CAPABILITY_SELECTOR',
      'capability_version','1.0.0',
      'freeze_ref','event://20163',
      'comparison_ref','event://20167',
      'selector_stress_ref','event://20168',
      'architecture_closure_ref','event://20170',
      'expected',jsonb_build_object(
        'route_checks',8,
        'route_matches',8,
        'critical_false_green',0,
        'out_of_distribution_probes',3,
        'forced_misclassification_probes',3
      )
    ),
    'DYNAMIC_SELECTION_RUNTIME',
    jsonb_build_object(
      'status','NOT_EVALUATED_BY_M3_9',
      'consumer_unit','M5.4',
      'rule','SHADOW_PASS_MUST_NOT_BE_USED_AS_RUNTIME_SELECTION_PASS'
    )
  )
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M3.9';

-- 3) M5.4 consumes the already-proven selector work as a separate gate.
update programacion.engineering_plan_units
set
  exit_criterion =
    'Curator no llama classify/probes legacy; pipeline único DETECT→RESEARCH→DISCOVER→ACQUIRE→SYNTHESIZE→PROPOSE→VERIFY→SemanticResolution→ADMIT; CAPABILITY_SELECTOR multi-label por señales; NO_SIGNAL/CONTRADICTORY/failure→FULL_SAFE_MIX; 0 method router paralelo; shared evidence base; output final normalizado exacto sin instrucciones interpretativas; FAMILY_REGRESSION_PASS es independiente y NO satisface DYNAMIC_SELECTION_PASS; selector benchmark debe conservar 8/8 rutas, 0 false green y fallbacks OOD/misclassification; runtime M5.4 debe demostrar consumo real del selector antes de DYNAMIC_SELECTION_RUNTIME_PASS.',
  unit_metadata = unit_metadata || jsonb_build_object(
    'validation_layers_v1',
    jsonb_build_object(
      'FAMILY_REGRESSION',
      jsonb_build_object(
        'source_unit','M3.9',
        'status','REUSE_PROVEN_REGRESSION',
        'scope','47_FAMILIES',
        'decision_authority',false,
        'reuse_rule','DO_NOT_RERUN_INTEGRAL_47_FAMILIES_UNLESS_ESCALATION_TRIGGER',
        'cannot_satisfy',jsonb_build_array('DYNAMIC_SELECTION_BENCHMARK','DYNAMIC_SELECTION_RUNTIME')
      ),
      'DYNAMIC_SELECTION_BENCHMARK',
      jsonb_build_object(
        'status','REUSE_PROVEN_EXISTING_WORK',
        'capability_code','CAPABILITY_SELECTOR',
        'capability_version','1.0.0',
        'manifest_sha256','fd4d6b41303dad446873c9d9d9ad1e3a87461f880f458b68debfcacacb4c1ff3',
        'freeze_ref','event://20163',
        'comparison_ref','event://20167',
        'selector_stress_ref','event://20168',
        'architecture_closure_ref','event://20170',
        'required_metrics',jsonb_build_object(
          'route_checks',8,
          'route_matches',8,
          'critical_false_green',0,
          'out_of_distribution_probes',3,
          'forced_misclassification_probes',3
        )
      ),
      'DYNAMIC_SELECTION_RUNTIME',
      jsonb_build_object(
        'status','TO_BE_VERIFIED_IN_M5_4',
        'required_at',jsonb_build_array('CORE_INVOCATION','SEMANTIC_PLAN_RESOLVERS','NEGATIVE_NO_CLASSIFY','TERMINAL'),
        'pass_rule','CURATOR_CONSUMES_CAPABILITY_SELECTOR_OR_DECLARED_SAFE_FALLBACK_AND_PRESERVES_NORMALIZED_OUTPUT',
        'negative_rule','FORCED_OR_NO_SIGNAL_MUST_NOT_PRODUCE_ARBITRARY_SPECIALIST_OR_FALSE_GREEN'
      )
    )
  )
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M5.4';

-- 4) Wire exact existing evidence into M5.4 SEMANTIC_PLAN_RESOLVERS input.
update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  unit_metadata,
  '{source_pack_v1,checkpoint_inputs,SEMANTIC_PLAN_RESOLVERS}',
  (
    coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,SEMANTIC_PLAN_RESOLVERS}','{}'::jsonb)
    || jsonb_build_object(
      'selection_gate',
      jsonb_build_object(
        'contract','DYNAMIC_SELECTION_VALIDATION_V1',
        'benchmark_status','REUSE_EXISTING',
        'runtime_status','VERIFY_CURRENT_CHECKPOINT',
        'family_regression_is_not_selection_pass',true
      )
    )
  )
  ||
  jsonb_build_object(
    'inputs',
    (
      coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,SEMANTIC_PLAN_RESOLVERS,inputs}','{}'::jsonb)
      || jsonb_build_object(
        'assets',
        (
          select coalesce(jsonb_agg(distinct x order by x),'[]'::jsonb)
          from jsonb_array_elements_text(
            coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,SEMANTIC_PLAN_RESOLVERS,inputs,assets}','[]'::jsonb)
            || '["CAPABILITY_SELECTOR"]'::jsonb
          ) t(x)
        ),
        'events',
        (
          select coalesce(jsonb_agg(distinct x order by x),'[]'::jsonb)
          from jsonb_array_elements(
            coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,SEMANTIC_PLAN_RESOLVERS,inputs,events}','[]'::jsonb)
            || '[20163,20167,20168,20170]'::jsonb
          ) t(x)
        ),
        'queries',
        coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,SEMANTIC_PLAN_RESOLVERS,inputs,queries}','[]'::jsonb)
        || jsonb_build_array(
          'select r.capability_code,r.status,r.owner_scope,c.version current_version,c.manifest_sha256,v.release_state from public.lf_capability_registry r join public.lf_capability_current c on c.capability_code=r.capability_code join public.lf_capability_version_registry v on v.capability_code=c.capability_code and v.version=c.version where r.capability_code=''CAPABILITY_SELECTOR''',
          'select id,evento_tipo,entidad_codigo,payload from public.lf_eventos where id in (20163,20167,20168,20170) order by id'
        )
      )
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M5.4';

-- 5) Terminal readback must reconcile the two gates separately.
update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  unit_metadata,
  '{source_pack_v1,checkpoint_inputs,TERMINAL}',
  (
    coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,TERMINAL}','{}'::jsonb)
    || jsonb_build_object(
      'validation_gate_contract',
      jsonb_build_object(
        'family_regression_gate','REUSE_M3_9',
        'dynamic_selection_benchmark_gate','REUSE_T_SELECT_EVENTS_20163_20167_20168_20170',
        'dynamic_selection_runtime_gate','M5_4_CURRENT_RUN',
        'required_distinct',true,
        'forbidden','FAMILY_REGRESSION_PASS_AS_DYNAMIC_SELECTION_PASS'
      )
    )
  )
  ||
  jsonb_build_object(
    'inputs',
    (
      coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,TERMINAL,inputs}','{}'::jsonb)
      || jsonb_build_object(
        'assets',
        (
          select coalesce(jsonb_agg(distinct x order by x),'[]'::jsonb)
          from jsonb_array_elements_text(
            coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,TERMINAL,inputs,assets}','[]'::jsonb)
            || '["CAPABILITY_SELECTOR","TEST_SUITE_INPUT_GOVERNANCE_REGRESSION_V1"]'::jsonb
          ) t(x)
        ),
        'events',
        (
          select coalesce(jsonb_agg(distinct x order by x),'[]'::jsonb)
          from jsonb_array_elements(
            coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,TERMINAL,inputs,events}','[]'::jsonb)
            || '[20163,20167,20168,20170]'::jsonb
          ) t(x)
        ),
        'queries',
        coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,TERMINAL,inputs,queries}','[]'::jsonb)
        || jsonb_build_array(
          'select r.capability_code,r.status,c.version current_version,c.manifest_sha256,v.release_state from public.lf_capability_registry r join public.lf_capability_current c on c.capability_code=r.capability_code join public.lf_capability_version_registry v on v.capability_code=c.capability_code and v.version=c.version where r.capability_code=''CAPABILITY_SELECTOR''',
          'select id,payload#>>''{metrics,route_checks}'' route_checks,payload#>>''{metrics,route_matches}'' route_matches,payload#>>''{metrics,misclassification_critical_false_green}'' misclassification_false_green,payload#>>''{metrics,out_of_distribution_critical_false_green}'' ood_false_green from public.lf_eventos where id=20168',
          'select id,payload->>''architecture'' architecture,payload->>''selection_model'' selection_model,payload->>''default_fallback'' default_fallback,payload#>>''{demonstration,critical_false_green}'' critical_false_green from public.lf_eventos where id=20170'
        )
      )
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M5.4';
