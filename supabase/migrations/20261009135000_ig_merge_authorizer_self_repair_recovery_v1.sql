-- Canonical merge authorization separates ordinary effects from recovery of its own stale authority.
-- No new gate. Existing safe classifier remains mandatory for ordinary material execution.
-- Recovery is a distinct governed route, NOT SAFE_CHANGE_ADMISSION PASS.
create or replace function programacion.fn_engineering_merge_authorization_contract_v1()
returns jsonb language sql immutable
set search_path to 'pg_catalog'
as $function$
select jsonb_build_object(
 'schema_version','ENGINEERING_PROCESS_MERGE_AUTHORIZATION_V1_2',
 'authorization_owner','PROCESS',
 'human_approval_required',false,
 'auto_merge_when_authorized',true,
 'authorization_capability','SAFE_CHANGE_ADMISSION',
 'required_execution_permission','DOWNSTREAM_EXECUTION_ELIGIBLE',
 'required_preconditions',jsonb_build_array('EKB_PREFLIGHT_CLEAR','EXACT_HEAD_MATCH','PR_MERGEABLE_TRUE'),
 'source_vs_effect',jsonb_build_object(
   'git_source_publication','NOT_A_RUNTIME_ACTIVATION',
   'sandbox_migration_apply','SEPARATE_EXECUTION_ADMISSION',
   'production_activation','REQUIRES_SEPARATE_EXPLICIT_OWNER_APPROVAL'),
 'self_repair_route',jsonb_build_object(
   'code','AUTHORITY_PIN_RECOVERY_V1',
   'purpose','RECOVER_STALE_MERGE_AUTHORIZER_WITHOUT_DEPENDING_ON_ITS_OWN_OUTPUT',
   'applies_to','EXACTLY_BOUNDED_SELF_REPAIR_WHEN_SAFE_CHANGE_ADMISSION_RETURNS_DEPENDENCY_CURRENTNESS_DRIFT',
   'not_applicable_to','ORDINARY_GIT_CHANGES_OR_OTHER_SAFE_CHANGE_DENIALS',
   'owner_decision','EXPLICIT_SUPER_ADMIN_APPROVAL_REQUIRED',
   'owner_approval_may_substitute_for_stale_classifier_only',true,
   'admission_authority','TRUSTED_GITHUB_BASE_PROTECTIONS_PLUS_INDEPENDENT_ROLLBACK_EVIDENCE_PLUS_OWNER_APPROVAL',
   'required_preconditions',jsonb_build_array(
     'EKB_PREFLIGHT_CLEAR',
     'EXACT_HEAD_MATCH',
     'PR_MERGEABLE_TRUE',
     'NATIVE_GITHUB_PROTECTION_NOT_BYPASSED',
     'PASE_EFFECTIVE_APPLICABILITY_VERIFIED',
     'CHANGESET_PATHS_EXACTLY_IN_REPAIR_SCOPE',
     'DEPENDENCY_DRIFT_LIVE_READBACK',
     'INDEPENDENT_NEGATIVE_AND_POSITIVE_TESTS_EXECUTED',
     'REVERSIBLE_SANDBOX_FULL_LOT_TEST_PASS',
     'POST_MERGE_GIT_LEDGER_DB_PARITY_REQUIRED'),
   'scope','SAFE_CHANGE_ADMISSION_DEPENDENCY_PIN_RECONCILIATION_AND_ITS_TYPED_RECEIPT_AND_DOWNSTREAM_CONSUMERS',
   'allowed_effects',jsonb_build_array('GIT_SOURCE_MERGE','EXACT_RECONCILIATION_MIGRATIONS_TO_SANDBOX_AFTER_MERGE'),
   'forbidden_effects',jsonb_build_array('PRODUCTION_ACTIVATION','DISABLE_CONTROL','ARBITRARY_OTHER_CHANGES',
      'ASSUME_SKIPPED_WORKFLOW_PASS','IGNORE_ACTIVE_BLOCKING_CONTROL','UNBOUNDED_OWNER_OVERRIDE'),
   'self_repair_may_claim_safe_change_pass',false,
   'unknown_or_unverified','BLOCK',
   'on_success','RECHECK_STANDARD_SAFE_CHANGE_ADMISSION_POST_REPAIR'),
 'pase_policy',jsonb_build_object(
   'repair_policy_id','PASE_CONTROL_REPAIR_QUARANTINE_V1',
   'repair_window_state','SUPPORTED',
   'activation_resolution','TRUSTED_BASE_EXACT_HEAD_READBACK_REQUIRED',
   'on_disabled','NOT_APPLICABLE',
   'disabled_skipped_workflow_is_pass',false,
   'on_enabled','REQUIRE_PASE_MERGE_POLICY_EFFECTIVE_ALLOW',
   'on_unknown','BLOCK',
   'observe_only_results_cannot_block_merge',true,
   'active_blocking_controls_require_exact_terminal_pass',true,
   'structural_governance_remains_fail_closed',true,
   'global_f09_f10_completion_required_for_ordinary_merge',false,
   'control_system_activation_requires_separate_terminal_qualification',true),
 'forbidden',jsonb_build_array(
   'MERGE_WITHOUT_PROCESS_AUTHORIZATION',
   'TREAT_RECOMMENDATION_AS_PERMISSION',
   'SKIP_EKB_PREFLIGHT',
   'SKIP_ACTIVE_BLOCKING_CONTROL_WHEN_APPLICABLE',
   'TREAT_REPAIR_OBSERVE_ONLY_AS_MERGE_BLOCKER',
   'REQUIRE_GLOBAL_PASE_F09_F10_FOR_ORDINARY_MERGE',
   'MERGE_DIFFERENT_HEAD',
   'TREAT_SKIPPED_WORKFLOW_AS_PASS',
   'ASSUME_DISABLED_WITHOUT_TRUSTED_BASE_READBACK',
   'TREAT_AUTHORIZER_SELF_REPAIR_AS_ORDINARY_SAFE_CHANGE_PASS'),
 'on_authorized','MERGE_AND_CONTINUE_CURRENT_UNIT',
 'on_not_authorized','YIELD_CURRENT_UNIT_CONTINUE_SCHEDULER',
 'global_scheduler_stop',false,'fail_closed',true
);
$function$;

