-- Freeze and verify PE10_C3 real SOURCE V2 evidence using existing LF EVIDENCE_LEDGER.
-- This creates NO assurance verdict and authorizes NO runtime activation.
BEGIN;
DO $pe$
DECLARE
 v_w bigint;
 v_meta jsonb; v_pack jsonb; v_request jsonb;
 v_source jsonb; v_verify jsonb;
 v_subject_sha text; v_head constant text:='578e15f654dfccaba8c094c5f33121df8f44f216';
 v_plan_digest text; v_orch text; v_producer text; v_ledger text;
 v_orch_manifest jsonb; v_ledger_manifest jsonb;
 v_res jsonb; v_dispatch jsonb; v_bind jsonb; v_anchor jsonb;
 v_subject_type constant text:='PROFILE_EVOLUTION_CUTOVER';
 v_subject_ref constant text:='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10';
 v_cap_sha text; v_source_receipt_id uuid;
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT v_w,v_meta
 FROM programacion.engineering_plan_units
 WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10' FOR UPDATE;
 IF (select status from programacion.engineering_work_checkpoints where work_item_id=v_w and checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
 OR v_meta#>>'{source_pack_v2,checkpoint_inputs,PE10_C3,review_request,review_result_state}' IS DISTINCT FROM 'NOT_STARTED'
 OR v_meta#>>'{phase_separation_v1,independent_cutover_assurance,owner}' IS DISTINCT FROM 'SUPER_ADMIN'
 OR v_meta#>>'{action_specs_v1,PE10_C3,subject_adapter,subject_type}' IS DISTINCT FROM v_subject_type
 THEN RAISE EXCEPTION 'PE10_C3_SOURCE_PRESTATE_DRIFT'; END IF;

 SELECT jsonb_build_object(
 'plan','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','unit','PE10',
 'c1',(select c.assertion_receipt_sha256 from programacion.engineering_work_checkpoints c where c.work_item_id=v_w and c.checkpoint_code='PE10_C1' and c.status='DONE'),
 'c2',(select c.assertion_receipt_sha256 from programacion.engineering_work_checkpoints c where c.work_item_id=v_w and c.checkpoint_code='PE10_C2' and c.status='DONE'),
 'c2b',(select c.assertion_receipt_sha256 from programacion.engineering_work_checkpoints c where c.work_item_id=v_w and c.checkpoint_code='PE10_C2B' and c.status='DONE'),
 'first_evolution',(select c.assertion_receipt_sha256 from programacion.engineering_work_checkpoints c join programacion.engineering_plan_units u on u.work_item_id=c.work_item_id where u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' and u.unit_code='PE10E' and c.checkpoint_code='PE10E_C4' and c.status='DONE'),
 'active_policy',(select policy_sha from public.lf_policy_versions where policy_code='POL-PROFILE-UPDATE-PASS' and status='ACTIVE')
) INTO v_source;
 IF coalesce(v_source->>'c1','') !~ '^[a-f0-9]{64}$'
 OR coalesce(v_source->>'c2','') !~ '^[a-f0-9]{64}$'
 OR coalesce(v_source->>'c2b','') !~ '^[a-f0-9]{64}$'
 OR coalesce(v_source->>'first_evolution','') !~ '^[a-f0-9]{64}$'
 OR coalesce(v_source->>'active_policy','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'PE10_C3_FROZEN_AUTHORITY_HASH_INCOMPLETE'; END IF;
 v_subject_sha:=encode(extensions.digest(convert_to(v_source::text,'UTF8'),'sha256'),'hex');
 IF EXISTS(select 1 from private.lf_evidence_ledger_v1
  where subject_type=v_subject_type and subject_ref=v_subject_ref
  and receipt_kind='SOURCE_SNAPSHOT' and verification_state='VERIFIED')
 THEN RAISE EXCEPTION 'PE10_C3_SOURCE_ALREADY_ATTESTED_RECONCILE_FIRST'; END IF;

 SELECT c.manifest_sha256 INTO STRICT v_cap_sha FROM public.lf_capability_current c
 JOIN public.lf_capability_registry r USING(capability_code)
 WHERE c.capability_code='EVIDENCE_LEDGER' AND r.status='ACTIVE';
 IF v_cap_sha !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'PE10_C3_EVIDENCE_LEDGER_NOT_CURRENT'; END IF;
 v_plan_digest:=encode(extensions.digest(convert_to(jsonb_build_object(
  'schema','PE10_C3_PROVIDER_SOURCE_PLAN_V1','subject_sha',v_subject_sha,
  'source_head_sha',v_head,'capability_manifest_sha',v_cap_sha
 )::text,'UTF8'),'sha256'),'hex');
 v_orch:='EXEC-PE10C3-ORCH-'||substr(v_plan_digest,1,16);
 v_producer:='EXEC-PE10C3-PRODUCER-'||substr(v_plan_digest,1,16);
 v_ledger:='EXEC-PE10C3-LEDGER-'||substr(v_plan_digest,1,16);
 v_orch_manifest:=jsonb_build_object('schema','PE10_C3_SOURCE_ORCHESTRATOR_V1',
  'plan_digest',v_plan_digest,'subject_sha256',v_subject_sha,'source_head_sha',v_head,
  'subject_ref',v_subject_ref,'capability_code','EVIDENCE_LEDGER');
 v_res:=public.fn_lf_operation_reserve_execution_v1(
  v_orch,'ORQUESTACION_PIPELINE_LF',v_subject_type,v_subject_ref,
  'pe10c3:source:orch:'||v_plan_digest,v_plan_digest,v_orch,null,null,v_orch_manifest);
 IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS' OR v_res->>'execution_id' IS DISTINCT FROM v_orch
 THEN RAISE EXCEPTION 'PE10_C3_ORCHESTRATOR_RESERVE_FAILED:%',v_res; END IF;

 v_res:=public.fn_lf_operation_reserve_execution_v1(
  v_producer,'ORQUESTACION_PIPELINE_LF',v_subject_type,v_subject_ref,
  'pe10c3:source:producer:'||v_plan_digest,v_plan_digest,v_orch,null,null,
  jsonb_build_object('schema','PE10_C3_FROZEN_EVIDENCE_PRODUCER_V1','plan_digest',v_plan_digest,
    'orchestrator_execution_id',v_orch,'producer_execution_id',v_producer,
    'subject_sha256',v_subject_sha,'source_head_sha',v_head));
 IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS' OR v_res->>'execution_id' IS DISTINCT FROM v_producer
 THEN RAISE EXCEPTION 'PE10_C3_SOURCE_PRODUCER_RESERVE_FAILED:%',v_res; END IF;

 v_ledger_manifest:=jsonb_build_object('schema','PE10_C3_EVIDENCE_LEDGER_CONSUMER_V1',
  'capability_code','EVIDENCE_LEDGER','plan_digest',v_plan_digest,
  'orchestrator_execution_id',v_orch,'producer_execution_id',v_producer,
  'subject_sha256',v_subject_sha,'source_head_sha',v_head);
 v_res:=public.fn_lf_operation_reserve_execution_v1(
  v_ledger,'ORQUESTACION_PIPELINE_LF',v_subject_type,v_subject_ref,
  'pe10c3:source:ledger:'||v_plan_digest,v_plan_digest,v_orch,null,null,v_ledger_manifest);
 IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS' OR v_res->>'execution_id' IS DISTINCT FROM v_ledger
 THEN RAISE EXCEPTION 'PE10_C3_LEDGER_RESERVE_FAILED:%',v_res; END IF;

 v_dispatch:=public.fn_lf_orchestrator_dispatch_receipt_v1(
  v_orch,v_ledger,'EVIDENCE_LEDGER',v_plan_digest,
  jsonb_build_object('subject_type',v_subject_type,'subject_ref',v_subject_ref,
    'subject_sha256',v_subject_sha,'producer_execution_id',v_producer,
    'source_head_sha',v_head),v_orch);
 IF NOT coalesce((v_dispatch->>'ready')::boolean,false)
 THEN RAISE EXCEPTION 'PE10_C3_LEDGER_DISPATCH_FAILED:%',v_dispatch; END IF;
 v_bind:=public.fn_lf_capability_bind_from_orchestrator_v1(
  v_ledger,'EVIDENCE_LEDGER',v_cap_sha,v_plan_digest,(v_dispatch->>'receipt_id')::uuid,v_orch);
 IF NOT coalesce((v_bind->>'ready')::boolean,false)
 THEN RAISE EXCEPTION 'PE10_C3_LEDGER_BIND_FAILED:%',v_bind; END IF;

 SELECT jsonb_build_object(
 'plan','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','unit','PE10',
 'c1',(select c.assertion_receipt_sha256 from programacion.engineering_work_checkpoints c where c.work_item_id=v_w and c.checkpoint_code='PE10_C1' and c.status='DONE'),
 'c2',(select c.assertion_receipt_sha256 from programacion.engineering_work_checkpoints c where c.work_item_id=v_w and c.checkpoint_code='PE10_C2' and c.status='DONE'),
 'c2b',(select c.assertion_receipt_sha256 from programacion.engineering_work_checkpoints c where c.work_item_id=v_w and c.checkpoint_code='PE10_C2B' and c.status='DONE'),
 'first_evolution',(select c.assertion_receipt_sha256 from programacion.engineering_work_checkpoints c join programacion.engineering_plan_units u on u.work_item_id=c.work_item_id where u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' and u.unit_code='PE10E' and c.checkpoint_code='PE10E_C4' and c.status='DONE'),
 'active_policy',(select policy_sha from public.lf_policy_versions where policy_code='POL-PROFILE-UPDATE-PASS' and status='ACTIVE')
) INTO v_verify;
 IF v_verify IS DISTINCT FROM v_source
 THEN RAISE EXCEPTION 'PE10_C3_FROZEN_SOURCE_CHANGED_BETWEEN_READBACKS'; END IF;

 v_anchor:=public.fn_lf_evidence_ledger_anchor_v1(
  v_producer,'EVIDENCE_LEDGER','PE10_C3_VERIFIED_SOURCE','SOURCE_SNAPSHOT',
  v_subject_type,v_subject_ref,v_subject_sha,v_head,
  'supabase://public.lf_policy_versions/POL-PROFILE-UPDATE-PASS',
  'LF_SUPABASE_READBACK_V1','SUPABASE',
  'supabase://programacion.engineering_work_checkpoints/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10#C1-C2-C2B-PE10E-C4',
  'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST','VERIFIED',
  jsonb_build_object('provider_readback_verified',true,'digest_recomputed',true,
   'stable_double_readback',true,'source_head_pinned',true,
   'semantic_assurance_pass',false,'cutover_allowed',false),
  jsonb_build_object('schema','PE10_C3_FROZEN_SOURCE_RECEIPT_V1',
   'subject_snapshot',v_source,'subject_sha256',v_subject_sha,'source_head_sha',v_head,
   'independent_verdict','NOT_STARTED','no_statistical_expert_claim',true),
  v_ledger);
 v_source_receipt_id:=(v_anchor->>'receipt_id')::uuid;
 IF v_source_receipt_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM private.lf_evidence_ledger_v1 l
   WHERE l.receipt_id=v_source_receipt_id AND l.execution_id=v_producer
     AND l.created_by_execution_id=v_ledger
     AND l.capability_code='EVIDENCE_LEDGER' AND l.receipt_kind='SOURCE_SNAPSHOT'
     AND l.subject_type=v_subject_type AND l.subject_ref=v_subject_ref
     AND l.subject_sha256=v_subject_sha AND l.source_head_sha=v_head
     AND l.verification_state='VERIFIED')
 THEN RAISE EXCEPTION 'PE10_C3_PROVIDER_RECEIPT_READBACK_FAILED'; END IF;

 v_pack:=v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C3}';
 v_request:=v_pack->'review_request' || jsonb_build_object(
  'producer_receipt_state','VERIFIED_PROVIDER_BOUND_SUBJECT',
  'subject_receipt_id',v_source_receipt_id::text,
  'subject_sha256',v_subject_sha,'source_head_sha',v_head,
  'source_producer_execution_id',v_producer,'source_ledger_execution_id',v_ledger,
  'orchestrator_execution_id',v_orch,'source_plan_digest',v_plan_digest,
  'ledger_dispatch_receipt_id',v_dispatch->>'receipt_id',
  'review_result_state','NOT_STARTED','dispatch_receipt_state','MISSING_EXACT_ORCHESTRATOR_DISPATCH');
 v_pack:=jsonb_set(v_pack,'{review_request}',v_request,false);
 v_meta:=jsonb_set(v_meta,'{source_pack_v2,checkpoint_inputs,PE10_C3}',v_pack,false);
 v_meta:=jsonb_set(v_meta,'{phase_separation_v1,independent_cutover_assurance}',
   (v_meta#>'{phase_separation_v1,independent_cutover_assurance}') ||
    jsonb_build_object('review_request_state','SOURCE_VERIFIED_AWAITING_REVIEW_DISPATCH',
       'receipt_status','MISSING_REAL_INDEPENDENT_REVIEW',
       'operational_cutover_allowed',false),false);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta
 WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10';
END $pe$;

INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT 'LF-PE10-C3-SOURCE-UNDECLARED-VAR-20261012-001','PROFILE_EVOLUTION',
 'Train aborted source receipt because of an undeclared SQL variable',
 'The original PE10_C3 source receipt migration used v_work where the declared work_item variable was v_w; SQL rejected the nested snapshot SELECT and the whole transaction rolled back.',
 'Undeclared variable in one of the nested immutable readback queries.',
 'SQL source snapshot can be structurally complete yet fail on unresolved PLpgSQL variable binding.',
 'Read back exact migration source and verify each identifier against DECLARE; run read-only snapshot SELECT before Train; use new PR after failed apply, not retry invalid source.',
 'V2 read-only snapshot SHA256 recomputes to 73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a; final source ledger should contain VERIFIED subject receipt, original failed migration absent.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C3','ACTIVO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2375'
WHERE NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge
 WHERE codigo='LF-PE10-C3-SOURCE-UNDECLARED-VAR-20261012-001');

COMMIT;
