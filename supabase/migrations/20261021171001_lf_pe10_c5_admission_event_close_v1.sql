-- PE10_C5: govern the exact admission event type, emit one source-bound
-- preactivation admission event, execute the CURRENT C5 validator query, record
-- the assertion receipt and close only PE10_C5.
--
-- This does NOT activate v0.2, does NOT activate steps 35/37, does NOT alter
-- the active v0.1 policy/registry, and leaves PE10_C6/PE10_C7 pending.
BEGIN;

DO $pe10_c5_close$
DECLARE
  v_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
  v_unit constant text := 'PE10';
  v_checkpoint constant text := 'PE10_C5';
  v_event_type constant text := 'PROFILE_EVOLUTION_CUTOVER_ADMITTED';
  v_actor constant text := 'EXEC-PE10C5-ADMISSION-CLOSE-20261021-V1';

  v_frozen_sha constant text := '73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a';
  v_c2_sha constant text := '586b92af62baa5d54a9726a5a3deedcf316d81c102fd0af76e0d54df05887c15';
  v_c2b_sha constant text := 'be86ad8ab314156382c804b6c20ade503cd38503b7f161c0e36ca3913d3760d5';
  v_policy_sha constant text := '5ae6804ded17dea94a7ec2d8c4ebe588b1017222ab8d92b912bc8607996892b5';

  v_safe constant uuid := 'd5225fea-9218-4e94-8cbe-d35335632b55'::uuid;
  v_native_source constant uuid := '731e93ae-a230-4172-ad6c-f2fb4c9024d6'::uuid;
  v_review constant uuid := 'ae10a7bb-0e99-4589-a7c7-38e61af506b0'::uuid;

  v_raw_sha constant text := 'dfbd274fe909bd005027e27f383a8c1e679882bf45e72b9b2429b986900d6cde';
  v_native_head constant text := '8b3b41c20d77125cf4767c79487bc13d752c01a1';
  v_handoff constant text := 'c07498fa3cd34ad65e296d63536c743a251d90834f4698ecd7ed318db293692a';
  v_capture constant text := '944eaa1ce1d7c10ccd80f2f6e1153d657a523ecba875284a8b51a20d4644795a';
  v_source_manifest constant text := '673888f8a720aa9167bc558036f0a26d540ae1e3fb664d11621e4a93df709fe3';

  v_contract jsonb;
  v_request bigint;
  v_contract_sha text;
  v_approval bigint;
  v_work bigint;
  v_query text;
  v_gate record;
  v_event_payload jsonb;
  v_event_id bigint;
  v_assertion jsonb;
  v_transition jsonb;
