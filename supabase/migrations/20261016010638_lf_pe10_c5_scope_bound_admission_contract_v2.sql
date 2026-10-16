-- PE10_C5 exact current contract repair. Scope-specific qualification, no automatic cutover.
-- Evidence is ALREADY PRODUCED; never repeat semantic campaign or mint review PASS.
-- Existing FULL_EXPERT route remains independently assured. Limited mode
-- may eventually qualify only measured decision/composition scope with a real
-- SAFE_CHANGE_ADMISSION capability receipt and explicit non-expert limitation.
-- It never implies production activation, new evaluator, or profile mutation.
-- Only action_spec + checkpoint contract + source pack + acceptance criteria + audit event.
-- ACT-0001 -> ACTUALIZACION_DB_LF -> LF Migration Merge Train.
BEGIN;
DO $pe10_c5$
DECLARE
 v_plan constant text:='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
 v_unit constant text:='PE10';
 v_actor constant text:='EXEC-PE10-C5-SCOPE-CONTRACT-20261016-V2';
 v_event_code constant text:='PE10_C5.SCOPE_BOUND_ADMISSION_CONTRACT_RECONCILED.V2';
 v_source_receipt constant uuid:='37db027e-ad58-4cbb-b4dc-01b7568f6ac2';
 v_w bigint;
 v_old jsonb;v_new jsonb;
 v_contract jsonb;v_spec jsonb;v_pack jsonb;v_scope jsonb;
 v_old_criteria jsonb;v_new_criteria jsonb;
 v_old_query text;v_query text;
 v_result record;
 v_packet jsonb;
 v_event_payload jsonb;v_event_id bigint;
BEGIN
 SELECT u.work_item_id,u.unit_metadata INTO v_w,v_old
 FROM programacion.engineering_plan_units u
 WHERE u.plan_code=v_plan AND u.unit_code=v_unit AND u.disposition='ASSIGNED'
 FOR UPDATE;
 IF v_w IS NULL THEN RAISE EXCEPTION 'PE10_C5_NO_CURRENT_UNIT'; END IF;
 SELECT w.acceptance_criteria INTO v_old_criteria FROM programacion.engineering_work_items w WHERE w.id=v_w FOR UPDATE;
 IF v_old_criteria IS NULL THEN RAISE EXCEPTION 'PE10_C5_NO_CRITERIA'; END IF;
 IF (SELECT c.status FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_w AND c.checkpoint_code='PE10_C5')<>'PENDING'
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_w AND c.checkpoint_code IN ('PE10_C3','PE10_C4') AND c.status='DONE')<>2
  OR (SELECT count(*) FROM public.lf_operation_registry r WHERE r.operation_code='ACTUALIZACION_PERFIL_LF' AND r.version='v0.1' AND r.status='PRODUCCION_CONTROLADA')<>1
  OR (SELECT count(*) FROM public.lf_operation_execution e WHERE e.operation_code='ACTUALIZACION_PERFIL_LF' AND e.status='IN_PROGRESS')<>0
  OR (SELECT count(*) FROM public.lf_operation_steps s WHERE s.operation_code='ACTUALIZACION_PERFIL_LF' AND s.step_id IN ('method_selection','evolution_decision') AND NOT s.active)<>2
  OR (SELECT count(*) FROM public.lf_policy_versions p WHERE p.policy_code='POL-PROFILE-UPDATE-PASS' AND p.policy_version='v1.4-evolved-routing-candidate' AND p.status='CANDIDATE')<>1
 THEN RAISE EXCEPTION 'PE10_C5_PRESTATE_DRIFT'; END IF;
 IF (SELECT count(*) FROM private.lf_evidence_ledger_v1 l WHERE l.receipt_id=v_source_receipt
 AND l.receipt_kind='SOURCE_SNAPSHOT' AND l.verification_state='VERIFIED'
 AND l.subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
 AND l.subject_sha256='73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a')<>1
 THEN RAISE EXCEPTION 'PE10_C5_FROZEN_SUBJECT_NOT_VERIFIED'; END IF;
 IF (SELECT c.status FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_w AND c.checkpoint_code='PE10_C3')<>'DONE'
 OR NOT EXISTS(SELECT 1 FROM public.lf_eventos e WHERE e.id=21093
 AND e.payload->>'admission_status'='NOT_ADMITTED_NO_CURRENT_PASS_RECEIPT'
 AND e.payload->>'independent_review_pass'='false')
 THEN RAISE EXCEPTION 'PE10_C5_NO_EXPERT_ASSURANCE_MUST_BE_PRESERVED'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_eventos e WHERE e.evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
  AND e.entidad_codigo='ACTUALIZACION_PERFIL_LF')
 OR EXISTS(SELECT 1 FROM public.lf_eventos e WHERE e.entidad_codigo=v_event_code)
 THEN RAISE EXCEPTION 'PE10_C5_EVIDENCE_OR_CONTRACT_ALREADY_PUBLISHED'; END IF;
 IF (SELECT count(*) FROM private.lf_event_type_contracts_v2 WHERE event_type='ARTIFACT_RECONCILED' AND active AND contract_mode='OPERATIONAL')<>1
 THEN RAISE EXCEPTION 'PE10_C5_OPERATIONAL_EVENT_AUTHORITY_MISSING'; END IF;
 v_contract:=v_old#>'{checkpoint_contracts,PE10_C5}';
 v_spec:=v_old#>'{action_specs_v1,PE10_C5}';
 v_pack:=v_old#>'{source_pack_v2,checkpoint_inputs,PE10_C5}';
 IF v_contract->>'validator_code' IS DISTINCT FROM 'PROFILE_EVOLUTION_CUTOVER_GATE_V1'
 OR v_spec#>>'{assertion_contract,pass_when,admissible_events}' IS DISTINCT FROM '1'
 OR v_spec->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
 OR v_pack->>'execution_kind' IS DISTINCT FROM 'READBACK_ONCE'
 OR v_pack#>>'{inputs,queries,0}' IS DISTINCT FROM v_spec#>>'{verification_queries,0}'
 THEN RAISE EXCEPTION 'PE10_C5_CONTRACT_OR_SOURCE_PREIMAGE_DRIFT'; END IF;
 v_old_query:=v_spec#>>'{verification_queries,0}';
 IF position('PROFILE_EVOLUTION_CUTOVER_ADMITTED' in v_old_query)=0
 OR position('independent_assurance_ref' in v_old_query)=0
 THEN RAISE EXCEPTION 'PE10_C5_OLD_ADMISSION_SEMANTICS_DRIFT'; END IF;

 v_query:=$pe10_admission_sql$
