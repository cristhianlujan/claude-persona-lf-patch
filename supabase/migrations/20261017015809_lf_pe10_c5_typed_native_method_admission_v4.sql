-- PE10 C5: one v0.2 dynamic updater, with distinct authoring/engine evidence.
-- No method qualification bypass: remote packs still require qualification and receipts.
-- No C5/C6 closure, event-contract auto-registration, provider signature mint or activation.
-- Changes the canonic checkpoint consumer (query/criteria/source) through LF Merge Train.
BEGIN;
DO $pe10_c5_v4$
DECLARE
 v_plan constant text:='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
 v_actor constant text:='EXEC-PE10C5-TYPED-NATIVE-CONTRACT-20261017-V4';
 v_audit constant text:='PE10_C5.TYPED_NATIVE_ADMISSION_CONTRACT.V4';
 v_rollback constant text:='PE10_C5.TYPED_NATIVE_CONTRACT_TX_ROLLBACK.V4';
 v_work bigint; v_prior jsonb; v_next jsonb; v_contract jsonb;v_spec jsonb;
 v_pack jsonb;v_old_criteria jsonb;v_new_criteria jsonb;
 v_query text;v_prev_query text;v_new_packet jsonb;v_event_payload jsonb;
 v_n int;v_b int;v_event bigint;v_probe bigint;
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT v_work,v_prior
 FROM programacion.engineering_plan_units
 WHERE plan_code=v_plan AND unit_code='PE10' AND disposition='ASSIGNED' FOR UPDATE;
 SELECT acceptance_criteria INTO STRICT v_old_criteria
 FROM programacion.engineering_work_items WHERE id=v_work FOR UPDATE;
 IF (SELECT status FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_work AND checkpoint_code='PE10_C5') IS DISTINCT FROM 'PENDING'
 OR (SELECT status FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_work AND checkpoint_code='PE10_C6') IS DISTINCT FROM 'PENDING'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_work AND checkpoint_code IN ('PE10_C3','PE10_C4')
 AND status='DONE')<>2
 OR (SELECT count(*) FROM public.lf_operation_registry
 WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1'
 AND status='PRODUCCION_CONTROLADA')<>1
 OR (SELECT count(*) FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>0
 OR (SELECT count(*) FROM public.lf_policy_versions
 WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate'
 AND status='CANDIDATE')<>1
 OR (SELECT count(*) FROM private.lf_evidence_ledger_v1
 WHERE receipt_id='37db027e-ad58-4cbb-b4dc-01b7568f6ac2'::uuid
 AND subject_ref=v_plan||'/PE10'
 AND subject_sha256='73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a'
 AND receipt_kind='SOURCE_SNAPSHOT' AND verification_state='VERIFIED')<>1
 THEN RAISE EXCEPTION 'PE10_C5_V4_PRESTATE_OR_SOURCE_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_eventos
 WHERE entidad_codigo IN(v_audit,v_rollback))
 OR EXISTS(SELECT 1 FROM public.lf_eventos
 WHERE evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
 AND entidad_codigo='ACTUALIZACION_PERFIL_LF')
 THEN RAISE EXCEPTION 'PE10_C5_V4_EVENT_REPLAY_OR_CUTOVER'; END IF;
 IF (SELECT count(*) FROM private.lf_event_type_contracts_v2
 WHERE event_type='ARTIFACT_RECONCILED' AND active AND contract_mode='OPERATIONAL')<>1
 THEN RAISE EXCEPTION 'PE10_C5_V4_AUDIT_TYPE_NOT_GOVERNED'; END IF;
 v_contract:=v_prior#>'{checkpoint_contracts,PE10_C5}';
 v_spec:=v_prior#>'{action_specs_v1,PE10_C5}';
 v_pack:=v_prior#>'{source_pack_v2,checkpoint_inputs,PE10_C5}';
 v_prev_query:=v_spec#>>'{verification_queries,0}';
 IF v_prior#>>'{pe10_c5_single_dynamic_updater_v3,schema}' IS DISTINCT FROM
 'PE10_C5_SINGLE_DYNAMIC_UPDATER_V3'
 OR v_spec#>>'{scope_qualification_policy,mode}' IS DISTINCT FROM 'SINGLE_DYNAMIC_UPDATER_V02'
 OR v_spec->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
 OR v_contract->>'validator_code' IS DISTINCT FROM 'PROFILE_EVOLUTION_CUTOVER_GATE_V1'
 OR v_prev_query IS DISTINCT FROM v_pack#>>'{inputs,queries,0}'
 OR v_prev_query IS DISTINCT FROM v_contract#>>'{validation_input,queries,0}'
 OR position('(SELECT n FROM qualified_methods)=8' in v_prev_query)=0
 OR v_spec#>>'{assertion_contract,pass_when,admissible_events}' IS DISTINCT FROM '1'
 THEN RAISE EXCEPTION 'PE10_C5_V4_CONSUMER_PREIMAGE_DRIFT'; END IF;

 v_query:=$v4_query$