BEGIN
  SELECT work_item_id INTO STRICT v_work
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND disposition='ASSIGNED';

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code=v_checkpoint) IS DISTINCT FROM 'PENDING'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work AND checkpoint_code='PE10_C4') IS DISTINCT FROM 'DONE'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work AND checkpoint_code='PE10_C6') IS DISTINCT FROM 'PENDING'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work AND checkpoint_code='PE10_C7') IS DISTINCT FROM 'PENDING'
     OR EXISTS (
       SELECT 1 FROM public.lf_eventos
       WHERE evento_tipo=v_event_type
         AND entidad_codigo='ACTUALIZACION_PERFIL_LF')
  THEN
    RAISE EXCEPTION 'PE10_C5_CLOSE_PRESTATE_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='EVENT_CONTRACT_GOVERNANCE'
      AND estado_operativo='ACTIVO'
      AND metadata#>>'{transversal_inventory,inventory_status}'='ACTIVE_SHARED_ENFORCEMENT'
  ) THEN
    RAISE EXCEPTION 'PE10_C5_EVENT_GOVERNANCE_NOT_ACTIVE';
  END IF;

  -- Exact safe-change permission.
  IF NOT EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1 l
    JOIN private.lf_evidence_resolver_registry_v1 r ON r.resolver_id=l.resolver_id
    WHERE l.receipt_id=v_safe
      AND l.capability_code='SAFE_CHANGE_ADMISSION'
      AND l.receipt_kind='SAFE_CHANGE_ADMISSION_RESULT'
      AND l.subject_type='PROFILE_EVOLUTION_CUTOVER'
      AND l.subject_ref=v_plan||'/PE10'
      AND l.subject_sha256=v_frozen_sha
      AND l.verification_state='VERIFIED'
      AND l.receipt_payload->>'classification'='AUTOMATIZABLE'
      AND l.receipt_payload->>'execution_permission'='DOWNSTREAM_EXECUTION_ELIGIBLE'
      AND l.receipt_payload->>'production_activation_authorized'='false'
      AND r.active AND r.trust_level='TRUSTED_PROVIDER_BOUND'
  ) THEN
    RAISE EXCEPTION 'PE10_C5_SAFE_CHANGE_NOT_CURRENT';
  END IF;

  -- Exact native source/reviewer pair.
  IF NOT EXISTS (
    SELECT 1
    FROM private.lf_evidence_ledger_v1 raw
    JOIN private.lf_evidence_resolver_registry_v1 rs ON rs.resolver_id=raw.resolver_id
    WHERE raw.receipt_id=v_native_source
      AND raw.capability_code='EVIDENCE_LEDGER'
      AND raw.receipt_kind='SOURCE_SNAPSHOT'
      AND raw.subject_type='PROFILE_NATIVE_CHAT_MATERIAL_REVIEW'
      AND raw.subject_ref=v_plan||'/PE10_C5'
      AND raw.subject_sha256=v_raw_sha
      AND raw.source_head_sha=v_native_head
      AND raw.verification_state='VERIFIED'
      AND raw.receipt_payload->>'handoff_sha256'=v_handoff
      AND raw.receipt_payload->>'capture_sha256'=v_capture
      AND raw.receipt_payload->>'source_manifest_sha256'=v_source_manifest
      AND raw.receipt_payload->'selected_method_ids'=jsonb_build_array('CAUSAL_ANALYSIS','SELF_REFINE')
      AND raw.receipt_payload->>'native_conversation_scope'='EXISTING_CONVERSATION_ONLY'
      AND raw.receipt_payload->>'api_invocation'='false'
      AND raw.receipt_payload->>'session_creation'='false'
      AND raw.verification_payload->>'provider_readback_verified'='true'
      AND raw.verification_payload->>'digest_recomputed'='true'
      AND rs.active AND rs.trust_level='TRUSTED_PROVIDER_BOUND'
  ) OR NOT EXISTS (
    SELECT 1
    FROM private.lf_evidence_ledger_v1 rev
    JOIN private.lf_evidence_resolver_registry_v1 rr ON rr.resolver_id=rev.resolver_id
    JOIN public.lf_operation_execution ro ON ro.execution_id=rev.execution_id
    WHERE rev.receipt_id=v_review
      AND rev.capability_code='INDEPENDENT_ASSURANCE'
      AND rev.receipt_kind='INDEPENDENT_REVIEW_RECEIPT'
      AND rev.subject_type='PROFILE_NATIVE_CHAT_MATERIAL_REVIEW'
      AND rev.subject_ref=v_plan||'/PE10_C5'
      AND rev.subject_sha256=v_raw_sha
      AND rev.source_head_sha=v_native_head
      AND rev.verification_state='VERIFIED'
      AND rev.receipt_payload->>'verdict'='PASS'
      AND rr.active AND rr.trust_level='TRUSTED_PROVIDER_BOUND'
      AND ro.operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND ro.status='COMPLETED'
  ) THEN
    RAISE EXCEPTION 'PE10_C5_NATIVE_SOURCE_OR_REVIEW_NOT_CURRENT';
  END IF;

  IF (SELECT count(*) FROM public.lf_operation_execution_steps
      WHERE execution_id='EXEC-PE10C5-INDEP-d288c5ee8b3335e4'
        AND step_id IN ('route_bind','target_currentness','semantic_review',
                        'judge_record','reviewer_readback','report_output')
        AND status='STEP_PASS_WITH_EVIDENCE') <> 6
  THEN
    RAISE EXCEPTION 'PE10_C5_REVIEW_NOT_SIX_OF_SIX';
  END IF;

  IF (SELECT assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code='PE10_C2') IS DISTINCT FROM v_c2_sha
     OR (SELECT assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work AND checkpoint_code='PE10_C2B') IS DISTINCT FROM v_c2b_sha
     OR (SELECT count(*) FROM public.lf_policy_versions
         WHERE policy_code='POL-PROFILE-UPDATE-PASS'
           AND policy_version='v1.4-evolved-routing-candidate'
           AND status='CANDIDATE' AND policy_sha=v_policy_sha) <> 1
  THEN
    RAISE EXCEPTION 'PE10_C5_BENCHMARK_OR_POLICY_DRIFT';
  END IF;

  -- Register the event as actual validation/acceptance evidence, never OPERATIONAL.
  v_contract:=jsonb_build_object(
    'active',true,
    'rationale',
      'Preactivation admission of the single dynamic Profile Updater v0.2 only after exact frozen benchmarks, provider-bound SAFE_CHANGE_ADMISSION and exact native reviewer/selection evidence. This event permits C6 transactional cutover testing but never authorizes production activation by itself.',
    'contract_mode','VALIDATION_ACCEPTANCE',
    'allowed_evidence_schemas',jsonb_build_array('architecture-gate-test/v1')
  );

  IF NOT EXISTS (
    SELECT 1 FROM private.lf_event_type_contracts_v2
    WHERE event_type=v_event_type
  ) THEN
    v_request := private.fn_create_lf_event_type_contract_request_v2(
      v_event_type,'INSERT',v_contract,v_actor
    );

    SELECT proposed_contract_sha256 INTO STRICT v_contract_sha
    FROM private.lf_event_type_contract_change_requests_v2
    WHERE id=v_request AND status='REQUESTED';

    INSERT INTO public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,
      payload,origen,created_at,created_by_execution_id
    ) VALUES (
      'EVENT_TYPE_CONTRACT_CHANGE_APPROVED',
      'EVENT_TYPE_CONTRACT',v_event_type,
      'Governed registration of the PE10 v0.2 preactivation admission event; it authorizes only continuation to transactional cutover checks.',
      'INFO',
      jsonb_build_object(
        'evidence_schema_version','event-type-contract-governance/v1',
        'decision','APPROVED',
        'request_id',v_request,
        'event_type',v_event_type,
        'proposed_contract_sha256',v_contract_sha,
        'approved_at',clock_timestamp(),
        'execution_id',v_actor
      ),
      'DERIVE_FROM_EXECUTION_ID',clock_timestamp(),v_actor
    ) RETURNING id INTO v_approval;

    PERFORM private.fn_approve_lf_event_type_contract_request_v2(v_request,v_approval);
    PERFORM private.fn_apply_lf_event_type_contract_change_v2(v_request);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.v_lf_event_type_contract_audit_v2
    WHERE event_type=v_event_type
      AND active=true
      AND contract_mode='VALIDATION_ACCEPTANCE'
      AND allowed_evidence_schemas=ARRAY['architecture-gate-test/v1']::text[]
      AND governance_state='GOVERNED_V2'
  ) THEN
    RAISE EXCEPTION 'PE10_C5_ADMISSION_EVENT_CONTRACT_NOT_GOVERNED';
  END IF;

  v_event_payload:=jsonb_build_object(
    'evidence_schema_version','architecture-gate-test/v1',
    'all_confirmed',true,
    'probe_persistence',true,
    'positive_control_count',4,
    'negative_rejection_count',3,

    'status','ADMIT_CUTOVER',
    'target','SINGLE_DYNAMIC_PROFILE_UPDATER_V02',
    'frozen_subject_sha256',v_frozen_sha,
    'benchmark_c2_sha256',v_c2_sha,
    'benchmark_c2b_sha256',v_c2b_sha,
    'candidate_policy_sha256',v_policy_sha,
    'safe_change_admission_ref',v_safe::text,

    'executor_mode','GPT_NATIVE',
    'profile_slug','systemic_root_cause_repair_lf',
    'selected_method_ids',jsonb_build_array('CAUSAL_ANALYSIS','SELF_REFINE'),
    'method_execution_verified',false,
    'native_external_engine_certified',false,
    'native_conversation_scope','EXISTING_CONVERSATION_ONLY',
    'native_api_invocation',false,
    'native_session_creation',false,
    'native_handoff_sha256',v_handoff,
    'native_capture_sha256',v_capture,
    'native_raw_sha256',v_raw_sha,
    'native_source_head_sha',v_native_head,
    'native_source_manifest_sha256',v_source_manifest,
    'native_run_id','PE10-C6-GPT-SAME-CHAT-MATERIAL-20261016',
    'native_source_receipt_ref',v_native_source::text,
    'operational_selection_evidence_ref',v_native_source::text,
    'independent_assurance_ref',v_review::text,

    'production_activation_authorized',false,
    'cutover_eligible',false,
    'next_gate','PE10_C6_TRANSACTIONAL_CUTOVER_VALIDATION',
    'scope','PREACTIVATION_C5_ADMISSION_ONLY'
  );

  IF private.fn_lf_typed_evidence_payload_valid_v3(
       'architecture-gate-test/v1',v_event_payload) IS NOT TRUE
  THEN
    RAISE EXCEPTION 'PE10_C5_ADMISSION_EVENT_TYPED_EVIDENCE_INVALID';
  END IF;

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,
    payload,origen,created_at,created_by_execution_id
  ) VALUES (
    v_event_type,'OPERACION','ACTUALIZACION_PERFIL_LF',
    'PE10 C5 preactivation admission for the single dynamic Profile Updater v0.2; production activation remains prohibited pending C6/C7.',
    'INFO',v_event_payload,'PE10_C5_ADMISSION_GATE',clock_timestamp(),v_actor
  ) RETURNING id INTO v_event_id;

  -- Reuse the exact CURRENT checkpoint validator query rather than duplicating
  -- its semantics in this migration.
  SELECT unit_metadata#>>'{action_specs_v1,PE10_C5,verification_queries,0}'
    INTO STRICT v_query
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit;

  IF position('PROFILE_EVOLUTION_CUTOVER_ADMITTED' in v_query)=0
     OR position('safe_change_admission_ref' in v_query)=0
     OR position('native_source_receipt_ref' in v_query)=0
     OR position('independent_assurance_ref' in v_query)=0
  THEN
    RAISE EXCEPTION 'PE10_C5_CURRENT_VALIDATOR_QUERY_DRIFT';
  END IF;

  EXECUTE v_query INTO v_gate;

  IF v_gate.admissible_events IS DISTINCT FROM 1
     OR v_gate.measured_benchmark_pairs IS DISTINCT FROM 1
     OR v_gate.event_candidates IS DISTINCT FROM 1
  THEN
    RAISE EXCEPTION
      'PE10_C5_ADMISSION_GATE_FAILED:admissible=% benchmark=% candidates=%',
      v_gate.admissible_events,v_gate.measured_benchmark_pairs,v_gate.event_candidates;
  END IF;

  v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    v_plan,v_unit,v_checkpoint,
    jsonb_build_object(
      'status','PASS',
      'observed',jsonb_build_object(
        'admissible_events',v_gate.admissible_events,
        'measured_benchmark_pairs',v_gate.measured_benchmark_pairs,
        'event_candidates',v_gate.event_candidates
      ),
      'evidence_ref','supabase://public/lf_eventos/'||v_event_id::text
    ),
    v_actor
  );

  IF v_assertion->>'passed' IS DISTINCT FROM 'true'
     OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION 'PE10_C5_ASSERTION_RECEIPT_INVALID:%',v_assertion;
  END IF;

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_checkpoint,'DONE',
    'supabase://public/lf_eventos/'||v_event_id::text,
    v_actor,
    'C5 closed from exact current validator after provider-bound safe change, native source/reviewer and governed admission event.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN
    RAISE EXCEPTION 'PE10_C5_TRANSITION_FAILED:%',v_transition;
  END IF;

  -- Hard postconditions: only C5 closes.
  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code='PE10_C5') IS DISTINCT FROM 'DONE'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work AND checkpoint_code='PE10_C6') IS DISTINCT FROM 'PENDING'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work AND checkpoint_code='PE10_C7') IS DISTINCT FROM 'PENDING'
     OR (SELECT count(*) FROM public.lf_eventos
         WHERE evento_tipo=v_event_type
           AND entidad_codigo='ACTUALIZACION_PERFIL_LF') <> 1
     OR NOT EXISTS (
       SELECT 1 FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_work AND checkpoint_code='PE10_C5'
         AND assertion_receipt->>'passed'='true'
         AND assertion_receipt_sha256=programacion.fn_v09_sha256_jsonb(assertion_receipt))
     OR (SELECT count(*) FROM public.lf_operation_registry
         WHERE operation_code='ACTUALIZACION_PERFIL_LF'
           AND version='v0.1' AND status='PRODUCCION_CONTROLADA') <> 1
     OR (SELECT count(*) FROM public.lf_operation_registry
         WHERE operation_code='ACTUALIZACION_PERFIL_LF'
           AND version='v0.2') <> 0
     OR (SELECT count(*) FROM public.lf_operation_steps
         WHERE operation_code='ACTUALIZACION_PERFIL_LF'
           AND step_id IN ('method_selection','evolution_decision')
           AND active) <> 0
  THEN
    RAISE EXCEPTION 'PE10_C5_CLOSE_POSTSTATE_INVALID';
  END IF;

  INSERT INTO public.lf_error_knowledge
    (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
     severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
  SELECT
    'LF-PE10-C5-ADMISSION-EVENT-TYPE-MISSING-20261021-001',
    'PROFILE_EVOLUTION',
    'C5 admission evidence existed but its acceptance event type was not governed',
    'After source anchoring, independent review and SAFE_CHANGE_ADMISSION were complete, the exact C5 validator still returned zero because PROFILE_EVOLUTION_CUTOVER_ADMITTED was default-denied and had no event-type contract.',
    'The admission event channel had intentionally not been registered before the evidence prerequisites existed.',
    'A complete evidence chain cannot satisfy a checkpoint that explicitly requires one typed admission event until that event type is governed and exactly one source-bound event is emitted.',
    'Register acceptance event types through EVENT_CONTRACT_GOVERNANCE only after prerequisites are verified; use VALIDATION_ACCEPTANCE rather than OPERATIONAL when the event deliberately conveys an admission decision.',
    'Current migration requires a governed VALIDATION_ACCEPTANCE contract, exact current C5 query result admissible_events=1, assertion receipt, C5 DONE, C6/C7 still PENDING and no v0.2 registry activation.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C5','ACTIVO',
    'github://cristhianlujan/claude-persona-lf-patch/pull/PENDING'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-PE10-C5-ADMISSION-EVENT-TYPE-MISSING-20261021-001'
  );
END
$pe10_c5_close$;

COMMIT;
