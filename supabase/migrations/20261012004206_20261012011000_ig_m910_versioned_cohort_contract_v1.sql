-- IG M9.10 contract-only repair: existing versioned release governance, no cutover/activation.
DO $m910$
DECLARE m jsonb; s jsonb; a jsonb; pack jsonb; w bigint;
        q_cohort jsonb; q_drill jsonb; q_baseline jsonb;
BEGIN
 SELECT u.unit_metadata,u.work_item_id INTO m,w FROM programacion.engineering_plan_units u
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M9.10' FOR UPDATE;
 IF w IS NULL OR m#>>'{action_specs_v1,COHORT_BY_COHORT,status}' IS DISTINCT FROM 'BLOCK_CAPABILITY_CUTOVER_NOT_REGISTERED'
 THEN RAISE EXCEPTION 'M910_LOCAL_CONTRACT_DRIFT'; END IF;
 IF (SELECT count(*) FROM programacion.fn_engineering_effective_dependencies_v1(w) WHERE is_unmet)<>1
 OR NOT EXISTS(SELECT 1 FROM programacion.fn_engineering_effective_dependencies_v1(w) WHERE effective_work_code='PAULO-093' AND is_unmet)
 THEN RAISE EXCEPTION 'M910_DEPENDENCY_GRAPH_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0' AND manifest_sha256~'^[0-9a-f]{64}$')
 OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current WHERE capability_code='REVERSIBLE_CANDIDATE_VERIFICATION' AND version='1.0.3' AND manifest_sha256~'^[0-9a-f]{64}$')
 OR EXISTS(SELECT 1 FROM public.lf_capability_current WHERE capability_code='CAPABILITY_CUTOVER')
 THEN RAISE EXCEPTION 'M910_GOVERNANCE_CURRENTNESS_DRIFT'; END IF;
 q_cohort:=jsonb_build_array(
 'select ct.cohort_type_code,cm.pantalla_id,cm.authority_ref from programacion.input_governance_cohort_types ct join programacion.input_governance_cohort_memberships cm using(cohort_type_code) where ct.status=''ACTIVE'' and cm.status=''ACTIVE'' order by ct.display_order,cm.representative_rank,cm.pantalla_id',
 'select capability_code,version,manifest_sha256 from public.lf_capability_current where capability_code in (''INPUT_GOVERNANCE'',''REVERSIBLE_CANDIDATE_VERIFICATION'')',
 'select id,subject_ref,subject_sha256 from programacion.provenance_receipts where subject_type=''IG_CANARY_OBSERVATION'' order by id desc limit 40');
 q_drill:=jsonb_build_array(
 'select capability_code,version,manifest_sha256,previous_version from public.lf_capability_current where capability_code=''INPUT_GOVERNANCE''',
 'select capability_code,version,manifest_sha256 from public.lf_capability_version_registry where capability_code=''INPUT_GOVERNANCE'' order by version',
 'select id,subject_ref,subject_sha256 from programacion.provenance_receipts where subject_type=''IG_CANARY_OBSERVATION'' order by id desc limit 40');
 q_baseline:=jsonb_build_array(
 'select count(*) as historical_runs from programacion.input_readiness_runs',
 'select capability_code,binding_state,count(*) as historical_bindings from public.lf_capability_binding group by capability_code,binding_state',
 'select capability_code,version,manifest_sha256 from public.lf_capability_version_registry where capability_code=''INPUT_GOVERNANCE'' order by version');
 s:=m->'action_specs_v1';
 a:=s->'COHORT_BY_COHORT';
 a:=a||jsonb_build_object(
 'status','READY','action_kind','MATERIALIZE_DECLARED_DELIVERABLE',
 'recipe_mode','SCOPED_GIT_FIRST_GOVERNED_COHORT_EXPANSION',
 'precision','EXPLICIT_COHORT_AUTHORITY_AND_DEPENDENCY',
 'contract_family','BOUNDED_IMPLEMENTATION_AUTHORING','requires_material_execution',true,
 'mutation_policy','ONLY_DECLARED_TARGETS',
 'expected','Only after M9.9 DONE, use dynamic governed cohorts sequentially; prove per-cohort verified receipts, switch/revert with version registry, 5 failure conditions and poststate=prestate. Never execute production cutover.',
 'forbidden',jsonb_build_array('DIRECT_POINTER_MUTATION','INVENT_LOCAL_CUTOVER_ENGINE','TREAT_MISSING_CAPABILITY_AS_READY','BYPASS_M9_9_DEPENDENCY','HARDCODE_COHORT_IDS','SYNTHETIC_CANARY_RECEIPTS','CLAIM_RUNTIME_ACTIVATION'),
 'target',jsonb_build_object(
 'checkpoint','COHORT_BY_COHORT','declared_assets',jsonb_build_array('INPUT_GOVERNANCE','REVERSIBLE_CANDIDATE_VERIFICATION'),
 'declared_events','[]'::jsonb,
 'declared_objects',jsonb_build_array('public.lf_capability_current','public.lf_capability_version_registry','programacion.input_governance_cohort_types','programacion.input_governance_cohort_memberships','programacion.provenance_receipts'),
 'declared_artifacts',jsonb_build_array(jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_10/cohort_by_cohort.py','role','MUTATION_TARGET','target_kind','EXACT_NEW_OR_UPDATE_FILE','purpose','SANDBOX_EXECUTOR'))),
 'verification_queries',q_cohort,
 'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET','pass_when',jsonb_build_object('git_merged',true,'implementation_written',true,'readback_passed',true,'per_cohort_receipts_verified',true,'rollback_zero_residue',true)),
 'authoring_contract',jsonb_build_object('mode','REUSE_EXISTING_PRODUCER_PROCEDURES','git_route','SCOPED_BRANCH_PR_MERGE','post_merge_readback_required',true,'direct_main_write','FORBIDDEN','no_synthetic_receipts',true,'runtime_activation','NOT_IMPLIED','dependency_gate','PAULO-093_DONE','cohort_selection','DYNAMIC_ACTIVE_GOVERNED_MEMBERSHIPS','test_scope','SANDBOX_WITH_ROLLBACK','missing_procedure','LEAVE_CHECKPOINT_PENDING_WITH_OWNER'));
 s:=jsonb_set(s,'{COHORT_BY_COHORT}',a,true);
 a:=s->'ROLLBACK_DRILL';
 a:=a||jsonb_build_object('expected','Reversible per-cohort drill via canonical versioned promoter, 5 negative causes and currentness proof, never SADM/POST_PASE','verification_queries',q_drill);
 a:=jsonb_set(a,'{target,declared_objects}',jsonb_build_array('public.lf_capability_current','public.lf_capability_version_registry','programacion.provenance_receipts'),true);
 a:=jsonb_set(a,'{test_execution_contract,declared_queries}',q_drill,true);
 a:=jsonb_set(a,'{test_execution_contract,declared_objects}',jsonb_build_array('public.lf_capability_current','public.lf_capability_version_registry','programacion.provenance_receipts'),true);
 a:=jsonb_set(a,'{test_execution_contract,checkpoint_title_context}',to_jsonb('Drill de rollback via promotor versionado vigente, no CAPABILITY_CUTOVER nominal'::text),true);
 s:=jsonb_set(s,'{ROLLBACK_DRILL}',a,true);
 a:=s->'RESIDUE_NEGATIVE';
 a:=a||jsonb_build_object('expected','Compare prestate/poststate deltas of candidate-only readiness runs, assessments, bindings and versions, not global historical totals','verification_queries',q_baseline);
 a:=jsonb_set(a,'{target,declared_objects}',jsonb_build_array('programacion.input_readiness_runs','public.lf_capability_binding','public.lf_capability_version_registry'),true);
 a:=jsonb_set(a,'{test_execution_contract,declared_queries}',q_baseline,true);
 s:=jsonb_set(s,'{RESIDUE_NEGATIVE}',a,true);
 a:=s->'DRILL_READBACK';
 a:=a||jsonb_build_object('expected','Require proven per-cohort receipts, pointer baseline equality and no residual candidate versions, not aggregate receipt-kind counts','verification_queries',q_drill);
 a:=jsonb_set(a,'{target,declared_objects}',jsonb_build_array('programacion.provenance_receipts','public.lf_capability_current','public.lf_capability_version_registry'),true);
 s:=jsonb_set(s,'{DRILL_READBACK}',a,true);
 m:=jsonb_set(m,'{action_specs_v1}',s,true);
 m:=jsonb_set(m,'{cohort_expansion_governance_v1}',jsonb_build_object(
 'schema_version','IG_COHORT_EXPANSION_GOVERNANCE_V1',
 'transversal_governance_change','NOT_APPLICABLE_REUSE_EXISTING_GATES',
 'reused_authority',jsonb_build_array('public.lf_capability_current','public.lf_capability_version_registry','public.fn_lf_capability_promote_v1','programacion.fn_engineering_effective_dependencies_v1'),
 'expected_upstream','PAULO-093:DONE','cohort_selection','DYNAMIC_ACTIVE_GOVERNED_MEMBERSHIPS',
 'no_local_capability_cutover',true,'runtime_activation',false,'release_switch_authorized',false),true);
 pack:=m->'source_pack_v1';
 pack:=jsonb_set(pack,'{checkpoint_inputs,COHORT_BY_COHORT,inputs,queries}',q_cohort,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,COHORT_BY_COHORT,inputs,db_objects}',jsonb_build_array('programacion.input_governance_cohort_types','programacion.input_governance_cohort_memberships','public.lf_capability_current','programacion.provenance_receipts'),true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,ROLLBACK_DRILL,inputs,queries}',q_drill,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,ROLLBACK_DRILL,inputs,db_objects}',jsonb_build_array('public.lf_capability_current','public.lf_capability_version_registry','programacion.provenance_receipts'),true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,RESIDUE_NEGATIVE,inputs,queries}',q_baseline,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,DRILL_READBACK,inputs,queries}',q_drill,true);
 m:=jsonb_set(m,'{source_pack_v1}',pack,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.10';
 UPDATE programacion.engineering_work_checkpoints
 SET title='Simulacro de rollback por cohorte usando promotor transversal versionado'
 WHERE work_item_id=w AND checkpoint_code='ROLLBACK_DRILL' AND title='Simulacro de rollback total vía CAPABILITY_CUTOVER';
 IF NOT FOUND THEN RAISE EXCEPTION 'M910_CHECKPOINT_TITLE_DRIFT'; END IF;
END $m910$;
