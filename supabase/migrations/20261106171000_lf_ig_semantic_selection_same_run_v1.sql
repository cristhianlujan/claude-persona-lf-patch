-- LF IG candidate: semantic selection is an INTERNAL phase of the profile's IG dependency.
-- No new profile RUN, Router path, worker, or transport.
-- Does not activate without a source-bound, verified activation contract receipt.
-- EKB GOV-010 / GOV-032 / GOV-LF-RECEIPT-001 / IG-M811.
BEGIN;
DO $preflight$
BEGIN
 IF md5(pg_get_functiondef(
     'programacion.fn_input_run_default_validation_scope_v1()'::regprocedure))
    IS DISTINCT FROM 'cac2bb8aeedbfc0bc6a2db419cfc2518' THEN
   RAISE EXCEPTION 'IG_SEMANTIC_SCOPE_SOURCE_DRIFT';
 END IF;
END $preflight$;

CREATE OR REPLACE FUNCTION programacion.fn_input_run_default_validation_scope_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog'
AS $scope$
DECLARE
 v_activation jsonb;
 v_selected jsonb;
 v_registry jsonb;
 v_screen_code text;
 v_receipt programacion.provenance_receipts%ROWTYPE;
 v_count integer;
 v_family text;
 v_activation_sha text;
 v_caller_source_only boolean:=false;
