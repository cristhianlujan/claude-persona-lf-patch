-- PE10 C3 canonical v3 consumer contract repair only. No semantic verdict forged.
BEGIN;
DO $fix$
DECLARE
  v_w bigint; v_meta jsonb; v_spec jsonb; v_pack jsonb; v_packet jsonb;
  v_query text:=$verify$with frozen as (
  select encode(extensions.digest(convert_to(
    jsonb_build_object(
      'plan','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1',
      'unit','PE10',
      'c1',(select assertion_receipt_sha256 from programacion.engineering_work_checkpoints
            where work_item_id=(select work_item_id from programacion.engineering_plan_units where plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' and unit_code='PE10') and checkpoint_code='PE10_C1'),
      'c2',(select assertion_receipt_sha256 from programacion.engineering_work_checkpoints
            where work_item_id=(select work_item_id from programacion.engineering_plan_units where plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' and unit_code='PE10') and checkpoint_code='PE10_C2'),
      'c2b',(select assertion_receipt_sha256 from programacion.engineering_work_checkpoints
            where work_item_id=(select work_item_id from programacion.engineering_plan_units where plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' and unit_code='PE10') and checkpoint_code='PE10_C2B'),
      'first_evolution',(select c.assertion_receipt_sha256
            from programacion.engineering_work_checkpoints c
            join programacion.engineering_plan_units u on u.work_item_id=c.work_item_id
            where u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
              and u.unit_code='PE10E' and c.checkpoint_code='PE10E_C4'),
      'active_policy',(select policy_sha from public.lf_policy_versions
             where policy_code='POL-PROFILE-UPDATE-PASS' and status='ACTIVE')
    )::text,'UTF8'),'sha256'),'hex') digest
), receipts as (
  select e.receipt_id,e.execution_id
  from private.lf_evidence_ledger_v1 e
  join public.lf_operation_execution op on op.execution_id=e.execution_id
    and op.operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' and op.status='COMPLETED'
  join public.lf_capability_binding cb on cb.execution_id=e.execution_id
    and cb.capability_code='INDEPENDENT_ASSURANCE' and cb.binding_state='BOUND'
  join public.lf_capability_current cur on cur.capability_code=cb.capability_code
    and cb.bound_version=cur.version and cb.bound_manifest_sha256=cur.manifest_sha256
 join private.lf_evidence_ledger_v1 src on src.receipt_id=(op.manifest->>'subject_receipt_id')::uuid
    and src.capability_code='EVIDENCE_LEDGER' and src.receipt_kind='SOURCE_SNAPSHOT'
    and src.verification_state='VERIFIED' and src.execution_id=op.manifest->>'producer_execution_id'
    and src.subject_sha256=e.subject_sha256 and src.source_head_sha=e.source_head_sha
  join private.lf_evidence_ledger_v1 dec on dec.receipt_id=(e.receipt_payload->>'review_record_receipt_id')::uuid
    and dec.capability_code='INDEPENDENT_ASSURANCE' and dec.receipt_kind='REVIEW_DECISION'
    and dec.verification_state='VERIFIED' and dec.execution_id=e.execution_id
  join private.lf_orchestrator_dispatch_receipts_v1 disp on disp.consumer_execution_id=e.execution_id
    and disp.capability_code='INDEPENDENT_ASSURANCE' and disp.plan_digest=op.manifest->>'plan_digest'
  join public.lf_operation_execution_steps sem on sem.execution_id=e.execution_id
    and sem.step_id='semantic_review' and sem.status='STEP_PASS_WITH_EVIDENCE'
  cross join frozen f
  where e.capability_code='INDEPENDENT_ASSURANCE' and e.receipt_kind='INDEPENDENT_REVIEW_RECEIPT'
    and e.verification_state='VERIFIED'
    and e.subject_type='PROFILE_EVOLUTION_CUTOVER'
    and e.subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
    and e.subject_sha256=f.digest
    and e.receipt_payload->>'verdict'='PASS'
    and op.manifest->>'producer_execution_id'<>e.execution_id
    and dec.receipt_payload->>'verdict'='PASS'
    and sem.evidence_payload->>'verdict'='PASS'
    and sem.evidence_payload->>'review_context'='INDEPENDENT_OPERATION_CONTEXT'
    and sem.evidence_payload->'utility_dimensions_checked' @> '["dependency","data","author"]'::jsonb
    and sem.evidence_payload#>>'{independence_measure,dependency_dimension,state}'='INDEPENDENT'
    and sem.evidence_payload#>>'{independence_measure,data_dimension,state}'='INDEPENDENT'
    and sem.evidence_payload#>>'{independence_measure,author_dimension,state}'='INDEPENDENT'
    and (select count(*) from public.lf_operation_execution_steps es
       where es.execution_id=e.execution_id and es.status='STEP_PASS_WITH_EVIDENCE'
         and es.step_id in ('route_bind','target_currentness','semantic_review',
                           'judge_record','reviewer_readback','report_output'))=6
    and sem.evidence_payload#>>'{independence_measure,state}'='INDEPENDENT'
    and e.receipt_payload->>'execution_id'=e.execution_id
    and e.receipt_payload->>'subject_sha256'=e.subject_sha256
    and e.receipt_payload->>'source_head_sha'=e.source_head_sha
    and e.receipt_sha256 is not null
)
select (select digest from frozen) as frozen_subject_digest,
 (select count(*) from receipts) as qualified_current_independent_review_receipts,
 (select count(*) from private.lf_evidence_ledger_v1
   where capability_code='INDEPENDENT_ASSURANCE' and receipt_kind='AUDIT_VERDICT'
     and verification_state='VERIFIED') as historical_verified_unscoped_receipts$verify$;
BEGIN
  SELECT work_item_id,unit_metadata INTO STRICT v_w,v_meta
  FROM programacion.engineering_plan_units
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10' FOR UPDATE;
  IF (select status from programacion.engineering_work_checkpoints
      where work_item_id=v_w and checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
    OR v_meta#>>'{action_specs_v1,PE10_C3,subject_adapter,schema}' IS DISTINCT FROM 'PE10_C3_INDEPENDENT_ASSURANCE_CONSUMER_V1'
    OR v_meta#>>'{source_pack_v2,checkpoint_inputs,PE10_C3,review_request,review_next_step}' IS DISTINCT FROM 'semantic_review'
    OR v_meta#>>'{phase_separation_v1,independent_cutover_assurance,owner}' IS DISTINCT FROM 'SUPER_ADMIN'
  THEN RAISE EXCEPTION 'PE10_C3_CANONICAL_REVIEW_RECEIPT_PRESTATE_DRIFT'; END IF;

  v_spec:=v_meta#>'{action_specs_v1,PE10_C3}';
  v_pack:=v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C3}';
  v_spec:=v_spec||jsonb_build_object(
    'verification_queries',jsonb_build_array(v_query),
    'canonical_receipt_kind','INDEPENDENT_REVIEW_RECEIPT',
    'historical_audit_verdict_not_admissible',true,
    'required_clean_review_steps',6,
    'validator_contract',jsonb_build_object(
       'required',true,'validator_code','PROFILE_EVOLUTION_BENCHMARK_ADMISSION_V1',
       'failure_code','PE10_C3_CANONICAL_INDEPENDENT_REVIEW_RECEIPT_MISSING',
       'pass_when','Completed independent review-v3 execution, exact frozen source digest, current bound capability, canonical dispatch, REVIEW_DECISION and INDEPENDENT_REVIEW_RECEIPT VERIFIED, six clean steps, explicit dependency/data/author independence and semantic PASS',
       'resolver_policy','CONSUME_EXISTING_REVIEW_V3_WITHOUT_SECOND_JUDGE'),
    'missing_receipt_action','REAL_SEPARATE_SEMANTIC_JUDGE_REQUIRED_NOT_SELF_ATTESTED');
  v_pack:=jsonb_set(v_pack,'{inputs,queries}',jsonb_build_array(v_query),false);
  v_pack:=v_pack||jsonb_build_object(
    'canonical_receipt_kind','INDEPENDENT_REVIEW_RECEIPT',
    'historical_audit_verdict_not_admissible',true,
    'no_semantic_pass_without_distinct_reviewer_evidence',true);
  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10','PE10_C3',v_spec,v_pack);
  IF v_packet->>'status' IS DISTINCT FROM 'READY'
  THEN RAISE EXCEPTION 'PE10_C3_CONSUMER_PACKET_INVALID:%',v_packet->'block_reasons'; END IF;
  v_meta:=jsonb_set(v_meta,'{action_specs_v1,PE10_C3}',v_spec,false);
  v_meta:=jsonb_set(v_meta,'{source_pack_v2,checkpoint_inputs,PE10_C3}',v_pack,false);
  v_meta:=jsonb_set(v_meta,'{phase_separation_v1,independent_cutover_assurance}',
    (v_meta#>'{phase_separation_v1,independent_cutover_assurance}')||
    jsonb_build_object('canonical_receipt_kind','INDEPENDENT_REVIEW_RECEIPT',
      'review_request_state','INDEPENDENT_REVIEW_AWAITING_SEMANTIC_VERDICT',
      'legacy_receipts_rejected',true,'operational_cutover_allowed',false),false);
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10';
END $fix$;

INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT 'LF-PE10-C3-RECEIPT-KIND-DRIFT-20261013-001','PROFILE_EVOLUTION',
 'PE10 C3 adapter consumed AUDIT_VERDICT rather than canonical review-v3 completion receipt',
 'The existing generic six-step reviewer emits a verified INDEPENDENT_REVIEW_RECEIPT and REVIEW_DECISION; previous consumer only accepted legacy AUDIT_VERDICT from other domains.',
 'Consumer contract anchored to old Gold B receipt instead of actual canonical v3 reviewer terminal receipt.',
 'Valid review-v3 could never satisfy its own consumer; historical other-domain verdicts could create confusion.',
 'Bind readback to exact v3 terminal receipt, true completed review, all six clean steps, current binding, source and dispatch, semantic verdict and all three independence dimensions; reject legacy unrelated receipts.',
 'Positive SQL syntax and frozen subject digest; negative currently 0 matching receipts and 7 historical legacy verdicts excluded. Never claim a semantic PASS before distinct reviewer execution.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C3','ACTIVO',
 'supabase://programacion.engineering_plan_units/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
WHERE NOT EXISTS(select 1 from public.lf_error_knowledge where codigo='LF-PE10-C3-RECEIPT-KIND-DRIFT-20261013-001');
COMMIT;
