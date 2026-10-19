-- IG M9.9: bind existing transversal reversible verification as a consumer,
-- without duplicating its core, inventing a product owner, or activating runtime.
-- Declarative contract only. Missing IG adapter and live receipts remain fail-closed.
DO $contract$
DECLARE v_unit jsonb; v_cp4 jsonb; v_cp5 jsonb; v_provider jsonb; v_timeout jsonb;
BEGIN
 SELECT unit_metadata INTO v_unit FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9' FOR UPDATE;
 v_cp4:=v_unit#>'{action_specs_v1,ROLLBACK_TRIGGER_NEGATIVE}';
 IF v_cp4#>>'{assertion_contract,pass_when,runtime_canary_proven}' IS DISTINCT FROM 'true'
 OR v_cp4#>>'{assertion_contract,pass_when,real_canary_receipts_verified}' IS DISTINCT FROM 'true'
 OR v_unit#>'{action_specs_v1,CANARY_READBACK}' IS NOT NULL
 THEN RAISE EXCEPTION 'M99_CONTRACT_REBASE_REQUIRED'; END IF;
 SELECT jsonb_build_object('capability_code',c.capability_code,'version',c.version,
   'manifest_sha256',c.manifest_sha256) INTO v_provider
 FROM public.lf_capability_current c
 WHERE c.capability_code='REVERSIBLE_CANDIDATE_VERIFICATION'
   AND c.version='1.0.3'
   AND c.manifest_sha256='eccc53277bdd449482ebd5328c38988bba8695d4ce84045b7603751d566f26ab';
 IF v_provider IS NULL THEN RAISE EXCEPTION 'M99_REVERSIBLE_PROVIDER_DRIFT'; END IF;
 SELECT jsonb_build_object('capability_code',c.capability_code,'version',c.version,
   'manifest_sha256',c.manifest_sha256) INTO v_timeout
 FROM public.lf_capability_current c WHERE c.capability_code='TIMEOUT_PHASE_BUDGET_POLICY'
 AND c.version='1.0.0'
 AND c.manifest_sha256='cc91bb3cda65e0cae8e7c8bc0e8d3355d1ec3e6f277f51723c6a4bbe7ed33fd9';
 IF v_timeout IS NULL THEN RAISE EXCEPTION 'M99_TIMEOUT_PROVIDER_DRIFT'; END IF;
 v_cp4:=jsonb_set(v_cp4,'{target,declared_assets}',
   coalesce(v_cp4#>'{target,declared_assets}','[]'::jsonb) ||
   '["REVERSIBLE_CANDIDATE_VERIFICATION","INDEPENDENT_ASSURANCE","INPUT_GOVERNANCE"]'::jsonb,true);
 v_cp4:=v_cp4||jsonb_build_object('reversible_consumer_binding_v1',
   jsonb_build_object(
     'provider',v_provider,'timeout_policy',v_timeout,
     'provider_inputs','["candidate_identity","flow_adapter","baseline_oracle","rollback_contract"]'::jsonb,
     'provider_outputs','["verdict","findings","oracle_result","adapter_receipt","rollback_exact","material_residue_count","independent_assurance"]'::jsonb,
     'flow_adapter_binding_status','REQUIRED_NOT_VERIFIED',
     'baseline_oracle','INDEPENDENT_ASSURANCE_2.0.1',
     'rollback_mode','ROLLBACK_ONLY',
     'receipt_channel','EVIDENCE_VERIFIER_V1',
     'execution_admission','BLOCK_UNTIL_SIGNED_LIVE_RECEIPTS_AND_ADAPTER',
     'scope','IG_CONSUMER_ONLY_NO_PRODUCTION'));
 v_cp5:=jsonb_build_object(
   'status','READY','action_kind','READBACK_ONCE',
   'precision','RECEIPT_BOUND_CANARY_READBACK_V1',
   'recipe_mode','ASSERT_VERIFIED_RECEIPT_AND_ZERO_RESIDUE',
   'requires_material_execution',false,'mutation_policy','NO_DOMAIN_MUTATION',
   'expected','PASS only with actual signed live IG canary receipts for five negative causes, exact baseline current/manifest restored and zero residue; empty receipts cannot PASS.',
   'target',jsonb_build_object('checkpoint','CANARY_READBACK',
      'declared_assets','["INPUT_GOVERNANCE","REVERSIBLE_CANDIDATE_VERIFICATION","TIMEOUT_PHASE_BUDGET_POLICY"]'::jsonb,
      'declared_events','[]'::jsonb,
      'declared_objects','["programacion.provenance_receipts","public.lf_capability_current","public.lf_capability_version_registry","programacion.input_governance_cohort_memberships","programacion.fn_ig_m99_canary_receipt_gate_v1"]'::jsonb,
      'declared_artifacts','[]'::jsonb),
   'verification_queries',jsonb_build_array(
      'select id,receipt_sha256,subject_sha256,payload->>''verification_status'' as verification_status,payload->>''cohort_type_code'' as cohort_type_code from programacion.provenance_receipts where subject_type=''IG_CANARY_OBSERVATION'' and receipt_kind=''EVIDENCE_VERIFICATION'' and issuer_channel=''EVIDENCE_VERIFIER_V1'' order by id desc limit 20',
      'select capability_code,version,manifest_sha256,previous_version from public.lf_capability_current where capability_code=''INPUT_GOVERNANCE'''),
   'readback_acceptance_v1',jsonb_build_object(
      'signed_live_receipts_required',true,'all_five_triggers_required',true,
      'trigger_codes','["FALSE_PASS","DIVERGENCE","TIMEOUT","EXECUTION_ERROR","MISSING_RECEIPT"]'::jsonb,
      'same_baseline_manifest_required',true,'zero_material_residue_required',true,
      'empty_result','BLOCK','simulated_only','BLOCK','production_activation',false));
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(
    jsonb_set(unit_metadata,'{action_specs_v1,ROLLBACK_TRIGGER_NEGATIVE}',v_cp4,true),
    '{action_specs_v1,CANARY_READBACK}',v_cp5,true)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9';
 IF NOT FOUND THEN RAISE EXCEPTION 'M99_CONSUMER_BINDING_NOT_WRITTEN'; END IF;
 IF programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.9','CANARY_READBACK')->>'status'
    IS DISTINCT FROM 'READY' THEN RAISE EXCEPTION 'M99_CP5_NOT_COMPILED'; END IF;
END $contract$;
UPDATE public.lf_error_knowledge
SET evidencia=coalesce(evidencia,'')||
 ' | 2026-10-11: PR2255 real-runtime assertion applied; signed IG_CANARY_OBSERVATION receipts still 0; RCV v1.0.3 is available but IG flow_adapter not yet verified. Contract declares consumer binding and keeps M9.9 checkpoint 4/5 pending, without production activation.',
 updated_at=now()
WHERE codigo='IG-M99-ROLLBACK-FIVE-TRIGGERS-VALIDATION-GAP-001' AND estado='ACTIVO';
