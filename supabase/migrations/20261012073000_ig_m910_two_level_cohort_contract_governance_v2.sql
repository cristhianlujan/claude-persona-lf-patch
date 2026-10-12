-- M9.10 scoped engineering contract + governance; no operational release.
-- M9.9 authoritative six-case sandbox matrix is reused rather than rerun.
DO $m910$
DECLARE u record; c2 jsonb; c3 jsonb; c5 jsonb; md jsonb; g jsonb; v text;
BEGIN
 SELECT * INTO STRICT u FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.10' FOR UPDATE;
 md:=u.unit_metadata;
 c2:=md#>'{action_specs_v1,COHORT_BY_COHORT}';
 c3:=md#>'{action_specs_v1,ROLLBACK_DRILL}';
 c5:=md#>'{action_specs_v1,DRILL_READBACK}';
 IF c2#>>'{assertion_contract,pass_when,per_cohort_receipts_verified}' IS DISTINCT FROM 'true'
 OR md#>>'{cohort_expansion_governance_v1,runtime_activation}' IS DISTINCT FROM 'false'
 OR md#>>'{action_specs_v1,RESIDUE_NEGATIVE,residue_policy_v1,scope}' IS DISTINCT FROM 'CANDIDATE_ONLY'
 OR NOT EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints WHERE work_item_id=u.work_item_id AND checkpoint_code='COHORT_BY_COHORT' AND status='IN_PROGRESS')
 OR NOT EXISTS (SELECT 1 FROM programacion.engineering_plan_units pu JOIN programacion.engineering_work_items w ON w.id=pu.work_item_id WHERE pu.plan_code=u.plan_code AND pu.unit_code='M9.9' AND w.status='DONE')
 THEN RAISE EXCEPTION 'M910_CONTRACT_BASELINE_DRIFT'; END IF;

 g:=jsonb_build_object(
 'schema_version','IG_M910_TWO_LEVEL_COHORT_GOVERNANCE_V2',
 'unit_acceptance_scope','SANDBOX_REVERSIBLE_EXPANSION_ONLY',
 'selection','DYNAMIC_ACTIVE_GOVERNED_MEMBERSHIPS',
 'sandbox_required','actual DB candidate promotion/revert per active cohort; positive and negative integration controls; prestate=poststate with candidate-only zero residue; source-bound evidence',
 'sandbox_fake_or_mock_proof_allowed',false,
 'm99_six_case_matrix','REUSE_BY_CURRENT_GIT_SOURCE_AND_DB_READBACK',
 'rerun_m99_triggers','ONLY_ON_PROVEN_SOURCE_DRIFT',
 'operational_gate',jsonb_build_object('status','BLOCKED_SEPARATE_RELEASE',
    'signed_live_canary_receipts_required',true,'independent_review_required',true,
    'production_activation',false,'runtime_activation',false),
 'anti_loop',jsonb_build_object('max_no_progress_repeats',2,
    'next_action','AUDIT_CONTRACT_AND_GOVERNANCE_NOT_REPEAT_TEST'),
 'transversal_policy','REUSE_EXISTING_CAPABILITIES_NO_PARALLEL_ENGINE');

 c2:=jsonb_set(c2,'{assertion_contract,pass_when}',jsonb_build_object(
 'git_merged',true,'implementation_written',true,'readback_passed',true,
 'per_cohort_sandbox_db_execution_verified',true,'rollback_zero_residue',true,
 'source_bound_test_receipt_recorded',true),true);
 c2:=c2||jsonb_build_object(
 'expected','Each dynamically active governed cohort receives an actual SQL-transaction promotion/revert in sandbox, source-bound positive and negative integration checks, baseline equality and per-cohort readback. Signed live canary receipts remain a separate release gate.',
 'acceptance_profile','SANDBOX_COHORT_EXPANSION_V2',
 'operational_canary_receipts_required',false,
 'm99_verified_six_case_reused',true);
 c2:=jsonb_set(c2,'{authoring_contract}',coalesce(c2->'authoring_contract','{}'::jsonb)||
 jsonb_build_object('test_scope','SANDBOX_TRANSACTION_ONLY',
 'signed_live_receipts_required',false,'no_mock_proof',true),true);
 c2:=jsonb_set(c2,'{verification_queries}',jsonb_build_array(
 'select ct.cohort_type_code,cm.pantalla_id,cm.authority_ref from programacion.input_governance_cohort_types ct join programacion.input_governance_cohort_memberships cm using(cohort_type_code) where ct.status=''ACTIVE'' and cm.status=''ACTIVE'' order by ct.display_order,cm.representative_rank,cm.pantalla_id',
 'select capability_code,version,manifest_sha256 from public.lf_capability_current where capability_code in (''INPUT_GOVERNANCE'',''REVERSIBLE_CANDIDATE_VERIFICATION'')'),true);

 c3:=c3||jsonb_build_object(
 'expected','Reuse M9.9 six-case rollback matrix from current exact Git and DB evidence. Test M9.10 new per-cohort integration with real DB promotion/revert and one negative integration safeguard; do not rerun five previously proven triggers absent fingerprint drift.',
 'acceptance_profile','M99_REUSED_PLUS_M910_DB_INTEGRATION_V2',
 'operational_receipts_required',false,
 'm99_retest_only_on_drift',true);
 c3:=jsonb_set(c3,'{test_execution_contract}',coalesce(c3->'test_execution_contract','{}'::jsonb)||
 jsonb_build_object('reuse_m99_six_case_proof',true,'rerun_prior_five_triggers',false,
 'negative_integration_control_required',true,'signed_live_receipts_required',false),true);

 c5:=c5||jsonb_build_object(
 'expected','Read back source-bound per-cohort sandbox DB results, dynamic coverage, exact pointer/manifest and historical-data-aware candidate-only zero residue; signed live canary review is an independent blocked release gate.',
 'acceptance_profile','SANDBOX_FINAL_READBACK_V2',
 'signed_live_receipts_required',false,'operational_release_gate','SEPARATE_BLOCKED');
 c5:=jsonb_set(c5,'{verification_queries}',jsonb_build_array(
 'select capability_code,version,manifest_sha256,previous_version from public.lf_capability_current where capability_code=''INPUT_GOVERNANCE''',
 'select capability_code,version,manifest_sha256 from public.lf_capability_version_registry where capability_code=''INPUT_GOVERNANCE'' order by version'),true);

 md:=jsonb_set(md,'{action_specs_v1,COHORT_BY_COHORT}',c2,true);
 md:=jsonb_set(md,'{action_specs_v1,ROLLBACK_DRILL}',c3,true);
 md:=jsonb_set(md,'{action_specs_v1,DRILL_READBACK}',c5,true);
 md:=jsonb_set(md,'{m910_two_level_cohort_governance_v2}',g,true);
 md:=jsonb_set(md,'{cohort_expansion_governance_v1}',
 coalesce(md->'cohort_expansion_governance_v1','{}'::jsonb)||
 jsonb_build_object('unit_acceptance_scope','SANDBOX_REVERSIBLE_EXPANSION_ONLY',
 'signed_live_receipts_required_for_engineering',false,
 'operational_release_gate_separate',true,'m99_proof_reused',true),true);
 -- Remove stale operational-receipt discovery from checkpoint input packet.
 md:=jsonb_set(md,'{source_pack_v1,checkpoint_inputs,COHORT_BY_COHORT,inputs,queries}',c2->'verification_queries',true);
 md:=jsonb_set(md,'{source_pack_v1,checkpoint_inputs,DRILL_READBACK,inputs,queries}',c5->'verification_queries',true);
 UPDATE programacion.engineering_plan_units SET
 title='Expansión reversible de cohortes en sandbox; admisión operativa separada',
 exit_criterion='M9.10 sandbox engineering: dynamically select active governed cohorts; exercise actual transaction-bound candidate promotion/revert and independent in-transaction pre/post readback per cohort, prove candidate-only zero residue including runs, assessments, bindings and version registry; reuse M9.9 six-case evidence without repeat unless drift. Signed operational live canary receipts and production authorization remain blocked separate release gates.',
 unit_metadata=md WHERE id=u.id;
 UPDATE programacion.engineering_work_checkpoints SET title=
 CASE checkpoint_code
 WHEN 'COHORT_BY_COHORT' THEN 'Expansión reversible y evidencia DB por cohorte (sandbox)'
 WHEN 'ROLLBACK_DRILL' THEN 'Reutilización M9.9 y negativo de integración M9.10'
 WHEN 'DRILL_READBACK' THEN 'Readback sandbox source-bound; live gate separado'
 ELSE title END
 WHERE work_item_id=u.work_item_id AND checkpoint_code IN
 ('COHORT_BY_COHORT','ROLLBACK_DRILL','DRILL_READBACK');
 IF programacion.fn_engineering_checkpoint_action_spec_v3(u.plan_code,'M9.10','COHORT_BY_COHORT')
 #>>'{assertion_contract,pass_when,per_cohort_sandbox_db_execution_verified}' IS DISTINCT FROM 'true'
 OR programacion.fn_engineering_checkpoint_action_spec_v3(u.plan_code,'M9.10','DRILL_READBACK')
 #>>'{signed_live_receipts_required}' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'M910_COMPILER_POSTSTATE_FAIL'; END IF;
END $m910$;
