-- PE10_C5: anchor the existing frozen GPT_NATIVE same-chat material as a
-- provider-bound SOURCE_SNAPSHOT using the existing EVIDENCE_LEDGER.
-- This migration creates NO independent verdict, NO C5 PASS, NO cutover event,
-- NO v0.2 activation and NO profile/runtime write authority.
BEGIN;

DO $pe10_c5_source$
DECLARE
  v_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
  v_checkpoint constant text := 'PE10_C5';
  v_subject_type constant text := 'PROFILE_NATIVE_CHAT_MATERIAL_REVIEW';
  v_subject_ref constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5';

  -- Frozen material authored in the existing GPT conversation.
  v_authoring_head constant text := '663683bf2c101651291a89caa5ea56cea8649f32';
  v_readback_head constant text := '8b3b41c20d77125cf4767c79487bc13d752c01a1';
  v_capture_blob constant text := '9b36d39555950a3baeb22d1bc57f80d489250d07';
  v_profile_blob constant text := 'b0864fbdd96a6874bcf7c7f048a2280abb94df69';
  v_raw_sha constant text := 'dfbd274fe909bd005027e27f383a8c1e679882bf45e72b9b2429b986900d6cde';
  v_handoff_sha constant text := 'c07498fa3cd34ad65e296d63536c743a251d90834f4698ecd7ed318db293692a';
  v_capture_sha constant text := '944eaa1ce1d7c10ccd80f2f6e1153d657a523ecba875284a8b51a20d4644795a';
  v_source_manifest_sha constant text := '673888f8a720aa9167bc558036f0a26d540ae1e3fb664d11621e4a93df709fe3';
  v_profile_sha constant text := '2187c2671d0c05e7db0939b987c0a64f032e8d837603470b1330be61cf4e21f7';
  v_run_id constant text := 'PE10-C6-GPT-SAME-CHAT-MATERIAL-20261016';

  v_work bigint;
  v_meta jsonb;
  v_next jsonb;
  v_cap_sha text;
  v_plan_digest text;
  v_orch text;
  v_producer text;
  v_ledger text;
  v_res jsonb;
  v_dispatch jsonb;
  v_bind jsonb;
  v_anchor jsonb;
  v_receipt_id uuid;
  v_event_payload jsonb;
  v_event_id bigint;
