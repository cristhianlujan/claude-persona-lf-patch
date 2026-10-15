-- PE10 C3: close the ALREADY-EVALUATED checkpoint by truthful non-admission disposition.
-- ACT-0001 -> ACTUALIZACION_DB_LF -> LF Migration Merge Train only.
-- This does NOT grant independent assurance PASS; does NOT create a new review.
-- Only PE10 C3 contract/metadata, checkpoint and canonical engineering progress log.
-- C5/C6/C7 cutover admission gates, v0.1 registry, evidence ledger and profiles unchanged.
-- Test first: full contract+checkpoint terminal transition inside rollback subtransaction.
BEGIN;
DO $pe10_c3$
DECLARE
  v_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
  v_unit constant text := 'PE10';
  v_cp constant text := 'PE10_C3';
  v_actor constant text := 'EXEC-PE10-C3-TERMINAL-DISPOSITION-CONTRACT-20261015-001';
  v_event constant bigint := 21093;
  v_event_ref constant text := 'supabase://public/lf_eventos/21093';
  v_subject_digest constant text := '73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a';
  v_source_receipt constant uuid := '37db027e-ad58-4cbb-b4dc-01b7568f6ac2';
  v_work_item_id bigint;
  v_meta_old jsonb;
  v_meta_new jsonb;
  v_contract_old jsonb;
  v_contract_new jsonb;
  v_spec_old jsonb;
  v_spec_new jsonb;
  v_disposition jsonb;
  v_observed jsonb;
  v_digest text;
  v_title_old text;
  v_state_old text;
  v_receipt_ref_old text;
  v_old_write_updates bigint;
  v_transition jsonb;
  v_check_code text;