WITH frozen AS (
 SELECT subject_sha256 FROM private.lf_evidence_ledger_v1
 WHERE receipt_id='37db027e-ad58-4cbb-b4dc-01b7568f6ac2'::uuid
 AND receipt_kind='SOURCE_SNAPSHOT' AND verification_state='VERIFIED'
 AND subject_type='PROFILE_EVOLUTION_CUTOVER'
 AND subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
), benchmarks AS (
 SELECT c.assertion_receipt_sha256 c2_sha,b.assertion_receipt_sha256 c2b_sha
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c
 ON c.work_item_id=u.work_item_id AND c.checkpoint_code='PE10_C2'
 JOIN programacion.engineering_work_checkpoints b
 ON b.work_item_id=u.work_item_id AND b.checkpoint_code='PE10_C2B'
 WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND u.unit_code='PE10'
 AND c.status='DONE' AND b.status='DONE'
 AND c.assertion_receipt->>'result'='PASS'
 AND b.assertion_receipt->>'result'='PASS'
 AND c.assertion_receipt#>>'{observed,benchmark_scope}'='DECISION_POLICY_AND_COMPOSITION'
 AND b.assertion_receipt#>>'{observed,benchmark_scope}'='FULL_PROFILE_EVOLUTION_BEHAVIOR'
 AND (c.assertion_receipt#>>'{observed,case_count}')::int>=24
 AND (b.assertion_receipt#>>'{observed,case_count}')::int>=21
 AND (c.assertion_receipt#>>'{observed,critical_regressions}')::int=0
 AND (b.assertion_receipt#>>'{observed,critical_regressions}')::int=0
), candidate AS (
 SELECT ev.id,ev.payload p
 FROM public.lf_eventos ev CROSS JOIN frozen s CROSS JOIN benchmarks b
 JOIN public.lf_policy_versions pol
 ON pol.policy_code='POL-PROFILE-UPDATE-PASS'
 AND pol.policy_version='v1.4-evolved-routing-candidate' AND pol.status='CANDIDATE'
 WHERE ev.evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
 AND ev.entidad_tipo='OPERACION'
 AND ev.entidad_codigo='ACTUALIZACION_PERFIL_LF'
 AND ev.payload->>'status'='ADMIT_CUTOVER'
 AND ev.payload->>'target'='SINGLE_DYNAMIC_PROFILE_UPDATER_V02'
 AND ev.payload->>'frozen_subject_sha256'=s.subject_sha256
 AND ev.payload->>'benchmark_c2_sha256'=b.c2_sha
 AND ev.payload->>'benchmark_c2b_sha256'=b.c2b_sha
 AND ev.payload->>'candidate_policy_sha256'=pol.policy_sha
 AND ev.payload->>'production_activation_authorized'='false'
 AND ev.payload->>'cutover_eligible'='false'
 AND jsonb_typeof(ev.payload->'selected_method_ids')='array'
 AND jsonb_array_length(ev.payload->'selected_method_ids')>0
 AND (SELECT count(*) FROM jsonb_array_elements_text(ev.payload->'selected_method_ids') x)
 = (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(ev.payload->'selected_method_ids') x)
 AND EXISTS (
 SELECT 1 FROM private.lf_evidence_ledger_v1 safe
 JOIN private.lf_evidence_resolver_registry_v1 sr ON sr.resolver_id=safe.resolver_id
 WHERE safe.receipt_id::text=ev.payload->>'safe_change_admission_ref'
 AND safe.capability_code='SAFE_CHANGE_ADMISSION'
 AND safe.verification_state='VERIFIED'
 AND safe.subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
 AND safe.subject_sha256=s.subject_sha256
 AND safe.receipt_payload->>'execution_permission'='DOWNSTREAM_EXECUTION_ELIGIBLE'
 AND sr.active AND sr.trust_level='TRUSTED_PROVIDER_BOUND'
 )
 AND nullif(ev.payload->>'operational_selection_evidence_ref','') IS NOT NULL
), admitted AS (
 SELECT c.id FROM candidate c WHERE
 (
  c.p->>'executor_mode' IN('GPT_NATIVE','CLAUDE_NATIVE')
  AND c.p->>'method_execution_verified'='false'
  AND c.p->>'native_external_engine_certified'='false'
  AND c.p->>'native_conversation_scope'='EXISTING_CONVERSATION_ONLY'
  AND c.p->>'native_api_invocation'='false'
  AND c.p->>'native_session_creation'='false'
  AND c.p->>'native_handoff_sha256' ~ '^[0-9a-f]{64}$'
  AND c.p->>'native_capture_sha256' ~ '^[0-9a-f]{64}$'
  AND c.p->>'native_raw_sha256' ~ '^[0-9a-f]{64}$'
  AND EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1 raw
    JOIN private.lf_evidence_resolver_registry_v1 rs ON rs.resolver_id=raw.resolver_id
    JOIN private.lf_evidence_ledger_v1 reviewer
     ON reviewer.receipt_id::text=c.p->>'independent_assurance_ref'
    JOIN private.lf_evidence_resolver_registry_v1 rv ON rv.resolver_id=reviewer.resolver_id
    JOIN public.lf_operation_execution ro
     ON ro.execution_id=reviewer.execution_id
    WHERE raw.receipt_id::text=c.p->>'native_source_receipt_ref'
      AND raw.capability_code='EVIDENCE_LEDGER'
      AND raw.receipt_kind='SOURCE_SNAPSHOT'
      AND raw.subject_type='PROFILE_NATIVE_CHAT_MATERIAL_REVIEW'
      AND raw.subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5'
      AND raw.subject_sha256=c.p->>'native_raw_sha256'
      AND raw.verification_state='VERIFIED'
      AND raw.source_head_sha=c.p->>'native_source_head_sha'
      AND raw.receipt_payload->>'handoff_sha256'=c.p->>'native_handoff_sha256'
      AND raw.receipt_payload->>'capture_sha256'=c.p->>'native_capture_sha256'
      AND raw.receipt_payload->>'executor_mode'=c.p->>'executor_mode'
      AND raw.receipt_payload->>'source_manifest_sha256'=c.p->>'native_source_manifest_sha256'
      AND raw.verification_payload->>'provider_readback_verified'='true'
      AND raw.verification_payload->>'digest_recomputed'='true'
      AND rs.active AND rs.trust_level='TRUSTED_PROVIDER_BOUND'
      AND reviewer.capability_code='INDEPENDENT_ASSURANCE'
      AND reviewer.receipt_kind='INDEPENDENT_REVIEW_RECEIPT'
      AND reviewer.verification_state='VERIFIED'
      AND reviewer.subject_type=raw.subject_type
      AND reviewer.subject_ref=raw.subject_ref
      AND reviewer.subject_sha256=raw.subject_sha256
      AND reviewer.source_head_sha=raw.source_head_sha
      AND reviewer.receipt_payload->>'verdict'='PASS'
      AND reviewer.verification_payload->>'producer_execution_id'=raw.execution_id
      AND reviewer.verification_payload->>'reviewer_execution_id'=reviewer.execution_id
      AND reviewer.execution_id<>raw.execution_id
      AND rv.active AND rv.trust_level='TRUSTED_PROVIDER_BOUND'
      AND ro.operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND ro.status='COMPLETED'
      AND ro.manifest->>'subject_sha256'=raw.subject_sha256
      AND ro.manifest->>'producer_execution_id'=raw.execution_id
      AND (SELECT count(DISTINCT es.step_id)
          FROM public.lf_operation_execution_steps es
          WHERE es.execution_id=reviewer.execution_id
          AND es.status='STEP_PASS_WITH_EVIDENCE'
          AND es.step_id IN('route_bind','target_currentness','semantic_review',
                            'judge_record','reviewer_readback','report_output'))=6
      AND EXISTS (
       SELECT 1 FROM public.lf_operation_execution_steps se
       WHERE se.execution_id=reviewer.execution_id AND se.step_id='semantic_review'
       AND se.status='STEP_PASS_WITH_EVIDENCE'
       AND se.evidence_payload->>'verdict'='PASS'
       AND se.evidence_payload->>'review_context'='INDEPENDENT_OPERATION_CONTEXT'
       AND se.evidence_payload#>>'{independence_measure,state}'='INDEPENDENT'
      )
  )
 )
 OR
 (
  c.p->>'executor_mode'='METHOD_PACK_EXECUTOR'
  AND c.p->>'method_execution_verified'='true'
  AND (SELECT v.manifest#>>'{usage,allow_runtime_execution}'
       FROM public.lf_capability_current cur
       JOIN public.lf_capability_version_registry v
       ON v.capability_code=cur.capability_code AND v.version=cur.version
       WHERE cur.capability_code='METHOD_PACK_REGISTRY')='true'
  AND NOT EXISTS (
   SELECT 1 FROM jsonb_array_elements_text(c.p->'selected_method_ids') mid
   WHERE NOT EXISTS (
      SELECT 1 FROM public.lf_capability_current cur
      JOIN public.lf_capability_version_registry v
       ON v.capability_code=cur.capability_code AND v.version=cur.version
      CROSS JOIN LATERAL jsonb_array_elements(
        CASE WHEN jsonb_typeof(v.manifest->'qualified_method_portfolio')='array'
        THEN v.manifest->'qualified_method_portfolio' ELSE '[]'::jsonb END
      ) mp
      JOIN private.lf_evidence_ledger_v1 qualification
       ON qualification.subject_type='METHOD_QUALIFICATION'
       AND qualification.subject_ref=mp->>'method_id'||'@'||(mp->>'exact_version')
      JOIN private.lf_evidence_resolver_registry_v1 qr ON qr.resolver_id=qualification.resolver_id
      JOIN private.lf_evidence_ledger_v1 execution
       ON execution.subject_type='METHOD_EXECUTION'
       AND execution.subject_ref=mp->>'method_id'||'@'||(mp->>'exact_version')
      JOIN private.lf_evidence_resolver_registry_v1 er ON er.resolver_id=execution.resolver_id
      WHERE cur.capability_code='METHOD_PACK_REGISTRY'
       AND v.release_state='RELEASED'
       AND mp->>'method_id'=mid
       AND mp->>'qualification_state'='QUALIFIED'
       AND qualification.provider_ref=mp->>'benchmark_receipt_ref'
       AND qualification.verification_state='VERIFIED'
       AND qr.active AND qr.trust_level='TRUSTED_PROVIDER_BOUND'
       AND execution.receipt_kind='METHOD_EXECUTION_RECEIPT'
       AND execution.verification_state='VERIFIED'
       AND execution.receipt_id::text IN (
          SELECT jsonb_array_elements_text(
           CASE WHEN jsonb_typeof(c.p->'method_execution_receipt_refs')='array'
           THEN c.p->'method_execution_receipt_refs' ELSE '[]'::jsonb END))
       AND execution.receipt_payload->>'execution_id'=c.p->>'producer_execution_id'
       AND er.active AND er.trust_level='TRUSTED_PROVIDER_BOUND'
   )
  )
 )
)
SELECT (SELECT count(*)::int FROM admitted) admissible_events,
 (SELECT count(*)::int FROM benchmarks) measured_benchmark_pairs,
 (SELECT count(*)::int FROM candidate) event_candidates
$v4_query$;
 EXECUTE v_query INTO v_n,v_b,v_event;
 IF v_n<>0 OR v_b<>1 OR v_event<>0
 THEN RAISE EXCEPTION 'PE10_C5_V4_FAIL_CLOSED_BASELINE:%,%,%',v_n,v_b,v_event; END IF;
 v_contract:=v_contract||jsonb_build_object(
  'pass_when','One dynamic v0.2 Updater: source-bound selected techniques, GPT/Claude native same-chat RAW with independent six-step review OR externally qualified method receipts for each selected pack, plus existing verified SAFE_CHANGE_ADMISSION and exact admission event. No automatic activation.',
  'resolver_policy','REUSE_CANONICAL_NATIVE_ASSURANCE_AND_PER_SELECTED_EXTERNAL_PACK_RECEIPTS',
  'validation_input',jsonb_build_object('source','VERIFIED_TYPED_DYNAMIC_V02_ADMISSION','queries',jsonb_build_array(v_query)));
 v_spec:=v_spec||jsonb_build_object(
  'verification_queries',jsonb_build_array(v_query),
  'scope_qualification_policy',jsonb_build_object(
   'mode','SINGLE_DYNAMIC_UPDATER_V02',
   'executor_modes',jsonb_build_array('GPT_NATIVE','CLAUDE_NATIVE','METHOD_PACK_EXECUTOR'),
   'native_authoring','CURRENT_CONVERSATION_ONLY_SOURCE_BOUND_REVIEWED_NOT_ENGINE_ATTESTED',
   'external_method_execution','QUALIFIED_AND_RECEIPTED_PER_SELECTED_METHOD',
   'safe_change_required',true,
   'production_activation','SEPARATE_AFTER_C6_C7_READBACK'),
  'validator_contract',(v_spec->'validator_contract')||jsonb_build_object(
   'pass_when','One exact verified typed dynamic admission with native material review OR qualified selected external method receipts, existing SAFE_CHANGE_ADMISSION and no production activation',
   'validation_input',jsonb_build_object('mode','TYPED_DYNAMIC_OPERATIONAL_READBACK')),
  'forbidden',(v_spec->'forbidden')||jsonb_build_array(
   'TREAT_NATIVE_CHAT_TECHNIQUES_AS_EXTERNAL_ENGINE_CERTIFICATION',
   'TREAT_INTEGRITY_TEST_AS_SEMANTIC_PASS',
   'REUSE_PE10_C3_GLOBAL_REVIEW_FOR_PE10_C5_NATIVE_RAW',
   'EIGHT_GLOBAL_METHODS_AS_GATE',
   'BYPASS_SAFE_CHANGE_ADMISSION'));
 v_pack:=jsonb_set(v_pack,'{inputs,queries}',jsonb_build_array(v_query),false);
 v_next:=jsonb_set(v_prior,'{checkpoint_contracts,PE10_C5}',v_contract,false);
 v_next:=jsonb_set(v_next,'{action_specs_v1,PE10_C5}',v_spec,false);
 v_next:=jsonb_set(v_next,'{source_pack_v2,checkpoint_inputs,PE10_C5}',v_pack,false);
 v_next:=jsonb_set(v_next,'{pe10_c5_typed_native_admission_v4}',
 jsonb_build_object('schema','PE10_C5_TYPED_NATIVE_ADMISSION_V4',
  'prior_schema','PE10_C5_SINGLE_DYNAMIC_UPDATER_V3',
  'one_updater_v02',true,'native_chat_same_conversation',true,
  'external_methods_per_selected',true,
  'assurance_subject_type','PROFILE_NATIVE_CHAT_MATERIAL_REVIEW',
  'assurance_subject_ref',v_plan||'/PE10_C5',
  'native_review_receipt_kind','INDEPENDENT_REVIEW_RECEIPT',
  'c3_and_c4_preserved',true,'c6_c7_contracts_unchanged',true,
  'event_contract_registration_not_automatic',true,
  'cutover_admitted',false,'production_activated',false),true);
 IF v_next#>'{checkpoint_contracts,PE10_C3}' IS DISTINCT FROM v_prior#>'{checkpoint_contracts,PE10_C3}'
 OR v_next#>'{checkpoint_contracts,PE10_C4}' IS DISTINCT FROM v_prior#>'{checkpoint_contracts,PE10_C4}'
 OR v_next#>'{checkpoint_contracts,PE10_C6}' IS DISTINCT FROM v_prior#>'{checkpoint_contracts,PE10_C6}'
 OR v_next#>'{checkpoint_contracts,PE10_C7}' IS DISTINCT FROM v_prior#>'{checkpoint_contracts,PE10_C7}'
 OR v_next#>'{action_specs_v1,PE10_C6}' IS DISTINCT FROM v_prior#>'{action_specs_v1,PE10_C6}'
 OR v_next#>'{action_specs_v1,PE10_C7}' IS DISTINCT FROM v_prior#>'{action_specs_v1,PE10_C7}'
 THEN RAISE EXCEPTION 'PE10_C5_V4_CROSS_CHECKPOINT_DRIFT'; END IF;
 SELECT jsonb_agg(CASE WHEN a.value LIKE 'PE10_C5:%' THEN
 to_jsonb('PE10_C5: one dynamic v0.2 with per-request execution modes: native current-chat source-bound RAW plus real independent assurance, OR qualified and receipt-bound methods actually selected for external executor; SAFE_CHANGE_ADMISSION always required. No global eight-engine threshold and no automatic activation.'::text)
 ELSE to_jsonb(a.value) END ORDER BY a.ordinality)
 INTO v_new_criteria
 FROM jsonb_array_elements_text(v_old_criteria) WITH ORDINALITY a(value,ordinality);
 IF v_new_criteria IS NULL OR
 (SELECT count(*) FROM jsonb_array_elements_text(v_new_criteria) x
 WHERE x LIKE 'PE10_C5:%')<>1
 THEN RAISE EXCEPTION 'PE10_C5_V4_ACCEPTANCE_CRITERIA_INVALID'; END IF;
 v_new_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    v_plan,'PE10','PE10_C5',v_spec,v_pack);
 IF v_new_packet->>'status' IS DISTINCT FROM 'READY'
 THEN RAISE EXCEPTION 'PE10_C5_V4_CONSUMER_PACKET_INVALID:%',v_new_packet->'block_reasons'; END IF;
 v_event_payload:=jsonb_build_object(
 'evidence_schema_version','operational-event/v2','execution_id',v_actor,
 'producer','PE10_C5_CANONICAL_TYPED_CONTRACT_REPAIR',
 'purpose','Repair typed C5 admission with safe-change and no production cutover',
 'occurred_at',clock_timestamp(),'plan_code',v_plan,'checkpoint_code','PE10_C5',
 'new_contract','PE10_C5_TYPED_NATIVE_ADMISSION_V4',
 'baseline_accepted',v_n,'benchmark_pairs',v_b,'event_candidates',v_event,
 'checkpoint_pass',false,'cutover_admitted',false,'production_activation',false,
 'acceptance_declared',false);
 IF private.fn_lf_event_acceptance_signal_v2('ARTIFACT_RECONCILED',v_audit,
  'C5 native and external typed admission contract - no cutover',v_event_payload) IS NOT NULL
 THEN RAISE EXCEPTION 'PE10_C5_V4_AUDIT_FALSE_ACCEPTANCE'; END IF;
 BEGIN
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_next
   WHERE work_item_id=v_work AND unit_metadata=v_prior;
  UPDATE programacion.engineering_work_items SET acceptance_criteria=v_new_criteria
   WHERE id=v_work AND acceptance_criteria=v_old_criteria;
  INSERT INTO public.lf_eventos
   (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
   VALUES('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_rollback,
     'PE10 C5 V4 transaction rollback sentinel','INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_event_payload)
   RETURNING id INTO v_probe;
  IF NOT EXISTS(SELECT 1 FROM programacion.engineering_plan_units
   WHERE work_item_id=v_work AND unit_metadata#>>'{pe10_c5_typed_native_admission_v4,schema}'
   ='PE10_C5_TYPED_NATIVE_ADMISSION_V4') OR v_probe IS NULL
  THEN RAISE EXCEPTION 'PE10_C5_V4_DRY_PROBE_NOT_WRITTEN'; END IF;
  RAISE EXCEPTION 'PE10_C5_V4_EXPECTED_ROLLBACK';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'PE10_C5_V4_EXPECTED_ROLLBACK' THEN RAISE; END IF;
 END;
 IF (SELECT unit_metadata FROM programacion.engineering_plan_units
 WHERE work_item_id=v_work) IS DISTINCT FROM v_prior
 OR EXISTS(SELECT 1 FROM public.lf_eventos WHERE entidad_codigo=v_rollback)
 THEN RAISE EXCEPTION 'PE10_C5_V4_ROLLBACK_RESIDUE'; END IF;
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_next
 WHERE work_item_id=v_work AND unit_metadata=v_prior;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C5_V4_METADATA_CAS'; END IF;
 UPDATE programacion.engineering_work_items SET acceptance_criteria=v_new_criteria
 WHERE id=v_work AND acceptance_criteria=v_old_criteria;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C5_V4_CRITERIA_CAS'; END IF;
 INSERT INTO public.lf_eventos
 (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
 VALUES ('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_audit,
 'PE10 C5: typed native/pack consumer contract; no admission or cutover',
 'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_event_payload)
 RETURNING id INTO v_event;
 EXECUTE v_query INTO v_n,v_b,v_probe;
 IF v_n<>0 OR v_b<>1 OR v_probe<>0
 OR (SELECT status FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_work AND checkpoint_code='PE10_C5')<>'PENDING'
 OR (SELECT version FROM public.lf_operation_registry
 WHERE operation_code='ACTUALIZACION_PERFIL_LF')<>'v0.1'
 OR (SELECT count(*) FROM public.lf_eventos
 WHERE id=v_event AND payload->>'cutover_admitted'='false')<>1
 THEN RAISE EXCEPTION 'PE10_C5_V4_DURABLE_READBACK_FAILED'; END IF;
END $pe10_c5_v4$;
COMMIT;