BEGIN
 IF TG_OP<>'INSERT' THEN RETURN NEW; END IF;
 IF NEW.scope IS NULL OR
    NEW.scope->>'analysis_revision' IS DISTINCT FROM
     'INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX' THEN
   RETURN NEW;
 END IF;

 -- Valid explicit SOURCE_INTEGRITY_ONLY inputs remain compatible.
 -- A caller can never request selected semantics or present a fake receipt.
 IF NEW.scope ? 'validator_semantic_mode' OR
    NEW.scope ? 'validator_semantic_comparison_families' OR
    NEW.scope ? 'semantic_activation_receipt_id' THEN
   v_caller_source_only:=(
     NEW.scope->>'validator_semantic_mode'='SOURCE_INTEGRITY_ONLY'
     AND NEW.scope->'validator_semantic_comparison_families'='[]'::jsonb
     AND NEW.scope->>'semantic_promotion_authorized'='false'
     AND NOT (NEW.scope ? 'semantic_activation_receipt_id'));
   IF NOT coalesce(v_caller_source_only,false) THEN
      RAISE EXCEPTION 'IG_SEMANTIC_SCOPE_CALLER_OVERRIDE_DENIED';
   END IF;
 END IF;

 SELECT count(*) INTO v_count
 FROM programacion.contratos c
 WHERE c.version_id=NEW.version_id
   AND c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
   AND c.estado='defined' AND c.fail_closed;
 IF v_count<>1 THEN RAISE EXCEPTION 'IG_SEMANTIC_EXECUTION_CONTRACT_AMBIGUOUS'; END IF;
 SELECT c.especificacion->'validator_semantic_activation_v1'
 INTO v_activation FROM programacion.contratos c
 WHERE c.version_id=NEW.version_id
   AND c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
   AND c.estado='defined' AND c.fail_closed;

 -- Absent/disabled activation preserves legacy behavior, with no model call.
 IF v_activation IS NULL OR v_activation='null'::jsonb OR
    v_activation->>'activation_state'='DISABLED' THEN
   IF v_caller_source_only THEN RETURN NEW; END IF;
   NEW.scope:=NEW.scope||jsonb_build_object(
      'validator_semantic_mode','SOURCE_INTEGRITY_ONLY',
      'validator_semantic_comparison_families','[]'::jsonb,
      'semantic_promotion_authorized',false);
   RETURN NEW;
 END IF;

 -- An activation missing a receipt or a bounded subject is never authoritative.
 IF v_activation->>'schema_version' IS DISTINCT FROM 'IG_SEMANTIC_ACTIVATION_V1'
    OR v_activation->>'activation_state' IS DISTINCT FROM 'ACTIVE_GOVERNED_CANDIDATE'
    OR v_activation->>'production_authorized' IS DISTINCT FROM 'false'
    OR v_activation->>'semantic_promotion_authorized' IS DISTINCT FROM 'false'
    OR nullif(v_activation->>'decision_id','') IS NULL
    OR nullif(v_activation->>'provenance_receipt_id','') IS NULL
    OR jsonb_typeof(v_activation#>'{target_scope,screen_codes}') IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_activation#>'{target_scope,screen_codes}')=0
    OR jsonb_typeof(v_activation->'selected_families') IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_activation->'selected_families')=0
    OR jsonb_array_length(v_activation->'selected_families')>2 THEN
   RAISE EXCEPTION 'IG_SEMANTIC_ACTIVATION_AUTHORITY_INCOMPLETE';
 END IF;

 SELECT p.codigo INTO v_screen_code FROM lf_ops.pantallas p
 WHERE p.id=NEW.pantalla_id AND p.activa;
 IF v_screen_code IS NULL THEN RAISE EXCEPTION 'IG_SEMANTIC_SCREEN_INVALID'; END IF;

 -- Contract is scoped to explicit target screens; never applies globally.
 IF NOT EXISTS (
   SELECT 1 FROM jsonb_array_elements_text(
       v_activation#>'{target_scope,screen_codes}') e(code)
   WHERE e.code=v_screen_code
 ) THEN
   IF v_caller_source_only THEN RETURN NEW; END IF;
   NEW.scope:=NEW.scope||jsonb_build_object(
      'validator_semantic_mode','SOURCE_INTEGRITY_ONLY',
      'validator_semantic_comparison_families','[]'::jsonb,
      'semantic_promotion_authorized',false);
   RETURN NEW;
 END IF;

 -- An in-scope comparison is not optional by caller.
 IF v_caller_source_only THEN
   RAISE EXCEPTION 'IG_SEMANTIC_REQUIRED_COMPARISON_CANNOT_BE_SKIPPED';
 END IF;
 -- Only the existing Curator Edge identity may be selected.
 IF NEW.curator_identity NOT LIKE
    'INPUT_CURATOR:EDGE:input-governance-curator-v1:%' THEN
   RAISE EXCEPTION 'IG_SEMANTIC_CURATOR_IDENTITY_NOT_ADMITTED';
 END IF;

 v_activation_sha:=programacion.fn_v09_sha256_jsonb(
    v_activation-'provenance_receipt_id'-'provenance_receipt_sha256');
 SELECT * INTO v_receipt FROM programacion.provenance_receipts r
 WHERE r.id=(v_activation->>'provenance_receipt_id')::bigint;
 IF NOT FOUND OR
    v_receipt.receipt_kind IS DISTINCT FROM 'EVIDENCE_VERIFICATION' OR
    v_receipt.issuer_channel IS DISTINCT FROM 'EVIDENCE_VERIFIER_V1' OR
    v_receipt.subject_type IS DISTINCT FROM 'input_governance_semantic_activation' OR
    v_receipt.subject_ref IS DISTINCT FROM v_activation->>'decision_id' OR
    v_receipt.subject_sha256 IS DISTINCT FROM v_activation_sha OR
    v_receipt.payload->>'verification_status' IS DISTINCT FROM 'VERIFIED' OR
    v_receipt.receipt_sha256 IS DISTINCT FROM
      v_activation->>'provenance_receipt_sha256' THEN
   RAISE EXCEPTION 'IG_SEMANTIC_ACTIVATION_RECEIPT_NOT_VERIFIED';
 END IF;
 PERFORM programacion.fn_assert_provenance_receipt(
    v_receipt.id,'EVIDENCE_VERIFICATION',v_receipt.execution_id,
    v_receipt.head_sha,v_receipt.subject_type,
    v_receipt.subject_ref,v_receipt.subject_sha256);

 SELECT c.especificacion->'families' INTO v_registry
 FROM programacion.contratos c
 WHERE c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
   AND c.version_id=NEW.version_id AND c.estado='defined' AND c.fail_closed
 ORDER BY c.id DESC LIMIT 1;
 IF jsonb_typeof(v_registry)<>'object' THEN
   RAISE EXCEPTION 'IG_SEMANTIC_FAMILY_REGISTRY_UNRESOLVED';
 END IF;
 v_selected:=v_activation->'selected_families';

 -- Pilot scope is narrow; all eligibility comes from contract and registry.
 FOR v_family IN SELECT value FROM jsonb_array_elements_text(v_selected) LOOP
   IF v_family NOT IN ('RATE_LIMIT','SESSION')
      OR coalesce(v_registry->v_family->'validator_oracle_strategy'->>'strategy','')='' THEN
     RAISE EXCEPTION 'IG_SEMANTIC_FAMILY_NOT_AUTHORIZED:%',v_family;
   END IF;
 END LOOP;
 IF (SELECT count(DISTINCT x.value)
     FROM jsonb_array_elements_text(v_selected) x(value))
       <>jsonb_array_length(v_selected) THEN
   RAISE EXCEPTION 'IG_SEMANTIC_FAMILY_DUPLICATED';
 END IF;
 NEW.scope:=NEW.scope||jsonb_build_object(
    'validator_semantic_mode','SELECTED_SEMANTIC_COMPARISON',
    'validator_semantic_comparison_families',v_selected,
    'semantic_promotion_authorized',false,
    'semantic_activation_decision_id',v_activation->>'decision_id',
    'semantic_activation_receipt_id',v_receipt.id,
    'semantic_activation_receipt_sha256',v_receipt.receipt_sha256);
 RETURN NEW;
END $scope$;
-- Does not write contract data, only reads an optional governed activation node.
COMMIT;
