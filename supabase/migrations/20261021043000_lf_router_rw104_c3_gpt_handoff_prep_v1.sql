-- RW1-04_C3 blind-review handoff prep. Leaves C3 PENDING.
BEGIN;
DO $rw104_c3_handoff$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-04';
  v_cp constant text := 'RW1-04_C3';
  v_wi constant bigint := 1130;
  v_prior_md5 constant text := 'bd76a08cca7cf8b172f2c0f2eef67563';
  v_exec constant text := 'LF_ROUTER_RW104_C3_GPT_HANDOFF_V1|RW1-04_C3';
  v_packet_path constant text := 'docs/programming-agent/router_wave/RW1_04_C3_BLIND_REVIEW_PACKET_V1.json';
  v_packet_blob constant text := '7a5c0e9048ebd3029efe258ade9a352ddaacc7ee';
  v_c2_receipt constant text := '5b3f6f5d00de5c760a227ef8352a791cf09e02becc01ee91e4c7e9b4f801a0bf';
  v_decision_blob constant text := '9d80848dca36c94ba901028a4c27a1c58e425cb4';
  v_manifest jsonb := jsonb_build_object(
    'schema','RW104_C3_GPT_NATIVE_HANDOFF_MANIFEST_V1',
    'subject_ref',v_plan||'/'||v_unit||'/'||v_cp,
    'packet_path',v_packet_path,
    'packet_git_blob',v_packet_blob,
    'c2_assertion_receipt_sha256',v_c2_receipt,
    'owner_decision_ref','docs/programming-agent/ROUTER_WAVE_C3_PROPORTIONAL_TIER_DECISION_V1.md',
    'owner_decision_git_blob',v_decision_blob,
    'evidence_tier','OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT',
    'limits',jsonb_build_object('provider_attested',false,'real_execution_receipt',false,'independent_review',false,'runtime_activation',false,'production_activation',false),
    'separate_chat_required',true,
    'acceptance_declared',false
  );
  v_key jsonb := jsonb_build_object(
    'schema','RW104_C3_BLIND_KEY_V1',
    'packet_git_blob',v_packet_blob,
    'real_item_id','ITEM_A',
    'decoy_item_id','ITEM_B',
    'decoy_must_fail_checks',jsonb_build_array(
      'DESIGN_CODE_ALIGNMENT',
      'SECURITY_AUTHORITY_INVARIANTS',
      'CURRENT_SOURCE_AND_ACL',
      'ROLLBACK_LEGACY_COMPATIBILITY',
      'NO_REGRESSION_SCOPE'
    ),
    'reviewer_requirement','SEPARATE_GPT_NATIVE_CHAT',
    'isolation_provable',false
  );
  v_instructions text :=
    'Open ONLY the exact packet '||v_packet_path||' at git blob '||v_packet_blob||
    ' in a NEW GPT Native chat separate from the producer context. Evaluate both items against all five checks and six prompts. '||
    'Return ONLY the JSON required by output_contract. Do not inspect any answer key or producer conversation. '||
    'Do not claim provider attestation, real execution receipt or independent review.';
  v_m jsonb;
  v_before_specs jsonb;
  v_before_cps text;
  v_after_cps text;
BEGIN
  SELECT unit_metadata INTO STRICT v_m
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
    AND disposition='ASSIGNED' AND md5(unit_metadata::text)=v_prior_md5
  FOR UPDATE;

  IF (SELECT status FROM programacion.engineering_work_items WHERE id=v_wi) IS DISTINCT FROM 'IN_PROGRESS'
     OR (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi AND checkpoint_code='RW1-04_C2') IS DISTINCT FROM 'DONE'
     OR (SELECT assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi AND checkpoint_code='RW1-04_C2') IS DISTINCT FROM v_c2_receipt
     OR (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi AND checkpoint_code=v_cp) IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'RW104_C3_HANDOFF_LIFECYCLE_DRIFT'; END IF;

  IF v_m#>'{gpt_native_packets_v1,RW1-04_C3}' IS NOT NULL
     OR v_m#>'{gpt_native_c3_keys_v1,RW1-04_C3}' IS NOT NULL
     OR v_m#>'{gpt_native_captures_v1,RW1-04_C3}' IS NOT NULL
  THEN RAISE EXCEPTION 'RW104_C3_HANDOFF_ALREADY_EXISTS'; END IF;

  v_before_specs:=v_m->'action_specs_v1';
  SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_before_cps
  FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi;

  UPDATE programacion.engineering_plan_units
     SET unit_metadata =
       v_m
       || jsonb_build_object('gpt_native_packets_v1',coalesce(v_m->'gpt_native_packets_v1','{}'::jsonb)||jsonb_build_object(v_cp,v_manifest))
       || jsonb_build_object('gpt_native_c3_keys_v1',coalesce(v_m->'gpt_native_c3_keys_v1','{}'::jsonb)||jsonb_build_object(v_cp,v_key))
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

  SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

  IF v_m#>array['gpt_native_packets_v1',v_cp] IS DISTINCT FROM v_manifest
     OR v_m#>array['gpt_native_c3_keys_v1',v_cp] IS DISTINCT FROM v_key
     OR v_m->'action_specs_v1' IS DISTINCT FROM v_before_specs
  THEN RAISE EXCEPTION 'RW104_C3_HANDOFF_READBACK_MISMATCH'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_eventos WHERE evento_tipo='HANDOFF_DEEP_CONTEXT' AND created_by_execution_id=v_exec
  ) THEN
    INSERT INTO public.lf_eventos(evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
    VALUES(
      'HANDOFF_DEEP_CONTEXT','PROGRAM_PLAN',v_plan||'.'||v_cp||'.GPT_NATIVE_HANDOFF',
      'Blinded RW1-04_C3 design-vs-code review handed to a separate GPT Native chat; no acceptance declared.',
      'INFO','DERIVE_FROM_EXECUTION_ID',v_exec,
      jsonb_build_object(
        'evidence_schema_version','operational-event/v2',
        'execution_id',v_exec,
        'producer','LF_ROUTER_RW104_C3_GPT_HANDOFF_V1',
        'purpose','Adversarially review RW1-04 implementation against approved design in a GPT Native chat separate from producer context.',
        'occurred_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"+00:00"'),
        'acceptance_declared',false,
        'subject_ref',v_manifest->>'subject_ref',
        'checkpoint',v_cp,'work_item_id',v_wi,
        'packet_path',v_packet_path,'packet_git_blob',v_packet_blob,
        'evidence_tier',v_manifest->>'evidence_tier',
        'provider_attested',false,'real_execution_receipt',false,'independent_review',false,
        'separate_chat_required',true,
        'instructions_for_gpt',v_instructions,
        'return_instructions','Reply in the NEW chat with ONLY the JSON object, unedited.',
        'limits_note','This handoff is not acceptance and does not close RW1-04_C3.'
      )
    );
  END IF;

  SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_after_cps
  FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi;

  IF v_after_cps IS DISTINCT FROM v_before_cps
     OR (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi AND checkpoint_code=v_cp) IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'RW104_C3_HANDOFF_CHANGED_CHECKPOINT'; END IF;
END
$rw104_c3_handoff$;
COMMIT;
