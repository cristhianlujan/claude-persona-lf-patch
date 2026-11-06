-- LF IG L15: independent provenance readback INSIDE the existing Validator Edge.
-- Read only: reuse programacion.provenance_receipts and its token-gated channels.
-- Does NOT create a judge, issue a receipt, or authorize family PASS/production.
-- EKB GOV-010 / GOV-032 / GOV-LF-RECEIPT-001 / IG-M811.
BEGIN;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_external_receipt_readback_core_v1(
 p_run_id bigint, p_validator_identity text, p_handoff_receipt_id bigint,
 p_candidate_sha256 text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','public'
AS $body$
DECLARE
 v_run programacion.input_readiness_runs%ROWTYPE;
 v_packet jsonb;
 v_handoff jsonb;
 v_subject_ref text;
 v_evidence programacion.provenance_receipts%ROWTYPE;
 v_audit programacion.provenance_receipts%ROWTYPE;
 v_count integer;
 v_expected_sha text;
BEGIN
 IF p_run_id IS NULL OR p_run_id<1 OR p_handoff_receipt_id IS NULL OR p_handoff_receipt_id<1
    OR p_validator_identity !~ '^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$'
    OR (p_candidate_sha256 IS NOT NULL AND p_candidate_sha256 !~ '^[a-f0-9]{64}$') THEN
   RAISE EXCEPTION 'IG_SEMANTIC_RECEIPT_INPUT_INVALID';
 END IF;
 SELECT * INTO v_run FROM programacion.input_readiness_runs r WHERE r.id=p_run_id;
 IF NOT FOUND OR v_run.status<>'VALIDATING' OR v_run.invalidated_at IS NOT NULL
    OR v_run.validator_identity IS DISTINCT FROM p_validator_identity
    OR v_run.curator_identity IS NOT DISTINCT FROM p_validator_identity THEN
   RAISE EXCEPTION 'IG_SEMANTIC_RECEIPT_RUN_NOT_CURRENT';
 END IF;

 -- The same Curator handoff and source-pinned packet must still validate.
 v_handoff:=programacion.fn_input_governance_validator_handoff_assert_v1(
   p_run_id,p_handoff_receipt_id);
 IF v_handoff->>'status'<>'VERIFIED' THEN
   RAISE EXCEPTION 'IG_SEMANTIC_RECEIPT_CURATOR_HANDOFF_INVALID';
 END IF;
 v_packet:=programacion.fn_input_governance_semantic_packet_core_v1(
   p_run_id,p_validator_identity,p_handoff_receipt_id);
 IF v_packet->>'status'<>'READY_FOR_MODEL_CANDIDATE'
    OR v_packet->>'source_integrity_verified'<>'true' THEN
   RAISE EXCEPTION 'IG_SEMANTIC_RECEIPT_SOURCE_PIN_STALE';
 END IF;
 v_subject_ref:='input-readiness-run:'||p_run_id::text;
 -- Verification receipt is emitted ONLY by the existing external EVIDENCE_VERIFIER.
 SELECT count(*) INTO v_count FROM programacion.provenance_receipts e
 WHERE e.receipt_kind='EVIDENCE_VERIFICATION'
   AND e.issuer_channel='EVIDENCE_VERIFIER_V1'
   AND e.subject_type='input_governance_semantic_model_candidate'
   AND e.subject_ref=v_subject_ref
   AND e.subject_sha256 ~ '^[a-f0-9]{64}$'
   AND (p_candidate_sha256 IS NULL OR e.subject_sha256=p_candidate_sha256)
   AND e.payload->>'verification_status'='VERIFIED'
   AND e.payload->>'run_id'=p_run_id::text
   AND e.payload->>'validator_identity'=p_validator_identity
   AND e.payload->>'handoff_receipt_id'=p_handoff_receipt_id::text
   AND e.payload->>'db_packet_sha256'=v_packet->>'db_packet_sha256'
   AND e.payload->>'curator_source_pins_sha256'=v_packet->>'curator_source_pins_sha256';
 IF v_count=0 THEN
   RETURN jsonb_build_object('status','SEMANTIC_CANDIDATE_VERIFICATION_REQUIRED',
      'run_id',p_run_id,'model_candidate_verified',false,'auditor_verified',false,
      'promotion_authorized',false,'production_authorized',false);
 END IF;
 IF v_count<>1 THEN RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_VERIFICATION_AMBIGUOUS'; END IF;
 SELECT * INTO v_evidence FROM programacion.provenance_receipts e
 WHERE e.receipt_kind='EVIDENCE_VERIFICATION'
   AND e.issuer_channel='EVIDENCE_VERIFIER_V1'
   AND e.subject_type='input_governance_semantic_model_candidate'
   AND e.subject_ref=v_subject_ref
   AND e.subject_sha256 ~ '^[a-f0-9]{64}$'
   AND (p_candidate_sha256 IS NULL OR e.subject_sha256=p_candidate_sha256)
   AND e.payload->>'verification_status'='VERIFIED'
   AND e.payload->>'run_id'=p_run_id::text
   AND e.payload->>'validator_identity'=p_validator_identity
   AND e.payload->>'handoff_receipt_id'=p_handoff_receipt_id::text
   AND e.payload->>'db_packet_sha256'=v_packet->>'db_packet_sha256'
   AND e.payload->>'curator_source_pins_sha256'=v_packet->>'curator_source_pins_sha256';
 -- Recalculate the originally token-gated receipt digest for readback integrity.
 v_expected_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
   'schema_version',1,'receipt_kind',v_evidence.receipt_kind,
   'execution_id',v_evidence.execution_id,'head_sha',v_evidence.head_sha,
   'subject_type',v_evidence.subject_type,'subject_ref',v_evidence.subject_ref,
   'subject_sha256',v_evidence.subject_sha256,'issuer_channel',v_evidence.issuer_channel,
   'issuer_identity',v_evidence.issuer_identity,'verification_ref',v_evidence.verification_ref,
   'payload',v_evidence.payload));
 IF v_evidence.receipt_sha256 IS DISTINCT FROM v_expected_sha OR
    nullif(v_evidence.verification_ref,'') IS NULL OR
    v_evidence.payload->>'verifier_identity' IS DISTINCT FROM v_evidence.issuer_identity OR
    v_evidence.issuer_identity IN (v_run.curator_identity,p_validator_identity) THEN
   RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_RECEIPT_NOT_ATTESTED';
 END IF;

 -- The auditor is separately authenticated by an independent AUDIT_VERDICT channel.
 SELECT count(*) INTO v_count FROM programacion.provenance_receipts a
 WHERE a.receipt_kind='AUDIT_VERDICT'
   AND a.issuer_channel='INDEPENDENT_AUDITOR_V1'
   AND a.subject_type='input_governance_semantic_verdict'
   AND a.subject_ref=v_subject_ref
   AND a.subject_sha256=v_evidence.subject_sha256
   AND a.payload->>'run_id'=p_run_id::text
   AND a.payload->>'candidate_sha256'=v_evidence.subject_sha256
   AND a.payload->>'candidate_evidence_receipt_id'=v_evidence.id::text
   AND a.payload->>'db_packet_sha256'=v_packet->>'db_packet_sha256'
   AND a.payload->>'curator_source_pins_sha256'=v_packet->>'curator_source_pins_sha256'
   AND a.payload->>'handoff_receipt_id'=p_handoff_receipt_id::text
   AND a.payload->>'independent'='true'
   AND a.payload->>'verdict' IN ('PASS','FAIL','BLOCKED');
 IF v_count=0 THEN
   RETURN jsonb_build_object('status','INDEPENDENT_SEMANTIC_VERDICT_REQUIRED',
      'run_id',p_run_id,'candidate_sha256',v_evidence.subject_sha256,
      'candidate_evidence_receipt_id',v_evidence.id,
      'model_candidate_verified',true,'auditor_verified',false,
      'promotion_authorized',false,'production_authorized',false);
 END IF;
 IF v_count<>1 THEN RAISE EXCEPTION 'IG_SEMANTIC_AUDIT_VERDICT_AMBIGUOUS'; END IF;
 SELECT * INTO v_audit FROM programacion.provenance_receipts a
 WHERE a.receipt_kind='AUDIT_VERDICT'
   AND a.issuer_channel='INDEPENDENT_AUDITOR_V1'
   AND a.subject_type='input_governance_semantic_verdict'
   AND a.subject_ref=v_subject_ref
   AND a.subject_sha256=v_evidence.subject_sha256
   AND a.payload->>'run_id'=p_run_id::text
   AND a.payload->>'candidate_sha256'=v_evidence.subject_sha256
   AND a.payload->>'candidate_evidence_receipt_id'=v_evidence.id::text
   AND a.payload->>'db_packet_sha256'=v_packet->>'db_packet_sha256'
   AND a.payload->>'curator_source_pins_sha256'=v_packet->>'curator_source_pins_sha256'
   AND a.payload->>'handoff_receipt_id'=p_handoff_receipt_id::text
   AND a.payload->>'independent'='true'
   AND a.payload->>'verdict' IN ('PASS','FAIL','BLOCKED');
 v_expected_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
   'schema_version',1,'receipt_kind',v_audit.receipt_kind,
   'execution_id',v_audit.execution_id,'head_sha',v_audit.head_sha,
   'subject_type',v_audit.subject_type,'subject_ref',v_audit.subject_ref,
   'subject_sha256',v_audit.subject_sha256,'issuer_channel',v_audit.issuer_channel,
   'issuer_identity',v_audit.issuer_identity,'verification_ref',v_audit.verification_ref,
   'payload',v_audit.payload));
 IF v_audit.receipt_sha256 IS DISTINCT FROM v_expected_sha
    OR nullif(v_audit.verification_ref,'') IS NULL
    OR v_audit.payload->>'auditor_identity' IS DISTINCT FROM v_audit.issuer_identity
    OR v_audit.issuer_identity IN (v_evidence.issuer_identity,
       v_run.curator_identity,p_validator_identity)
 THEN RAISE EXCEPTION 'IG_SEMANTIC_AUDIT_PROVENANCE_NOT_INDEPENDENT'; END IF;

 -- A verified AUDIT_VERDICT is provenance evidence, NOT yet an authorized
 -- validator-family PASS; the independent semantic oracle/benchmarks still apply.
 RETURN jsonb_build_object(
   'status','SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE',
   'run_id',p_run_id,
   'candidate_sha256',v_evidence.subject_sha256,
   'candidate_evidence_receipt_id',v_evidence.id,
   'candidate_evidence_receipt_sha256',v_evidence.receipt_sha256,
   'independent_audit_receipt_id',v_audit.id,
   'independent_audit_receipt_sha256',v_audit.receipt_sha256,
   'audit_verdict',v_audit.payload->>'verdict',
   'model_candidate_verified',true,
   'auditor_verified',true,
   'semantic_independence_credited',false,
   'official_write_authorized',false,
   'promotion_authorized',false,'production_authorized',false);
END $body$;

-- The only callable surface is the existing Validator Edge, with the existing ticket.
CREATE OR REPLACE FUNCTION public.fn_input_governance_semantic_external_receipt_readback_v1(
 p_run_id bigint, p_validator_identity text, p_handoff_receipt_id bigint,
 p_ticket uuid, p_candidate_sha256 text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','public'
AS $body$
BEGIN
 PERFORM public.lf_profile_ig_ticket_verify_v1(p_ticket,NULL,p_run_id);
 RETURN programacion.fn_input_governance_semantic_external_receipt_readback_core_v1(
   p_run_id,p_validator_identity,p_handoff_receipt_id,p_candidate_sha256);
END $body$;
REVOKE ALL ON FUNCTION
 programacion.fn_input_governance_semantic_external_receipt_readback_core_v1(bigint,text,bigint,text)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
 public.fn_input_governance_semantic_external_receipt_readback_v1(bigint,text,bigint,uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.fn_input_governance_semantic_external_receipt_readback_v1(bigint,text,bigint,uuid,text)
 TO service_role;
COMMIT;