BEGIN
  SELECT work_item_id, unit_metadata
    INTO STRICT v_work, v_meta
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code='PE10'
  FOR UPDATE;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code=v_checkpoint) IS DISTINCT FROM 'PENDING'
     OR (SELECT count(*) FROM public.lf_operation_execution
         WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS') <> 0
     OR (SELECT status FROM public.lf_policy_versions
         WHERE policy_code='POL-PROFILE-UPDATE-PASS'
           AND policy_version='v1.4-evolved-routing-candidate') IS DISTINCT FROM 'CANDIDATE'
  THEN
    RAISE EXCEPTION 'PE10_C5_NATIVE_SOURCE_PRESTATE_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM private.lf_evidence_ledger_v1
    WHERE subject_type=v_subject_type
      AND subject_ref=v_subject_ref
      AND receipt_kind='SOURCE_SNAPSHOT'
  ) THEN
    RAISE EXCEPTION 'PE10_C5_NATIVE_SOURCE_ALREADY_EXISTS_RECONCILE_FIRST';
  END IF;

  IF (SELECT count(*) FROM private.lf_evidence_resolver_registry_v1
      WHERE resolver_id='LF_GITHUB_SOURCE_READBACK_V1'
        AND provider='GITHUB'
        AND verification_method='GITHUB_API_READBACK_PLUS_OFFLINE_HASH'
        AND trust_level='TRUSTED_PROVIDER_BOUND'
        AND active) <> 1
  THEN
    RAISE EXCEPTION 'PE10_C5_GITHUB_RESOLVER_NOT_CURRENT';
  END IF;

  SELECT c.manifest_sha256 INTO STRICT v_cap_sha
  FROM public.lf_capability_current c
  JOIN public.lf_capability_registry r USING(capability_code)
  WHERE c.capability_code='EVIDENCE_LEDGER' AND r.status='ACTIVE';

  IF v_cap_sha IS DISTINCT FROM 'b9c21eaa0cb4eceec3e6a0ae78272ed2da84e408e804c127ed6e43d1360f0982'
  THEN
    RAISE EXCEPTION 'PE10_C5_EVIDENCE_LEDGER_CURRENTNESS_DRIFT';
  END IF;

  -- The immutable subject is the RAW output, not the surrounding JSON file.
  v_plan_digest := encode(extensions.digest(convert_to(jsonb_build_object(
      'schema','PE10_C5_NATIVE_SOURCE_PLAN_V1',
      'subject_type',v_subject_type,
      'subject_ref',v_subject_ref,
      'subject_sha256',v_raw_sha,
      'source_head_sha',v_readback_head,
      'authoring_head_sha',v_authoring_head,
      'capture_blob_sha1',v_capture_blob,
      'profile_blob_sha1',v_profile_blob,
      'evidence_ledger_manifest_sha256',v_cap_sha
    )::text,'UTF8'),'sha256'),'hex');

  v_orch := 'EXEC-PE10C5-SOURCE-ORCH-' || substr(v_plan_digest,1,16);
  v_producer := 'EXEC-PE10C5-SOURCE-PRODUCER-' || substr(v_plan_digest,1,16);
  v_ledger := 'EXEC-PE10C5-SOURCE-LEDGER-' || substr(v_plan_digest,1,16);

  v_res := public.fn_lf_operation_reserve_execution_v1(
    v_orch,'ORQUESTACION_PIPELINE_LF',v_subject_type,v_subject_ref,
    'pe10c5:native-source:orch:'||v_plan_digest,v_plan_digest,v_orch,null,null,
    jsonb_build_object(
      'schema','PE10_C5_NATIVE_SOURCE_ORCHESTRATOR_V1',
      'plan_digest',v_plan_digest,
      'subject_type',v_subject_type,'subject_ref',v_subject_ref,
      'subject_sha256',v_raw_sha,'source_head_sha',v_readback_head,
      'authoring_head_sha',v_authoring_head,
      'capability_code','EVIDENCE_LEDGER',
      'runtime_activation',false,'production_activation',false));
  IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS'
     OR v_res->>'execution_id' IS DISTINCT FROM v_orch
  THEN
    RAISE EXCEPTION 'PE10_C5_SOURCE_ORCHESTRATOR_RESERVE_FAILED:%',v_res;
  END IF;

  v_res := public.fn_lf_operation_reserve_execution_v1(
    v_producer,'ORQUESTACION_PIPELINE_LF',v_subject_type,v_subject_ref,
    'pe10c5:native-source:producer:'||v_plan_digest,v_plan_digest,v_orch,null,null,
    jsonb_build_object(
      'schema','PE10_C5_NATIVE_SOURCE_PRODUCER_V1',
      'orchestrator_execution_id',v_orch,'producer_execution_id',v_producer,
      'plan_digest',v_plan_digest,'capability_code','EVIDENCE_LEDGER',
      'subject_type',v_subject_type,'subject_ref',v_subject_ref,
      'subject_sha256',v_raw_sha,'source_head_sha',v_readback_head,
      'authoring_head_sha',v_authoring_head,
      'capture_blob_sha1',v_capture_blob,'profile_blob_sha1',v_profile_blob));
  IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS'
     OR v_res->>'execution_id' IS DISTINCT FROM v_producer
  THEN
    RAISE EXCEPTION 'PE10_C5_SOURCE_PRODUCER_RESERVE_FAILED:%',v_res;
  END IF;

  v_res := public.fn_lf_operation_reserve_execution_v1(
    v_ledger,'ORQUESTACION_PIPELINE_LF',v_subject_type,v_subject_ref,
    'pe10c5:native-source:ledger:'||v_plan_digest,v_plan_digest,v_orch,null,null,
    jsonb_build_object(
      'schema','PE10_C5_NATIVE_SOURCE_LEDGER_CONSUMER_V1',
      'orchestrator_execution_id',v_orch,'producer_execution_id',v_producer,
      'plan_digest',v_plan_digest,'capability_code','EVIDENCE_LEDGER',
      'subject_sha256',v_raw_sha,'source_head_sha',v_readback_head));
  IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS'
     OR v_res->>'execution_id' IS DISTINCT FROM v_ledger
  THEN
    RAISE EXCEPTION 'PE10_C5_SOURCE_LEDGER_RESERVE_FAILED:%',v_res;
  END IF;

  v_dispatch := public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orch,v_ledger,'EVIDENCE_LEDGER',v_plan_digest,
    jsonb_build_object(
      'subject_type',v_subject_type,'subject_ref',v_subject_ref,
      'subject_sha256',v_raw_sha,'source_head_sha',v_readback_head,
      'producer_execution_id',v_producer,
      'provider','GITHUB',
      'resolver_id','LF_GITHUB_SOURCE_READBACK_V1'),
    v_orch);
  IF NOT coalesce((v_dispatch->>'ready')::boolean,false)
  THEN
    RAISE EXCEPTION 'PE10_C5_SOURCE_LEDGER_DISPATCH_FAILED:%',v_dispatch;
  END IF;

  v_bind := public.fn_lf_capability_bind_from_orchestrator_v1(
    v_ledger,'EVIDENCE_LEDGER',v_cap_sha,v_plan_digest,
    (v_dispatch->>'receipt_id')::uuid,v_orch);
  IF NOT coalesce((v_bind->>'ready')::boolean,false)
  THEN
    RAISE EXCEPTION 'PE10_C5_SOURCE_LEDGER_BIND_FAILED:%',v_bind;
  END IF;

  v_anchor := public.fn_lf_evidence_ledger_anchor_v1(
    v_producer,
    'EVIDENCE_LEDGER',
    'PE10_C5_NATIVE_CHAT_SOURCE',
    'SOURCE_SNAPSHOT',
    v_subject_type,
    v_subject_ref,
    v_raw_sha,
    v_readback_head,
    'github://cristhianlujan/claude-persona-lf-patch/blob/'||v_authoring_head||
      '/skills/profile_creator/evals/results/pe10_c6_same_chat_gpt_material_authoring_20261016.json',
    'LF_GITHUB_SOURCE_READBACK_V1',
    'GITHUB',
    'github-api://repos/cristhianlujan/claude-persona-lf-patch@'||v_readback_head||
      '/contents/skills/profile_creator/evals/results/pe10_c6_same_chat_gpt_material_authoring_20261016.json',
    'GITHUB_API_READBACK_PLUS_OFFLINE_HASH',
    'VERIFIED',
    jsonb_build_object(
      'provider_readback_verified',true,
      'digest_recomputed',true,
      'authoring_head_sha',v_authoring_head,
      'readback_head_sha',v_readback_head,
      'capture_git_blob_sha1',v_capture_blob,
      'profile_git_blob_sha1',v_profile_blob,
      'capture_blob_identical_authoring_to_readback',true,
      'profile_blob_identical_authoring_to_readback',true,
      'offline_ci_head_sha','c9ad71ef89c963979d145919c28c6475f1e178d1',
      'offline_ci_run_id','38993548064',
      'offline_ci_job_id','117280931884',
      'offline_ci_test_count',33,
      'offline_ci_status','PASS',
      'raw_output_sha256',v_raw_sha,
      'profile_source_sha256',v_profile_sha,
      'source_currentness_at_readback',true,
      'semantic_review_executed',false,
      'cutover_allowed',false),
    jsonb_build_object(
      'schema','PE10_C5_NATIVE_CHAT_SOURCE_SNAPSHOT_V1',
      'profile_slug','systemic_root_cause_repair_lf',
      'run_id',v_run_id,
      'executor_mode','GPT_NATIVE',
      'native_conversation_scope','EXISTING_CONVERSATION_ONLY',
      'api_invocation',false,
      'session_creation',false,
      'handoff_sha256',v_handoff_sha,
      'capture_sha256',v_capture_sha,
      'source_manifest_sha256',v_source_manifest_sha,
      'raw_output_sha256',v_raw_sha,
      'selected_method_ids',jsonb_build_array('CAUSAL_ANALYSIS','SELF_REFINE'),
      'profile_source_ref','profiles/systemic_root_cause_repair_lf/SKILL.md',
      'profile_source_sha256',v_profile_sha,
      'authoring_head_sha',v_authoring_head,
      'readback_head_sha',v_readback_head,
      'capture_git_blob_sha1',v_capture_blob,
      'profile_git_blob_sha1',v_profile_blob,
      'cutover_eligible',false,
      'method_execution_certified',false,
      'runtime_provider_attested',false,
      'independent_review_executed',false,
      'production_activated',false),
    v_ledger);

  v_receipt_id := (v_anchor->>'receipt_id')::uuid;

  IF v_receipt_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1 l
    WHERE l.receipt_id=v_receipt_id
      AND l.execution_id=v_producer
      AND l.created_by_execution_id=v_ledger
      AND l.capability_code='EVIDENCE_LEDGER'
      AND l.receipt_kind='SOURCE_SNAPSHOT'
      AND l.subject_type=v_subject_type
      AND l.subject_ref=v_subject_ref
      AND l.subject_sha256=v_raw_sha
      AND l.source_head_sha=v_readback_head
      AND l.resolver_id='LF_GITHUB_SOURCE_READBACK_V1'
      AND l.provider='GITHUB'
      AND l.verification_method='GITHUB_API_READBACK_PLUS_OFFLINE_HASH'
      AND l.verification_state='VERIFIED'
      AND l.verification_payload->'provider_readback_verified'='true'::jsonb
      AND l.verification_payload->'digest_recomputed'='true'::jsonb
      AND l.receipt_payload->>'handoff_sha256'=v_handoff_sha
      AND l.receipt_payload->>'capture_sha256'=v_capture_sha
      AND l.receipt_payload->>'source_manifest_sha256'=v_source_manifest_sha
      AND l.receipt_payload->'selected_method_ids'=jsonb_build_array('CAUSAL_ANALYSIS','SELF_REFINE')
  ) THEN
    RAISE EXCEPTION 'PE10_C5_NATIVE_SOURCE_RECEIPT_READBACK_FAILED';
  END IF;

  v_next := jsonb_set(
    v_meta,
    '{pe10_c5_native_source_snapshot_v1}',
    jsonb_build_object(
      'schema','PE10_C5_NATIVE_SOURCE_SNAPSHOT_V1',
      'status','SOURCE_VERIFIED_AWAITING_INDEPENDENT_REVIEW',
      'subject_type',v_subject_type,
      'subject_ref',v_subject_ref,
      'subject_sha256',v_raw_sha,
      'source_head_sha',v_readback_head,
      'authoring_head_sha',v_authoring_head,
      'source_receipt_id',v_receipt_id::text,
      'producer_execution_id',v_producer,
      'ledger_execution_id',v_ledger,
      'orchestrator_execution_id',v_orch,
      'plan_digest',v_plan_digest,
      'independent_review_receipt_id',null,
      'c5_pass',false,
      'cutover_admitted',false,
      'production_activated',false),
    true);

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=v_next
  WHERE work_item_id=v_work AND unit_metadata=v_meta;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PE10_C5_NATIVE_SOURCE_METADATA_CAS_FAILED';
  END IF;

  v_event_payload := jsonb_build_object(
    'evidence_schema_version','operational-event/v2',
    'execution_id',v_ledger,
    'producer','PE10_C5_NATIVE_SOURCE_SNAPSHOT_V1',
    'purpose','Anchor existing GPT native same-chat material as provider-bound source; no semantic verdict or cutover',
    'occurred_at',clock_timestamp(),
    'plan_code',v_plan,
    'checkpoint_code',v_checkpoint,
    'subject_type',v_subject_type,
    'subject_ref',v_subject_ref,
    'subject_sha256',v_raw_sha,
    'source_head_sha',v_readback_head,
    'source_receipt_id',v_receipt_id::text,
    'github_authoring_head_sha',v_authoring_head,
    'github_capture_blob_sha1',v_capture_blob,
    'github_profile_blob_sha1',v_profile_blob,
    'offline_ci_run_id','38993548064',
    'offline_ci_tests',33,
    'independent_review_executed',false,
    'checkpoint_pass',false,
    'cutover_admitted',false,
    'production_activation',false,
    'acceptance_declared',false);

  IF private.fn_lf_event_acceptance_signal_v2(
      'ARTIFACT_RECONCILED',
      'PE10_C5.NATIVE_SOURCE_SNAPSHOT.V1',
      'PE10 C5 verified native source snapshot; no independent verdict',
      v_event_payload) IS NOT NULL
  THEN
    RAISE EXCEPTION 'PE10_C5_NATIVE_SOURCE_FALSE_ACCEPTANCE';
  END IF;

  INSERT INTO public.lf_eventos
    (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
     created_by_execution_id,payload)
  VALUES
    ('ARTIFACT_RECONCILED','PROGRAM_PLAN','PE10_C5.NATIVE_SOURCE_SNAPSHOT.V1',
     'PE10 C5 GPT Native source snapshot verified; independent review still required',
     'INFO','DERIVE_FROM_EXECUTION_ID',v_ledger,v_event_payload)
  RETURNING id INTO v_event_id;

  IF v_event_id IS NULL
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work AND checkpoint_code=v_checkpoint) <> 'PENDING'
     OR EXISTS (
        SELECT 1 FROM public.lf_eventos
        WHERE evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
          AND entidad_codigo='ACTUALIZACION_PERFIL_LF')
  THEN
    RAISE EXCEPTION 'PE10_C5_NATIVE_SOURCE_POSTSTATE_INVALID';
  END IF;

  INSERT INTO public.lf_error_knowledge
    (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
     severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
  SELECT
    'LF-PE10-C5-NATIVE-SOURCE-SNAPSHOT-MISSING-20261021-001',
    'PROFILE_EVOLUTION',
    'Native same-chat material existed without a verified C5 source snapshot',
    'The frozen GPT Native handoff/capture and its consumer were present and tested, but C5 had no exact SOURCE_SNAPSHOT for PROFILE_NATIVE_CHAT_MATERIAL_REVIEW, so independent assurance could not bind to the RAW subject.',
    'Evidence transport stopped between source-bound chat capture and Evidence Ledger anchoring; the semantic reviewer correctly had nothing provider-bound to review.',
    'A validated native capture is not equivalent to a provider-bound source receipt; C5 must anchor exact RAW, source revision, selected methods and hashes before independent review.',
    'After any native capture selected for admission, perform GitHub API readback plus offline digest and create exactly one VERIFIED SOURCE_SNAPSHOT before review dispatch; never reuse the global C3 subject.',
    'Receipt readback requires subject SHA '||v_raw_sha||', exact selected methods, GitHub resolver, digest recomputation, C5 remains PENDING and zero cutover events.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C5','ACTIVO',
    'supabase/migrations/20261021162500_lf_pe10_c5_native_source_snapshot_v1.sql'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-PE10-C5-NATIVE-SOURCE-SNAPSHOT-MISSING-20261021-001'
  );

  INSERT INTO public.lf_error_knowledge
    (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
     severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
  SELECT
    'LF-PE10-C5-GITHUB-PROVIDER-REF-HEAD-MISMATCH-20261021-001',
    'PROFILE_EVOLUTION',
    'Evidence Ledger rejected GitHub provider reference without source-head binding',
    'Migration Train run 39632655557 reached the exact apply step but the Evidence Ledger guard rejected the source anchor before ledger effect because provider_ref did not encode @source_head_sha.',
    'The first candidate used a GitHub blob locator as provider_ref. The canonical guard requires provider_ref to contain @<40-char source_head_sha>/ so provider identity and frozen revision are cross-bound.',
    'A provider URL may identify a real blob yet still be inadmissible when it does not bind the exact source revision required by the ledger guard.',
    'For LF_GITHUB_SOURCE_READBACK_V1 always encode the exact source head in provider_ref and verify it matches source_head_sha before Train apply.',
    'Failing Train receipt public.lf_eventos.id=21376 recorded APPLY_FAILED_BEFORE_LEDGER_EFFECT; corrected provider_ref binds @'||v_readback_head||'/ and the durable snapshot readback below must pass.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C5','ACTIVO',
    'github://cristhianlujan/claude-persona-lf-patch/pull/3016'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-PE10-C5-GITHUB-PROVIDER-REF-HEAD-MISMATCH-20261021-001'
  );
END
$pe10_c5_source$;

COMMIT;
