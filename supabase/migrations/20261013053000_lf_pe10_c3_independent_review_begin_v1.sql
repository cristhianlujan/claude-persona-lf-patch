-- PE10_C3: issue canonical dispatch and begin existing INDEPENDENT_ASSURANCE review.
-- No review verdict, no simulated independent judge, no profile runtime activation.
BEGIN;
DO $pe$
DECLARE
 v_w bigint; v_meta jsonb; v_pack jsonb; v_request jsonb; v_gov jsonb;
 v_receipt private.lf_evidence_ledger_v1%rowtype;
 v_orch text; v_producer text; v_plan_digest text;
 v_review_id text; v_review_sha text; v_cap_sha text;
 v_manifest jsonb; v_res jsonb; v_dispatch jsonb; v_begin jsonb;
 v_scope jsonb; v_orch_op public.lf_operation_execution%rowtype;
 v_subject_type constant text:='PROFILE_EVOLUTION_CUTOVER';
 v_subject_ref constant text:='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10';
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT v_w,v_meta
 FROM programacion.engineering_plan_units
 WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10'
 FOR UPDATE;
 v_pack:=v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C3}';
 v_request:=v_pack->'review_request';
 IF (select status from programacion.engineering_work_checkpoints where work_item_id=v_w and checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
  OR v_request->>'producer_receipt_state' IS DISTINCT FROM 'VERIFIED_PROVIDER_BOUND_SUBJECT'
  OR v_request->>'dispatch_receipt_state' IS DISTINCT FROM 'MISSING_EXACT_ORCHESTRATOR_DISPATCH'
  OR v_request->>'review_result_state' IS DISTINCT FROM 'NOT_STARTED'
  OR v_request#>>'{subject,subject_type}' IS DISTINCT FROM v_subject_type
  OR v_request#>>'{subject,subject_ref}' IS DISTINCT FROM v_subject_ref
  OR v_meta#>>'{phase_separation_v1,independent_cutover_assurance,owner}' IS DISTINCT FROM 'SUPER_ADMIN'
 THEN RAISE EXCEPTION 'PE10_C3_INDEP_BEGIN_PRESTATE_DRIFT'; END IF;

 SELECT * INTO STRICT v_receipt FROM private.lf_evidence_ledger_v1
 WHERE receipt_id=(v_request->>'subject_receipt_id')::uuid;
 IF v_receipt.capability_code IS DISTINCT FROM 'EVIDENCE_LEDGER'
  OR v_receipt.receipt_kind IS DISTINCT FROM 'SOURCE_SNAPSHOT'
  OR v_receipt.verification_state IS DISTINCT FROM 'VERIFIED'
  OR v_receipt.subject_type IS DISTINCT FROM v_subject_type
  OR v_receipt.subject_ref IS DISTINCT FROM v_subject_ref
  OR v_receipt.subject_sha256 IS DISTINCT FROM v_request->>'subject_sha256'
  OR v_receipt.source_head_sha IS DISTINCT FROM v_request->>'source_head_sha'
  OR v_receipt.receipt_sha256 !~ '^[a-f0-9]{64}$'
  OR v_receipt.verification_payload->'provider_readback_verified' IS DISTINCT FROM 'true'::jsonb
  OR v_receipt.verification_payload->'digest_recomputed' IS DISTINCT FROM 'true'::jsonb
 THEN RAISE EXCEPTION 'PE10_C3_SOURCE_RECEIPT_NOT_PROVIDER_BOUND'; END IF;

 v_orch:=v_request->>'orchestrator_execution_id';
 v_producer:=v_request->>'source_producer_execution_id';
 v_plan_digest:=v_request->>'source_plan_digest';
 IF coalesce(v_plan_digest,'') !~ '^[a-f0-9]{64}$'
  OR v_producer IS DISTINCT FROM v_receipt.execution_id
  OR v_producer=v_orch
 THEN RAISE EXCEPTION 'PE10_C3_SOURCE_EXECUTION_IDENTITY_INVALID'; END IF;
 SELECT * INTO STRICT v_orch_op FROM public.lf_operation_execution WHERE execution_id=v_orch;
 IF v_orch_op.status IS DISTINCT FROM 'IN_PROGRESS'
   OR v_orch_op.operation_code IS DISTINCT FROM 'ORQUESTACION_PIPELINE_LF'
 THEN RAISE EXCEPTION 'PE10_C3_ORCHESTRATOR_NOT_ACTIVE'; END IF;

 SELECT c.manifest_sha256 INTO STRICT v_cap_sha
 FROM public.lf_capability_current c
 JOIN public.lf_capability_registry r USING(capability_code)
 JOIN public.lf_capability_version_registry v
   ON v.capability_code=c.capability_code AND v.version=c.version
 WHERE c.capability_code='INDEPENDENT_ASSURANCE'
 AND r.status='ACTIVE' AND r.owner_scope='SUPER_ADMIN'
 AND v.manifest#>>'{contract,subject_contract,mode}'='CONTRACT_DRIVEN_ANY_SUBJECT'
 AND v.manifest#>>'{contract,subject_contract,subject_type_whitelist}'='false';
 IF v_cap_sha !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'PE10_C3_INDEP_CAPABILITY_CURRENT_INVALID'; END IF;

 v_review_id:='EXEC-PE10C3-INDEP-'||substr(encode(extensions.digest(
  convert_to(jsonb_build_object('subject_sha',v_receipt.subject_sha256,
    'plan_digest',v_plan_digest,'cap_manifest',v_cap_sha)::text,'UTF8'),'sha256'),'hex'),1,16);

 v_manifest:=jsonb_build_object(
    'schema','PE10_C3_INDEPENDENT_REVIEW_V1',
    'orchestrator_execution_id',v_orch,
    'plan_digest',v_plan_digest,
    'capability_code','INDEPENDENT_ASSURANCE',
    'capability_manifest_sha256',v_cap_sha,
    'subject_type',v_subject_type,'subject_ref',v_subject_ref,
    'subject_sha256',v_receipt.subject_sha256,'source_head_sha',v_receipt.source_head_sha,
    'subject_receipt_id',v_receipt.receipt_id::text,
    'producer_execution_id',v_producer,
    'reviewer_execution_id',v_review_id,
    'review_required',true,
    'required_dimensions',jsonb_build_array('dependency','data','author'),
    'runtime_activation',false,'production_activation',false,
    'business_effect_allowed',false);
 v_review_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
 v_res:=public.fn_lf_operation_reserve_execution_v1(
   v_review_id,'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
   v_subject_type,v_subject_ref,
   'pe10c3:review:'||v_review_sha,v_review_sha,v_orch,null,null,v_manifest);
 IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS'
   OR v_res->>'execution_id' IS DISTINCT FROM v_review_id
 THEN RAISE EXCEPTION 'PE10_C3_INDEP_REVIEW_RESERVATION_REJECTED:%',v_res; END IF;

 v_scope:=jsonb_build_object(
   'schema','PE10_C3_REVIEW_DISPATCH_V1',
   'subject_type',v_subject_type,'subject_ref',v_subject_ref,
   'subject_sha256',v_receipt.subject_sha256,
   'source_head_sha',v_receipt.source_head_sha,
   'subject_receipt_id',v_receipt.receipt_id::text,
   'producer_execution_id',v_producer,
   'reviewer_execution_id',v_review_id,
   'authority_role','SUPER_ADMIN','operational_cutover_allowed',false);
 v_dispatch:=public.fn_lf_orchestrator_dispatch_receipt_v1(
  v_orch,v_review_id,'INDEPENDENT_ASSURANCE',v_plan_digest,v_scope,v_orch);
 IF NOT coalesce((v_dispatch->>'ready')::boolean,false)
 THEN RAISE EXCEPTION 'PE10_C3_INDEPENDENT_DISPATCH_REJECTED:%',v_dispatch; END IF;

 v_begin:=public.lf_independent_review_begin_v3(
  v_review_id,v_subject_type,v_subject_ref,
  v_receipt.subject_sha256,v_receipt.source_head_sha,v_receipt.receipt_id,
  v_producer,v_cap_sha,v_plan_digest,(v_dispatch->>'receipt_id')::uuid,
  v_review_sha,'pe10c3:review:'||v_review_sha,v_orch,v_manifest);
 IF v_begin->>'status' IS DISTINCT FROM 'IN_PROGRESS'
   OR v_begin->>'next_step' IS DISTINCT FROM 'route_bind'
   OR NOT coalesce((v_begin#>>'{capability_binding_receipt,ready}')::boolean,false)
 THEN RAISE EXCEPTION 'PE10_C3_INDEPENDENT_REVIEW_NOT_INITIALIZED:%',v_begin; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_capability_binding b
  JOIN public.lf_capability_current c ON c.capability_code=b.capability_code
  WHERE b.execution_id=v_review_id AND b.capability_code='INDEPENDENT_ASSURANCE'
   AND b.binding_state='BOUND' AND b.bound_manifest_sha256=c.manifest_sha256
   AND b.bound_version=c.version)
 THEN RAISE EXCEPTION 'PE10_C3_INDEP_BINDING_READBACK_FAILED'; END IF;

 v_request:=v_request || jsonb_build_object(
  'dispatch_receipt_state','ISSUED_EXACT_ORCHESTRATOR_DISPATCH',
  'review_dispatch_receipt_id',v_dispatch->>'receipt_id',
  'review_execution_id',v_review_id,
  'review_result_state','IN_PROGRESS',
  'review_next_step','route_bind',
  'capability_manifest_sha256',v_cap_sha);
 v_pack:=jsonb_set(v_pack,'{review_request}',v_request,false);
 v_meta:=jsonb_set(v_meta,'{source_pack_v2,checkpoint_inputs,PE10_C3}',v_pack,false);
 v_gov:=v_meta#>'{phase_separation_v1,independent_cutover_assurance}' ||
   jsonb_build_object('review_request_state','INDEPENDENT_REVIEW_IN_PROGRESS',
    'reviewer_execution_id',v_review_id,
    'review_dispatch_receipt_id',v_dispatch->>'receipt_id',
    'receipt_status','MISSING_REAL_INDEPENDENT_REVIEW',
    'operational_cutover_allowed',false);
 v_meta:=jsonb_set(v_meta,'{phase_separation_v1,independent_cutover_assurance}',v_gov,false);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta
 WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10';
 IF (select status from programacion.engineering_work_checkpoints where work_item_id=v_w and checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
 THEN RAISE EXCEPTION 'PE10_C3_UNAUTHORIZED_CHECKPOINT_CLOSE'; END IF;
END $pe$;
COMMIT;
