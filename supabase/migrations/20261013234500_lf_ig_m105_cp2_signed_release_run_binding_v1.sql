-- M10.5/CP2 only. An attestable existing Edge run, not a new release or a simulated run.
-- Reuses the canonical EVIDENCE_VERIFIER_V1 issuer; never writes run, policy, promotion or human decision.
CREATE OR REPLACE FUNCTION public.fn_ig_m105_cp2_attest_run_v1(p_run_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, programacion, public
AS $m105$
DECLARE
 v_run programacion.input_readiness_runs%rowtype;
 v_release record;
 v_handoff programacion.provenance_receipts%rowtype;
 v_promotion record;
 v_cutover_receipt programacion.provenance_receipts%rowtype;
 v_authority_receipt programacion.provenance_receipts%rowtype;
 v_families bigint; v_valid bigint;
 v_source jsonb; v_sha text; v_ref text;
 v_token text; v_payload jsonb;
 v_id bigint; v_receipt_sha text;
 v_issuer constant text := 'SUPABASE:IG_M105_CP2_CANONICAL_EDGE_RELEASE_VERIFIER_V1';
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'IG_M105_CP2_ATTESTATION_SERVICE_ROLE_ONLY';
 END IF;
 IF p_run_id IS NULL OR p_run_id<1 THEN RAISE EXCEPTION 'IG_M105_CP2_RUN_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('M105_ATTEST_RUN:'||p_run_id,0));
 SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=p_run_id;
 IF NOT EXISTS(
   SELECT 1 FROM programacion.engineering_plan_units u,
     LATERAL jsonb_array_elements_text(u.unit_metadata#>'{m105_scope_v1,screen_ids}') e
   WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.5'
   AND e.value=v_run.pantalla_id::text
 ) THEN RAISE EXCEPTION 'IG_M105_CP2_SCREEN_OUTSIDE_FROZEN_COHORT'; END IF;
 SELECT c.version,c.previous_version,c.manifest_sha256,c.promoted_at,r.release_state,r.supersedes_version
 INTO STRICT v_release
 FROM public.lf_capability_current c
 JOIN public.lf_capability_version_registry r
   ON r.capability_code=c.capability_code AND r.version=c.version
 WHERE c.capability_code='INPUT_GOVERNANCE';
 IF v_release.previous_version IS NULL OR v_release.version=v_release.previous_version
 OR v_release.release_state<>'RELEASED'
 OR v_release.supersedes_version IS DISTINCT FROM v_release.previous_version
 OR v_release.manifest_sha256 !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'IG_M105_CP2_AUTHENTIC_VNEXT_REQUIRED'; END IF;
 IF v_run.status IS DISTINCT FROM 'COMPLETED'
 OR v_run.created_at<=v_release.promoted_at
 OR v_run.curator_completed_at IS NULL OR v_run.validator_completed_at IS NULL
 OR v_run.curator_identity NOT LIKE 'INPUT_CURATOR:EDGE:input-governance-curator-v1:%'
 OR v_run.validator_identity NOT LIKE 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:%'
 OR v_run.source_snapshot_sha256 !~ '^[0-9a-f]{64}$'
 OR NOT programacion.fn_input_run_is_source_current(v_run.id)
 OR EXISTS(SELECT 1 FROM programacion.input_readiness_runs latest
   WHERE latest.pantalla_id=v_run.pantalla_id AND latest.id>v_run.id)
 THEN RAISE EXCEPTION 'IG_M105_CP2_NO_CURRENT_COMPLETED_EDGE_RUN:%',p_run_id; END IF;
 SELECT count(*),count(*) FILTER(
   WHERE a.validator_outcome IN ('PASS','FAIL','BLOCKED')
    AND a.validator_identity=v_run.validator_identity
    AND a.validator_sha256 ~ '^[0-9a-f]{64}$'
    AND jsonb_typeof(a.validator_evidence)='object'
    AND a.validator_assessed_at IS NOT NULL
 ) INTO v_families,v_valid FROM programacion.input_family_assessments a WHERE a.run_id=v_run.id;
 IF v_run.family_count<=0 OR v_families<>v_run.family_count OR v_valid<>v_families
 THEN RAISE EXCEPTION 'IG_M105_CP2_EDGE_EVALUATION_INCOMPLETE:%',p_run_id; END IF;
 SELECT * INTO v_handoff
 FROM programacion.provenance_receipts h
 WHERE h.subject_type='input_governance_curator_handoff'
   AND h.receipt_kind='EVIDENCE_VERIFICATION'
   AND h.issuer_channel='EVIDENCE_VERIFIER_V1'
   AND h.subject_ref='input-readiness-run:'||v_run.id
   AND h.payload->>'verification_status'='VERIFIED'
   AND h.payload#>>'{handoff,run_id}'=v_run.id::text
   AND h.payload#>>'{handoff,curator_identity}'=v_run.curator_identity
   AND h.created_at>=v_run.created_at
 ORDER BY h.id DESC LIMIT 1;
 IF v_handoff.id IS NULL THEN
   RAISE EXCEPTION 'IG_M105_CP2_SIGNED_EDGE_HANDOFF_REQUIRED:%',p_run_id;
 END IF;
 PERFORM programacion.fn_assert_provenance_receipt(
   v_handoff.id,'EVIDENCE_VERIFICATION',v_handoff.execution_id,
   v_handoff.head_sha,v_handoff.subject_type,v_handoff.subject_ref,v_handoff.subject_sha256);
 -- The operational release requires actual governed promotion/human admission.
 -- The project construction and sandbox tests do NOT create these records.
 SELECT p.id AS promotion_id,p.head_sha,p.technical_manifest_sha256,
        p.audit_receipt_id,d.id AS human_decision_id,d.authority_receipt_id
 INTO v_promotion
 FROM programacion.promotions p
 JOIN programacion.human_decisions d ON d.id=p.human_decision_id
 WHERE d.decision='APPROVE'
   AND d.metadata->>'decision_class'='CUTOVER_AUTHORIZED'
   AND d.authority_receipt_id IS NOT NULL
   AND p.audit_receipt_id IS NOT NULL
   AND p.created_at<=v_release.promoted_at
   AND EXISTS(
     SELECT 1 FROM programacion.provenance_receipts b
     WHERE b.id=p.audit_receipt_id AND b.issuer_channel='EVIDENCE_VERIFIER_V1'
      AND b.receipt_kind='EVIDENCE_VERIFICATION'
      AND b.payload->>'verification_status'='VERIFIED'
   )
 ORDER BY p.id DESC LIMIT 1;
 IF v_promotion.promotion_id IS NULL THEN
   RAISE EXCEPTION 'IG_M105_CP2_GOVERNED_CUTOVER_RECEIPT_REQUIRED'; END IF;
 SELECT * INTO STRICT v_cutover_receipt
 FROM programacion.provenance_receipts WHERE id=v_promotion.audit_receipt_id;
 IF v_cutover_receipt.head_sha IS DISTINCT FROM v_promotion.head_sha
 OR v_cutover_receipt.receipt_kind IS DISTINCT FROM 'EVIDENCE_VERIFICATION'
 OR v_cutover_receipt.issuer_channel IS DISTINCT FROM 'EVIDENCE_VERIFIER_V1'
 OR v_cutover_receipt.payload->>'verification_status' IS DISTINCT FROM 'VERIFIED'
 THEN RAISE EXCEPTION 'IG_M105_CP2_CUTOVER_AUDIT_RECEIPT_INVALID'; END IF;
 PERFORM programacion.fn_assert_provenance_receipt(
   v_cutover_receipt.id,v_cutover_receipt.receipt_kind,v_cutover_receipt.execution_id,
   v_cutover_receipt.head_sha,v_cutover_receipt.subject_type,
   v_cutover_receipt.subject_ref,v_cutover_receipt.subject_sha256);
 SELECT * INTO STRICT v_authority_receipt
 FROM programacion.provenance_receipts WHERE id=v_promotion.authority_receipt_id;
 PERFORM programacion.fn_assert_provenance_receipt(
   v_authority_receipt.id,v_authority_receipt.receipt_kind,
   v_authority_receipt.execution_id,v_authority_receipt.head_sha,
   v_authority_receipt.subject_type,v_authority_receipt.subject_ref,
   v_authority_receipt.subject_sha256);
 v_ref:='input-readiness-run:'||v_run.id::text;
 v_source:=jsonb_build_object(
    'schema_version','IG_M105_CP2_RELEASE_RUN_BINDING_SUBJECT_V1',
    'runtime','input-governance-agent-v1',
    'run_id',v_run.id,'pantalla_id',v_run.pantalla_id,
    'source_snapshot_sha256',v_run.source_snapshot_sha256,
    'release_id',v_release.version,
    'release_manifest_sha256',v_release.manifest_sha256,
    'curator_identity',v_run.curator_identity,
    'validator_identity',v_run.validator_identity,
    'curator_handoff_receipt_sha256',v_handoff.receipt_sha256,
    'promotion_id',v_promotion.promotion_id,
    'cutover_audit_receipt_id',v_promotion.audit_receipt_id,
    'family_count',v_run.family_count);
 v_sha:=programacion.fn_v09_sha256_jsonb(v_source);
 SELECT id,receipt_sha256 INTO v_id,v_receipt_sha
 FROM programacion.provenance_receipts pr
 WHERE pr.subject_type='IG_RELEASE_RUN_BINDING'
 AND pr.subject_ref=v_ref AND pr.subject_sha256=v_sha
 AND pr.head_sha=v_promotion.head_sha
 AND pr.issuer_channel='EVIDENCE_VERIFIER_V1'
 AND pr.receipt_kind='EVIDENCE_VERIFICATION'
 AND pr.payload->>'verification_status'='VERIFIED'
 ORDER BY id DESC LIMIT 1;
 IF v_id IS NULL THEN
   SELECT decrypted_secret INTO v_token FROM vault.decrypted_secrets
   WHERE name='EVIDENCE_VERIFIER_V1_TOKEN' ORDER BY created_at DESC LIMIT 1;
   IF length(coalesce(v_token,''))<32 THEN
     RAISE EXCEPTION 'IG_M105_CP2_CANONICAL_VERIFIER_TOKEN_UNAVAILABLE'; END IF;
   v_payload:=jsonb_build_object(
     'schema_version','IG_M105_CP2_RELEASE_RUN_BINDING_RECEIPT_V1',
     'runtime','input-governance-agent-v1',
     'head_sha',v_promotion.head_sha,
     'subject_type','IG_RELEASE_RUN_BINDING',
     'subject_ref',v_ref,'subject_sha256',v_sha,
     'run_id',v_run.id::text,'pantalla_id',v_run.pantalla_id::text,
     'release_id',v_release.version,
     'release_manifest_sha256',v_release.manifest_sha256,
     'verification_status','VERIFIED',
     'verifier_identity',v_issuer,
     'verification_method','CANONICAL_EDGE_RUN_HANDOFF_CUTOVER_READBACK_V1',
     'signed_curator_handoff_id',v_handoff.id,
     'promotion_id',v_promotion.promotion_id,
     'source_snapshot_sha256',v_run.source_snapshot_sha256);
   SELECT id,receipt_sha256 INTO v_id,v_receipt_sha
   FROM programacion.issue_provenance_receipt(
     'EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',
     null,v_promotion.head_sha,'IG_RELEASE_RUN_BINDING',v_ref,v_sha,
     v_issuer,'supabase://programacion.input_readiness_runs/'||v_run.id||'#m105-cp2-release',
     v_payload);
 END IF;
 PERFORM programacion.fn_assert_provenance_receipt(
   v_id,'EVIDENCE_VERIFICATION',null,v_promotion.head_sha,
   'IG_RELEASE_RUN_BINDING',v_ref,v_sha);
 RETURN jsonb_build_object(
   'status','PERSISTED_VERIFIED','run_id',v_run.id,
   'receipt_id',v_id,'receipt_sha256',v_receipt_sha,
   'release_id',v_release.version,'pantalla_id',v_run.pantalla_id,
   'production_activation',false);
END $m105$;
REVOKE ALL ON FUNCTION public.fn_ig_m105_cp2_attest_run_v1(bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_ig_m105_cp2_attest_run_v1(bigint)
  TO service_role;

DO $align$
DECLARE u jsonb; wid bigint;
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT wid,u
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5' FOR UPDATE;
 IF (SELECT status FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=wid AND checkpoint_code='NEW_RUNS_VNEXT')<>'PENDING'
 OR u#>>'{m105_cp2_producer_v1,schema_version}'
   IS DISTINCT FROM 'IG_M105_CP2_CANONICAL_DISPATCH_PRODUCER_V1'
 OR u#>>'{action_specs_v1,NEW_RUNS_VNEXT,action_kind}'
   IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
 THEN RAISE EXCEPTION 'IG_M105_CP2_ISSUER_PRESTATE_DRIFT'; END IF;
 u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,action_kind}',
   to_jsonb('DECLARED_TEST_EXECUTION'::text),true);
 u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,recipe_mode}',
   to_jsonb('RUN_EXACT_TEST_SET'::text),true);
 u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,precision}',
   to_jsonb('EXPLICIT_M105_AUTHENTIC_EDGE_RELEASE_COHORT_V1'::text),true);
 u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,contract_family}',
   to_jsonb('DECLARED_TEST_EXECUTION'::text),true);
 u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,mutation_policy}',
   to_jsonb('ONLY_DECLARED_TARGETS'::text),true);
 u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,authoring_required}',
   'false'::jsonb,true);
 u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,negative_required}',
   'true'::jsonb,true);
 u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,attestation_rpc}',
   to_jsonb('public.fn_ig_m105_cp2_attest_run_v1'::text),true);
 u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,canonical_exit_criterion}',
   to_jsonb('13 authentic vNext Edge runs with independently signed receipts and per-screen readback; semantic rejections and manual reviews are outcomes, not execution errors'::text),true);
 u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,assertion_contract,pass_when}',
   jsonb_build_object('cohort_count',13,'technical_pass_count',13,
   'technical_error_count',0,'cp2_pass_count',13,'cp2_not_executed_count',0,
   'cp2_provenance_error_count',0,'cp2_pending_count',0,
   'edge_provenance_receipt_count',13,'release_bound_count',13,
   'not_a_production_authorization',true),true);
 u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,target,declared_objects}',
   u#>'{action_specs_v1,NEW_RUNS_VNEXT,target,declared_objects}'
   || jsonb_build_array('public.fn_ig_m105_cp2_attest_run_v1'),true);
 u:=jsonb_set(u,'{source_pack_v1,checkpoint_inputs,NEW_RUNS_VNEXT,inputs,db_objects}',
   u#>'{source_pack_v1,checkpoint_inputs,NEW_RUNS_VNEXT,inputs,db_objects}'
   || jsonb_build_array('public.fn_ig_m105_cp2_attest_run_v1'),true);
 u:=jsonb_set(u,'{m105_cp2_producer_v1,receipt_issuer}',
   to_jsonb('public.fn_ig_m105_cp2_attest_run_v1'::text),true);
 u:=jsonb_set(u,'{m105_cp2_producer_v1,execution_status}',
   to_jsonb('ISSUER_READY_VNEXT_REQUIRED'::text),true);
 u:=jsonb_set(u,'{m105_cp2_producer_v1,release_gate}',
   to_jsonb('AUTHENTIC_PROMOTED_RELEASE_WITH_GOVERNED_HUMAN_AND_AUDIT_RECEIPTS'::text),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=u
 WHERE work_item_id=wid AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5';
 IF (SELECT unit_metadata#>>'{m105_cp2_producer_v1,receipt_issuer}'
 FROM programacion.engineering_plan_units WHERE work_item_id=wid)
 IS DISTINCT FROM 'public.fn_ig_m105_cp2_attest_run_v1'
 THEN RAISE EXCEPTION 'IG_M105_CP2_ISSUER_READBACK_FAIL'; END IF;
END $align$;

INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
SELECT 'IG-M105-CP2-NO-SIGNED-RUN-BINDING-007','INPUT_GOVERNANCE',
'CP2 producer compiled READY without canonical receipt issuance',
'Existing Agent Edge and Python dispatcher did not independently attest run-to-release evidence.',
'No IG_RELEASE_RUN_BINDING issuer existed, and checkpoint action_kind remained TEST_AUTHORING.',
'Reuse existing EVIDENCE_VERIFIER_V1 signing channel; require authentic promoted version, live Edge identities, signed Curator handoff, current terminal family run and governed cutover before issuing idempotent receipt. Align only CP2 action to declared execution.',
'Read-only preflight: version=1.0.0 previous=NULL, 0 admitted runs and 0 receipts. No synthetic PASS or production promotion.',
'github://cristhianlujan/claude-persona-lf-patch/ig/m105-cp2-authentic-issuer-20261013',
'programacion.engineering_plan_units/M10.5/NEW_RUNS_VNEXT','IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5',
'ACTIVO','CONTRACT_PREFLIGHT',ARRAY['Architect','Builder','Judge','Auditor']::text[]
WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge WHERE codigo='IG-M105-CP2-NO-SIGNED-RUN-BINDING-007');
