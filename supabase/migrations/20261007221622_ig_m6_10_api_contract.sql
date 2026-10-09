-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M6.10 / API_CONTRACT
-- Contract only. Read-only implementation is owned by next checkpoint.
-- Declares one-family provenance chain; does not infer missing receipts or PASS.
DO $m610_contract$
DECLARE
  v_source_id bigint;
  v_version_id bigint;
  v_existing jsonb;
BEGIN
  SELECT id, version_id
    INTO v_source_id, v_version_id
  FROM programacion.contratos
  WHERE contrato_codigo = 'INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    AND estado = 'defined'
  ORDER BY id DESC
  LIMIT 1;

  IF v_source_id IS NULL THEN
    RAISE EXCEPTION 'M6_10_API_CONTRACT_SOURCE_NOT_FOUND';
  END IF;

  SELECT especificacion
    INTO v_existing
  FROM programacion.contratos
  WHERE version_id = v_version_id
    AND contrato_codigo = 'INPUT_EXPLAIN_FAMILY_ASSESSMENT_CONTRACT'
  ORDER BY id DESC
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    IF v_existing->>'schema_version' <> 'INPUT_EXPLAIN_FAMILY_ASSESSMENT_V1' THEN
      RAISE EXCEPTION 'M6_10_API_CONTRACT_EXISTS_WITH_DIFFERENT_SCHEMA';
    END IF;
    RETURN;
  END IF;

  INSERT INTO programacion.contratos
    (version_id, contrato_codigo, tipo, nombre, descripcion,
     estado, especificacion, fail_closed, productor_componente_id)
  SELECT
    c.version_id,
    'INPUT_EXPLAIN_FAMILY_ASSESSMENT_CONTRACT',
    'EXECUTION_INTERFACE',
    'Input Governance family assessment explain contract',
    'Read-only run/family provenance chain: source > source receipt > deterministic > semantic (conditional) > policy > independent validator. A missing mandatory link is INCOMPLETE, never fabricated PASS.',
    'defined',
    '{"schema_version":"INPUT_EXPLAIN_FAMILY_ASSESSMENT_V1","contract_revision":"1.0","function_signature":"programacion.fn_input_explain_family_assessment(bigint,text)","implementation_state":"CONTRACT_DEFINED_IMPLEMENTATION_PENDING","invocation":{"run_id":"bigint","family_code":"text","operation":"READ_ONLY","consumer_interface":"JSONB_NO_SQL"},"scope":{"identity":["run_id","family_code"],"single_family_only":true,"no_cross_family_fanout":true},"chain_order":["SOURCE","SOURCE_RECEIPT","DETERMINISTIC","SEMANTIC","POLICY","VALIDATOR"],"chain":{"SOURCE":{"fields":["source_refs","authority","lifecycle","sha256"],"require_current_authority":true,"no_full_payload":true},"SOURCE_RECEIPT":{"fields":["receipt_id","receipt_kind","subject_type","subject_sha256","source_refs"],"receipt_required_for_used_source":true,"no_synthetic_receipts":true},"DETERMINISTIC":{"fields":["deterministic_sha256","assessment_ref"],"replayable":true,"required_for_assessed_family":true},"SEMANTIC":{"fields":["resolver_id","resolver_version","input_sha256","output_sha256","receipt_ref"],"required_if_resolver_used":true,"not_applicable_if_no_resolver_used":true,"model_output_is_not_authority":true},"POLICY":{"fields":["policy_ref","policy_version","decision","evidence_refs"],"source_of_authority":"CANONICAL_CURRENT_POLICY","no_self_asserted_policy":true},"VALIDATOR":{"fields":["validator_outcome","validator_evidence","validator_sha256","receipt_ref"],"independent_of_curator":true,"no_pass_without_validator_proof":true}},"output":{"type":"jsonb","required_keys":["schema_version","run_id","family_code","run_current","status","chain","missing_evidence","explainable"],"status_values":["EXPLAINABLE","INCOMPLETE"],"not_applicable_step_status":"NOT_APPLICABLE","explainable_only_if_all_applicable_steps_evidenced":true},"guards":{"run_currentness_source":"programacion.fn_input_readiness_run_is_current","completed_run_required":true,"fail_closed_on_missing_run_or_family":true,"fail_closed_on_stale_identity":true,"fail_closed_on_missing_required_receipt":true,"fail_closed_on_digest_mismatch":true,"unknown_is_incomplete":true,"no_source_payload_leakage":true,"only_internal_authorized_consumers":true},"source_contracts":["INPUT_GOVERNANCE_EXECUTION_CONTRACT","INPUT_CONTEXT_MANIFEST_CONTRACT"],"checkpoint_owner":"IG_CURATOR_VALIDATOR_REFACTOR_V2/M6.10/API_CONTRACT","followup_implementation_checkpoint":"READONLY_IMPL"}'::jsonb,
    true,
    c.productor_componente_id
  FROM programacion.contratos c
  WHERE c.id = v_source_id;

  IF NOT EXISTS (
    SELECT 1 FROM programacion.contratos
    WHERE version_id = v_version_id
      AND contrato_codigo = 'INPUT_EXPLAIN_FAMILY_ASSESSMENT_CONTRACT'
      AND fail_closed = true
      AND especificacion->>'schema_version' = 'INPUT_EXPLAIN_FAMILY_ASSESSMENT_V1'
  ) THEN
    RAISE EXCEPTION 'M6_10_API_CONTRACT_POSTINSERT_ASSERTION_FAILED';
  END IF;
END;
$m610_contract$;
