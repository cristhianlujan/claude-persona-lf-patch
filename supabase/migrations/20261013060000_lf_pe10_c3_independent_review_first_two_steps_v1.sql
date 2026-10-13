-- PE10_C3: execute only deterministic first two steps of the existing governed review.
-- The independent semantic verdict is NOT produced here. No cutover or self-judged PASS.
BEGIN;
DO $pe$
DECLARE
 v_w bigint; v_meta jsonb; v_pack jsonb; v_req jsonb; v_gov jsonb;
 v_review text; v_receipt uuid; v_dispatch uuid;
 v_subject_sha text; v_source_head text;
 v_operation public.lf_operation_execution%rowtype;
 v_bind public.lf_capability_binding%rowtype;
 v_step1 jsonb; v_step2 jsonb;
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT v_w,v_meta
 FROM programacion.engineering_plan_units
 WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
 AND unit_code='PE10' FOR UPDATE;
 v_pack:=v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C3}';
 v_req:=v_pack->'review_request';
 v_review:=v_req->>'review_execution_id';
 v_receipt:=(v_req->>'subject_receipt_id')::uuid;
 v_dispatch:=(v_req->>'review_dispatch_receipt_id')::uuid;
 v_subject_sha:=v_req->>'subject_sha256';
 v_source_head:=v_req->>'source_head_sha';
 IF (select status from programacion.engineering_work_checkpoints where work_item_id=v_w and checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
 OR v_req->>'review_result_state' IS DISTINCT FROM 'IN_PROGRESS'
 OR v_req->>'review_next_step' IS DISTINCT FROM 'route_bind'
 OR v_req->>'dispatch_receipt_state' IS DISTINCT FROM 'ISSUED_EXACT_ORCHESTRATOR_DISPATCH'
 OR v_meta#>>'{phase_separation_v1,independent_cutover_assurance,owner}' IS DISTINCT FROM 'SUPER_ADMIN'
 THEN RAISE EXCEPTION 'PE10_C3_REVIEW_STEP_PRESTATE_DRIFT'; END IF;

 SELECT * INTO STRICT v_operation
 FROM public.lf_operation_execution WHERE execution_id=v_review FOR UPDATE;
 IF v_operation.operation_code IS DISTINCT FROM 'REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
 OR v_operation.status IS DISTINCT FROM 'IN_PROGRESS'
 OR v_operation.target_type IS DISTINCT FROM 'PROFILE_EVOLUTION_CUTOVER'
 OR v_operation.target_code IS DISTINCT FROM 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
 OR v_operation.manifest->>'subject_sha256' IS DISTINCT FROM v_subject_sha
 OR v_operation.manifest->>'source_head_sha' IS DISTINCT FROM v_source_head
 OR v_operation.manifest->>'subject_receipt_id' IS DISTINCT FROM v_receipt::text
 THEN RAISE EXCEPTION 'PE10_C3_REVIEW_IDENTITY_NOT_CURRENT'; END IF;
 IF NOT EXISTS(select 1 from private.lf_orchestrator_dispatch_receipts_v1
   where receipt_id=v_dispatch and consumer_execution_id=v_review
   and capability_code='INDEPENDENT_ASSURANCE')
 OR NOT EXISTS(select 1 from private.lf_evidence_ledger_v1
   where receipt_id=v_receipt and verification_state='VERIFIED'
   and subject_sha256=v_subject_sha and source_head_sha=v_source_head)
 THEN RAISE EXCEPTION 'PE10_C3_REVIEW_DISPATCH_OR_SOURCE_NOT_VERIFIED'; END IF;
 SELECT * INTO STRICT v_bind FROM public.lf_capability_binding
 WHERE execution_id=v_review AND capability_code='INDEPENDENT_ASSURANCE';
 IF v_bind.binding_state IS DISTINCT FROM 'BOUND'
 OR NOT EXISTS(select 1 from public.lf_capability_current
  where capability_code='INDEPENDENT_ASSURANCE'
  and manifest_sha256=v_bind.bound_manifest_sha256
  and version=v_bind.bound_version)
 THEN RAISE EXCEPTION 'PE10_C3_REVIEW_BINDING_NOT_CURRENT'; END IF;

 v_step1:=public.lf_record_independent_review_step_v3(
   v_review,'route_bind',
   'supabase://public/lf_capability_binding/'||v_review||'/INDEPENDENT_ASSURANCE',
   jsonb_build_object('source','CURRENT_CAPABILITY_BINDING','verified_source_receipt_id',v_receipt::text),
   v_review,null);
 IF v_step1->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
   OR v_step1->>'status' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'PE10_C3_ROUTE_BIND_NOT_CLEAN:%',v_step1; END IF;

 v_step2:=public.lf_record_independent_review_step_v3(
   v_review,'target_currentness',
   'supabase://private/lf_evidence_ledger_v1/'||v_receipt::text,
   jsonb_build_object('source','VERIFIED_PROVIDER_BOUND_SNAPSHOT',
    'subject_sha256',v_subject_sha,'source_head_sha',v_source_head),
   v_review,null);
 IF v_step2->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
   OR v_step2->>'status' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'PE10_C3_SUBJECT_CURRENTNESS_NOT_CLEAN:%',v_step2; END IF;

 IF (SELECT count(*) FROM public.lf_operation_execution_steps s
    WHERE s.execution_id=v_review
    AND s.step_id IN ('route_bind','target_currentness')
    AND s.status='STEP_PASS_WITH_EVIDENCE')<>2
 OR (SELECT count(*) FROM public.lf_operation_execution_steps s
    WHERE s.execution_id=v_review AND s.step_id='semantic_review')<>0
 THEN RAISE EXCEPTION 'PE10_C3_REVIEW_DETERMINISTIC_READBACK_FAILED'; END IF;

 v_req:=v_req||jsonb_build_object(
   'review_next_step','semantic_review','review_result_state','IN_PROGRESS',
   'deterministic_steps_passed',jsonb_build_array('route_bind','target_currentness'),
   'semantic_independent_verdict','NOT_STARTED');
 v_pack:=jsonb_set(v_pack,'{review_request}',v_req,false);
 v_meta:=jsonb_set(v_meta,'{source_pack_v2,checkpoint_inputs,PE10_C3}',v_pack,false);
 v_gov:=v_meta#>'{phase_separation_v1,independent_cutover_assurance}' ||
   jsonb_build_object('review_request_state','INDEPENDENT_REVIEW_AWAITING_SEMANTIC_VERDICT',
     'receipt_status','MISSING_REAL_INDEPENDENT_REVIEW',
     'operational_cutover_allowed',false);
 v_meta:=jsonb_set(v_meta,'{phase_separation_v1,independent_cutover_assurance}',v_gov,false);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta
 WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10';
 IF (select status from programacion.engineering_work_checkpoints where work_item_id=v_w and checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
 THEN RAISE EXCEPTION 'PE10_C3_INDEPENDENT_VERDICT_FABRICATED'; END IF;
END $pe$;
COMMIT;