do $verify$
declare v jsonb := programacion.fn_engineering_merge_authorization_contract_v1();
begin
 if v->>'schema_version'<>'ENGINEERING_PROCESS_MERGE_AUTHORIZATION_V1_2'
 or v#>>'{self_repair_route,code}'<>'AUTHORITY_PIN_RECOVERY_V1'
 or v#>>'{self_repair_route,owner_approval_may_substitute_for_stale_classifier_only}'<>'true'
 or v#>>'{self_repair_route,self_repair_may_claim_safe_change_pass}'<>'false'
 or v#>>'{self_repair_route,unknown_or_unverified}'<>'BLOCK'
 or v#>>'{pase_policy,on_unknown}'<>'BLOCK'
 or v#>>'{pase_policy,on_disabled}'<>'NOT_APPLICABLE'
 or v->>'required_execution_permission'<>'DOWNSTREAM_EXECUTION_ELIGIBLE'
 then raise exception 'BLOCK_SELF_REPAIR_GOVERNANCE_CONTRACT_INVALID'; end if;
 if (v#>'{self_repair_route,required_preconditions}') ? 'NATIVE_GITHUB_PROTECTION_NOT_BYPASSED' is not true
 or (v#>'{self_repair_route,forbidden_effects}') ? 'PRODUCTION_ACTIVATION' is not true
 then raise exception 'BLOCK_SELF_REPAIR_PROTECTION_MISSING'; end if;
end $verify$;
