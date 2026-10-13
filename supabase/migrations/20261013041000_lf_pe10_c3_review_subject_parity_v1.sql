-- PE10_C3: align reviewer subject identity, assertion, and consumer governance.
-- Source-first review preparation ONLY. Does not emit audit verdict or authorize cutover.
BEGIN;
DO $fix$
DECLARE
 v_meta jsonb;
 v_w bigint;
 v_spec jsonb;
 v_input jsonb;
 v_pass jsonb;
 v_subject jsonb;
 v_gov jsonb;
 v_packet jsonb;
BEGIN
 SELECT unit_metadata,work_item_id INTO STRICT v_meta,v_w
 FROM programacion.engineering_plan_units
 WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
   AND unit_code='PE10' FOR UPDATE;

 IF (SELECT status FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_w AND checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
 OR v_meta#>>'{action_specs_v1,PE10_C3,subject_adapter,schema}'
     IS DISTINCT FROM 'PE10_C3_INDEPENDENT_ASSURANCE_CONSUMER_V1'
 OR v_meta#>>'{phase_separation_v1,independent_cutover_assurance,receipt_status}'
     IS DISTINCT FROM 'MISSING_REAL_INDEPENDENT_REVIEW'
 OR jsonb_typeof(v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C3}') IS DISTINCT FROM 'object'
 OR v_meta#>>'{action_specs_v1,PE10_C3,assertion_contract,pass_when,subject_type}' IS DISTINCT FROM 'OPERATION'
 THEN RAISE EXCEPTION 'PE10_C3_REVIEW_SUBJECT_PRESTATE_DRIFT'; END IF;

 v_spec:=v_meta#>'{action_specs_v1,PE10_C3}';
 v_input:=v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C3}';
 v_subject:=jsonb_build_object(
   'subject_type','PROFILE_EVOLUTION_CUTOVER',
   'subject_ref','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10',
   'capability_code','INDEPENDENT_ASSURANCE',
   'evidence_ledger','private.lf_evidence_ledger_v1',
   'review_operation','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
   'review_entrypoint','public.lf_independent_review_begin_v3',
   'digest_rule','SHA256_JSONB_FROZEN_C1_C2_C2B_PE10E_C4_ACTIVE_POLICY',
   'required_dimensions',jsonb_build_array('dependency','data','author'));

 v_pass:=jsonb_build_object(
   'schema','PE10_C3_INDEPENDENT_REVIEW_ASSERTION_V1',
   'assurance','PASS',
   'verdict','PASS',
   'independent',true,
   'independence_measure_state','INDEPENDENT',
   'subject_type','PROFILE_EVOLUTION_CUTOVER',
   'subject_ref','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10',
   'capability_code','INDEPENDENT_ASSURANCE',
   'verification_state','VERIFIED',
   'current_capability_bound',true,
   'provenance_attested',true,
   'critical_regressions',0,
   'operational_cutover_allowed',false);

 v_spec:=jsonb_set(v_spec,'{assertion_contract}',
    jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET','pass_when',v_pass),false);
 v_spec:=v_spec || jsonb_build_object(
    'review_subject_contract',v_subject,
    'missing_receipt_action','PREPARE_VERIFIED_SUBJECT_RECEIPT_AND_ORCHESTRATOR_DISPATCH_THEN_EXECUTE_EXISTING_INDEPENDENT_REVIEW',
    'admission_receipt_rule','ONLY_EXACT_CURRENT_INDEPENDENT_AUDIT_VERDICT_MAY_SATISFY_ASSERTION');

 v_input:=v_input || jsonb_build_object(
   'review_request',jsonb_build_object(
      'schema','PE10_C3_REVIEW_REQUEST_V1',
      'subject',v_subject,
      'authority_operation_code','ACTUALIZACION_PERFIL_LF',
      'authority_role','SUPER_ADMIN',
      'producer_receipt_state','MISSING_VERIFIED_PROVIDER_BOUND_SUBJECT',
      'dispatch_receipt_state','MISSING_EXACT_ORCHESTRATOR_DISPATCH',
      'review_result_state','NOT_STARTED',
      'reviewer_must_differ_from_producer',true,
      'no_existing_pilot_as_independent_verdict',true,
      'cutover_activated',false));

 v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
   'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10','PE10_C3',v_spec,v_input);
 IF v_packet->>'status' IS DISTINCT FROM 'READY'
 OR v_spec#>>'{assertion_contract,pass_when,subject_type}' IS DISTINCT FROM
      v_spec#>>'{subject_adapter,subject_type}'
 OR v_spec#>>'{assertion_contract,pass_when,subject_ref}' IS DISTINCT FROM
      v_spec#>>'{subject_adapter,subject_ref}'
 THEN RAISE EXCEPTION 'PE10_C3_SUBJECT_CONTRACT_PARITY_FAILURE'; END IF;

 v_meta:=jsonb_set(v_meta,'{action_specs_v1,PE10_C3}',v_spec,false);
 v_meta:=jsonb_set(v_meta,'{source_pack_v2,checkpoint_inputs,PE10_C3}',v_input,false);
 v_gov:=v_meta#>'{phase_separation_v1,independent_cutover_assurance}' ||
     jsonb_build_object(
       'authority_operation_code','ACTUALIZACION_PERFIL_LF',
       'review_subject',v_subject,
       'review_request_state','PREPARED_AWAITING_VERIFIED_SUBJECT_AND_DISPATCH',
       'operational_cutover_allowed',false);
 v_meta:=jsonb_set(v_meta,
     '{phase_separation_v1,independent_cutover_assurance}',v_gov,false);

 UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta
 WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
  AND unit_code='PE10';

 IF (SELECT status FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_w AND checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
 THEN RAISE EXCEPTION 'PE10_C3_STATUS_MUTATED_UNEXPECTEDLY'; END IF;
END $fix$;

INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT 'LF-PE10-C3-ASSERTION-SUBJECT-MISMATCH-20261012-001','PROFILE_EVOLUTION',
 'PE10 C3 reviewer subject differs from assertion contract',
 'The source-bound Independent Assurance adapter requested PROFILE_EVOLUTION_CUTOVER while assertion_contract expected OPERATION, making legitimate review nonadmissible.',
 'Consumer adapter and checkpoint assertion were evolved separately and left with different subject identities.',
 'Independent verdict cannot satisfy mismatched subject contracts even if provenance is verified.',
 'Update PE10_C3 action assertion and governance in the same migration to share the exact subject_ref/type; distinguish policy authority OPERATION from review subject.',
 'Check identical reviewer subject in action, assertion and governance; execution packet READY; checkpoint IN_PROGRESS and cutover disabled absent real provider-bound subject and dispatch receipts.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C3','ACTIVO',
 'supabase://programacion.engineering_plan_units/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
WHERE NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge
 WHERE codigo='LF-PE10-C3-ASSERTION-SUBJECT-MISMATCH-20261012-001');
COMMIT;
