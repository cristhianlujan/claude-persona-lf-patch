-- M9.9 consumer correction: source-discover existing generic RCV IG N9 adapter,
-- but never mistake it for verified automatic M9.9 five-trigger rollback.
-- No pointer switch, artifact ownership change, execution receipt fabrication.
DO $repair$
DECLARE v_u record; v_binding jsonb; v_adapter jsonb;
BEGIN
 SELECT id,unit_metadata INTO v_u FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9'
 FOR UPDATE;
 IF NOT FOUND OR v_u.unit_metadata#>>'{action_specs_v1,ROLLBACK_TRIGGER_NEGATIVE,reversible_consumer_binding_v1,flow_adapter_binding_status}' IS DISTINCT FROM 'REQUIRED_NOT_VERIFIED'
 OR v_u.unit_metadata#>>'{action_specs_v1,ROLLBACK_TRIGGER_NEGATIVE,assertion_contract,pass_when,runtime_canary_proven}' IS DISTINCT FROM 'true'
 OR v_u.unit_metadata#>>'{action_specs_v1,CANARY_READBACK,readback_acceptance_v1,empty_result}' IS DISTINCT FROM 'BLOCK'
 THEN RAISE EXCEPTION 'M99_CONSUMER_CONTRACT_BASELINE_DRIFT'; END IF;
 IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current c
    JOIN public.lf_capability_version_registry vr
      ON vr.capability_code=c.capability_code AND vr.version=c.version
    WHERE c.capability_code='REVERSIBLE_CANDIDATE_VERIFICATION'
      AND c.version='1.0.3'
      AND c.manifest_sha256='eccc53277bdd449482ebd5328c38988bba8695d4ce84045b7603751d566f26ab'
      AND vr.manifest_sha256=c.manifest_sha256
      AND vr.manifest#>>'{delivery,ig_adapter_blob_sha1}'='feb877298f7064f69cf8312b241daa49b60e5111'
      AND vr.manifest#>>'{delivery,mode}'='REPOSITORY_BOUND_PYTHON_PROVIDER'
 ) THEN RAISE EXCEPTION 'M99_EXISTING_IG_ADAPTER_SOURCE_DRIFT'; END IF;
 v_adapter:=jsonb_build_object(
    'adapter_code','IG_N9_FLOW_ADAPTER_V1',
    'source_ref','github://cristhianlujan/claude-persona-lf-patch@b23416192a2a87e8407c8d758af424611f9fd80a/sandbox/lf_contract_gate_test/transversal_assets/reversible_candidate_verification/ig_n9_adapter_v1.py',
    'source_blob_sha1','feb877298f7064f69cf8312b241daa49b60e5111',
    'status','SOURCE_VERIFIED_M99_EXECUTION_UNPROVEN',
    'preserved_use','N9_CANDIDATE_REVERSIBILITY_ONLY',
    'm99_five_trigger_adapter_qualification','NOT_PROVEN',
    'false_pass_boundary','POSTSTATE_DIGEST_EQUALITY_ALONE_IS_NOT_PROOF_OF_AUTOMATIC_ROLLBACK',
    'required_material_proof','TRIGGERED_ADAPTER_ACTION_PLUS_SIGNED_RECEIPT_PLUS_EXACT_BASELINE_RESTORE',
    'must_not_be_reported_as','M99_CANARY_RUNTIME_PASS');
 v_binding:=v_u.unit_metadata#>'{action_specs_v1,ROLLBACK_TRIGGER_NEGATIVE,reversible_consumer_binding_v1}';
 v_binding:=v_binding||jsonb_build_object('existing_ig_prior_art_adapter',v_adapter,
   'execution_admission','BLOCK_UNTIL_M99_SPECIFIC_TRIGGER_EXECUTOR_AND_SIGNED_RECEIPTS',
   'automatic_rollback_evidence_required',true,
   'self_reported_boolean_insufficient',true);
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,
   '{action_specs_v1,ROLLBACK_TRIGGER_NEGATIVE,reversible_consumer_binding_v1}',v_binding,true)
 WHERE id=v_u.id;
 IF NOT FOUND THEN RAISE EXCEPTION 'M99_CONSUMER_BIND_WRITE_FAILED'; END IF;
 IF programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.9','ROLLBACK_TRIGGER_NEGATIVE'
  )#>>'{reversible_consumer_binding_v1,existing_ig_prior_art_adapter,status}'
    IS DISTINCT FROM 'SOURCE_VERIFIED_M99_EXECUTION_UNPROVEN'
 THEN RAISE EXCEPTION 'M99_COMPILED_BINDING_NOT_PRESENT'; END IF;
END $repair$;

UPDATE public.lf_error_knowledge
SET evidencia=coalesce(evidencia,'')||
 ' | M9.9 source audit 2026-10-11: RCV v1.0.3 manifest declares IG N9 adapter source Git blob feb877298f7064f69cf8312b241daa49b60e5111, but IgN9FlowAdapter status ROLLED_BACK is inferred from before/after state digest only. This proves neither M9.9 automatic trigger invocation nor verified provenance. M9.9 consumer explicitly distinguishes source available from M9.9 execution qualified. No signed IG_CANARY_OBSERVATION receipts yet.',
    updated_at=now()
WHERE codigo='IG-M99-ROLLBACK-FIVE-TRIGGERS-VALIDATION-GAP-001' AND estado='ACTIVO';

UPDATE public.lf_error_knowledge SET estado='VERIFICADO',
    validacion='Historical CAPABILITY_CUTOVER requirement replaced by actual INPUT_GOVERNANCE CURRENT readback in M9.9 COHORT_BINDING; checkpoint 2 DONE, 0 open blockers, no cutover promotion.',
    evidencia=coalesce(evidencia,'')||' | PR2249 merged/applied, M9.9 COHORT_BINDING DONE; INPUT_GOVERNANCE current 1.0.0; unmet_deps=0.',
    updated_at=now()
WHERE codigo='IG-M99-CUTOVER-UNREGISTERED-AUTHORITY-001' AND estado='ACTIVO'
  AND EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=267 AND checkpoint_code='COHORT_BINDING' AND status='DONE')
  AND EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0');

UPDATE public.lf_error_knowledge SET estado='VERIFICADO',
    validacion='SOURCE_PACK COHORT_BINDING missing=[]; graph canonical dependency closure has unmet_deps=0, no duplicated dependency injected.',
    evidencia=coalesce(evidencia,'')||' | 2026-10-11 canonical bootstrap progress 55%, open_blockers=0, unmet_deps=0; COHORT_BINDING source_pack checkpoint_inputs.missing is empty.',
    updated_at=now()
WHERE codigo='IG-M99-CHECKPOINT-MISSING-NARRATIVE-STALE-001' AND estado='ACTIVO'
  AND EXISTS (SELECT 1 FROM programacion.engineering_plan_units
     WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9'
       AND unit_metadata#>'{source_pack_v1,checkpoint_inputs,COHORT_BINDING,missing}'='[]'::jsonb);
