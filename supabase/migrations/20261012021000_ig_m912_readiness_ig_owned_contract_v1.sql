-- IG M9.12 contract-only: CUTOVER_READY is an IG-owned signed receipt, not POST_PASE.
DO $m$
DECLARE m jsonb;s jsonb;u bigint;
BEGIN
 SELECT work_item_id,unit_metadata INTO u,m FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.12' FOR UPDATE;
 s:=m#>'{action_specs_v1,CLOSURE_GATE_CONSUME}';
 IF u IS NULL OR s->>'status' IS DISTINCT FROM 'READY'
 OR s#>>'{capability_execution_contract,result}' IS DISTINCT FROM 'CUTOVER_READY'
 THEN RAISE EXCEPTION 'M912_CONTRACT_PRESTATE_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.fn_engineering_effective_dependencies_v1(u)
 WHERE effective_work_code='PAULO-150' AND is_unmet)
 THEN RAISE EXCEPTION 'M912_UPSTREAM_GATE_CHANGED'; END IF;
 s:=s||jsonb_build_object(
 'expected','Verify an IG-owned signed CUTOVER_READY receipt from the current four prerequisites and M9.0 signed bundle; never rely on disabled POST_PASE execution',
 'capability_execution_contract',jsonb_build_object(
  'schema_version','IG_CUTOVER_READINESS_RECEIPT_V1','result','CUTOVER_READY',
  'mode','IG_LEDGER_SIGNED_RECEIPT','subject_type','IG_CUTOVER_READINESS',
  'receipt_kind','EVIDENCE_VERIFICATION','issuer_channel','EVIDENCE_VERIFIER_V1',
  'require_m98_current_pass',true,'require_m910_drill',true,'require_m911_soak',true,
  'require_bundle_sha',true,'production_activation',false,'external_post_pase','FORBIDDEN'),
 'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET',
   'pass_when',jsonb_build_object('test_passed',true,'test_exit_code',0,
    'semantic_authority_bound',true,'verified_cutover_receipt_current',true,
    'prerequisites_current',true,'production_inactive',true)));
 s:=jsonb_set(s,'{target,evidence_artifacts}','[]'::jsonb,true);
 s:=jsonb_set(s,'{target,declared_artifacts}',s#>'{target,mutation_artifacts}',true);
 s:=jsonb_set(s,'{target,declared_objects}',jsonb_build_array(
 'programacion.provenance_receipts','programacion.engineering_work_checkpoints','public.lf_capability_current'),true);
 s:=jsonb_set(s,'{test_execution_contract,canonical_exit_criterion}',
 to_jsonb('IG-owned ledger CUTOVER_READY with current verifier receipt, M9.0 bundle and M9.8/M9.10/M9.11 proofs; no production activation'::text),true);
 s:=jsonb_set(s,'{test_execution_contract,checkpoint_title_context}',
 to_jsonb('IG-ledger CUTOVER_READY signed receipt without disabled POST_PASE'::text),true);
 m:=jsonb_set(m,'{action_specs_v1,CLOSURE_GATE_CONSUME}',s,true);
 m:=jsonb_set(m,'{cutover_readiness_governance_v1}',jsonb_build_object(
 'transversal_change','NOT_APPLICABLE_REUSE_GOVERNED_PROVENANCE',
 'issuer','EVIDENCE_VERIFIER_V1','receipt_sink','programacion.provenance_receipts',
 'require_m98_live_pass',true,'require_m910_done',true,'require_m90_signed_bundle',true,
 'post_pase_disabled',true,'no_production_activation',true),true);
 IF m IS NULL THEN RAISE EXCEPTION 'M912_NULL_METADATA'; END IF;
 UPDATE programacion.engineering_plan_units SET unit_metadata=m
 WHERE work_item_id=u AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2';
 UPDATE programacion.engineering_work_checkpoints
 SET title='Validar CUTOVER_READY del ledger IG sin POST_PASE'
 WHERE work_item_id=u AND checkpoint_code='CLOSURE_GATE_CONSUME';
 IF NOT FOUND THEN RAISE EXCEPTION 'M912_CHECKPOINT_NOT_FOUND'; END IF;
END $m$;