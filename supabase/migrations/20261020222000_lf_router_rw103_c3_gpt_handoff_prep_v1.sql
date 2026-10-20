-- RW1-03_C3 blind-review handoff prep.
-- Stores only the hash-bound packet manifest + answer key separately and emits HANDOFF_DEEP_CONTEXT.
-- C3 stays PENDING. No action spec, runtime, ACL, operation, profile/adapter or production change.
BEGIN;
DO $rw103_c3_handoff$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-03';
  v_cp constant text := 'RW1-03_C3';
  v_wi constant bigint := 1129;
  v_prior_md5 constant text := '6555677e0b7290ecb81ddcbe89c66ff8';
  v_exec constant text := 'LF_ROUTER_RW103_C3_GPT_HANDOFF_V1|RW1-03_C3';
  v_packet_path constant text := 'docs/programming-agent/router_wave/RW1_03_C3_BLIND_REVIEW_PACKET_V2.json';
  v_packet_blob constant text := '4654cdab6de895890aedaa0163321cb977a174ac';
  v_c2_blob constant text := 'bfd571d5e7c7d1d80c5ed39414a822b4096c20d6';
  v_c2_receipt constant text := '22b93f4a983bf12a7c110917e74759f457b4da5555fb7f152ad90f400ede3b97';
  v_decision_blob constant text := '9d80848dca36c94ba901028a4c27a1c58e425cb4';

  v_manifest jsonb := jsonb_build_object(
    'schema','RW103_C3_GPT_NATIVE_HANDOFF_MANIFEST_V1',
    'subject_ref',v_plan||'/'||v_unit||'/'||v_cp,
    'packet_path',v_packet_path,
    'packet_git_blob',v_packet_blob,
    'c2_contract_git_blob',v_c2_blob,
    'c2_assertion_receipt_sha256',v_c2_receipt,
    'owner_decision_ref','docs/programming-agent/ROUTER_WAVE_C3_PROPORTIONAL_TIER_DECISION_V1.md',
    'owner_decision_git_blob',v_decision_blob,
    'evidence_tier','OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT',
    'limits',jsonb_build_object(
      'provider_attested',false,
      'real_execution_receipt',false,
      'independent_review',false,
      'runtime_activation',false,
      'production_activation',false
    ),
    'separate_chat_required',true,
    'acceptance_declared',false
  );

  v_key jsonb := jsonb_build_object(
    'schema','RW103_C3_BLIND_KEY_V1',
    'packet_git_blob',v_packet_blob,
    'real_item_id','ITEM_A',
    'decoy_item_id','ITEM_B',
    'decoy_must_fail_checks',jsonb_build_array(
      'AUTHORITY_SEPARATION',
      'TRAIN_AND_ROLLBACK_NON_CIRCULAR',
      'STALE_NEGATIVE_FAIL_CLOSED',
      'LEGACY_COMPATIBILITY_NO_BYPASS'
    ),
    'reviewer_requirement','SEPARATE_GPT_NATIVE_CHAT',
    'producer_context','RW1-03_C2_AND_C3_HANDOFF_PREP_CURRENT_PROJECT_CHAT',
    'isolation_provable',false
  );

  v_instructions text :=
    'Open ONLY the exact packet '||v_packet_path||' at git blob '||v_packet_blob||
    ' in a NEW GPT Native chat separate from the producer context. Evaluate both blind items against the five checks and six synthetic prompts. '||
    'Return ONLY the JSON required by output_contract. Do not inspect any answer key or producer conversation. '||
    'Do not claim provider attestation, real execution receipt or independent review.';

  v_m jsonb;
  v_before_specs jsonb;
  v_before_cps text;
  v_after_cps text;
  v_id bigint;
  v_payload jsonb;
