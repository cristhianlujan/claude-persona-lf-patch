-- PE10 C3 only: reconcile existing evidence into the EXISTING append-only event channel.
-- FAIL-FORWARD of PRE-APPLY Train run 38783888361, PR #2770:
-- original event was rejected by the existing operational-event/v2 envelope guard.
-- This version adds execution_id, producer, purpose, occurred_at, acceptance_declared=false.
-- Source persisted by prior Train but NOT applied to DB; new exact migration only.
-- Acceptance-signal function checked read-only and returned NULL.
-- Route: ACT-0001 -> ACTUALIZACION_DB_LF -> LF Migration Merge Train (not SQL Editor).
-- Scope: one ARTIFACT_RECONCILED event. NO profile runtime, steps, policy, ledger,
-- review verdict, C3 assertion, historical RAW or operation status modification.
-- The record states NOT_ADMITTED, never PASS or VERIFIED.
BEGIN;
DO $pre$
DECLARE v_digest text; v_review_raw_sha text; v_steps integer; v_count integer;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.v_lf_event_type_contract_audit_v2 WHERE event_type='ARTIFACT_RECONCILED'
     AND active AND contract_mode='OPERATIONAL' AND 'operational-event/v2'=ANY(allowed_evidence_schemas))
 THEN RAISE EXCEPTION 'PE10_C3_RECON_EVENT_CONTRACT_INACTIVE'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u USING(work_item_id)
   WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
 THEN RAISE EXCEPTION 'PE10_C3_RECON_CHECKPOINT_CHANGED'; END IF;
 SELECT encode(extensions.digest(convert_to(jsonb_build_object(
   'plan','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','unit','PE10',
   'c1',(SELECT c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u USING(work_item_id) WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C1'),
   'c2',(SELECT c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u USING(work_item_id) WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C2'),
   'c2b',(SELECT c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u USING(work_item_id) WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C2B'),
   'first_evolution',(SELECT c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u USING(work_item_id) WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND u.unit_code='PE10E' AND c.checkpoint_code='PE10E_C4'),
   'active_policy',(SELECT policy_sha FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND status='ACTIVE')
 )::text,'UTF8'),'sha256'),'hex') INTO v_digest;
 IF v_digest IS DISTINCT FROM '73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a'
 THEN RAISE EXCEPTION 'PE10_C3_RECON_FROZEN_DIGEST_DRIFT'; END IF;
 IF (SELECT count(*) FROM private.lf_evidence_ledger_v1
     WHERE receipt_id='37db027e-ad58-4cbb-b4dc-01b7568f6ac2'::uuid AND capability_code='EVIDENCE_LEDGER'
       AND receipt_kind='SOURCE_SNAPSHOT' AND verification_state='VERIFIED'
       AND subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10' AND subject_sha256=v_digest
       AND source_head_sha='578e15f654dfccaba8c094c5f33121df8f44f216')<>1
 THEN RAISE EXCEPTION 'PE10_C3_RECON_SOURCE_SNAPSHOT_NOT_VERIFIED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution
     WHERE execution_id='EXEC-PE10C3-INDEP-e983544d2ee0aeb9' AND operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
       AND status='IN_PROGRESS' AND manifest->>'producer_execution_id'='EXEC-PE10C3-PRODUCER-ba99d625fdf0e3ea')
 THEN RAISE EXCEPTION 'PE10_C3_RECON_REVIEW_CONTEXT_CHANGED'; END IF;
 SELECT count(*) INTO v_steps FROM public.lf_operation_execution_steps
 WHERE execution_id='EXEC-PE10C3-INDEP-e983544d2ee0aeb9'
   AND status='STEP_PASS_WITH_EVIDENCE'
   AND step_id IN ('route_bind','target_currentness','semantic_review','judge_record','reviewer_readback','report_output');
 IF v_steps<>2 THEN RAISE EXCEPTION 'PE10_C3_RECON_REVIEW_STEPS_CHANGED'; END IF;
 IF EXISTS (SELECT 1 FROM private.lf_evidence_ledger_v1 WHERE capability_code='INDEPENDENT_ASSURANCE'
     AND receipt_kind='INDEPENDENT_REVIEW_RECEIPT' AND subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
     AND subject_sha256=v_digest AND verification_state='VERIFIED' AND receipt_payload->>'verdict'='PASS')
 THEN RAISE EXCEPTION 'PE10_C3_RECON_NEW_PASS_RECEIPT_REASSESS_REQUIRED'; END IF;
 SELECT encode(extensions.digest(decode(payload->>'raw_utf8_b64','base64'),'sha256'),'hex')
 INTO v_review_raw_sha FROM public.lf_eventos WHERE id=21048 AND evento_tipo='RAW_CAPTURE_BATCH_PREPARED'
  AND payload->>'provider_attested'='false';
 IF v_review_raw_sha IS DISTINCT FROM '53f855d14260761cef4d260d060e847c2bcb4cf9a8f0047948178271a82c96bc'
 THEN RAISE EXCEPTION 'PE10_C3_RECON_REVIEW_RAW_CHANGED'; END IF;
 IF (SELECT count(*) FROM public.lf_eventos WHERE id BETWEEN 21045 AND 21047 AND evento_tipo='RAW_CAPTURE_BATCH_PREPARED'
      AND encode(extensions.digest(decode(payload->>'raw_utf8_b64','base64'),'sha256'),'hex')=payload->>'raw_sha256')<>3
 THEN RAISE EXCEPTION 'PE10_C3_RECON_212_S_BYTES_CHANGED'; END IF;
 IF (SELECT count(*) FROM public.lf_eventos WHERE id BETWEEN 21042 AND 21044 AND evento_tipo='RAW_CAPTURE_BATCH_PREPARED'
      AND char_length(convert_from(decode(payload->>'raw_utf8_b64','base64'),'UTF8')) IN (16520,23183,31677))<>3
 THEN RAISE EXCEPTION 'PE10_C3_RECON_212_R_BYTES_CHANGED'; END IF;
 SELECT count(*) INTO v_count FROM public.lf_eventos
  WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1.PE10_C3.EXISTING_EVIDENCE_RECONCILIATION'
    AND created_by_execution_id='PE10_C3_EVIDENCE_RECONCILIATION_20261015_V2';
 IF v_count<>0 THEN RAISE EXCEPTION 'PE10_C3_RECON_ALREADY_REGISTERED'; END IF;
END $pre$;
SAVEPOINT pe10_c3_recon_probe;
INSERT INTO public.lf_eventos (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
VALUES ('ARTIFACT_RECONCILED','PROGRAM_PLAN','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1.PE10_C3.EXISTING_EVIDENCE_RECONCILIATION',
'PE10_C3 existing evidence reconciled with raw integrity reservations; no independent assurance PASS.',
'INFO','DERIVE_FROM_EXECUTION_ID','PE10_C3_EVIDENCE_RECONCILIATION_20261015_V2',($recon_payload${"evidence_schema_version":"operational-event/v2","operation_code":"ACTUALIZACION_PERFIL_LF","plan_code":"PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1","unit_code":"PE10","checkpoint_code":"PE10_C3","reconciliation_schema":"PE10_C3_EXISTING_EVIDENCE_RECONCILIATION_V1","reconciliation_status":"EVIDENCE_RECONCILED_WITH_INTEGRITY_RESERVATIONS","semantic_review_status":"COMPARISON_DONE_NOT_CERTIFIED","admission_status":"NOT_ADMITTED_NO_CURRENT_PASS_RECEIPT","independent_review_operation_status":"IN_PROGRESS_2_OF_6","source_snapshot_receipt_id":"37db027e-ad58-4cbb-b4dc-01b7568f6ac2","subject_type":"PROFILE_EVOLUTION_CUTOVER","subject_ref":"PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10","subject_sha256":"73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a","source_head_sha":"578e15f654dfccaba8c094c5f33121df8f44f216","review_execution_id":"EXEC-PE10C3-INDEP-e983544d2ee0aeb9","producer_execution_id":"EXEC-PE10C3-PRODUCER-ba99d625fdf0e3ea","semantic_review_raw_event_id":21048,"semantic_review_raw_sha256":"53f855d14260761cef4d260d060e847c2bcb4cf9a8f0047948178271a82c96bc","case_206":"P_SEMANTICALLY_PREFERRED_OVER_Q_WITHOUT_OPERATIONAL_ATTESTATION","case_212":"R_S_SEMANTIC_TIE","reviewer_raw_sha_212_r":"DOES_NOT_MATCH_STORED_21042_21044_TEN_CHAR_DISCREPANCY_EACH","reviewer_raw_sha_212_s":"MATCHES_STORED_21045_21047_ALL_THREE","case_206_reviewer_pair_sha":"NOT_FULLY_BOUND_TO_STORED_21041","provider_attested":false,"independent_review_pass":false,"operational_cutover_allowed":false,"historical_raw_immutable":true,"repeat_evaluation_required":false,"new_model_dispatch":false,"next_governed_action":"HANDLE_NOT_ADMITTED_DISPOSITION_UNDER_EXISTING_CONTRACT_AND_PURSUE_SEPARATE_PE10_C4","document_ref":"docs/profile_updater/PE10_C3_EXISTING_EVIDENCE_RECONCILIATION_20261015.md"}$recon_payload$::jsonb || jsonb_build_object('execution_id','PE10_C3_EVIDENCE_RECONCILIATION_20261015_V2','producer','PE10_C3_EVIDENCE_RECONCILIATION_V2','purpose','Readback of existing PE10 C3 evidence and non-admitted disposition without new review','acceptance_declared',false,'occurred_at',clock_timestamp())));
DO $test_positive$
BEGIN
 IF (SELECT count(*) FROM public.lf_eventos WHERE evento_tipo='ARTIFACT_RECONCILED'
 AND entidad_codigo='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1.PE10_C3.EXISTING_EVIDENCE_RECONCILIATION' AND created_by_execution_id='PE10_C3_EVIDENCE_RECONCILIATION_20261015_V2'
 AND payload->>'reconciliation_status'='EVIDENCE_RECONCILED_WITH_INTEGRITY_RESERVATIONS'
 AND payload->>'admission_status'='NOT_ADMITTED_NO_CURRENT_PASS_RECEIPT'
 AND payload->>'provider_attested'='false' AND payload->>'independent_review_pass'='false') <> 1
 THEN RAISE EXCEPTION 'PE10_C3_RECON_ROLLBACK_TEST_POSITIVE_FAILED'; END IF;
END $test_positive$;
ROLLBACK TO SAVEPOINT pe10_c3_recon_probe;
DO $test_negative$
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_eventos WHERE evento_tipo='ARTIFACT_RECONCILED'
 AND entidad_codigo='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1.PE10_C3.EXISTING_EVIDENCE_RECONCILIATION' AND created_by_execution_id='PE10_C3_EVIDENCE_RECONCILIATION_20261015_V2')
 THEN RAISE EXCEPTION 'PE10_C3_RECON_ROLLBACK_TEST_NEGATIVE_FAILED'; END IF;
END $test_negative$;
RELEASE SAVEPOINT pe10_c3_recon_probe;
INSERT INTO public.lf_eventos (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
VALUES ('ARTIFACT_RECONCILED','PROGRAM_PLAN','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1.PE10_C3.EXISTING_EVIDENCE_RECONCILIATION',
'PE10_C3 existing evidence reconciled with raw integrity reservations; no independent assurance PASS.',
'INFO','DERIVE_FROM_EXECUTION_ID','PE10_C3_EVIDENCE_RECONCILIATION_20261015_V2',($recon_payload${"evidence_schema_version":"operational-event/v2","operation_code":"ACTUALIZACION_PERFIL_LF","plan_code":"PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1","unit_code":"PE10","checkpoint_code":"PE10_C3","reconciliation_schema":"PE10_C3_EXISTING_EVIDENCE_RECONCILIATION_V1","reconciliation_status":"EVIDENCE_RECONCILED_WITH_INTEGRITY_RESERVATIONS","semantic_review_status":"COMPARISON_DONE_NOT_CERTIFIED","admission_status":"NOT_ADMITTED_NO_CURRENT_PASS_RECEIPT","independent_review_operation_status":"IN_PROGRESS_2_OF_6","source_snapshot_receipt_id":"37db027e-ad58-4cbb-b4dc-01b7568f6ac2","subject_type":"PROFILE_EVOLUTION_CUTOVER","subject_ref":"PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10","subject_sha256":"73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a","source_head_sha":"578e15f654dfccaba8c094c5f33121df8f44f216","review_execution_id":"EXEC-PE10C3-INDEP-e983544d2ee0aeb9","producer_execution_id":"EXEC-PE10C3-PRODUCER-ba99d625fdf0e3ea","semantic_review_raw_event_id":21048,"semantic_review_raw_sha256":"53f855d14260761cef4d260d060e847c2bcb4cf9a8f0047948178271a82c96bc","case_206":"P_SEMANTICALLY_PREFERRED_OVER_Q_WITHOUT_OPERATIONAL_ATTESTATION","case_212":"R_S_SEMANTIC_TIE","reviewer_raw_sha_212_r":"DOES_NOT_MATCH_STORED_21042_21044_TEN_CHAR_DISCREPANCY_EACH","reviewer_raw_sha_212_s":"MATCHES_STORED_21045_21047_ALL_THREE","case_206_reviewer_pair_sha":"NOT_FULLY_BOUND_TO_STORED_21041","provider_attested":false,"independent_review_pass":false,"operational_cutover_allowed":false,"historical_raw_immutable":true,"repeat_evaluation_required":false,"new_model_dispatch":false,"next_governed_action":"HANDLE_NOT_ADMITTED_DISPOSITION_UNDER_EXISTING_CONTRACT_AND_PURSUE_SEPARATE_PE10_C4","document_ref":"docs/profile_updater/PE10_C3_EXISTING_EVIDENCE_RECONCILIATION_20261015.md"}$recon_payload$::jsonb || jsonb_build_object('execution_id','PE10_C3_EVIDENCE_RECONCILIATION_20261015_V2','producer','PE10_C3_EVIDENCE_RECONCILIATION_V2','purpose','Readback of existing PE10 C3 evidence and non-admitted disposition without new review','acceptance_declared',false,'occurred_at',clock_timestamp())));
DO $final_readback$
BEGIN
 IF (SELECT count(*) FROM public.lf_eventos WHERE evento_tipo='ARTIFACT_RECONCILED'
 AND entidad_codigo='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1.PE10_C3.EXISTING_EVIDENCE_RECONCILIATION' AND created_by_execution_id='PE10_C3_EVIDENCE_RECONCILIATION_20261015_V2'
 AND payload->>'subject_sha256'='73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a'
 AND payload->>'semantic_review_raw_sha256'='53f855d14260761cef4d260d060e847c2bcb4cf9a8f0047948178271a82c96bc'
 AND payload->>'admission_status'='NOT_ADMITTED_NO_CURRENT_PASS_RECEIPT'
 AND payload->>'independent_review_pass'='false' AND payload->>'operational_cutover_allowed'='false')<>1
 THEN RAISE EXCEPTION 'PE10_C3_RECON_DURABLE_READBACK_FAILED'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u USING(work_item_id)
 WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C3')<>'IN_PROGRESS'
 THEN RAISE EXCEPTION 'PE10_C3_RECON_CHECKPOINT_MUST_STAY_OPEN'; END IF;
END $final_readback$;
COMMIT;
