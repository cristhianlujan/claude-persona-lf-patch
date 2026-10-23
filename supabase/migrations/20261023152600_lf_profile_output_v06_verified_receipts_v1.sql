-- Profile Output V0.6: materialize two provider-bound output-validation receipts.
-- Source provider run: https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39977664105
-- Exact provider-verified PR head: a4f55d64cd32bfc780cbe156b6bb1308b6446a26
-- This does NOT activate Profile Updater v0.2, authorize cutover, or close PE10_C6.
-- Materialization uses the existing EVIDENCE_LEDGER only; no parallel evidence store.
BEGIN;
DO $profile_output_v06$
DECLARE
  v_slug CONSTANT text := 'systemic_root_cause_repair_lf';
  v_head CONSTANT text := 'a4f55d64cd32bfc780cbe156b6bb1308b6446a26';
  v_run CONSTANT bigint := 39977664105;
  v_evidence_sha CONSTANT text := 'e7abf94f781d2bd2c307285fb9c59c97d4249ed639215901bbf55a0159a0971a';
  v_positive_sha CONSTANT text := '0b76b5a33e9ea7ececc157662c9196abecc581d3078fdb8fa048e8c6cc1ca9bb';
  v_negative_sha CONSTANT text := 'd209a542a10bd6aedc097bbcbed9343060873ab85cfc6810123a8bb899663c60';
  v_manifest_sha CONSTANT text := '9538bd47a653725f045ae93cb60694b08947506d84dfd16fb1b4709af53e8517';
  v_provider jsonb := $provider_e2e${"authoring_mode":"GPT_NATIVE_CURRENT_CHAT_SOURCE_AUTHORED","candidate_output_provider_e2e_verified":true,"candidate_status":"NEEDS_MORE_EVIDENCE","capability_code":"PACK_VALIDATION_HARNESS","checkpoint_closed":false,"cutover_authorized":false,"evidence_scope":"CURRENT_V06_EVOLVED_CANDIDATE","evidence_sha256":"e7abf94f781d2bd2c307285fb9c59c97d4249ed639215901bbf55a0159a0971a","gate_code":"PROFILE_OUTPUT_CONTRACT_VALIDATION","github_actions_run_id":"39977664105","github_readback_source_sha256":{"builder":"cfb23a2872bd143c53b129fb26994cf7db246a1e2f7ae3ae4626a8fbba46cac6","evidence_manifest":"9538bd47a653725f045ae93cb60694b08947506d84dfd16fb1b4709af53e8517","negative_raw_output":"d209a542a10bd6aedc097bbcbed9343060873ab85cfc6810123a8bb899663c60","positive_raw_output":"0b76b5a33e9ea7ececc157662c9196abecc581d3078fdb8fa048e8c6cc1ca9bb","producer":"b5de5935b5ea209875c5647ab8f8e0dd0e7e00d049faa3a94dbf3423b4d4e2a0","runner":"159d0c3218d5a90de880e43fcf17cd29a9414da9c2317fb1aaff61ee0137c276","runtime_binding":"3408c4e1c4213ca2c615a909cd7530f6dae202f0d911610673741a969a9f336b","schema":"18ee653127fc938852248b0a5d50975558d6498b1d27f625cb6b04bccf173170","validator":"501a03881730d3bfcd99f66cd87452a1c8c3dd25f2a4a11cdf96743eed3e19be"},"ledger_verified":false,"negative_result":{"admission_authorized":false,"blocking_codes":[],"canonical_json_schema_executed":true,"independent_review_executed":false,"profile_validator_executed":false,"profile_write_authorized":false,"provider_attested":false,"raw_output_sha256":"d209a542a10bd6aedc097bbcbed9343060873ab85cfc6810123a8bb899663c60","runtime_activation_authorized":false,"runtime_binding_sha256":"3408c4e1c4213ca2c615a909cd7530f6dae202f0d911610673741a969a9f336b","schema":"PROFILE_OUTPUT_VALIDATION_RESULT_V1","shape_errors":[{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"}],"source_readback_matched":true,"source_refs":{"evidence_manifest":"skills/profile_creator/evals/results/profile_output_v06_current_evidence_manifest_20261023.json","raw_output":"skills/profile_creator/evals/results/profile_output_v06_current_candidate_negative_20261023.json","schema":"profiles/systemic_root_cause_repair_lf/schemas/output.schema.json","validator":"profiles/systemic_root_cause_repair_lf/validators/runtime_validate.py"},"status":"EXPECTED_NEGATIVE_REJECTED_BY_SHAPE","structural_check_executed":true},"positive_result":{"admission_authorized":false,"blocking_codes":[],"canonical_json_schema_executed":true,"independent_review_executed":false,"profile_validator_executed":true,"profile_write_authorized":false,"provider_attested":false,"raw_output_sha256":"0b76b5a33e9ea7ececc157662c9196abecc581d3078fdb8fa048e8c6cc1ca9bb","runtime_activation_authorized":false,"runtime_binding_sha256":"3408c4e1c4213ca2c615a909cd7530f6dae202f0d911610673741a969a9f336b","schema":"PROFILE_OUTPUT_VALIDATION_RESULT_V1","shape_errors":[],"source_readback_matched":true,"source_refs":{"evidence_manifest":"skills/profile_creator/evals/results/profile_output_v06_current_evidence_manifest_20261023.json","raw_output":"skills/profile_creator/evals/results/profile_output_v06_current_candidate_20261023.json","schema":"profiles/systemic_root_cause_repair_lf/schemas/output.schema.json","validator":"profiles/systemic_root_cause_repair_lf/validators/runtime_validate.py"},"status":"CANDIDATE_OUTPUT_PARITY_OBSERVED","structural_check_executed":true,"validator_errors":[],"validator_exit_code":0,"validator_stdout_sha256":"0721efeafa1041213a16755d82765d599fa5fe8d0ce820bc9fd0a02ae86d7afc"},"production_activation":false,"profile_pack_id":"SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6","profile_slug":"systemic_root_cause_repair_lf","provider":"GITHUB","receipt_issued":false,"runtime_provider_attested":false,"schema":"PROFILE_OUTPUT_V06_GITHUB_PROVIDER_E2E_V1","source_head_sha":"a4f55d64cd32bfc780cbe156b6bb1308b6446a26"}$provider_e2e$::jsonb;
  v_plan_sha text;
  v_ledger_cap_sha text;
  v_orch text;
  v_producer text;
  v_ledger text;
  v_res jsonb;
  v_dispatch jsonb;
  v_bind jsonb;
  v_anchor jsonb;
  v_result jsonb;
  v_receipt_id uuid;
  v_subject_type text;
  v_raw_path text;
  v_raw_sha text;
  v_receipts jsonb := '[]'::jsonb;
  v_actor CONSTANT text := 'EXEC-PROFILE-OUTPUT-V06-VERIFIED-RECEIPTS-20261023-V1';
  v_event_code CONSTANT text := 'PROFILE_OUTPUT_V06.PROVIDER_VERIFIED_RECEIPTS.V1';
  v_audit jsonb;
  v_event_id bigint;
BEGIN
  -- Provider envelope must describe the exact fail-closed candidate and run.
  IF v_provider->>'schema' IS DISTINCT FROM 'PROFILE_OUTPUT_V06_GITHUB_PROVIDER_E2E_V1'
     OR v_provider->>'evidence_scope' IS DISTINCT FROM 'CURRENT_V06_EVOLVED_CANDIDATE'
     OR v_provider->>'profile_slug' IS DISTINCT FROM v_slug
     OR v_provider->>'profile_pack_id' IS DISTINCT FROM 'SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6'
     OR v_provider->>'candidate_status' IS DISTINCT FROM 'NEEDS_MORE_EVIDENCE'
     OR v_provider->>'source_head_sha' IS DISTINCT FROM v_head
     OR v_provider->>'github_actions_run_id' IS DISTINCT FROM v_run::text
     OR v_provider->>'evidence_sha256' IS DISTINCT FROM v_evidence_sha
     OR v_provider->>'candidate_output_provider_e2e_verified' IS DISTINCT FROM 'true'
     OR v_provider->>'runtime_provider_attested' IS DISTINCT FROM 'false'
     OR v_provider->>'receipt_issued' IS DISTINCT FROM 'false'
     OR v_provider->>'ledger_verified' IS DISTINCT FROM 'false'
     OR v_provider->>'cutover_authorized' IS DISTINCT FROM 'false'
     OR v_provider->>'checkpoint_closed' IS DISTINCT FROM 'false'
     OR v_provider->>'production_activation' IS DISTINCT FROM 'false'
     OR v_provider#>>'{github_readback_source_sha256,positive_raw_output}' IS DISTINCT FROM v_positive_sha
     OR v_provider#>>'{github_readback_source_sha256,negative_raw_output}' IS DISTINCT FROM v_negative_sha
     OR v_provider#>>'{github_readback_source_sha256,evidence_manifest}' IS DISTINCT FROM v_manifest_sha
  THEN
    RAISE EXCEPTION 'PROFILE_OUTPUT_V06_PROVIDER_ENVELOPE_INVALID';
  END IF;

  IF v_provider#>>'{positive_result,status}' IS DISTINCT FROM 'CANDIDATE_OUTPUT_PARITY_OBSERVED'
     OR v_provider#>>'{positive_result,raw_output_sha256}' IS DISTINCT FROM v_positive_sha
     OR v_provider#>>'{positive_result,source_readback_matched}' IS DISTINCT FROM 'true'
     OR v_provider#>>'{positive_result,canonical_json_schema_executed}' IS DISTINCT FROM 'true'
     OR v_provider#>>'{positive_result,profile_validator_executed}' IS DISTINCT FROM 'true'
     OR v_provider#>>'{positive_result,validator_exit_code}' IS DISTINCT FROM '0'
     OR jsonb_array_length(v_provider#>'{positive_result,validator_errors}') <> 0
     OR v_provider#>>'{positive_result,source_refs,raw_output}' IS DISTINCT FROM
        'skills/profile_creator/evals/results/profile_output_v06_current_candidate_20261023.json'
     OR v_provider#>>'{positive_result,source_refs,evidence_manifest}' IS DISTINCT FROM
        'skills/profile_creator/evals/results/profile_output_v06_current_evidence_manifest_20261023.json'
     OR v_provider#>>'{positive_result,admission_authorized}' IS DISTINCT FROM 'false'
     OR v_provider#>>'{positive_result,provider_attested}' IS DISTINCT FROM 'false'
     OR v_provider#>>'{positive_result,runtime_activation_authorized}' IS DISTINCT FROM 'false'
  THEN
    RAISE EXCEPTION 'PROFILE_OUTPUT_V06_POSITIVE_RESULT_INVALID';
  END IF;

  IF v_provider#>>'{negative_result,status}' IS DISTINCT FROM 'EXPECTED_NEGATIVE_REJECTED_BY_SHAPE'
     OR v_provider#>>'{negative_result,raw_output_sha256}' IS DISTINCT FROM v_negative_sha
     OR v_provider#>>'{negative_result,source_readback_matched}' IS DISTINCT FROM 'true'
     OR v_provider#>>'{negative_result,canonical_json_schema_executed}' IS DISTINCT FROM 'true'
     OR v_provider#>>'{negative_result,profile_validator_executed}' IS DISTINCT FROM 'false'
     OR jsonb_array_length(v_provider#>'{negative_result,shape_errors}') = 0
     OR v_provider#>>'{negative_result,source_refs,raw_output}' IS DISTINCT FROM
        'skills/profile_creator/evals/results/profile_output_v06_current_candidate_negative_20261023.json'
     OR v_provider#>>'{negative_result,source_refs,evidence_manifest}' IS DISTINCT FROM
        'skills/profile_creator/evals/results/profile_output_v06_current_evidence_manifest_20261023.json'
     OR v_provider#>>'{negative_result,admission_authorized}' IS DISTINCT FROM 'false'
     OR v_provider#>>'{negative_result,provider_attested}' IS DISTINCT FROM 'false'
     OR v_provider#>>'{negative_result,runtime_activation_authorized}' IS DISTINCT FROM 'false'
  THEN
    RAISE EXCEPTION 'PROFILE_OUTPUT_V06_NEGATIVE_RESULT_INVALID';
  END IF;

  -- Live prestate: source-only example receipts remain non-authoritative.
  IF (SELECT version FROM public.lf_operation_registry
       WHERE operation_code='ACTUALIZACION_PERFIL_LF') IS DISTINCT FROM 'v0.1'
     OR (SELECT count(*) FROM public.lf_operation_steps
       WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND active) <> 15
     OR (SELECT count(*) FROM public.lf_operation_steps
       WHERE operation_code='ACTUALIZACION_PERFIL_LF'
         AND step_order IN (35,37) AND active) <> 0
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=1103 AND checkpoint_code IN ('PE10_C6','PE10_C7')
         AND status='PENDING') <> 2
     OR (SELECT count(*) FROM private.lf_evidence_ledger_v1
       WHERE subject_ref=v_slug
         AND subject_type IN ('PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE')
         AND verification_state='ANCHORED'
         AND receipt_payload->>'example_fixture_only'='true') <> 2
     OR EXISTS (
       SELECT 1 FROM private.lf_evidence_ledger_v1
       WHERE subject_ref=v_slug
         AND subject_type IN ('PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE')
         AND verification_state='VERIFIED'
     )
     OR EXISTS (SELECT 1 FROM public.lf_eventos WHERE entidad_codigo=v_event_code)
  THEN
    RAISE EXCEPTION 'PROFILE_OUTPUT_V06_LEDGER_PRESTATE_CHANGED';
  END IF;

  IF (SELECT count(*) FROM private.lf_evidence_resolver_registry_v1
       WHERE resolver_id='LF_GITHUB_SOURCE_READBACK_V1'
         AND provider='GITHUB'
         AND verification_method='GITHUB_API_READBACK_PLUS_OFFLINE_HASH'
         AND trust_level='TRUSTED_PROVIDER_BOUND'
         AND active) <> 1
     OR (SELECT count(*) FROM public.lf_capability_registry r
         JOIN public.lf_capability_current c USING(capability_code)
         WHERE r.capability_code='PACK_VALIDATION_HARNESS'
           AND r.status='ACTIVE' AND c.version='1.0.0') <> 1
     OR (SELECT count(*) FROM public.lf_capability_registry r
         JOIN public.lf_capability_current c USING(capability_code)
         WHERE r.capability_code='EVIDENCE_LEDGER'
           AND r.status='ACTIVE' AND c.version='1.1.0') <> 1
  THEN
    RAISE EXCEPTION 'PROFILE_OUTPUT_V06_PROVIDER_AUTHORITY_UNAVAILABLE';
  END IF;

  SELECT c.manifest_sha256 INTO STRICT v_ledger_cap_sha
  FROM public.lf_capability_current c
  JOIN public.lf_capability_registry r USING(capability_code)
  WHERE c.capability_code='EVIDENCE_LEDGER' AND r.status='ACTIVE';

  v_plan_sha := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'schema','PROFILE_OUTPUT_V06_VERIFIED_RECEIPT_PLAN_V1',
      'profile_slug',v_slug,
      'source_head_sha',v_head,
      'github_actions_run',v_run,
      'provider_evidence_sha256',v_evidence_sha,
      'positive_sha256',v_positive_sha,
      'negative_sha256',v_negative_sha,
      'evidence_manifest_sha256',v_manifest_sha,
      'ledger_cap_sha256',v_ledger_cap_sha
    )::text,'UTF8'),'sha256'),'hex');

  v_orch := 'EXEC-OUTV06-ORCH-'||substr(v_plan_sha,1,16);
  v_producer := 'EXEC-OUTV06-PRODUCER-'||substr(v_plan_sha,1,16);
  v_ledger := 'EXEC-OUTV06-LEDGER-'||substr(v_plan_sha,1,16);

  v_res := public.fn_lf_operation_reserve_execution_v1(
    v_orch,'ORQUESTACION_PIPELINE_LF','PROFILE_OUTPUT_VALIDATION',v_slug,
    'profile-output-v06:orch:'||v_plan_sha,v_plan_sha,v_orch,null,null,
    jsonb_build_object(
      'schema','PROFILE_OUTPUT_V06_ORCHESTRATOR_V1',
      'plan_digest',v_plan_sha,
      'capability_code','EVIDENCE_LEDGER',
      'source_head_sha',v_head,
      'provider_run_id',v_run,
      'production_activation',false,
      'checkpoint_closed',false
    ));
  IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS'
     OR v_res->>'execution_id' IS DISTINCT FROM v_orch
  THEN RAISE EXCEPTION 'PROFILE_OUTPUT_V06_ORCHESTRATOR_RESERVE_FAILED:%',v_res; END IF;

  v_res := public.fn_lf_operation_reserve_execution_v1(
    v_producer,'ORQUESTACION_PIPELINE_LF','PROFILE_OUTPUT_VALIDATION',v_slug,
    'profile-output-v06:producer:'||v_plan_sha,v_plan_sha,v_orch,null,null,
    jsonb_build_object(
      'schema','PROFILE_OUTPUT_V06_PRODUCER_V1',
      'orchestrator_execution_id',v_orch,
      'plan_digest',v_plan_sha,
      'capability_code','PACK_VALIDATION_HARNESS',
      'source_head_sha',v_head,
      'provider_ref','github-api://repos/cristhianlujan/claude-persona-lf-patch@'||v_head||
        '/actions/runs/'||v_run::text,
      'provider_evidence_sha256',v_evidence_sha,
      'candidate_output_provider_e2e_verified',true,
      'production_activation',false
    ));
  IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS'
     OR v_res->>'execution_id' IS DISTINCT FROM v_producer
  THEN RAISE EXCEPTION 'PROFILE_OUTPUT_V06_PRODUCER_RESERVE_FAILED:%',v_res; END IF;

  v_res := public.fn_lf_operation_reserve_execution_v1(
    v_ledger,'ORQUESTACION_PIPELINE_LF','PROFILE_OUTPUT_VALIDATION',v_slug,
    'profile-output-v06:ledger:'||v_plan_sha,v_plan_sha,v_orch,null,null,
    jsonb_build_object(
      'schema','PROFILE_OUTPUT_V06_LEDGER_V1',
      'orchestrator_execution_id',v_orch,
      'producer_execution_id',v_producer,
      'plan_digest',v_plan_sha,
      'capability_code','EVIDENCE_LEDGER',
      'source_head_sha',v_head,
      'materialization','VERIFIED_RECEIPTS_ONLY',
      'production_activation',false
    ));
  IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS'
     OR v_res->>'execution_id' IS DISTINCT FROM v_ledger
  THEN RAISE EXCEPTION 'PROFILE_OUTPUT_V06_LEDGER_RESERVE_FAILED:%',v_res; END IF;

  v_dispatch := public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orch,v_ledger,'EVIDENCE_LEDGER',v_plan_sha,
    jsonb_build_object(
      'subject_types',jsonb_build_array(
        'PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE'),
      'subject_ref',v_slug,
      'source_head_sha',v_head,
      'producer_execution_id',v_producer,
      'provider','GITHUB',
      'resolver_id','LF_GITHUB_SOURCE_READBACK_V1',
      'example_fixture_only',false,
      'candidate_output_provider_e2e_verified',true
    ),v_orch);
  IF NOT coalesce((v_dispatch->>'ready')::boolean,false)
  THEN RAISE EXCEPTION 'PROFILE_OUTPUT_V06_LEDGER_DISPATCH_FAILED:%',v_dispatch; END IF;

  v_bind := public.fn_lf_capability_bind_from_orchestrator_v1(
    v_ledger,'EVIDENCE_LEDGER',v_ledger_cap_sha,v_plan_sha,
    (v_dispatch->>'receipt_id')::uuid,v_orch);
  IF NOT coalesce((v_bind->>'ready')::boolean,false)
  THEN RAISE EXCEPTION 'PROFILE_OUTPUT_V06_LEDGER_BIND_FAILED:%',v_bind; END IF;

  FOR v_subject_type,v_result,v_raw_path,v_raw_sha IN
    SELECT *
    FROM (VALUES
      (
        'PROFILE_OUTPUT_VALIDATION_POSITIVE',
        v_provider->'positive_result',
        'skills/profile_creator/evals/results/profile_output_v06_current_candidate_20261023.json',
        v_positive_sha
      ),
      (
        'PROFILE_OUTPUT_VALIDATION_NEGATIVE',
        v_provider->'negative_result',
        'skills/profile_creator/evals/results/profile_output_v06_current_candidate_negative_20261023.json',
        v_negative_sha
      )
    ) AS current_output(subject_type,validation_result,raw_path,raw_sha)
  LOOP
    IF v_result->>'raw_output_sha256' IS DISTINCT FROM v_raw_sha
       OR v_result#>>'{source_refs,raw_output}' IS DISTINCT FROM v_raw_path
       OR v_result#>>'{source_refs,evidence_manifest}' IS DISTINCT FROM
          'skills/profile_creator/evals/results/profile_output_v06_current_evidence_manifest_20261023.json'
    THEN
      RAISE EXCEPTION 'PROFILE_OUTPUT_V06_RESULT_SOURCE_DRIFT:%',v_subject_type;
    END IF;

    v_anchor := public.fn_lf_evidence_ledger_anchor_v1(
      v_producer,
      'PACK_VALIDATION_HARNESS',
      'PROFILE_OUTPUT_CONTRACT_VALIDATION',
      'PROFILE_OUTPUT_VALIDATION_RESULT',
      v_subject_type,
      v_slug,
      v_raw_sha,
      v_head,
      'github://cristhianlujan/claude-persona-lf-patch/blob/'||v_head||'/'||v_raw_path,
      'LF_GITHUB_SOURCE_READBACK_V1',
      'GITHUB',
      'github-api://repos/cristhianlujan/claude-persona-lf-patch@'||v_head||
        '/actions/runs/'||v_run::text,
      'GITHUB_API_READBACK_PLUS_OFFLINE_HASH',
      'VERIFIED',
      jsonb_build_object(
        'provider_readback_verified',true,
        'digest_recomputed',true,
        'github_commit_provider_readback',true,
        'github_source_head_sha',v_head,
        'github_actions_run_id',v_run,
        'github_actions_status','SUCCESS',
        'source_hashes_provider_verified',v_provider->'github_readback_source_sha256',
        'provider_evidence_sha256',v_evidence_sha,
        'evidence_manifest_sha256',v_manifest_sha,
        'candidate_output_provider_e2e_verified',true,
        'example_fixture_only',false,
        'production_activation',false
      ),
      v_result || jsonb_build_object(
        'profile_slug',v_slug,
        'profile_pack_id','SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6',
        'candidate_status','NEEDS_MORE_EVIDENCE',
        'source_head_sha',v_head,
        'evidence_scope','CURRENT_V06_EVOLVED_CANDIDATE',
        'example_fixture_only',false,
        'provider_evidence_sha256',v_evidence_sha,
        'provider_run_id',v_run,
        'evidence_manifest_sha256',v_manifest_sha,
        'output_cutover_authorized',false,
        'candidate_output_provider_e2e_verified',true,
        'checkpoint_closed',false,
        'production_activation',false
      ),
      v_ledger
    );

    v_receipt_id := (v_anchor->>'receipt_id')::uuid;
    IF v_receipt_id IS NULL
       OR v_anchor->>'verification_state' IS DISTINCT FROM 'VERIFIED'
       OR NOT EXISTS (
         SELECT 1
         FROM private.lf_evidence_ledger_v1 l
         WHERE l.receipt_id=v_receipt_id
           AND l.execution_id=v_producer
           AND l.created_by_execution_id=v_ledger
           AND l.capability_code='PACK_VALIDATION_HARNESS'
           AND l.gate_code='PROFILE_OUTPUT_CONTRACT_VALIDATION'
           AND l.receipt_kind='PROFILE_OUTPUT_VALIDATION_RESULT'
           AND l.subject_type=v_subject_type
           AND l.subject_ref=v_slug
           AND l.subject_sha256=v_raw_sha
           AND l.source_head_sha=v_head
           AND l.verification_state='VERIFIED'
           AND l.verified_at IS NOT NULL
           AND l.resolver_id='LF_GITHUB_SOURCE_READBACK_V1'
           AND l.provider='GITHUB'
           AND l.verification_method='GITHUB_API_READBACK_PLUS_OFFLINE_HASH'
           AND l.receipt_payload->>'example_fixture_only'='false'
           AND l.receipt_payload->>'output_cutover_authorized'='false'
           AND l.receipt_payload->>'candidate_output_provider_e2e_verified'='true'
           AND l.receipt_payload->>'checkpoint_closed'='false'
           AND l.receipt_payload->>'production_activation'='false'
       )
       OR public.lf_profile_update_verified_receipt_v1(
            v_subject_type,v_slug,v_receipt_id::text,v_raw_sha,v_head
          ) IS DISTINCT FROM true
       OR public.lf_profile_update_verified_receipt_v1(
            v_subject_type,v_slug,v_receipt_id::text,repeat('0',64),v_head
          ) IS NOT false
       OR public.lf_profile_update_verified_receipt_v1(
            v_subject_type,v_slug,v_receipt_id::text,v_raw_sha,repeat('0',40)
          ) IS NOT false
    THEN
      RAISE EXCEPTION 'PROFILE_OUTPUT_V06_VERIFIED_RECEIPT_READBACK_FAILED:%',v_subject_type;
    END IF;

    v_receipts := v_receipts || jsonb_build_array(
      jsonb_build_object(
        'subject_type',v_subject_type,
        'receipt_id',v_receipt_id,
        'verification_state','VERIFIED',
        'subject_sha256',v_raw_sha,
        'source_head_sha',v_head
      )
    );
  END LOOP;

  -- The old canonical-example ANCHORED receipts must remain rejected by the reader.
  IF EXISTS (
    SELECT 1
    FROM private.lf_evidence_ledger_v1 l
    WHERE l.subject_ref=v_slug
      AND l.subject_type IN ('PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE')
      AND l.verification_state='ANCHORED'
      AND l.receipt_payload->>'example_fixture_only'='true'
      AND public.lf_profile_update_verified_receipt_v1(
        l.subject_type,l.subject_ref,l.receipt_id::text,l.subject_sha256,l.source_head_sha
      ) IS DISTINCT FROM false
  ) THEN
    RAISE EXCEPTION 'PROFILE_OUTPUT_V06_EXAMPLE_RECEIPT_FALSE_POSITIVE';
  END IF;

  IF (SELECT count(*) FROM private.lf_evidence_ledger_v1
       WHERE subject_ref=v_slug
         AND subject_type IN ('PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE')
         AND source_head_sha=v_head
         AND verification_state='VERIFIED'
         AND receipt_payload->>'example_fixture_only'='false'
         AND receipt_payload->>'candidate_output_provider_e2e_verified'='true') <> 2
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=1103 AND checkpoint_code IN ('PE10_C6','PE10_C7')
         AND status='PENDING') <> 2
     OR (SELECT version FROM public.lf_operation_registry
       WHERE operation_code='ACTUALIZACION_PERFIL_LF') IS DISTINCT FROM 'v0.1'
  THEN
    RAISE EXCEPTION 'PROFILE_OUTPUT_V06_POSTSTATE_INVALID';
  END IF;

  v_audit := jsonb_build_object(
    'evidence_schema_version','operational-event/v2',
    'execution_id',v_actor,
    'producer','LF_MIGRATION_TRAIN_PROFILE_OUTPUT_V06_LEDGER',
    'purpose','Materialize provider-bound V0.6 output-validation receipts without cutover or checkpoint closure',
    'occurred_at',clock_timestamp(),
    'provider_actions_run',v_run,
    'provider_source_head_sha',v_head,
    'provider_evidence_sha256',v_evidence_sha,
    'evidence_manifest_sha256',v_manifest_sha,
    'materialized_receipts',v_receipts,
    'producer_execution_id',v_producer,
    'ledger_execution_id',v_ledger,
    'example_fixture_only',false,
    'candidate_output_provider_e2e_verified',true,
    'output_receipts_verified_count',2,
    'output_cutover_authorized',false,
    'checkpoint_pass',false,
    'checkpoint_closed',false,
    'production_activation',false,
    'acceptance_declared',false
  );

  IF private.fn_lf_event_acceptance_signal_v2(
      'ARTIFACT_RECONCILED',
      v_event_code,
      'V0.6 provider-bound output receipts VERIFIED; checkpoint remains pending',
      v_audit
    ) IS NOT NULL
  THEN
    RAISE EXCEPTION 'PROFILE_OUTPUT_V06_FALSE_ACCEPTANCE_SIGNAL';
  END IF;

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,
    severidad,origen,created_by_execution_id,payload
  ) VALUES (
    'ARTIFACT_RECONCILED',
    'PROGRAM_PLAN',
    v_event_code,
    'Two current V0.6 provider-bound output validations materialized as VERIFIED; no cutover or checkpoint close',
    'INFO',
    'DERIVE_FROM_EXECUTION_ID',
    v_actor,
    v_audit
  ) RETURNING id INTO v_event_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE id=v_event_id
      AND payload->>'candidate_output_provider_e2e_verified'='true'
      AND payload->>'output_receipts_verified_count'='2'
      AND payload->>'output_cutover_authorized'='false'
      AND payload->>'checkpoint_pass'='false'
      AND payload->>'checkpoint_closed'='false'
      AND payload->>'production_activation'='false'
      AND jsonb_array_length(payload->'materialized_receipts')=2
  ) THEN
    RAISE EXCEPTION 'PROFILE_OUTPUT_V06_AUDIT_READBACK_FAILED';
  END IF;
END
$profile_output_v06$;
COMMIT;