BEGIN
  IF (SELECT count(*) FROM programacion.engineering_plan_units
      WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
        AND disposition='ASSIGNED' AND md5(unit_metadata::text)=v_prior_md5)<>1
  THEN RAISE EXCEPTION 'RW103_C3_HANDOFF_PRESTATE_DRIFT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=v_wi AND work_code='ROUTER-W1-03' AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code='RW1-03_C2'
           AND status='DONE' AND assertion_receipt_sha256=v_c2_receipt)<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code=v_cp
           AND status='PENDING' AND evidence_ref IS NULL AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW103_C3_HANDOFF_CHECKPOINT_DRIFT'; END IF;

  SELECT unit_metadata INTO STRICT v_m
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
  FOR UPDATE;

  IF v_m#>>'{source_pack_v2,checkpoint_inputs,RW1-03_C2,source_git_blobs,contract}' IS DISTINCT FROM v_c2_blob
     OR v_m#>'{gpt_native_packets_v1,RW1-03_C3}' IS NOT NULL
     OR v_m#>'{gpt_native_c3_keys_v1,RW1-03_C3}' IS NOT NULL
     OR v_m#>'{gpt_native_captures_v1,RW1-03_C3}' IS NOT NULL
  THEN RAISE EXCEPTION 'RW103_C3_HANDOFF_SOURCE_OR_DUPLICATE_DRIFT'; END IF;

  v_before_specs:=v_m->'action_specs_v1';
  SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no)
    INTO v_before_cps
  FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi;

  UPDATE programacion.engineering_plan_units
     SET unit_metadata =
       v_m
       || jsonb_build_object(
            'gpt_native_packets_v1',
            coalesce(v_m->'gpt_native_packets_v1','{}'::jsonb)
              || jsonb_build_object(v_cp,v_manifest)
          )
       || jsonb_build_object(
            'gpt_native_c3_keys_v1',
            coalesce(v_m->'gpt_native_c3_keys_v1','{}'::jsonb)
              || jsonb_build_object(v_cp,v_key)
          )
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

  SELECT unit_metadata INTO v_m
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

  IF v_m#>array['gpt_native_packets_v1',v_cp] IS DISTINCT FROM v_manifest
     OR v_m#>array['gpt_native_c3_keys_v1',v_cp] IS DISTINCT FROM v_key
     OR v_m->'action_specs_v1' IS DISTINCT FROM v_before_specs
  THEN RAISE EXCEPTION 'RW103_C3_HANDOFF_READBACK_MISMATCH'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE evento_tipo='HANDOFF_DEEP_CONTEXT'
      AND created_by_execution_id=v_exec
  ) THEN
    INSERT INTO public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload
    )
    VALUES(
      'HANDOFF_DEEP_CONTEXT',
      'PROGRAM_PLAN',
      v_plan||'.'||v_cp||'.GPT_NATIVE_HANDOFF',
      'Hash-bound blinded RW1-03_C3 packet handed to a separate GPT Native chat; no acceptance declared.',
      'INFO',
      'DERIVE_FROM_EXECUTION_ID',
      v_exec,
      jsonb_build_object(
        'evidence_schema_version','operational-event/v2',
        'execution_id',v_exec,
        'producer','LF_ROUTER_RW103_C3_GPT_HANDOFF_V1',
        'purpose','Review RW1-03_C2 contract adversarially in a GPT Native chat separate from the producer context.',
        'occurred_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"+00:00"'),
        'acceptance_declared',false,
        'subject_ref',v_manifest->>'subject_ref',
        'checkpoint',v_cp,
        'work_item_id',v_wi,
        'packet_path',v_packet_path,
        'packet_git_blob',v_packet_blob,
        'evidence_tier',v_manifest->>'evidence_tier',
        'provider_attested',false,
        'real_execution_receipt',false,
        'independent_review',false,
        'separate_chat_required',true,
        'instructions_for_gpt',v_instructions,
        'return_instructions','Reply in the NEW chat with ONLY the JSON object, unedited.',
        'limits_note','This handoff is not acceptance and does not close RW1-03_C3.'
      )
    )
    RETURNING id,payload INTO v_id,v_payload;

    IF v_payload->>'packet_git_blob' IS DISTINCT FROM v_packet_blob
       OR v_payload->>'instructions_for_gpt' IS DISTINCT FROM v_instructions
       OR v_payload->>'acceptance_declared' IS DISTINCT FROM 'false'
    THEN RAISE EXCEPTION 'RW103_C3_HANDOFF_EVENT_READBACK_MISMATCH'; END IF;
  END IF;

  SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no)
    INTO v_after_cps
  FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi;

  IF v_after_cps IS DISTINCT FROM v_before_cps
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code=v_cp) IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'RW103_C3_HANDOFF_CHANGED_CHECKPOINT_STATE'; END IF;
END
$rw103_c3_handoff$;
COMMIT;