WITH source AS (
 SELECT subject_sha256 FROM private.lf_evidence_ledger_v1
 WHERE receipt_id='37db027e-ad58-4cbb-b4dc-01b7568f6ac2'::uuid
 AND receipt_kind='SOURCE_SNAPSHOT' AND verification_state='VERIFIED'
 AND subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
), benchmarks AS (
 SELECT c2.assertion_receipt_sha256 sha_c2,c2b.assertion_receipt_sha256 sha_c2b
 FROM programacion.engineering_work_checkpoints c2
 JOIN programacion.engineering_plan_units u ON u.work_item_id=c2.work_item_id
 JOIN programacion.engineering_work_checkpoints c2b ON c2b.work_item_id=c2.work_item_id
 WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND u.unit_code='PE10'
 AND c2.checkpoint_code='PE10_C2' AND c2b.checkpoint_code='PE10_C2B'
 AND c2.status='DONE' AND c2b.status='DONE'
 AND c2.assertion_receipt->>'result'='PASS' AND c2b.assertion_receipt->>'result'='PASS'
 AND c2.assertion_receipt#>>'{observed,benchmark_scope}'='DECISION_POLICY_AND_COMPOSITION'
 AND c2b.assertion_receipt#>>'{observed,benchmark_scope}'='FULL_PROFILE_EVOLUTION_BEHAVIOR'
 AND (c2.assertion_receipt#>>'{observed,case_count}')::int>=24
 AND (c2b.assertion_receipt#>>'{observed,case_count}')::int>=21
 AND (c2.assertion_receipt#>>'{observed,critical_regressions}')::int=0
 AND (c2b.assertion_receipt#>>'{observed,critical_regressions}')::int=0
 AND (c2.assertion_receipt#>>'{observed,candidate_primary_capability_score}')::numeric >
 (c2.assertion_receipt#>>'{observed,baseline_primary_capability_score}')::numeric
 AND (c2b.assertion_receipt#>>'{observed,candidate_primary_capability_score}')::numeric >
 (c2b.assertion_receipt#>>'{observed,baseline_primary_capability_score}')::numeric
 AND (c2.assertion_receipt#>>'{observed,paired_delta_ci95,0}')::numeric>0
 AND (c2b.assertion_receipt#>>'{observed,paired_delta_ci95,0}')::numeric>0
 AND c2.assertion_receipt->>'fresh_validation'='true'
 AND c2b.assertion_receipt->>'fresh_validation'='true'
), qualified AS (
 SELECT ev.id,ev.payload->>'scope_mode' scope_mode
 FROM public.lf_eventos ev CROSS JOIN source src CROSS JOIN benchmarks b
 JOIN public.lf_policy_versions policy ON policy.policy_code='POL-PROFILE-UPDATE-PASS'
 AND policy.policy_version='v1.4-evolved-routing-candidate' AND policy.status='CANDIDATE'
 WHERE ev.evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
 AND ev.entidad_tipo='OPERACION' AND ev.entidad_codigo='ACTUALIZACION_PERFIL_LF'
 AND ev.payload->>'frozen_subject_sha256'=src.subject_sha256
 AND ev.payload->>'benchmark_c2_sha256'=b.sha_c2
 AND ev.payload->>'benchmark_c2b_sha256'=b.sha_c2b
 AND ev.payload->>'candidate_policy_sha256'=policy.policy_sha
 AND EXISTS (
 SELECT 1 FROM private.lf_evidence_ledger_v1 safe
 WHERE safe.receipt_id::text=ev.payload->>'safe_change_admission_ref'
 AND safe.capability_code='SAFE_CHANGE_ADMISSION'
 AND safe.verification_state='VERIFIED'
 AND safe.subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
 AND safe.subject_sha256=src.subject_sha256
 AND safe.receipt_payload->>'execution_permission'='DOWNSTREAM_EXECUTION_ELIGIBLE'
 )
 AND (
 (ev.payload->>'scope_mode'='LIMITED_MEASURED_DECISION_COMPOSITION'
 AND ev.payload->>'status'='ADMIT_LIMITED_SCOPE'
 AND ev.payload->>'qualified_scope'='DECISION_POLICY_AND_COMPOSITION'
 AND ev.payload->>'full_expert_claimed'='false'
 AND ev.payload->>'independent_assurance'='NOT_CLAIMED'
 AND ev.payload->>'production_activation_authorized'='false')
 OR
 (ev.payload->>'scope_mode'='FULL_EXPERT'
 AND ev.payload->>'status'='ADMIT_CUTOVER'
 AND ev.payload->>'independent_assurance'='PASS'
 AND EXISTS (SELECT 1 FROM private.lf_evidence_ledger_v1 reviewer
 WHERE reviewer.receipt_id::text=ev.payload->>'independent_assurance_ref'
 AND reviewer.receipt_kind='INDEPENDENT_REVIEW_RECEIPT'
 AND reviewer.capability_code='INDEPENDENT_ASSURANCE'
 AND reviewer.verification_state='VERIFIED'
 AND reviewer.subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
 AND reviewer.subject_sha256=src.subject_sha256
 AND reviewer.receipt_payload->>'verdict'='PASS'))
 ))
SELECT CASE WHEN EXISTS(SELECT 1 FROM qualified) THEN 1 ELSE 0 END AS admissible_events,
 (SELECT count(*)::int FROM benchmarks) AS measured_benchmark_pairs,
 (SELECT count(*)::int FROM qualified WHERE scope_mode='LIMITED_MEASURED_DECISION_COMPOSITION') AS limited_scope_events,
 (SELECT count(*)::int FROM qualified WHERE scope_mode='FULL_EXPERT') AS full_expert_events
$pe10_admission_sql$;

 EXECUTE v_query INTO v_result;
 IF v_result.admissible_events<>0 OR v_result.measured_benchmark_pairs<>1
 OR v_result.limited_scope_events<>0 OR v_result.full_expert_events<>0
 THEN RAISE EXCEPTION 'PE10_C5_BASELINE_READBACK_NOT_FAIL_CLOSED'; END IF;
 -- Negative: an unanchored reference cannot pass the verified ledger gate.
 IF EXISTS (SELECT 1 FROM private.lf_evidence_ledger_v1 l
 WHERE l.receipt_id::text='00000000-0000-0000-0000-000000000000'
 AND l.verification_state='VERIFIED')
 THEN RAISE EXCEPTION 'PE10_C5_NEGATIVE_REFERENCE_TEST_FAILED'; END IF;

 v_scope:=jsonb_build_object(
 'schema','PE10_C5_SCOPE_BOUND_ADMISSION_CONTRACT_V2',
 'full_mode',jsonb_build_object(
  'code','FULL_EXPERT','independent_review_receipt_required',true,
  'required_verdict','PASS','unverified_text_refs_accepted',false),
 'limited_mode',jsonb_build_object(
  'code','LIMITED_MEASURED_DECISION_COMPOSITION',
  'certified_capability','DECISION_POLICY_AND_COMPOSITION',
  'requires_c2_and_c2b_existing_positive_receipts',true,
  'requires_verified_safe_change_admission_receipt',true,
  'requires_explicit_candidate_policy_binding',true,
  'independent_general_expert_pass_claimed',false,
  'production_activation_authorized',false,
  'case_206_correction_and_no_known_regression_required_before_deploy',true,
  'profile_learning_expertise_not_certified',true),
 'admitted_event_type','PROFILE_EVOLUTION_CUTOVER_ADMITTED',
 'event_contract_registration_separately_required',true,
 'fail_closed_when_event_type_unregistered',true,
 'preserved_c3_not_admitted_event_id',21093,
 'pre_activation_only',true,
 'original_checkpoint_contract',v_contract,
 'original_assertion',v_spec->'assertion_contract'
 );
 v_contract:=v_contract||jsonb_build_object(
 'pass_when','Exact source-backed scope-qualified admission event, verified C2/C2B and SAFE_CHANGE_ADMISSION receipt; FULL_EXPERT additionally requires VERIFIED independent review PASS; LIMITED does not claim expert or authorize production',
 'failure_code','CUTOVER_SCOPE_ADMISSION_MISSING_OR_UNVERIFIED',
 'resolver_policy','RECONCILE_EXISTING_BENCHMARK_AND_CURRENT_SAFE_CHANGE_NO_NEW_SEMANTIC_CAMPAIGN',
 'validation_input',jsonb_build_object('source','EXACT_DECLARED_READBACK',
    'queries',jsonb_build_array(v_query),'scope_modes',jsonb_build_array('LIMITED_MEASURED_DECISION_COMPOSITION','FULL_EXPERT')));
 v_spec:=v_spec||jsonb_build_object(
 'verification_queries',jsonb_build_array(v_query),
 'validator_contract',(v_spec->'validator_contract')||jsonb_build_object(
    'pass_when','Only verified evidence-bound FULL_EXPERT or LIMITED_MEASURED_DECISION_COMPOSITION admission; no textual reference-only PASS',
    'failure_code','CUTOVER_SCOPE_ADMISSION_MISSING_OR_UNVERIFIED',
    'resolver_policy','RECONCILE_EXACT_SCOPE_BOUND_EVIDENCE_NO_SYNTHETIC_PASS',
    'validation_input',jsonb_build_object('scope_contract','PE10_C5_SCOPE_BOUND_ADMISSION_CONTRACT_V2')),
 'scope_qualification_policy',jsonb_build_object(
    'mode','TWO_DISJOINT_SCOPES_NO_AUTO_ACTIVATION',
    'limited_capability','DECISION_POLICY_AND_COMPOSITION','expert_capability_requires_independent_pass',true,
    'safe_change_admission_verified_required',true,
    'source_ref_verification','LEDGER_RECEIPT_UUID_SUBJECT_SHA_AND_CURRENT_POLICY'),
 'forbidden',(v_spec->'forbidden')||jsonb_build_array('TREAT_LIMITED_AS_FULL_EXPERT','ACCEPT_UNVERIFIED_REF_TEXT','AUTO_REGISTER_ADMISSION_EVENT_TYPE','TREAT_STAGED_CANDIDATE_AS_LIVE_V02')
 );
 v_pack:=jsonb_set(v_pack,'{inputs,queries}',jsonb_build_array(v_query),false);
 v_pack:=jsonb_set(v_pack,'{inputs,db_objects}',
 jsonb_build_array('public.lf_eventos','private.lf_evidence_ledger_v1','programacion.engineering_work_checkpoints','programacion.engineering_plan_units','public.lf_policy_versions'),false);
 v_pack:=v_pack||jsonb_build_object('expected_result','FAIL_CLOSED_UNTIL_SCOPED_GATE_PROVEN');
 v_new:=jsonb_set(v_old,'{checkpoint_contracts,PE10_C5}',v_contract,false);
 v_new:=jsonb_set(v_new,'{action_specs_v1,PE10_C5}',v_spec,false);
 v_new:=jsonb_set(v_new,'{source_pack_v2,checkpoint_inputs,PE10_C5}',v_pack,false);
 v_new:=jsonb_set(v_new,'{pe10_c5_scope_qualification_contract_v2}',v_scope,true);

 SELECT jsonb_agg(CASE WHEN x.value LIKE 'PE10_C5:%'
 THEN to_jsonb('PE10_C5: exact verified C2/C2B benchmark plus scoped safe-change admission for LIMITED decision/composition (no expert claim/no activation), or independent review VERIFIED PASS for FULL_EXPERT. Only source-backed receipt-bound event passes; no synthesis from text refs.'::text)
 ELSE to_jsonb(x.value) END ORDER BY x.ordinality)
 INTO v_new_criteria
 FROM jsonb_array_elements_text(v_old_criteria) WITH ORDINALITY x(value,ordinality);
 IF v_new_criteria IS NULL
 OR v_new#>'{checkpoint_contracts,PE10_C3}' IS DISTINCT FROM v_old#>'{checkpoint_contracts,PE10_C3}'
 OR v_new#>'{checkpoint_contracts,PE10_C4}' IS DISTINCT FROM v_old#>'{checkpoint_contracts,PE10_C4}'
 OR v_new#>'{checkpoint_contracts,PE10_C6}' IS DISTINCT FROM v_old#>'{checkpoint_contracts,PE10_C6}'
 OR v_new#>'{checkpoint_contracts,PE10_C7}' IS DISTINCT FROM v_old#>'{checkpoint_contracts,PE10_C7}'
 OR v_new#>'{action_specs_v1,PE10_C6}' IS DISTINCT FROM v_old#>'{action_specs_v1,PE10_C6}'
 OR v_new#>'{action_specs_v1,PE10_C7}' IS DISTINCT FROM v_old#>'{action_specs_v1,PE10_C7}'
 THEN RAISE EXCEPTION 'PE10_C5_CROSS_CHECKPOINT_DRIFT'; END IF;
 v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
 v_plan,v_unit,'PE10_C5',v_spec,v_pack);
 IF v_packet->>'status'<>'READY' THEN
 RAISE EXCEPTION 'PE10_C5_EXECUTION_PACKET_NOT_READY:%',v_packet->'block_reasons'; END IF;
 v_event_payload:=jsonb_build_object(
 'evidence_schema_version','operational-event/v2',
 'execution_id',v_actor,'producer','PE10_C5_SCOPE_BOUND_CONTRACT_REPAIR_V2',
 'purpose','Amend scoped C5 qualification while preserving unproven independent assurance and no cutover',
 'occurred_at',clock_timestamp(),'acceptance_declared',false,
 'plan_code',v_plan,'checkpoint_code','PE10_C5',
 'original_c5_status','PENDING','resulting_c5_status','PENDING',
 'measured_benchmark_pairs',v_result.measured_benchmark_pairs,
 'admissible_events',v_result.admissible_events,
 'limited_scope_events',v_result.limited_scope_events,'full_expert_events',v_result.full_expert_events,
 'independent_assurance_pass',false,'full_expert_certified',false,
 'cutover_admitted',false,'runtime_activated',false,
 'source_snapshot_receipt',v_source_receipt::text,
 'contract_ref','programacion.engineering_plan_units/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10/pe10_c5_scope_qualification_contract_v2',
 'current_op_version','v0.1','staged_policy_version','v1.4-evolved-routing-candidate',
 'fixes','VERIFY_LEDGER_RECEIPT_INSTEAD_OF_UNVERIFIED_TEXT;DISJOINT_LIMITED_VS_FULL_QUALIFICATION');
 IF private.fn_lf_event_acceptance_signal_v2('ARTIFACT_RECONCILED',
 v_event_code,'C5 source-bound admission contract corrected, no approval',
 v_event_payload) IS NOT NULL THEN RAISE EXCEPTION 'PE10_C5_EVENT_FALSE_ACCEPTANCE_SIGNAL'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_eventos WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo=v_event_code)
 THEN RAISE EXCEPTION 'PE10_C5_CONTRACT_ALREADY_RECONCILED'; END IF;

 -- TEST: proposed metadata and event are written and deliberately rolled back.
 BEGIN
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=v_new WHERE plan_code=v_plan AND unit_code=v_unit AND unit_metadata=v_old;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C5_DRY_METADATA_CAS'; END IF;
 UPDATE programacion.engineering_work_items SET acceptance_criteria=v_new_criteria WHERE id=v_w AND acceptance_criteria=v_old_criteria;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C5_DRY_CRITERIA_CAS'; END IF;
 INSERT INTO public.lf_eventos(evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
 VALUES('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_event_code,
 'C5 source-bound admission contract corrected, no approval','INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_event_payload)
 RETURNING id INTO v_event_id;
 IF (SELECT unit_metadata#>>'{pe10_c5_scope_qualification_contract_v2,schema}' FROM programacion.engineering_plan_units WHERE work_item_id=v_w)
 IS DISTINCT FROM 'PE10_C5_SCOPE_BOUND_ADMISSION_CONTRACT_V2'
 OR (SELECT count(*) FROM public.lf_eventos WHERE entidad_codigo=v_event_code)<>1
 OR (SELECT c.status FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_w AND c.checkpoint_code='PE10_C5')<>'PENDING'
 THEN RAISE EXCEPTION 'PE10_C5_DRY_POSITIVE_READBACK_FAILED'; END IF;
 RAISE EXCEPTION 'PE10_C5_INTENTIONAL_ROLLBACK_SENTINEL';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
 IF SQLERRM<>'PE10_C5_INTENTIONAL_ROLLBACK_SENTINEL' THEN RAISE; END IF;
 END;
 IF (SELECT unit_metadata FROM programacion.engineering_plan_units WHERE work_item_id=v_w) IS DISTINCT FROM v_old
 OR (SELECT acceptance_criteria FROM programacion.engineering_work_items WHERE id=v_w) IS DISTINCT FROM v_old_criteria
 OR EXISTS (SELECT 1 FROM public.lf_eventos WHERE entidad_codigo=v_event_code)
 THEN RAISE EXCEPTION 'PE10_C5_DRY_ROLLBACK_LEFT_RESIDUES'; END IF;

 UPDATE programacion.engineering_plan_units SET unit_metadata=v_new
 WHERE plan_code=v_plan AND unit_code=v_unit AND unit_metadata=v_old;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C5_FINAL_METADATA_CAS'; END IF;
 UPDATE programacion.engineering_work_items SET acceptance_criteria=v_new_criteria WHERE id=v_w AND acceptance_criteria=v_old_criteria;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C5_FINAL_CRITERIA_CAS'; END IF;
 INSERT INTO public.lf_eventos(evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
 VALUES('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_event_code,
 'C5 source-bound admission contract corrected, no approval','INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_event_payload)
 RETURNING id INTO v_event_id;
 EXECUTE v_query INTO v_result;
 IF v_result.admissible_events<>0 OR v_result.measured_benchmark_pairs<>1
 OR (SELECT count(*) FROM public.lf_eventos WHERE id=v_event_id AND evento_tipo='ARTIFACT_RECONCILED'
 AND payload->>'cutover_admitted'='false' AND payload->>'limited_scope_events'='0')<>1
 OR (SELECT c.status FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_w AND c.checkpoint_code='PE10_C5')<>'PENDING'
 OR (SELECT count(*) FROM public.lf_operation_registry WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1')<>1
 OR (SELECT count(*) FROM public.lf_operation_registry WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.2')<>0
 THEN RAISE EXCEPTION 'PE10_C5_FINAL_READBACK_FAILED'; END IF;
END $pe10_c5$;
COMMIT;