BEGIN
  SELECT u.work_item_id,u.unit_metadata
    INTO v_work_item_id,v_meta_old
  FROM programacion.engineering_plan_units u
  WHERE u.plan_code=v_plan AND u.unit_code=v_unit AND u.disposition='ASSIGNED'
  FOR UPDATE;
  IF v_work_item_id IS NULL THEN
    RAISE EXCEPTION 'PE10_C3_DISPOSITION_PLAN_UNIT_NOT_FOUND';
  END IF;

  SELECT c.status,c.title,c.evidence_ref
    INTO v_state_old,v_title_old,v_receipt_ref_old
  FROM programacion.engineering_work_checkpoints c
  WHERE c.work_item_id=v_work_item_id AND c.checkpoint_code=v_cp
  FOR UPDATE;
  IF v_state_old IS DISTINCT FROM 'IN_PROGRESS'
      OR v_receipt_ref_old IS NOT NULL
      OR v_title_old IS DISTINCT FROM 'Independent assurance passes on frozen evidence'
  THEN RAISE EXCEPTION 'PE10_C3_DISPOSITION_CHECKPOINT_PREIMAGE_CHANGED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_eventos e
    WHERE e.id=v_event AND e.evento_tipo='ARTIFACT_RECONCILED'
      AND e.entidad_tipo='PROGRAM_PLAN'
      AND e.entidad_codigo='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1.PE10_C3.EXISTING_EVIDENCE_RECONCILIATION'
      AND e.payload->>'reconciliation_status'='EVIDENCE_RECONCILED_WITH_INTEGRITY_RESERVATIONS'
      AND e.payload->>'admission_status'='NOT_ADMITTED_NO_CURRENT_PASS_RECEIPT'
      AND e.payload->>'subject_ref'='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
      AND e.payload->>'subject_sha256'=v_subject_digest
      AND e.payload->>'semantic_review_raw_sha256'='53f855d14260761cef4d260d060e847c2bcb4cf9a8f0047948178271a82c96bc'
      AND e.payload->>'provider_attested'='false'
      AND e.payload->>'independent_review_pass'='false'
      AND e.payload->>'operational_cutover_allowed'='false'
      AND e.payload->>'acceptance_declared'='false'
  ) THEN RAISE EXCEPTION 'PE10_C3_DISPOSITION_EVENT_NOT_BOUND'; END IF;

  SELECT encode(extensions.digest(convert_to(jsonb_build_object(
    'plan',v_plan,'unit',v_unit,
    'c1',(SELECT c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_work_item_id AND c.checkpoint_code='PE10_C1'),
    'c2',(SELECT c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_work_item_id AND c.checkpoint_code='PE10_C2'),
    'c2b',(SELECT c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_work_item_id AND c.checkpoint_code='PE10_C2B'),
    'first_evolution',(SELECT c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id WHERE u.plan_code=v_plan AND u.unit_code='PE10E' AND c.checkpoint_code='PE10E_C4'),
    'active_policy',(SELECT p.policy_sha FROM public.lf_policy_versions p WHERE p.policy_code='POL-PROFILE-UPDATE-PASS' AND p.status='ACTIVE')
  )::text,'UTF8'),'sha256'),'hex') INTO v_digest;
  IF v_digest IS DISTINCT FROM v_subject_digest
    OR (SELECT COUNT(*) FROM private.lf_evidence_ledger_v1 l
        WHERE l.receipt_id=v_source_receipt AND l.subject_sha256=v_subject_digest
          AND l.subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
          AND l.receipt_kind='SOURCE_SNAPSHOT' AND l.verification_state='VERIFIED')<>1
  THEN RAISE EXCEPTION 'PE10_C3_DISPOSITION_FROZEN_IDENTITY_NOT_CURRENT'; END IF;

  IF (SELECT COUNT(*) FROM public.lf_operation_execution op
      WHERE op.execution_id='EXEC-PE10C3-INDEP-e983544d2ee0aeb9'
        AND op.operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
        AND op.status='IN_PROGRESS')<>1
     OR (SELECT COUNT(*) FROM public.lf_operation_execution_steps s
      WHERE s.execution_id='EXEC-PE10C3-INDEP-e983544d2ee0aeb9'
        AND s.status='STEP_PASS_WITH_EVIDENCE')<>2
     OR EXISTS (
       SELECT 1 FROM private.lf_evidence_ledger_v1 l
       WHERE l.capability_code='INDEPENDENT_ASSURANCE'
         AND l.receipt_kind='INDEPENDENT_REVIEW_RECEIPT'
         AND l.subject_type='PROFILE_EVOLUTION_CUTOVER'
         AND l.subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
         AND l.subject_sha256=v_subject_digest
         AND l.verification_state='VERIFIED'
         AND l.receipt_payload->>'verdict'='PASS'
     )
  THEN RAISE EXCEPTION 'PE10_C3_DISPOSITION_NEW_INDEPENDENT_APPROVAL_REASSESS'; END IF;

  IF (SELECT COUNT(*) FROM public.lf_operation_registry r
       WHERE r.operation_code='ACTUALIZACION_PERFIL_LF' AND r.version='v0.1')<>1
    OR EXISTS (SELECT 1 FROM public.lf_eventos e WHERE e.evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
        AND e.entidad_tipo='OPERACION' AND e.entidad_codigo='ACTUALIZACION_PERFIL_LF'
        AND e.payload->>'status'='ADMIT_CUTOVER')
    OR EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints c
        WHERE c.work_item_id=v_work_item_id AND c.checkpoint_code IN ('PE10_C4','PE10_C5','PE10_C6','PE10_C7')
          AND c.status NOT IN ('PENDING','IN_PROGRESS'))
  THEN RAISE EXCEPTION 'PE10_C3_DISPOSITION_CUTOVER_STATE_DRIFT'; END IF;

  v_contract_old:=v_meta_old#>'{checkpoint_contracts,PE10_C3}';
  v_spec_old:=v_meta_old#>'{action_specs_v1,PE10_C3}';
  IF v_contract_old->>'validator_code' IS DISTINCT FROM 'PROFILE_EVOLUTION_BENCHMARK_ADMISSION_V1'
    OR v_spec_old#>>'{assertion_contract,pass_when,assurance}' IS DISTINCT FROM 'PASS'
    OR v_spec_old#>>'{subject_adapter,cutover_approval_implied}' IS DISTINCT FROM 'false'
    OR v_spec_old->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
  THEN RAISE EXCEPTION 'PE10_C3_DISPOSITION_ORIGINAL_ASSURANCE_CONTRACT_DRIFT'; END IF;

  -- C3 is an evaluation-disposition checkpoint; it is NOT cutover admission.
  -- Preserve the original assurance-PASS contract in immutable metadata snapshot.
  v_disposition:=jsonb_build_object(
    'schema','PE10_C3_TERMINAL_EVALUATION_DISPOSITION_V1',
    'resolution','C3_EVALUATION_RECONCILED_NOT_ADMITTED',
    'evaluation_conducted',true,
    'independent_assurance_pass',false,
    'not_admitted',true,
    'no_qualified_gain_proven',true,
    'operational_cutover_allowed',false,
    'no_rerun_required',true,
    'reconciliation_event_id',v_event,
    'reconciliation_event_ref',v_event_ref,
    'frozen_subject_digest',v_subject_digest,
    'original_cutover_assurance_contract',v_contract_old,
    'original_assertion_contract',v_spec_old->'assertion_contract',
    'next_checkpoint','PE10_C4',
    'c5_admission_gate_unchanged',true
  );

  v_contract_new:=jsonb_set(v_contract_old,'{pass_when}',
    to_jsonb('Documented final evaluation disposition: either verified independent approval or exact existing evidence reconciled as NOT_ADMITTED, with cutover blocked'::text),true);
  v_contract_new:=jsonb_set(v_contract_new,'{validator_code}',
    to_jsonb('PE10_C3_TERMINAL_DISPOSITION_READBACK_V1'::text),true);
  v_contract_new:=jsonb_set(v_contract_new,'{resolver_policy}',
    to_jsonb('READ_EXISTING_RECONCILED_NONADMISSION_STOP_RETEST'::text),true);
  v_contract_new:=jsonb_set(v_contract_new,'{validation_input}',
    jsonb_build_object('source','EXACT_EXISTING_RECONCILIATION_EVENT','event_id',v_event,
      'subject_digest',v_subject_digest,'expected_admission','NOT_ADMITTED_NO_CURRENT_PASS_RECEIPT',
      'not_a_cutover_approval',true),true);

  v_spec_new:=jsonb_set(v_spec_old,'{assertion_contract,pass_when}',
    jsonb_build_object('evaluation_reconciled',true,
      'review_disposition','NOT_ADMITTED_NO_CURRENT_PASS_RECEIPT',
      'reconciliation_event_id',v_event,
      'subject_sha256',v_subject_digest,
      'independent_assurance_pass',false,
      'operational_cutover_allowed',false),true);
  v_spec_new:=jsonb_set(v_spec_new,'{validator_contract}',
    jsonb_build_object('required',true,
      'validator_code','PE10_C3_TERMINAL_DISPOSITION_READBACK_V1',
      'pass_when','Exact event 21093 links frozen subject and completed comparison to NOT_ADMITTED; no independent PASS asserted; C5 retains separate cutover admission gate',
      'failure_code','PE10_C3_RECONCILIATION_DISPOSITION_MISSING',
      'resolver_policy','NO_NEW_EVALUATION_AND_NO_CUTOVER_WITHOUT_C5_ADMISSION'),true);
  v_spec_new:=jsonb_set(v_spec_new,'{phase_classification}',
    to_jsonb('EVALUATION_RESULT_ONLY_NO_CUTOVER'::text),true);
  v_spec_new:=jsonb_set(v_spec_new,'{verification_queries}',
    jsonb_build_array('SELECT count(*)::int AS reconciliation_events FROM public.lf_eventos e WHERE e.id=21093 AND e.evento_tipo=''ARTIFACT_RECONCILED'' AND e.payload->>''subject_sha256''=''73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a'' AND e.payload->>''admission_status''=''NOT_ADMITTED_NO_CURRENT_PASS_RECEIPT'' AND e.payload->>''independent_review_pass''=''false'' AND e.payload->>''operational_cutover_allowed''=''false'''),true);
  v_spec_new:=jsonb_set(v_spec_new,'{action_steps}',
    jsonb_build_array('READ_RECONCILIATION_EVENT_21093','RECALCULATE_FROZEN_SUBJECT_DIGEST','VERIFY_NO_ASSURANCE_PASS','DOCUMENT_NONADMITTED_DISPOSITION','RECORD_GOVERNED_TERMINAL_CHECKPOINT_WITHOUT_CUTOVER'),true);

  v_meta_new:=jsonb_set(v_meta_old,'{checkpoint_contracts,PE10_C3}',v_contract_new,false);
  v_meta_new:=jsonb_set(v_meta_new,'{action_specs_v1,PE10_C3}',v_spec_new,false);
  v_meta_new:=jsonb_set(v_meta_new,'{pe10_c3_terminal_disposition_v1}',v_disposition,true);

  -- Keep the C5-C7 original admission requirements byte-identical.
  IF v_meta_new#>'{action_specs_v1,PE10_C5}' IS DISTINCT FROM v_meta_old#>'{action_specs_v1,PE10_C5}'
     OR v_meta_new#>'{checkpoint_contracts,PE10_C5}' IS DISTINCT FROM v_meta_old#>'{checkpoint_contracts,PE10_C5}'
     OR v_meta_new#>'{action_specs_v1,PE10_C6}' IS DISTINCT FROM v_meta_old#>'{action_specs_v1,PE10_C6}'
     OR v_meta_new#>'{action_specs_v1,PE10_C7}' IS DISTINCT FROM v_meta_old#>'{action_specs_v1,PE10_C7}'
  THEN RAISE EXCEPTION 'PE10_C3_DISPOSITION_ADMISSION_GATES_DRIFT'; END IF;
  SELECT COUNT(*) INTO v_old_write_updates FROM programacion.engineering_work_updates
    WHERE work_item_id=v_work_item_id;

  -- POSITIVE rehearsal, followed by guaranteed transaction rollback.
  BEGIN
    UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta_new
     WHERE plan_code=v_plan AND unit_code=v_unit AND unit_metadata=v_meta_old;
    IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C3_TEST_METADATA_CAS_FAILED'; END IF;
    UPDATE programacion.engineering_work_checkpoints SET title='Independent evaluation reconciled; cutover not admitted'
     WHERE work_item_id=v_work_item_id AND checkpoint_code=v_cp;
    v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
      v_plan,v_unit,v_cp,'DONE',v_event_ref,v_actor,
      'Assessment completed and reconciled: NOT_ADMITTED; no independent PASS; C5 cutover admission still required.'
    );
    IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
       OR (SELECT status FROM programacion.engineering_work_checkpoints c
           WHERE c.work_item_id=v_work_item_id AND c.checkpoint_code=v_cp)<>'DONE'
    THEN RAISE EXCEPTION 'PE10_C3_TEST_POSITIVE_TRANSITION_FAILED:%',v_transition; END IF;
    RAISE EXCEPTION 'PE10_C3_TEST_ROLLBACK_SENTINEL';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'PE10_C3_TEST_ROLLBACK_SENTINEL' THEN RAISE; END IF;
  END;

  -- NEGATIVE check: no proposed effects survived rehearsal.
  IF (SELECT unit_metadata FROM programacion.engineering_plan_units
      WHERE plan_code=v_plan AND unit_code=v_unit) IS DISTINCT FROM v_meta_old
      OR (SELECT status FROM programacion.engineering_work_checkpoints c
        WHERE c.work_item_id=v_work_item_id AND c.checkpoint_code=v_cp) IS DISTINCT FROM v_state_old
      OR (SELECT title FROM programacion.engineering_work_checkpoints c
        WHERE c.work_item_id=v_work_item_id AND c.checkpoint_code=v_cp) IS DISTINCT FROM v_title_old
      OR (SELECT COUNT(*) FROM programacion.engineering_work_updates u
        WHERE u.work_item_id=v_work_item_id) IS DISTINCT FROM v_old_write_updates
  THEN RAISE EXCEPTION 'PE10_C3_TEST_ROLLBACK_NOT_CLEAN'; END IF;

  -- Durable replay of the SAME tested terminal transition.
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta_new
   WHERE plan_code=v_plan AND unit_code=v_unit AND unit_metadata=v_meta_old;
  IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C3_FINAL_METADATA_CAS_FAILED'; END IF;
  UPDATE programacion.engineering_work_checkpoints SET title='Independent evaluation reconciled; cutover not admitted'
   WHERE work_item_id=v_work_item_id AND checkpoint_code=v_cp;
  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_event_ref,v_actor,
    'Assessment completed and reconciled: NOT_ADMITTED; no independent PASS; C5 cutover admission still required.'
  );
  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
    OR (SELECT COUNT(*) FROM programacion.engineering_work_checkpoints c
        WHERE c.work_item_id=v_work_item_id AND c.checkpoint_code=v_cp AND c.status='DONE'
          AND c.evidence_ref=v_event_ref)<>1
  THEN RAISE EXCEPTION 'PE10_C3_FINAL_READBACK_FAILED:%',v_transition; END IF;

  IF (SELECT unit_metadata#>>'{pe10_c3_terminal_disposition_v1,resolution}'
      FROM programacion.engineering_plan_units u WHERE u.plan_code=v_plan AND u.unit_code=v_unit)
       IS DISTINCT FROM 'C3_EVALUATION_RECONCILED_NOT_ADMITTED'
     OR (SELECT status FROM programacion.engineering_work_checkpoints c
       WHERE c.work_item_id=v_work_item_id AND c.checkpoint_code='PE10_C4') IS DISTINCT FROM 'PENDING'
     OR (SELECT count(*) FROM public.lf_eventos WHERE evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
         AND entidad_codigo='ACTUALIZACION_PERFIL_LF')<>0
     OR (SELECT COUNT(*) FROM public.lf_operation_registry
         WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1')<>1
     OR (SELECT COUNT(*) FROM public.lf_operation_execution
         WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>22
  THEN RAISE EXCEPTION 'PE10_C3_FINAL_CUTOVER_OR_C4_INVARIANT_FAILED'; END IF;
END
$pe10_c3$;
COMMIT;
