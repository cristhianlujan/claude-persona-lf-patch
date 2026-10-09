-- IG M9.0 / BUNDLE_MANIFEST_SHA: re-route from the unfinished post-pase FINAL_EVIDENCE capability to an Input-Governance-owned deliverable.
-- Decision (user, 2026-10-09): post-pase is a large unfinished project; the plan must not consume components that do not exist yet.
-- The checkpoint now authors and runs a bounded test (bundle_manifest.py) that independently recomputes the bundle manifest SHA produced by
-- programacion.fn_input_governance_release_bundle_manifest_v1 (no post-pase dependency). FINAL_EVIDENCE remains registered and unused.
UPDATE programacion.engineering_plan_units
   SET unit_metadata = jsonb_set(
         unit_metadata #- '{transversal_execution_v1,BUNDLE_MANIFEST_SHA}',
         '{action_specs_v1,BUNDLE_MANIFEST_SHA}',
         jsonb_build_object(
           'status','READY',
           'target',jsonb_build_object(
             'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,
             'declared_objects',jsonb_build_array('programacion.contratos','public.lf_capability_current','public.lf_activos'),
             'declared_artifacts',jsonb_build_array(jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_0/bundle_manifest.py','role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE')),
             'evidence_artifacts','[]'::jsonb,
             'mutation_artifacts',jsonb_build_array(jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_0/bundle_manifest.py','role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE'))),
           'expected','Author and execute the exact checkpoint test against the canonical exit criterion and declared source pack. PASS requires real test evidence and machine assertion receipt.',
           'forbidden',jsonb_build_array('INFER_EXECUTION_SEMANTICS_FROM_TITLE','INFER_EXECUTION_SEMANTICS_FROM_REGEX','TREAT_EVIDENCE_ARTIFACT_AS_MUTATION_TARGET','SYNTHETIC_PASS_WITHOUT_MACHINE_ASSERTION','CONSUME_UNFINISHED_POST_PASE_CAPABILITY'),
           'precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
           'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING',
           'recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
           'schema_version','ENGINEERING_ACTION_SPEC_V3',
           'checkpoint_code','BUNDLE_MANIFEST_SHA',
           'contract_family','BOUNDED_CHECKPOINT_TEST',
           'contract_source','EXPLICIT_ACTION_SPEC',
           'mutation_policy','TEST_ARTIFACT_ONLY',
           'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET','pass_when',jsonb_build_object('test_passed',true,'test_exit_code',0,'semantic_authority_bound',true,'adversarial_case_executed',true)),
           'verification_queries',jsonb_build_array(
             'select id,contrato_codigo,estado,version_id from programacion.contratos where contrato_codigo ~* ''(INPUT_READINESS|INPUT_FRESHNESS|INPUT_GOVERNANCE)'' order by id',
             'select capability_code,version,manifest_sha256 from public.lf_capability_current order by 1',
             'select codigo_activo,runtime_estado,estado_operativo from public.lf_activos where codigo_activo like ''PROGRAMACION_FN_INPUT_GOVERNANCE_%'' order by 1'),
           'test_execution_contract',jsonb_build_object(
             'mode','AUTHORED_NEGATIVE','test_code','ENG_M9_0_BUNDLE_MANIFEST_SHA',
             'test_path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_0/bundle_manifest.py',
             'synthetic_pass','FORBIDDEN',
             'declared_objects',jsonb_build_array('programacion.contratos','public.lf_capability_current','public.lf_activos'),
             'declared_queries',jsonb_build_array(
               'select id,contrato_codigo,estado,version_id from programacion.contratos where contrato_codigo ~* ''(INPUT_READINESS|INPUT_FRESHNESS|INPUT_GOVERNANCE)'' order by id',
               'select capability_code,version,manifest_sha256 from public.lf_capability_current order by 1',
               'select codigo_activo,runtime_estado,estado_operativo from public.lf_activos where codigo_activo like ''PROGRAMACION_FN_INPUT_GOVERNANCE_%'' order by 1'),
             'negative_required',true,'authoring_required',true,
             'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN',
             'canonical_exit_criterion','Bundle de release candidate con SHA unico sobre identidades materiales aplicables (Git head, contratos, registry, Core, semantica, Curator, Validator y Edge), propiedad de Input Governance y sin depender de post-pase (no terminado).'),
           'source_pack_missing_typed','[]'::jsonb,
           'requires_material_execution',true),
         true)
 WHERE plan_code = 'IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code = 'M9.0'
   AND unit_metadata #>> '{transversal_execution_v1,BUNDLE_MANIFEST_SHA,capabilities,0,capability_code}' = 'FINAL_EVIDENCE';
